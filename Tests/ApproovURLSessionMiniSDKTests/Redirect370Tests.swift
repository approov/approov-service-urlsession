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
@testable import ApproovURLSessionPackage
import MiniSDKTestSupport

/// Redirects and re-sent requests. On every redirect the layer strips what it added, restoring a
/// substituted header to the app's placeholder if it still holds the installed value, and then treats
/// the follow-up as a brand-new request for its target. A request the layer already protected, sent
/// again, is stripped the same way before it is protected afresh.
final class Redirect370Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var base: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-redirect")
        _ = try ApproovService.fetchSecureString(key: "own-key", newDef: "secret-value")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning()
            .setDefaultFactory(ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
        MiniSDKAttesterProxyController.clearCallLog()
    }

    override func tearDown() {
        ApproovService.setServiceMutator(nil)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    private func redirect(to target: String, status: Int, method: String = "GET") throws -> URLRequest {
        let encoded = try XCTUnwrap(target.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/redirect-to?url=\(encoded)&status=\(status)")))
        request.httpMethod = method
        request.setValue("own-key", forHTTPHeaderField: "Api-Key")
        return request
    }

    // sends a request and returns the echo of the last hop: its headers, lower-cased, URL and method
    private func send(_ request: URLRequest) throws -> (headers: [String: String], url: String, method: String) {
        let session = ApproovURLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let done = expectation(description: "request")
        var body: Data?
        var failure: Error?
        session.dataTask(with: request) { data, _, error in
            body = data
            failure = error
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        XCTAssertNil(failure)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(body)) as? [String: Any])
        let headers = (json["headers"] as? [String: String]) ?? [:]
        return (headers, json["url"] as? String ?? "", json["method"] as? String ?? "")
    }

    // the host of an echo endpoint from the environment, or a skip when it is not set
    private func host(_ variable: String) throws -> String {
        guard let url = ProcessInfo.processInfo.environment[variable].flatMap({ URL(string: $0) }), let host = url.host else {
            throw XCTSkip("\(variable) is not set")
        }
        return host
    }

    func testARedirectToAHostNotAddedCarriesNothingTheLayerAdded() throws {
        let target = "https://\(try host("TESTING_REPLY_URL_UNPROTECTED"))/landing?k=v"
        let echo = try send(try redirect(to: target, status: 302))
        XCTAssertEqual(echo.url, target, "the target URL was rewritten")
        XCTAssertNil(echo.headers["approov-token"])
        XCTAssertNil(echo.headers["approov-traceid"])
        XCTAssertNil(echo.headers["signature"])
        XCTAssertNil(echo.headers["signature-input"])
        XCTAssertEqual(echo.headers["api-key"], "own-key", "the placeholder was not restored for a host not added to Approov")
    }

    func testARedirectToASecretsOnlyHostGetsItsSecretsAndNoToken() throws {
        let echo = try send(try redirect(to: "https://\(try host("TESTING_REPLY_URL_PINNING_ONLY"))/landing", status: 307))
        XCTAssertNil(echo.headers["approov-token"])
        XCTAssertNil(echo.headers["signature"])
        XCTAssertEqual(echo.headers["api-key"], "secret-value")
    }

    func testASameOriginRedirectIsProtectedAndSignedAfresh() throws {
        let target = base + "/after-redirect"
        let echo = try send(try redirect(to: target, status: 303, method: "POST"))
        XCTAssertEqual(echo.method, "GET")
        XCTAssertNotNil(echo.headers["approov-token"])
        XCTAssertNotNil(echo.headers["signature"])
        XCTAssertEqual(echo.headers["api-key"], "secret-value")
        let fetches = MiniSDKAttesterProxyController.callLog().filter { $0.hasPrefix("fetchApproovTokenAndWait:") }
        XCTAssertEqual(fetches.last, "fetchApproovTokenAndWait:" + target, "no token was fetched for the target")
        XCTAssertFalse(MiniSDKAttesterProxyController.callLog().contains("fetchSecureStringAndWait:secret-value"))
    }

    func testARequestSentAgainIsStrippedAndProtectedAfresh() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/a")))
        request.setValue("own-key", forHTTPHeaderField: "Api-Key")
        let first = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        XCTAssertEqual(first.request.value(forHTTPHeaderField: "Api-Key"), "secret-value")
        MiniSDKAttesterProxyController.clearCallLog()
        let again = ApproovService.updateRequestWithApproov(request: first.request, sessionConfig: nil)
        XCTAssertEqual(again.request.value(forHTTPHeaderField: "Api-Key"), "secret-value")
        XCTAssertEqual(MiniSDKAttesterProxyController.callLog().filter { $0.hasPrefix("fetchSecureStringAndWait:") },
                       ["fetchSecureStringAndWait:own-key"], "the secret was looked up as a key")
        XCTAssertNotEqual(again.request.value(forHTTPHeaderField: "Approov-Token"), first.request.value(forHTTPHeaderField: "Approov-Token"))
    }

    func testAHeaderTheAppChangedIsKept() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/a")))
        request.setValue("own-key", forHTTPHeaderField: "Api-Key")
        var protected = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil).request
        protected.setValue("another-key", forHTTPHeaderField: "Api-Key")
        let stripped = ApproovService.stripProtection(protected)
        XCTAssertEqual(stripped.value(forHTTPHeaderField: "Api-Key"), "another-key")
        XCTAssertNil(stripped.value(forHTTPHeaderField: "Approov-Token"))
        XCTAssertNil(stripped.value(forHTTPHeaderField: "Signature"))
    }

    func testASubstitutedQueryIsRestoredOnlyOnTheSameURL() throws {
        ApproovService.addSubstitutionQueryParam(key: "k")
        let request = URLRequest(url: try XCTUnwrap(URL(string: base + "/a?k=own-key")))
        let protected = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil).request
        XCTAssertEqual(protected.url?.absoluteString, base + "/a?k=secret-value")
        XCTAssertEqual(ApproovService.stripProtection(protected).url?.absoluteString, base + "/a?k=own-key")
        var moved = protected
        moved.url = URL(string: base + "/b?k=secret-value")
        XCTAssertEqual(ApproovService.stripProtection(moved).url?.absoluteString, base + "/b?k=secret-value",
                       "a URL the server sent was rewritten")
    }

    // the app's own delegate, which sees each redirect and follows it, adding a header of its own
    private final class RedirectingDelegate: NSObject, URLSessionDataDelegate {
        var seen: URLRequest?
        var body = Data()
        var done: XCTestExpectation?
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            seen = request
            var followed = request
            followed.setValue("app-value", forHTTPHeaderField: "X-App")
            completionHandler(followed)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            body.append(data)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            done?.fulfill()
        }
    }

    func testTheAppsRedirectDelegateSeesTheStrippedRequestAndItsChoiceIsProtected() throws {
        let delegate = RedirectingDelegate()
        delegate.done = expectation(description: "request")
        let session = ApproovURLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: try redirect(to: base + "/after-redirect", status: 302)).resume()
        wait(for: [delegate.done!], timeout: 20)
        let seen = try XCTUnwrap(delegate.seen)
        XCTAssertNil(seen.value(forHTTPHeaderField: "Approov-Token"), "the app's delegate saw the layer's token")
        XCTAssertEqual(seen.value(forHTTPHeaderField: "Api-Key"), "own-key", "the app's delegate saw the secret")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: delegate.body) as? [String: Any])
        let headers = (json["headers"] as? [String: String]) ?? [:]
        XCTAssertNotNil(headers["approov-token"])
        XCTAssertEqual(headers["api-key"], "secret-value")
        XCTAssertEqual(headers["x-app"], "app-value")
    }

    // a mutator that marks the request it processed, and on its first request installs another mutator,
    // as an app might while a request is in flight
    private final class Marking: ApproovServiceMutator {
        let mark: String
        var replacement: ApproovServiceMutator?
        init(_ mark: String, replacement: ApproovServiceMutator? = nil) {
            self.mark = mark
            self.replacement = replacement
        }
        func handleInterceptorProcessedRequest(_ request: URLRequest, changes: ApproovRequestMutations) throws -> URLRequest {
            var marked = request
            marked.setValue(mark, forHTTPHeaderField: "X-Mutator")
            if let next = replacement {
                replacement = nil
                ApproovService.setServiceMutator(next)
            }
            return marked
        }
    }

    func testARedirectIsProtectedWithTheMutatorTheRequestStartedWith() throws {
        ApproovService.setServiceMutator(Marking("first", replacement: Marking("second")))
        let echo = try send(try redirect(to: base + "/after-redirect", status: 302))
        XCTAssertEqual(echo.headers["x-mutator"], "first", "the redirect was decided by a mutator installed later")
        XCTAssertNotNil(echo.headers["approov-token"])
        // a request made after the change uses the new mutator
        let later = try send(URLRequest(url: try XCTUnwrap(URL(string: base + "/later"))))
        XCTAssertEqual(later.headers["x-mutator"], "second")
    }
}
