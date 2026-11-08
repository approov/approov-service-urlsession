// MIT License
//
// Copyright (c) 2026-present, Approov Ltd.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
// (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
// ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
// THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import XCTest
import Foundation
import Combine
import Approov
@testable import ApproovURLSessionPackage
import MiniSDKTestSupport

/// The errors a request can fail with. A standard decision keeps its 3.5.x ApproovError. The app's own
/// abort, a URLError, reaches the app unchanged. Anything else a hook throws, an ApproovError the app's
/// own code threw included, is a URLError naming the hook with the original underlying. A failed request
/// fails alone: the session stays valid.
final class ErrorSurface370Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var targetURL: URL!
    private var errorLines: [String] = []
    private let lock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        targetURL = try XCTUnwrap(URL(string: try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])))
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.error)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-error-surface")
        ApproovService.logSink = { [weak self] level, line in
            guard let self, level == .error else { return }
            self.lock.lock(); self.errorLines.append(line); self.lock.unlock()
        }
    }

    override func tearDown() {
        ApproovService.logSink = nil
        ApproovService.setLoggingLevel(.info)
        ApproovService.setServiceMutator(nil)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    private struct AppError: Error {}

    // a mutator whose token decision throws the given error
    private final class Throwing: ApproovServiceMutator {
        let error: Error
        init(_ error: Error) { self.error = error }
        func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult,
                                               url: String) throws -> Bool {
            throw error
        }
    }

    private func update() -> ApproovUpdateResponse {
        return ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
    }

    func testTheAppsOwnURLErrorIsUnchanged() {
        let abort = URLError(.notConnectedToInternet)
        ApproovService.setServiceMutator(Throwing(abort))
        let response = update()
        XCTAssertEqual(response.decision, .ShouldFail)
        XCTAssertEqual(response.error as? URLError, abort)
        XCTAssertThrowsError(try ApproovService.signRequest(URLRequest(url: targetURL))) { error in
            XCTAssertEqual(error as? URLError, abort)
        }
    }

    func testAnyOtherHookErrorIsAURLErrorNamingTheHook() throws {
        for thrown in [AppError() as Error, ApproovError.permanentError(message: "app's own")] {
            ApproovService.setServiceMutator(Throwing(thrown))
            let response = update()
            XCTAssertEqual(response.decision, .ShouldFail)
            let error = try XCTUnwrap(response.error as? URLError, "\(String(describing: response.error))")
            XCTAssertEqual(error.code, .unknown)
            XCTAssertTrue(error.localizedDescription.contains("handleInterceptorFetchTokenResult"), error.localizedDescription)
            XCTAssertNotNil(error.userInfo[NSUnderlyingErrorKey], "the original is not underlying")
        }
        lock.lock(); let lines = errorLines; lock.unlock()
        XCTAssertEqual(lines.filter { $0.contains("handleInterceptorFetchTokenResult") }.count, 2, "\(lines)")
    }

    func testAStandardDecisionKeepsItsApproovError() {
        // a custom mutator that delegates to CLOSE_FAILURE makes the standard decision
        final class Delegating: ApproovServiceMutator {
            func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult,
                                                   url: String) throws -> Bool {
                return try ApproovCloseFailureMutator.CLOSE_FAILURE.handleInterceptorFetchTokenResult(approovResults, url: url)
            }
        }
        for mutator in [ApproovCloseFailureMutator.CLOSE_FAILURE, Delegating()] as [ApproovServiceMutator] {
            ApproovService.setServiceMutator(mutator)
            MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
                "{\"operation\": \"fetchApproovToken\", \"response\": {\"status\": \"NO_NETWORK\"}}")
            let response = update()
            XCTAssertEqual(response.decision, .ShouldRetry, String(describing: mutator))
            guard case .networkingError? = response.error as? ApproovError else {
                return XCTFail("\(mutator): \(String(describing: response.error))")
            }
        }
    }

    func testARequiredBodyDigestFailureIsAURLError() throws {
        let factory = try ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setBodyDigestConfig(ApproovDefaultMessageSigning.DIGEST_SHA256, required: true)
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(factory))
        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.httpBodyStream = InputStream(data: Data("streamed".utf8))
        let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        XCTAssertEqual(response.decision, .ShouldFail)
        let error = try XCTUnwrap(response.error as? URLError, "\(String(describing: response.error))")
        XCTAssertTrue(error.localizedDescription.contains("Failed to create required body digest"), error.localizedDescription)
    }

    // the app's session delegate, recording whether it was told the session became invalid
    private final class SessionDelegate: NSObject, URLSessionDataDelegate {
        var invalidated = false
        var completed: XCTestExpectation?
        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
            invalidated = true
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            completed?.fulfill()
        }
    }

    func testAFailedTaskDoesNotInvalidateTheSession() {
        let delegate = SessionDelegate()
        delegate.completed = expectation(description: "task completed")
        let session = ApproovURLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            "{\"operation\": \"fetchApproovToken\", \"response\": {\"status\": \"REJECTED\"}}")
        session.dataTask(with: targetURL).resume()
        wait(for: [delegate.completed!], timeout: 20)
        XCTAssertFalse(delegate.invalidated, "one failed request told the app its session became invalid")
    }

    @available(iOS 13.0, *)
    func testAFailedPublisherLeavesTheOtherTasksAlone() {
        let delegate = SessionDelegate()
        let session = ApproovURLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let other = session.dataTask(with: targetURL)
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            "{\"operation\": \"fetchApproovToken\", \"response\": {\"status\": \"REJECTED\"}}")
        let (_, error) = session.dataTaskPublisherWithApproov(for: URLRequest(url: targetURL))
        XCTAssertNotNil(error)
        let settled = expectation(description: "cancellation would have reached the other task")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 5)
        XCTAssertNotEqual(other.state, .canceling, "the failure cancelled an unrelated task")
        XCTAssertNotEqual(other.state, .completed, "the failure cancelled an unrelated task")
        XCTAssertFalse(delegate.invalidated, "one failed request told the app its session became invalid")
        other.cancel()
    }
}
