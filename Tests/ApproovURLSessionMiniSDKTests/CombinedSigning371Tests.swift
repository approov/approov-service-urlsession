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

/// The signer under the decisions of another mutator. The signer makes the given mutator's decisions at
/// every hook and signs the request that mutator processed, so a change it makes is covered by the
/// signature. init() is unchanged: it makes the CLOSE_FAILURE decisions.
final class CombinedSigning371Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var base: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: validInitialConfig, comment: nil)
    }

    override func tearDown() {
        ApproovService.setServiceMutator(nil)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    // MARK: helpers

    private func factory() -> SignatureParametersFactory {
        return ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory().addOptionalHeaders(["X-Mutator"])
    }

    private func signer(_ decisions: ApproovServiceMutator) -> ApproovDefaultMessageSigning {
        return ApproovDefaultMessageSigning(decisions: decisions).setDefaultFactory(factory())
    }

    private func directive(_ operation: String, _ status: String) {
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            "{\"operation\": \"\(operation)\", \"response\": {\"status\": \"\(status)\", \"token\": \"\"}}")
    }

    private func update(_ url: String) throws -> ApproovUpdateResponse {
        return ApproovService.updateRequestWithApproov(request: URLRequest(url: try XCTUnwrap(URL(string: url))), sessionConfig: nil)
    }

    // the update of one request after a token fetch with the given status, or a normal fetch if it is nil
    private func update(_ url: String, tokenStatus: String?) throws -> ApproovUpdateResponse {
        if let tokenStatus {
            directive("fetchApproovToken", tokenStatus)
        }
        return try update(url)
    }

    // the members of a Signature or Signature-Input dictionary, in order, with their values as sent
    private func members(_ header: String?) -> [(String, String)] {
        guard let header else { return [] }
        var result: [(String, String)] = []
        var depth = 0, start = header.startIndex
        for index in header.indices {
            let c = header[index]
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            if c == "," && depth == 0 {
                result.append(split(String(header[start..<index])))
                start = header.index(after: index)
            }
        }
        result.append(split(String(header[start...])))
        return result
    }

    private func split(_ member: String) -> (String, String) {
        let trimmed = member.trimmingCharacters(in: .whitespaces)
        let equals = trimmed.firstIndex(of: "=")!
        return (String(trimmed[..<equals]), String(trimmed[trimmed.index(after: equals)...]))
    }

    private func memberNames(_ request: URLRequest) -> [String] {
        return members(request.value(forHTTPHeaderField: "Signature")).map { $0.0 }
    }

    // a mutator that marks the request it processed, and that can also add a query parameter to it
    private final class Marking: ApproovServiceMutator {
        private let lock = NSLock()
        private var count = 0
        private let addQuery: Bool
        init(addQuery: Bool = false) { self.addQuery = addQuery }
        var calls: Int { lock.lock(); defer { lock.unlock() }; return count }

        func handleInterceptorProcessedRequest(_ request: URLRequest, changes: ApproovRequestMutations) throws -> URLRequest {
            lock.lock(); count += 1; lock.unlock()
            var marked = request
            marked.setValue("marked", forHTTPHeaderField: "X-Mutator")
            if addQuery, let url = request.url?.absoluteString {
                marked.url = URL(string: url + (url.contains("?") ? "&" : "?") + "by=delegate")
            }
            return marked
        }
    }

    // a mutator that records each decision it is asked for. Each decision differs from the CLOSE_FAILURE
    // one, so its result shows that the decision was made here
    private final class Recording: ApproovServiceMutator, CustomStringConvertible {
        private let lock = NSLock()
        private var log: [String] = []
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return log }
        var description: String { return "Recording" }

        private func record(_ call: String) {
            lock.lock(); log.append(call); lock.unlock()
        }

        func handlePrecheckResult(_ approovResults: ApproovTokenFetchResult) throws {
            record("handlePrecheckResult:" + ApproovService.statusName(approovResults.status))
        }

        func handleFetchTokenResult(_ approovResults: ApproovTokenFetchResult) throws {
            record("handleFetchTokenResult:" + ApproovService.statusName(approovResults.status))
        }

        func handleFetchSecureStringResult(_ approovResults: ApproovTokenFetchResult, operation: String, key: String) throws {
            record("handleFetchSecureStringResult:\(operation):\(key):" + ApproovService.statusName(approovResults.status))
        }

        func handleFetchCustomJWTResult(_ approovResults: ApproovTokenFetchResult) throws {
            record("handleFetchCustomJWTResult:" + ApproovService.statusName(approovResults.status))
        }

        func handleInterceptorShouldProcessRequest(_ request: URLRequest) throws -> Bool {
            record("handleInterceptorShouldProcessRequest:" + (request.url?.path ?? ""))
            return request.url?.path != "/skip"
        }

        func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult, url: String) throws -> Bool {
            record("handleInterceptorFetchTokenResult:" + ApproovService.statusName(approovResults.status))
            return true
        }

        func handleInterceptorHeaderSubstitutionResult(_ approovResults: ApproovTokenFetchResult, header: String) throws -> Bool {
            record("handleInterceptorHeaderSubstitutionResult:" + header)
            return false
        }

        func handleInterceptorQueryParamSubstitutionResult(_ approovResults: ApproovTokenFetchResult, queryKey: String) throws -> Bool {
            record("handleInterceptorQueryParamSubstitutionResult:" + queryKey)
            return true
        }

        func handleInterceptorProcessedRequest(_ request: URLRequest, changes: ApproovRequestMutations) throws -> URLRequest {
            record("handleInterceptorProcessedRequest")
            var recorded = request
            recorded.setValue("recorded", forHTTPHeaderField: "X-Mutator")
            return recorded
        }

        func handlePinningShouldProcessRequest(_ request: URLRequest) -> Bool {
            record("handlePinningShouldProcessRequest")
            return false
        }
    }

    // MARK: each decision hook

    func testEachDecisionHookIsDelegated() throws {
        let recording = Recording()
        let signing = signer(recording)
        ApproovService.setServiceMutator(signing)

        // the direct methods: a REJECTED result does not throw, as the delegate decides
        directive("fetchSecureString", "REJECTED")
        XCTAssertNoThrow(try ApproovService.precheck())
        directive("fetchApproovToken", "REJECTED")
        XCTAssertNoThrow(try ApproovService.fetchToken(url: base + "/direct"))
        directive("fetchSecureString", "REJECTED")
        XCTAssertNoThrow(try ApproovService.fetchSecureString(key: "some-key", newDef: nil))
        directive("fetchCustomJWT", "REJECTED")
        XCTAssertNoThrow(try ApproovService.fetchCustomJWT(payload: "{\"a\":1}"))

        // connection checks: the delegate turns them off
        XCTAssertFalse(signing.handlePinningShouldProcessRequest(URLRequest(url: try XCTUnwrap(URL(string: base)))))

        // the interceptor: the delegate declines the header substitution and accepts the query one
        _ = try ApproovService.fetchSecureString(key: "own-key", newDef: "secret-value")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        ApproovService.addSubstitutionQueryParam(key: "k")
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/a?k=own-key")))
        request.setValue("own-key", forHTTPHeaderField: "Api-Key")
        let processed = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        XCTAssertEqual(processed.decision, .ShouldProceed, String(describing: processed.error))
        XCTAssertEqual(processed.request.value(forHTTPHeaderField: "Api-Key"), "own-key", "the declined substitution was made")
        XCTAssertEqual(processed.request.url?.absoluteString, base + "/a?k=secret-value")
        XCTAssertEqual(processed.request.value(forHTTPHeaderField: "X-Mutator"), "recorded")
        XCTAssertTrue(processed.request.value(forHTTPHeaderField: "Signature-Input")?.contains("\"x-mutator\"") ?? false)

        // a REJECTED token fetch proceeds, signed, as the delegate decides
        let rejected = try update(base + "/b", tokenStatus: "REJECTED")
        XCTAssertEqual(rejected.decision, .ShouldProceed, String(describing: rejected.error))
        XCTAssertEqual(memberNames(rejected.request), ["install"])

        // a request the delegate does not process gets nothing
        let skipped = try update(base + "/skip")
        XCTAssertEqual(skipped.decision, .ShouldIgnore)
        XCTAssertNil(skipped.request.value(forHTTPHeaderField: "Approov-Token"))

        let calls = recording.calls
        for expected in ["handlePrecheckResult:REJECTED",
                         "handleFetchTokenResult:REJECTED",
                         "handleFetchSecureStringResult:lookup:some-key:REJECTED",
                         "handleFetchCustomJWTResult:REJECTED",
                         "handlePinningShouldProcessRequest",
                         "handleFetchSecureStringResult:definition:own-key:SUCCESS",
                         "handleInterceptorShouldProcessRequest:/a",
                         "handleInterceptorFetchTokenResult:SUCCESS",
                         "handleInterceptorHeaderSubstitutionResult:Api-Key",
                         "handleInterceptorQueryParamSubstitutionResult:k",
                         "handleInterceptorProcessedRequest",
                         "handleInterceptorFetchTokenResult:REJECTED",
                         "handleInterceptorShouldProcessRequest:/skip"] {
            XCTAssertTrue(calls.contains(expected), "\(expected) was not delegated: \(calls)")
        }
    }


    // MARK: the delegate's processed request

    func testTheDelegatesProcessedRequestRunsFirstAndIsSigned() throws {
        let marking = Marking(addQuery: true)
        ApproovService.setServiceMutator(signer(marking))
        let response = try update(base + "/a?k=v")
        XCTAssertEqual(response.decision, .ShouldProceed, String(describing: response.error))
        XCTAssertEqual(marking.calls, 1)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "X-Mutator"), "marked")
        XCTAssertEqual(response.request.url?.absoluteString, base + "/a?k=v&by=delegate")
        let input = try XCTUnwrap(response.request.value(forHTTPHeaderField: "Signature-Input"))
        XCTAssertTrue(input.contains("\"x-mutator\""), "the delegate's header is not covered: \(input)")
        XCTAssertEqual(memberNames(response.request), ["install"])
    }

    // MARK: CLOSE_FAILURE and init()

    func testInitStillMakesTheCloseFailureDecisions() throws {
        XCTAssertEqual(String(describing: ApproovDefaultMessageSigning()), "ApproovDefaultMessageSigning")
        for status in ["NO_APPROOV_SERVICE", "NO_NETWORK", "REJECTED", "UNKNOWN_URL"] {
            ApproovService.setServiceMutator(.CLOSE_FAILURE)
            let expected = try update(base + "/a", tokenStatus: status)
            ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(factory()))
            let actual = try update(base + "/a", tokenStatus: status)
            XCTAssertEqual(actual.decision, expected.decision, status)
            XCTAssertEqual(String(reflecting: actual.error), String(reflecting: expected.error), status)
            XCTAssertEqual(actual.request.value(forHTTPHeaderField: "Approov-Token"),
                           expected.request.value(forHTTPHeaderField: "Approov-Token"), status)
        }
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(factory()))
        XCTAssertEqual(memberNames(try update(base + "/a").request), ["install"])
    }
}
