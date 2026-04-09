import XCTest
import Foundation
import Combine
import CryptoKit
@testable import ApproovURLSessionPackage
import Approov
import MiniSDKTestSupport

final class ApproovServiceMiniSDKTests: XCTestCase {
    private let validInitialConfig = "#cb-ivol#mAxOF0ekJUOC36J5XWmVmVipOcUoEdMjhPSp2FVtyTo="
    private var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try initializeService(comment: "reinit-urlsession-tests")
    }

    override func tearDown() {
        cancellables.removeAll()
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    func testInitializeIgnoresSameConfigAndRejectsDifferentConfig() throws {
        XCTAssertNoThrow(try ApproovService.initialize(config: validInitialConfig, comment: nil))

        let differentConfig = "#stg1006#aprv2stg-attest.api.approov.io#https://dev.approoval.com/token#dpcv6jv45r6LGC4E6ZXSMLhBVLrrhAoDcjizU/t9/Eg="
        XCTAssertThrowsError(try ApproovService.initialize(config: differentConfig, comment: nil)) { error in
            guard case let ApproovError.configurationError(message) = error else {
                return XCTFail("Expected configurationError, got \(error)")
            }
            XCTAssertEqual(message, "Attempting to initialize with a different configuration")
        }
    }

    func testPrecheckTreatsUnknownKeyAsSuccess() throws {
        XCTAssertNoThrow(try ApproovService.precheck())
    }

    func testGetDeviceIDReturnsMiniSDKDeviceID() {
        XCTAssertEqual(ApproovService.getDeviceID(), "daIvmEWBA2gvZny7a/RC/w==")
    }

    func testFetchTokenReturnsSignedTokenWithExpectedClaims() throws {
        try reinitializeServiceWithTargetHost()
        let token = try ApproovService.fetchToken(url: targetURLString)
        let payload = try XCTUnwrap(decodeJWTBody(token))

        XCTAssertEqual(payload["ip"] as? String, "81.149.55.236")
        XCTAssertEqual(payload["did"] as? String, "daIvmEWBA2gvZny7a/RC/w==")
        XCTAssertEqual(payload["mskid"] as? String, "j3AWy6")
        XCTAssertEqual(payload["arc"] as? String, "IXPSB7TRK26LXE3M")
        XCTAssertNotNil(payload["exp"] as? NSNumber)
    }

    func testFetchTokenThrowsNetworkingErrorForNoNetwork() throws {
        try reinitializeServiceWithTargetHost()
        setDirective(
            """
            {
              "operation": "fetchApproovToken",
              "response": {
                "status": "NO_NETWORK"
              }
            }
            """
        )

        XCTAssertThrowsError(try ApproovService.fetchToken(url: targetURLString)) { error in
            guard case let ApproovError.networkingError(message) = error else {
                return XCTFail("Expected networkingError, got \(error)")
            }
            XCTAssertEqual(message, "fetchToken network error: no network")
        }
    }

    func testFetchSecureStringReturnsConfiguredValue() throws {
        setDirective(
            """
            {
              "operation": "fetchSecureString",
              "response": {
                "status": "SUCCESS",
                "secureString": "mini-secret"
              }
            }
            """
        )

        let secureString = try ApproovService.fetchSecureString(key: "api-key", newDef: nil)
        XCTAssertEqual(secureString, "mini-secret")
    }

    func testFetchSecureStringReturnsNilForUnknownKey() throws {
        setDirective(
            """
            {
              "operation": "fetchSecureString",
              "response": {
                "status": "UNKNOWN_KEY"
              }
            }
            """
        )

        let secureString = try ApproovService.fetchSecureString(key: "missing-key", newDef: nil)
        XCTAssertNil(secureString)
    }

    func testFetchSecureStringEmptyKeyReturnsNil() throws {
        XCTAssertThrowsError(try ApproovService.fetchSecureString(key: "", newDef: nil)) { error in
            guard case let ApproovError.permanentError(message) = error else {
                return XCTFail("Expected permanentError, got \\(error)")
            }
            XCTAssertTrue(message.contains("bad key"), "Expected bad key message")
        }
    }

    func testFetchCustomJWTReturnsSignedJWT() throws {
        let jwt = try XCTUnwrap(ApproovService.fetchCustomJWT(payload: "{\"role\":\"tester\"}"))
        let payload = try XCTUnwrap(decodeJWTBody(jwt))

        XCTAssertEqual(payload["role"] as? String, "tester")
        XCTAssertNil(payload["exp"])
        XCTAssertNil(payload["did"])
    }

    struct CustomPayload: Codable {
        let data: String
    }

    func testFetchCustomJWT18KBPayload() throws {
        let largePayload = String(repeating: "A", count: 18 * 1024)
        let payloadStruct = CustomPayload(data: largePayload)
        
        let jsonData = try JSONEncoder().encode(payloadStruct)
        let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        
        let jwt = try XCTUnwrap(ApproovService.fetchCustomJWT(payload: json))
        let payloadMap = try XCTUnwrap(decodeJWTBody(jwt))
        XCTAssertEqual(payloadMap["data"] as? String, largePayload)
    }

    func testFetchCustomJWTDisabledRaisesPermanentError() throws {
        try reinitializeService(
            scenarioJSON: scenarioJSON(
                caseName: uniqueCaseName(prefix: "custom-jwt-disabled"),
                body: """
                "customJWTEnabled": false
                """
            ),
            comment: "reinit-custom-jwt-disabled"
        )

        XCTAssertThrowsError(try ApproovService.fetchCustomJWT(payload: "{\"role\":\"tester\"}")) { error in
            guard case let ApproovError.permanentError(message) = error else {
                return XCTFail("Expected permanentError, got \(error)")
            }
            XCTAssertEqual(message, "fetchCustomJWT: disabled")
        }
    }

    func testFetchCustomJWTBadPayloadRaisesPermanentError() {
        XCTAssertThrowsError(try ApproovService.fetchCustomJWT(payload: "not-json")) { error in
            guard case let ApproovError.permanentError(message) = error else {
                return XCTFail("Expected permanentError, got \(error)")
            }
            XCTAssertEqual(message, "fetchCustomJWT: bad payload")
        }
    }

    private var targetURLString: String {
        guard let url = ProcessInfo.processInfo.environment["TESTING_REPLY_URL"] else {
            fatalError("TESTING_REPLY_URL environment variable is not set")
        }
        return url
    }

    private var unprotectedURLString: String {
        guard let url = ProcessInfo.processInfo.environment["TESTING_REPLY_URL_UNPROTECTED"] else {
            fatalError("TESTING_REPLY_URL_UNPROTECTED environment variable is not set")
        }
        return url
    }

    private func fetchNetworkReply(for request: URLRequest) -> [String: Any]? {
        let expectation = self.expectation(description: "network request")
        var receivedData: Data?

        let configuration = URLSessionConfiguration.ephemeral
        let session = ApproovURLSession(configuration: configuration)
        let task = session.dataTask(with: request) { data, _, _ in
            receivedData = data
            expectation.fulfill()
        }
        task.resume()

        waitForExpectations(timeout: 5.0)

        guard let data = receivedData,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private func getHeader(from reply: [String: Any]?, key: String) -> String? {
        guard let headers = reply?["headers"] as? [String: Any] else { return nil }
        let lowerKey = key.lowercased()
        let val = headers[lowerKey] ?? headers[key]
        if let str = val as? String {
            return str
        }
        if let arr = val as? [String], let first = arr.first {
            return first
        }
        return nil
    }

    private func reinitializeServiceWithTargetHost(scenarioBody: String = "") throws {
        let targetHost = try XCTUnwrap(URL(string: targetURLString)?.host)
        let domainsJSON = "\"protectedDomains\": [\"\(targetHost)\"]"
        let fullBody = scenarioBody.isEmpty ? domainsJSON : "\(domainsJSON), \(scenarioBody)"

        try reinitializeService(
            scenarioJSON: scenarioJSON(
                caseName: uniqueCaseName(prefix: "target-host"),
                body: fullBody
            ),
            comment: "reinit-target-host"
        )
    }

    func testUpdateRequestAddsTokenTraceBindingHashAndSubstitutions() throws {
        let targetHost = try XCTUnwrap(URL(string: targetURLString)?.host)
        try reinitializeService(
            scenarioJSON: scenarioJSON(
                caseName: uniqueCaseName(prefix: "substitutions"),
                body: """
                "protectedDomains": ["\(targetHost)"],
                "initialSecureStrings": {
                  "header-key": "header-secret",
                  "query-key": "query-secret"
                }
                """
            ),
            comment: "reinit-substitutions"
        )

        ApproovService.setBindingHeader(header: "Authorization")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        ApproovService.addSubstitutionQueryParam(key: "api_key")

        var request = URLRequest(url: try XCTUnwrap(URL(string: "\(targetURLString)?api_key=query-key")))
        request.setValue("Bearer oauth-token", forHTTPHeaderField: "Authorization")
        request.setValue("header-key", forHTTPHeaderField: "Api-Key")

        let reply = fetchNetworkReply(for: request)

        let token = try XCTUnwrap(getHeader(from: reply, key: "Approov-Token"))
        XCTAssertFalse(token.isEmpty)
        XCTAssertNotNil(getHeader(from: reply, key: "Approov-TraceID"))
        XCTAssertEqual(getHeader(from: reply, key: "Api-Key"), "header-secret")

        let urlFromReply = try XCTUnwrap(reply?["url"] as? String)
        XCTAssertTrue(urlFromReply.contains("api_key=query-secret"))

        let payload = try XCTUnwrap(decodeJWTBody(token))
        XCTAssertEqual(payload["pay"] as? String, sha256Base64("Bearer oauth-token"))
    }

    func testUpdateRequestNoApproovServiceProceedsWithoutToken() throws {
        try reinitializeServiceWithTargetHost()
        setDirective(
            """
            {
              "operation": "fetchApproovToken",
              "response": {
                "status": "NO_APPROOV_SERVICE"
              }
            }
            """
        )

        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let reply = fetchNetworkReply(for: request)

        XCTAssertNotNil(reply, "Expected to receive a reply from worker when proceeding without token")
        XCTAssertNil(getHeader(from: reply, key: "Approov-Token"))
        XCTAssertNil(getHeader(from: reply, key: "Approov-TraceID"))
    }

    func testUpdateRequestInstallMessageSigningAddsSignatureHeaders() throws {
        try reinitializeServiceWithTargetHost()
        
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setUseInstallMessageSigning()
        let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)
        ApproovService.setServiceMutator(signer)

        var request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        request.httpMethod = "GET"
        let protectedReply = fetchNetworkReply(for: request)

        XCTAssertNotNil(getHeader(from: protectedReply, key: "Approov-Token"))
        let signatureInput = try XCTUnwrap(getHeader(from: protectedReply, key: "Signature-Input"))
        XCTAssertTrue(signatureInput.hasPrefix("install="))
        XCTAssertEqual(signatureInput.components(separatedBy: "install=").count, 2, "Should contain exactly one install signature input")
        XCTAssertFalse(signatureInput.contains("account="))
        
        let signature = try XCTUnwrap(getHeader(from: protectedReply, key: "Signature"))
        XCTAssertTrue(signature.hasPrefix("install="))
        XCTAssertEqual(signature.components(separatedBy: "install=").count, 2, "Should contain exactly one install signature")
        XCTAssertFalse(signature.contains("account="))
        
        var unprotectedRequest = URLRequest(url: try XCTUnwrap(URL(string: unprotectedURLString)))
        unprotectedRequest.httpMethod = "GET"
        let unprotectedReply = fetchNetworkReply(for: unprotectedRequest)
        
        XCTAssertNil(getHeader(from: unprotectedReply, key: "Approov-Token"))
        XCTAssertNil(getHeader(from: unprotectedReply, key: "Signature"))
        XCTAssertNil(getHeader(from: unprotectedReply, key: "Signature-Input"))
    }

    func testUpdateRequestAccountMessageSigningAddsSignatureHeaders() throws {
        try reinitializeServiceWithTargetHost()
        
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setUseAccountMessageSigning()
        let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)
        ApproovService.setServiceMutator(signer)

        var request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        request.httpMethod = "GET"
        let protectedReply = fetchNetworkReply(for: request)

        XCTAssertNotNil(getHeader(from: protectedReply, key: "Approov-Token"))
        let signatureInput = try XCTUnwrap(getHeader(from: protectedReply, key: "Signature-Input"))
        XCTAssertTrue(signatureInput.hasPrefix("account="))
        XCTAssertEqual(signatureInput.components(separatedBy: "account=").count, 2, "Should contain exactly one account signature input")
        XCTAssertFalse(signatureInput.contains("install="))
        
        let signature = try XCTUnwrap(getHeader(from: protectedReply, key: "Signature"))
        XCTAssertTrue(signature.hasPrefix("account="))
        XCTAssertEqual(signature.components(separatedBy: "account=").count, 2, "Should contain exactly one account signature")
        XCTAssertFalse(signature.contains("install="))
        
        var unprotectedRequest = URLRequest(url: try XCTUnwrap(URL(string: unprotectedURLString)))
        unprotectedRequest.httpMethod = "GET"
        let unprotectedReply = fetchNetworkReply(for: unprotectedRequest)
        
        XCTAssertNil(getHeader(from: unprotectedReply, key: "Approov-Token"))
        XCTAssertNil(getHeader(from: unprotectedReply, key: "Signature"))
        XCTAssertNil(getHeader(from: unprotectedReply, key: "Signature-Input"))
    }

    func testUpdateRequestCanIgnoreExcludedURL() throws {
        let exclusionStr = "^.*excluded.*$"
        ApproovService.addExclusionURLRegex(urlRegex: exclusionStr)

        let request = URLRequest(url: try XCTUnwrap(URL(string: "\(targetURLString)/excluded")))
        let reply = fetchNetworkReply(for: request)

        XCTAssertNotNil(reply, "Expected to receive a reply even for ignored domains")
        XCTAssertNil(getHeader(from: reply, key: "Approov-Token"))
    }

    func testPinningAcceptAny() throws {
        try reinitializeServiceWithTargetHost()
        
        MiniSDKAttesterProxyController.setNextPinningDirectiveJSON("{\"operation\": \"getPins\", \"acceptAny\": true}")
        
        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let reply = fetchNetworkReply(for: request)
        
        XCTAssertNotNil(reply, "Expected the request to succeed when acceptAny is used")
    }
    func testPinningFailureTriggersPinningError() throws {
        try reinitializeServiceWithTargetHost()
        
        // Set pinning failure directive
        MiniSDKAttesterProxyController.setNextPinningDirectiveJSON("{\"operation\": \"getPins\", \"shouldFail\": true}")
        
        let expectation = self.expectation(description: "network request failure")
        var receivedError: Error?
        
        let configuration = URLSessionConfiguration.ephemeral
        let session = ApproovURLSession(configuration: configuration)
        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let task = session.dataTask(with: request) { _, _, error in
            receivedError = error
            expectation.fulfill()
        }
        task.resume()
        
        waitForExpectations(timeout: 5.0)
        
        XCTAssertNotNil(receivedError, "Expected pinning failure but got success")
        // The error will likely be an URLError with code .serverCertificateHasBadDate or similar depending on the OS's interpretation of a garbage pin, 
        // but the key is that it's NOT nil.
    }

    func testDynamicPinningUpdatesFailureOnNewSession() throws {
        // Setup initial valid pinning
        try reinitializeServiceWithTargetHost()
        
        let configuration = URLSessionConfiguration.ephemeral
        var session = ApproovURLSession(configuration: configuration)
        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        
        // Warm up connection
        let expectation1 = self.expectation(description: "first network request success")
        var receivedError1: Error?
        let task1 = session.dataTask(with: request) { _, _, error in
            receivedError1 = error
            expectation1.fulfill()
        }
        task1.resume()
        waitForExpectations(timeout: 5.0)
        XCTAssertNil(receivedError1, "Expected first request to succeed")
        
        // Now rotate pins to trigger failure, and we must create a new session since URLSession caches connections natively
        MiniSDKAttesterProxyController.setNextPinningDirectiveJSON("{\"operation\": \"getPins\", \"shouldFail\": true}")
        session.invalidateAndCancel()
        session = ApproovURLSession(configuration: URLSessionConfiguration.ephemeral)
        
        let expectation2 = self.expectation(description: "second network request failure")
        var receivedError2: Error?
        let task2 = session.dataTask(with: request) { _, _, error in
            receivedError2 = error
            expectation2.fulfill()
        }
        task2.resume()
        waitForExpectations(timeout: 5.0)
        XCTAssertNotNil(receivedError2, "Expected pinning update failure on new session")
    }


    @available(macOS 10.15, *)
    func testDataTaskPublisherWithApproovSendsMutatedRequest() throws {
        try reinitializeServiceWithTargetHost()

        let expectation = expectation(description: "publisher completion")
        var receivedData: Data?

        let configuration = URLSessionConfiguration.ephemeral
        let session = ApproovURLSession(configuration: configuration)
        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))

        let (publisher, error) = session.dataTaskPublisherWithApproov(for: request)
        XCTAssertNil(error)

        publisher
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                    expectation.fulfill()
                },
                receiveValue: { data, _ in
                    receivedData = data
                }
            )
            .store(in: &cancellables)

        waitForExpectations(timeout: 5.0)

        let reply = try XCTUnwrap(try? JSONSerialization.jsonObject(with: receivedData ?? Data()) as? [String: Any])
        XCTAssertNotNil(getHeader(from: reply, key: "Approov-Token"))
        XCTAssertNotNil(getHeader(from: reply, key: "Approov-TraceID"))
    }

    func testInstallMessageSigningFailsGracefullyIfKeyGenerationFails() throws {
        // Target host setup with no-install-key comment
        let targetHost = try XCTUnwrap(URL(string: targetURLString)?.host)
        let domainsJSON = "\"protectedDomains\": [\"\\(targetHost)\"]"
        try reinitializeService(
            scenarioJSON: scenarioJSON(
                caseName: uniqueCaseName(prefix: "no-install-key"),
                body: domainsJSON
            ),
            comment: "options:no-install-key"
        )
        
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setUseInstallMessageSigning()
        let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)
        ApproovService.setServiceMutator(signer)

        var request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        request.httpMethod = "GET"
        let protectedReply = fetchNetworkReply(for: request)

        XCTAssertNotNil(getHeader(from: protectedReply, key: "Approov-Token"))
        XCTAssertNil(getHeader(from: protectedReply, key: "Signature"))
        XCTAssertNil(getHeader(from: protectedReply, key: "Signature-Input"))
    }

    func testDigestBodyAppendedForPOSTPUTPATCHRequests() throws {
        try reinitializeServiceWithTargetHost()
        
        let factory = try ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setUseInstallMessageSigning()
            .setBodyDigestConfig(ApproovDefaultMessageSigning.DIGEST_SHA256, required: true) // Required enforces body generation
        let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)
        ApproovService.setServiceMutator(signer)

        for method in ["POST", "PUT", "PATCH"] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
            request.httpMethod = method
            request.httpBody = Data("{\"test\": 1}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let protectedReply = fetchNetworkReply(for: request)
            
            XCTAssertNotNil(getHeader(from: protectedReply, key: "Approov-Token"))
            let signatureInput = try XCTUnwrap(getHeader(from: protectedReply, key: "Signature-Input"), "Failed on \\(method)")
            XCTAssertTrue(signatureInput.contains("content-digest"), "Signature-Input should include content-digest for \\(method)")
            XCTAssertNotNil(getHeader(from: protectedReply, key: "Content-Digest"), "Content-Digest should be generated for \\(method)")
        }
    }

    struct AlwaysProceedMutator: ApproovServiceMutator {
        func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult, url: String) throws -> Bool {
            return false // proceed without throwing
        }
    }

    func testServiceMutatorOverridesFailClosedBehavior() throws {
        try reinitializeServiceWithTargetHost()
        
        // Simulating MITM_DETECTED which normally throws a networkingError
        setDirective(
            """
            {
              "operation": "fetchApproovToken",
              "response": {
                "status": "MITM_DETECTED"
              }
            }
            """
        )
        
        ApproovService.setServiceMutator(AlwaysProceedMutator())

        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let reply = fetchNetworkReply(for: request)

        XCTAssertNotNil(reply, "Expected to receive a reply from worker when proceeding due to overridden mutator")
        XCTAssertNil(getHeader(from: reply, key: "Approov-Token"))
    }

    private func initializeService(comment: String?) throws {
        try ApproovService.initialize(config: validInitialConfig, comment: comment)
    }

    private func reinitializeService(scenarioJSON: String? = nil, comment: String) throws {
        MiniSDKAttesterProxyController.reset()
        if let scenarioJSON {
            MiniSDKAttesterProxyController.loadScenarioJSON(scenarioJSON)
        }
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try initializeService(comment: comment)
    }

    private func setDirective(_ json: String) {
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(json)
    }

    private func uniqueCaseName(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    private func scenarioJSON(caseName: String, body: String) -> String {
        """
        {
          "activeCase": "\(caseName)",
          "cases": {
            "\(caseName)": {
              \(body)
            }
          }
        }
        """
    }

    private func decodeJWTBody(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return nil
        }
        guard let data = base64URLDecode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func base64URLDecode(_ value: String) -> Data? {
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded.append(String(repeating: "=", count: (4 - padded.count % 4) % 4))
        return Data(base64Encoded: padded)
    }

    private func sha256Base64(_ value: String) -> String {
        Data(SHA256.hash(data: Data(value.utf8))).base64EncodedString()
    }

    private func assertDecision(_ decision: ApproovFetchDecision, is expected: ApproovFetchDecision, file: StaticString = #filePath, line: UInt = #line) {
        switch (decision, expected) {
        case (.ShouldProceed, .ShouldProceed),
             (.ShouldRetry, .ShouldRetry),
             (.ShouldFail, .ShouldFail),
             (.ShouldIgnore, .ShouldIgnore):
            return
        default:
            XCTFail("Expected decision \(expected), got \(decision)", file: file, line: line)
        }
    }
}

