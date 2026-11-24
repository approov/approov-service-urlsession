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
import CryptoKit
import Approov
@testable import ApproovURLSessionPackage
import MiniSDKTestSupport

/// The signer under the decisions of another mutator. ApproovDefaultMessageSigning(decisions:) makes the
/// given mutator's decisions at every hook and signs the request that mutator processed, so a change it
/// makes is covered by the signature. A standard decision keeps its ApproovError. init() is unchanged:
/// it makes the CLOSE_FAILURE decisions.
final class SigningDecisions371Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var base: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-signing-decisions")
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

    // checks that the install signature verifies over the components its Signature-Input names, each
    // read from the request as sent: method, URL and headers are given by the caller
    private func assertInstallSignatureVerifies(method: String, url: String, header: (String) -> String?,
                                                signature: String?, signatureInput: String?,
                                                file: StaticString = #filePath, line: UInt = #line) throws {
        let input = try XCTUnwrap(members(signatureInput).first { $0.0 == "install" }, file: file, line: line).1
        let list = try XCTUnwrap(input.split(separator: ")").first, file: file, line: line).dropFirst()
        var lines: [String] = []
        for component in list.split(separator: " ").map({ String($0.dropFirst().dropLast()) }) {
            switch component {
            case "@method":
                lines.append("\"@method\": \(method)")
            case "@target-uri":
                lines.append("\"@target-uri\": \(url.components(separatedBy: "#").first ?? url)")
            default:
                let value = try XCTUnwrap(header(component), "no \(component) on the request", file: file, line: line)
                lines.append("\"\(component)\": \(value)")
            }
        }
        lines.append("\"@signature-params\": \(input)")
        let signatureBase = lines.joined(separator: "\n")
        let value = try XCTUnwrap(members(signature).first { $0.0 == "install" }, file: file, line: line).1
        let raw = try XCTUnwrap(Data(base64Encoded: String(value.dropFirst().dropLast())), file: file, line: line)
        let key = try P256.Signing.PublicKey(derRepresentation: try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(Approov.getInstallPublicKey()))))
        let ecdsa = try P256.Signing.ECDSASignature(rawRepresentation: raw)
        XCTAssertTrue(key.isValidSignature(ecdsa, for: Data(signatureBase.utf8)), "the signature does not cover:\n\(signatureBase)",
                      file: file, line: line)
    }

    private func assertInstallSignatureVerifies(_ request: URLRequest, file: StaticString = #filePath, line: UInt = #line) throws {
        try assertInstallSignatureVerifies(method: request.httpMethod ?? "GET", url: try XCTUnwrap(request.url?.absoluteString),
                                           header: { request.value(forHTTPHeaderField: $0) },
                                           signature: request.value(forHTTPHeaderField: "Signature"),
                                           signatureInput: request.value(forHTTPHeaderField: "Signature-Input"),
                                           file: file, line: line)
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

    // a mutator of the app's own that makes the CLOSE_FAILURE token decision by calling it
    private final class DelegatingToCloseFailure: ApproovServiceMutator {
        func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult, url: String) throws -> Bool {
            return try ApproovCloseFailureMutator.CLOSE_FAILURE.handleInterceptorFetchTokenResult(approovResults, url: url)
        }
    }

    // a mutator of the app's own whose token decision throws an ApproovError of its own
    private final class ThrowingOwnError: ApproovServiceMutator {
        func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult, url: String) throws -> Bool {
            throw ApproovError.permanentError(message: "app's own")
        }
    }

    // MARK: ALWAYS_PROCEED and signing

    func testAlwaysProceedSignsANoNetworkTokenFetch() throws {
        ApproovService.setServiceMutator(signer(.ALWAYS_PROCEED))
        let response = try update(base + "/a", tokenStatus: "NO_NETWORK")
        XCTAssertEqual(response.decision, .ShouldProceed, String(describing: response.error))
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Approov-Token"), "", "the token header is not empty")
        XCTAssertEqual(memberNames(response.request), ["install"], "the request that proceeded is not signed")
        XCTAssertTrue(response.request.value(forHTTPHeaderField: "Signature-Input")?.contains("\"approov-token\"") ?? false,
                      "the signature does not cover the empty token header")
        try assertInstallSignatureVerifies(response.request)

        // the same request under init(), the CLOSE_FAILURE decisions, fails
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(factory()))
        XCTAssertEqual(try update(base + "/a", tokenStatus: "NO_NETWORK").decision, .ShouldRetry)
    }

    func testAlwaysProceedSignsEveryFailureStatus() throws {
        ApproovService.setServiceMutator(signer(.ALWAYS_PROCEED))
        for status in ["REJECTED", "MITM_DETECTED", "INTERNAL_ERROR", "NO_APPROOV_SERVICE"] {
            let response = try update(base + "/a", tokenStatus: status)
            XCTAssertEqual(response.decision, .ShouldProceed, status)
            XCTAssertEqual(response.request.value(forHTTPHeaderField: "Approov-Token"), "", status)
            XCTAssertEqual(memberNames(response.request), ["install"], status)
        }
    }

    // MARK: CLOSE_FAILURE and init()

    func testCloseFailureDecisionsMatchInit() throws {
        let statuses: [String?] = [nil, "NO_APPROOV_SERVICE", "NO_NETWORK", "POOR_NETWORK", "MITM_DETECTED", "REJECTED",
                                   "INTERNAL_ERROR", "UNKNOWN_URL", "UNPROTECTED_URL"]
        for useStatus in [false, true] {
            ApproovService.setUseApproovStatusIfNoToken(shouldUse: useStatus)
            for status in statuses {
                let label = "\(status ?? "SUCCESS") useStatus=\(useStatus)"
                ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(factory()))
                let expected = try update(base + "/a", tokenStatus: status)
                ApproovService.setServiceMutator(signer(.CLOSE_FAILURE))
                let actual = try update(base + "/a", tokenStatus: status)
                XCTAssertEqual(actual.decision, expected.decision, label)
                XCTAssertEqual(String(reflecting: actual.error), String(reflecting: expected.error), label)
                XCTAssertEqual(actual.request.value(forHTTPHeaderField: "Approov-Token") == nil,
                               expected.request.value(forHTTPHeaderField: "Approov-Token") == nil, label)
                if status != nil {
                    XCTAssertEqual(actual.request.value(forHTTPHeaderField: "Approov-Token"),
                                   expected.request.value(forHTTPHeaderField: "Approov-Token"), label)
                }
                XCTAssertEqual(memberNames(actual.request), memberNames(expected.request), label)
            }
        }
        ApproovService.setUseApproovStatusIfNoToken(shouldUse: false)

        // the direct methods throw the same errors
        let direct: [(String, () throws -> Void)] = [
            ("fetchSecureString", { try ApproovService.precheck() }),
            ("fetchApproovToken", { _ = try ApproovService.fetchToken(url: self.base + "/a") }),
            ("fetchSecureString", { _ = try ApproovService.fetchSecureString(key: "some-key", newDef: nil) }),
            ("fetchCustomJWT", { _ = try ApproovService.fetchCustomJWT(payload: "{\"a\":1}") }),
        ]
        for (operation, call) in direct {
            var errors: [String] = []
            for mutator in [ApproovDefaultMessageSigning(), ApproovDefaultMessageSigning(decisions: .CLOSE_FAILURE)] {
                ApproovService.setServiceMutator(mutator)
                directive(operation, "REJECTED")
                XCTAssertThrowsError(try call(), operation) { errors.append(String(reflecting: $0)) }
            }
            XCTAssertEqual(errors.count, 2, operation)
            XCTAssertEqual(errors.first, errors.last, operation)
        }

        // and both apply connection checks to every request
        let request = URLRequest(url: try XCTUnwrap(URL(string: base)))
        XCTAssertTrue(ApproovDefaultMessageSigning().handlePinningShouldProcessRequest(request))
        XCTAssertTrue(ApproovDefaultMessageSigning(decisions: .CLOSE_FAILURE).handlePinningShouldProcessRequest(request))
    }

    func testInitIsUnchanged() throws {
        let plain = ApproovDefaultMessageSigning()
        XCTAssertEqual(String(describing: plain), "ApproovDefaultMessageSigning")
        // its decisions are the CLOSE_FAILURE ones, installed on their own
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
        // and it still signs
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(factory()))
        let signed = try update(base + "/a")
        XCTAssertEqual(memberNames(signed.request), ["install"])
        try assertInstallSignatureVerifies(signed.request)
    }

    func testTheDescriptionNamesTheDecisions() {
        XCTAssertEqual(String(describing: ApproovDefaultMessageSigning(decisions: .ALWAYS_PROCEED)),
                       "ApproovDefaultMessageSigning(ApproovServiceMutator.ALWAYS_PROCEED)")
        XCTAssertEqual(String(describing: ApproovDefaultMessageSigning(decisions: .CLOSE_FAILURE)),
                       "ApproovDefaultMessageSigning(ApproovServiceMutator.CLOSE_FAILURE)")
        XCTAssertEqual(String(describing: ApproovDefaultMessageSigning(decisions: Recording())),
                       "ApproovDefaultMessageSigning(Recording)")
        // the factory setters keep the description
        ApproovService.setServiceMutator(signer(.ALWAYS_PROCEED))
        XCTAssertEqual(String(describing: ApproovService.getServiceMutator()),
                       "ApproovDefaultMessageSigning(ApproovServiceMutator.ALWAYS_PROCEED)")
    }

    // MARK: the delegate's processed request

    func testTheDelegatesProcessedRequestChangeIsSigned() throws {
        let marking = Marking(addQuery: true)
        ApproovService.setServiceMutator(signer(marking))
        let response = try update(base + "/a?k=v")
        XCTAssertEqual(response.decision, .ShouldProceed, String(describing: response.error))
        XCTAssertEqual(marking.calls, 1)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "X-Mutator"), "marked")
        XCTAssertEqual(response.request.url?.absoluteString, base + "/a?k=v&by=delegate")
        let input = try XCTUnwrap(response.request.value(forHTTPHeaderField: "Signature-Input"))
        XCTAssertTrue(input.contains("\"x-mutator\""), "the delegate's header is not covered: \(input)")
        // the signature verifies over the URL and header as the delegate left them
        try assertInstallSignatureVerifies(response.request)
    }

    func testASameOriginRedirectIsSignedAgain() throws {
        let marking = Marking()
        ApproovService.setServiceMutator(signer(marking))
        let target = base + "/after-redirect"
        let encoded = try XCTUnwrap(target.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let request = URLRequest(url: try XCTUnwrap(URL(string: base + "/redirect-to?url=\(encoded)&status=302")))
        MiniSDKAttesterProxyController.clearCallLog()

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
        XCTAssertEqual(json["url"] as? String, target)
        XCTAssertEqual(marking.calls, 2, "the delegate did not process the follow-up")
        XCTAssertEqual(headers["x-mutator"], "marked")
        XCTAssertEqual(members(headers["signature"]).map { $0.0 }, ["install"], "the follow-up is not signed")
        XCTAssertTrue(headers["signature-input"]?.contains("\"x-mutator\"") ?? false, headers["signature-input"] ?? "none")
        let fetches = MiniSDKAttesterProxyController.callLog().filter { $0.hasPrefix("fetchApproovTokenAndWait:") }
        XCTAssertEqual(fetches.last, "fetchApproovTokenAndWait:" + target, "no token was fetched for the target")
        // the follow-up's signature verifies over the target URL
        try assertInstallSignatureVerifies(method: json["method"] as? String ?? "", url: target, header: { headers[$0] },
                                           signature: headers["signature"], signatureInput: headers["signature-input"])
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

    // MARK: the error form of a standard decision

    func testAStandardDecisionThroughTheDelegateKeepsItsForm() throws {
        for status in ["NO_NETWORK", "REJECTED", "INTERNAL_ERROR"] {
            ApproovService.setServiceMutator(.CLOSE_FAILURE)
            let expected = try update(base + "/a", tokenStatus: status)
            for decisions in [ApproovCloseFailureMutator.CLOSE_FAILURE, DelegatingToCloseFailure()] as [ApproovServiceMutator] {
                let label = "\(status) \(decisions)"
                ApproovService.setServiceMutator(signer(decisions))
                let actual = try update(base + "/a", tokenStatus: status)
                XCTAssertEqual(actual.decision, expected.decision, label)
                XCTAssertNotNil(actual.error as? ApproovError, "\(label): \(String(describing: actual.error))")
                XCTAssertNil(actual.error as? URLError, "\(label): wrapped as a hook failure")
                XCTAssertEqual(String(reflecting: actual.error), String(reflecting: expected.error), label)
            }
        }
        ApproovService.setServiceMutator(signer(.CLOSE_FAILURE))
        directive("fetchApproovToken", "NO_NETWORK")
        let retry = try update(base + "/a")
        XCTAssertEqual(retry.decision, .ShouldRetry)
        guard case .networkingError(let message)? = retry.error as? ApproovError else {
            return XCTFail(String(describing: retry.error))
        }
        XCTAssertEqual(message, "Approov token fetch for \(base!)/a: NO_NETWORK")

        // signRequest throws the same ApproovError
        directive("fetchApproovToken", "REJECTED")
        XCTAssertThrowsError(try ApproovService.signRequest(URLRequest(url: try XCTUnwrap(URL(string: base + "/a"))))) { error in
            guard case .permanentError? = error as? ApproovError else {
                return XCTFail("\(error)")
            }
        }
    }

    func testAStandardDecisionThroughTheDelegateReachesTheApp() throws {
        var errors: [String] = []
        for mutator in [ApproovCloseFailureMutator.CLOSE_FAILURE, signer(.CLOSE_FAILURE)] as [ApproovServiceMutator] {
            ApproovService.setServiceMutator(mutator)
            directive("fetchApproovToken", "REJECTED")
            let session = ApproovURLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let done = expectation(description: "request")
            var failure: Error?
            session.dataTask(with: try XCTUnwrap(URL(string: base + "/a"))) { _, _, error in
                failure = error
                done.fulfill()
            }.resume()
            wait(for: [done], timeout: 20)
            XCTAssertNotNil(failure as? ApproovError, "\(mutator): \(String(describing: failure))")
            errors.append(String(reflecting: failure))
        }
        XCTAssertEqual(errors.first, errors.last)
    }

    func testTheAppsOwnErrorThroughTheDelegateIsAHookFailure() throws {
        ApproovService.setServiceMutator(ThrowingOwnError())
        let expected = try update(base + "/a")
        ApproovService.setServiceMutator(signer(ThrowingOwnError()))
        let actual = try update(base + "/a")
        XCTAssertEqual(actual.decision, .ShouldFail)
        let error = try XCTUnwrap(actual.error as? URLError, String(describing: actual.error))
        XCTAssertEqual(error.code, .unknown)
        XCTAssertTrue(error.localizedDescription.contains("handleInterceptorFetchTokenResult"), error.localizedDescription)
        XCTAssertEqual(error.localizedDescription, (expected.error as? URLError)?.localizedDescription)
    }
}
