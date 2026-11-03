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
import Approov
@testable import ApproovURLSessionPackage
import MiniSDKTestSupport

/// How a request is classified from its token fetch and the pin set, and what it then carries. A
/// failure for a host that is not listed goes out untouched under the standard mutators. Secure
/// strings go only to a protected channel (SUCCESS or UNPROTECTED_URL, over https); a failed fetch
/// writes its status into the placeholder; a value the stack cannot carry keeps the placeholder with a
/// warning; every query occurrence is looked up on its own and nothing else in the URL changes.
final class Classification370Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var base: String!
    private var warnings: [String] = []
    private let lock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.warning)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-classification")
        ApproovService.logSink = { [weak self] level, line in
            guard let self, level == .warning else { return }
            self.lock.lock(); self.warnings.append(line); self.lock.unlock()
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

    private func nextToken(_ status: String) {
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            "{\"operation\": \"fetchApproovToken\", \"response\": {\"status\": \"\(status)\", \"token\": \"\"}}")
    }

    private func define(_ key: String, _ value: String) throws {
        _ = try ApproovService.fetchSecureString(key: key, newDef: value)
    }

    private func update(_ request: URLRequest) -> ApproovUpdateResponse {
        MiniSDKAttesterProxyController.clearCallLog()
        return ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
    }

    private func request(_ url: String, header: String? = nil, value: String? = nil) throws -> URLRequest {
        var request = URLRequest(url: try XCTUnwrap(URL(string: url)))
        if let header { request.setValue(value, forHTTPHeaderField: header) }
        return request
    }

    private func secureStringFetches() -> [String] {
        return MiniSDKAttesterProxyController.callLog().filter { $0.hasPrefix("fetchSecureStringAndWait:") }
    }

    private func warned(_ text: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return warnings.contains { $0.contains(text) }
    }

    // MARK: listed hosts

    func testAFailureForAnUnlistedHostGoesOutUntouched() throws {
        let original = try request("https://unlisted.example.com/a")
        for mutator in [ApproovCloseFailureMutator.CLOSE_FAILURE, ApproovAlwaysProceedMutator.ALWAYS_PROCEED] as [ApproovServiceMutator] {
            ApproovService.setServiceMutator(mutator)
            nextToken("NO_NETWORK")
            let response = update(original)
            XCTAssertEqual(response.decision, .ShouldProceed, String(describing: mutator))
            XCTAssertNil(response.request.value(forHTTPHeaderField: "Approov-Token"), String(describing: mutator))
            XCTAssertEqual(response.request, original)
        }
    }

    func testACustomMutatorMayAbortAnUnlistedHost() throws {
        final class OwnHostsOnly: ApproovServiceMutator {
            func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult, url: String) throws -> Bool {
                if approovResults.status == .noNetwork { throw URLError(.notConnectedToInternet) }
                return true
            }
        }
        ApproovService.setServiceMutator(OwnHostsOnly())
        nextToken("NO_NETWORK")
        let response = update(try request("https://unlisted.example.com/a"))
        XCTAssertEqual(response.decision, .ShouldFail)
        XCTAssertEqual((response.error as? URLError)?.code, .notConnectedToInternet)
    }

    func testEveryHostIsUnlistedWhileThePinsCannotBeRead() throws {
        MiniSDKAttesterProxyController.setPinsUnavailable(true)
        nextToken("NO_NETWORK")
        let response = update(try request(base + "/a"))
        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertNil(response.request.value(forHTTPHeaderField: "Approov-Token"))
    }

    func testAListedHostIsMatchedWithoutCaseOrTrailingDot() throws {
        let host = try XCTUnwrap(URL(string: base)?.host)
        nextToken("NO_NETWORK")
        let response = update(try request("https://" + host.uppercased() + "./a"))
        XCTAssertEqual(response.decision, .ShouldRetry, "a listed host is decided by the mutator")
    }

    // MARK: protected channels

    func testAFailureCarriesNoSecureString() throws {
        ApproovService.setServiceMutator(.ALWAYS_PROCEED)
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        nextToken("REJECTED")
        let response = update(try request(base + "/a", header: "Api-Key", value: "api-key"))
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Api-Key"), "api-key", "no status for no fetch")
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Approov-Token"), "")
        XCTAssertEqual(secureStringFetches(), [])
    }

    func testASecretsOnlyAPIGetsItsSecureStringsAndNoToken() throws {
        try define("own-key", "secret-value")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        nextToken("UNPROTECTED_URL")
        let response = update(try request(base + "/a", header: "Api-Key", value: "own-key"))
        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Api-Key"), "secret-value")
        XCTAssertNil(response.request.value(forHTTPHeaderField: "Approov-Token"))
    }

    func testCleartextGetsNoSecureStringAndAWarning() throws {
        ApproovService.setServiceMutator(.ALWAYS_PROCEED)
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        let cleartext = base.replacingOccurrences(of: "https://", with: "http://") + "/a"
        let response = update(try request(cleartext, header: "Api-Key", value: "api-key"))
        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Api-Key"), "api-key")
        XCTAssertEqual(secureStringFetches(), [])
        XCTAssertTrue(warned("Api-Key"), "no warning: \(warnings)")
    }

    // MARK: secure string outcomes

    func testAFailedFetchWritesItsStatusAfterThePrefix() throws {
        ApproovService.addSubstitutionHeader(header: "Authorization", prefix: "Bearer ")
        var recorded: [String] = ["unset"]
        final class Recorder: ApproovServiceMutator {
            var onChanges: (([String]) -> Void)?
            func handleInterceptorProcessedRequest(_ request: URLRequest, changes: ApproovRequestMutations) throws -> URLRequest {
                onChanges?(changes.getSubstitutionHeaderKeys())
                return request
            }
        }
        let recorder = Recorder()
        recorder.onChanges = { recorded = $0 }
        ApproovService.setServiceMutator(recorder)
        let response = update(try request(base + "/a", header: "Authorization", value: "Bearer missing-key"))
        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Authorization"), "Bearer UNKNOWN_KEY")
        XCTAssertEqual(recorded, [], "a written status is not a substitution")
    }

    func testAValueAHeaderCannotCarryKeepsThePlaceholder() throws {
        try define("own-key", "line\r\nbreak")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        let response = update(try request(base + "/a", header: "Api-Key", value: "own-key"))
        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Api-Key"), "own-key")
        XCTAssertTrue(warned("Api-Key"), "no warning: \(warnings)")
        XCTAssertFalse(warnings.contains { $0.contains("break") }, "the value was logged")
    }

    func testEveryQueryOccurrenceHasItsOwnOutcome() throws {
        try define("key1", "s3cret+1")
        ApproovService.addSubstitutionQueryParam(key: "k")
        let response = update(try request(base + "/a?z=%2F&k=key1&other=1&k=missing#frag"))
        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.url?.absoluteString, base + "/a?z=%2F&k=s3cret+1&other=1&k=UNKNOWN_KEY#frag")
    }

    func testAQueryKeyIsALiteralNotAPattern() throws {
        ApproovService.addSubstitutionQueryParam(key: "a(")
        ApproovService.addSubstitutionQueryParam(key: "k.y")
        let response = update(try request(base + "/a?kxy=keep&a(=missing"))
        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.url?.absoluteString, base + "/a?kxy=keep&a(=UNKNOWN_KEY")
    }

    func testAValueAQueryCannotCarryKeepsThePlaceholder() throws {
        try define("key1", "a&b=c")
        ApproovService.addSubstitutionQueryParam(key: "k")
        let response = update(try request(base + "/a?k=key1"))
        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.url?.absoluteString, base + "/a?k=key1")
        XCTAssertTrue(warned("k"), "no warning: \(warnings)")
    }

    func testATokenAHeaderCannotCarryIsAnSDKProblem() throws {
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            "{\"operation\": \"fetchApproovToken\", \"response\": {\"status\": \"SUCCESS\", \"token\": \"bad\\r\\ntoken\"}}")
        let response = update(try request(base + "/a"))
        XCTAssertEqual(response.decision, .ShouldFail)
        let message = (response.error as? URLError)?.localizedDescription ?? ""
        XCTAssertTrue(message.contains("Approov-Token") && message.contains("SDK token"), message)
        XCTAssertFalse(message.contains("bad"), "the value was quoted")
    }
}
