import XCTest
import Foundation
import Combine
import CryptoKit
@testable import ApproovURLSessionPackage
import Approov
import MiniSDKTestSupport

/// Integration tests for the ApproovService URLSession service layer.
///
/// Tests are organized to match the sections defined in TESTING_REQUIREMENTS.md
/// from the core-service-layers-testing repository. Each test includes a comment
/// referencing the requirement(s) it covers.
///
/// - SeeAlso: `TESTING_REQUIREMENTS.md` in core-service-layers-testing
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
        ApproovService.setServiceMutator(nil)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    // MARK: - §1 Initialization
    // TESTING_REQUIREMENTS.md §1

    /// §1 Same Config Re-initialization / Different Config Re-initialization
    ///
    /// Re-initialize with the same config string should not fail.
    /// Re-initialize with a different config string should fail with an exception.
    func testInitializeIgnoresSameConfigAndRejectsDifferentConfig() throws {
        XCTAssertNoThrow(try ApproovService.initialize(config: validInitialConfig, comment: nil))

        let differentConfig = "#cb-other#mAxOF0ekJUOC36J5XWmVmVipOcUoEdMjhPSp2FVtyTo="
        XCTAssertThrowsError(try ApproovService.initialize(config: differentConfig, comment: nil)) { error in
            guard case let ApproovError.initializationFailure(message) = error else {
                return XCTFail("Expected initializationFailure, got \(error)")
            }
            XCTAssertTrue(message.contains("Approov SDK already initialized with a different configuration"),
                          "Unexpected message: \(message)")
        }
    }

    /// §1 Empty Configuration (Valid Comment) / Empty Configuration (Empty Comment)
    ///
    /// Initializing with an empty config should keep the service layer initialized
    /// while forwarding requests without Approov mutations.
    func testInitializeWithEmptyConfigForwardsPlainRequests() throws {
        MiniSDKAttesterProxyController.reset()
        let targetHost = try XCTUnwrap(URL(string: targetURLString)?.host)
        let domainsJSON = "\"protectedDomains\": [\"\(targetHost)\"]"
        MiniSDKAttesterProxyController.loadScenarioJSON(scenarioJSON(caseName: uniqueCaseName(prefix: "target-host"), body: domainsJSON))
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: "", comment: "reinit-empty-config")

        XCTAssertTrue(ApproovService.isInitialized())

        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let reply = fetchNetworkReply(for: request)

        XCTAssertNotNil(reply)
        XCTAssertNil(getHeader(from: reply, key: "Approov-Token"))
        XCTAssertNil(getHeader(from: reply, key: "Approov-TraceID"))
    }

    /// §1 Empty Configuration then Valid Configuration
    ///
    /// Initializing first with an empty config should allow a later valid config
    /// to enable Approov protection at runtime.
    func testInitializeWithEmptyConfigCanLaterEnableApproov() throws {
        MiniSDKAttesterProxyController.reset()
        let targetHost = try XCTUnwrap(URL(string: targetURLString)?.host)
        let domainsJSON = "\"protectedDomains\": [\"\(targetHost)\"]"
        MiniSDKAttesterProxyController.loadScenarioJSON(scenarioJSON(caseName: uniqueCaseName(prefix: "target-host"), body: domainsJSON))
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: "", comment: "reinit-empty-config")

        XCTAssertTrue(ApproovService.isInitialized())
        XCTAssertFalse(ApproovService.isApproovEnabled())

        let plainRequest = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let plainReply = fetchNetworkReply(for: plainRequest)
        XCTAssertNotNil(plainReply)
        XCTAssertNil(getHeader(from: plainReply, key: "Approov-Token"))
        XCTAssertNil(getHeader(from: plainReply, key: "Approov-TraceID"))

        try ApproovService.initialize(config: validInitialConfig, comment: nil)

        XCTAssertTrue(ApproovService.isInitialized())
        XCTAssertTrue(ApproovService.isApproovEnabled())

        let protectedRequest = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let protectedReply = fetchNetworkReply(for: protectedRequest)
        XCTAssertNotNil(protectedReply)
        XCTAssertNotNil(getHeader(from: protectedReply, key: "Approov-Token"))
    }

    /// §1 Cross-Service-Layer Same Config Initialization
    ///
    /// If another service layer has already initialized the native SDK with the
    /// same config, this service layer should still initialize successfully when
    /// it is unaware of that earlier initialization.
    func testInitializeSucceedsWhenNativeSdkAlreadyInitializedWithSameConfig() throws {
        ApproovService.resetForTesting()

        XCTAssertNoThrow(try ApproovService.initialize(config: validInitialConfig, comment: nil))
        XCTAssertTrue(ApproovService.isInitialized())
        XCTAssertTrue(ApproovService.isApproovEnabled())
    }

    /// §1 Cross-Service-Layer Different Config Initialization
    ///
    /// If another service layer has already initialized the native SDK with a
    /// different config, this service layer should surface the native error rather
    /// than silently accepting it.
    func testInitializeRejectsWhenNativeSdkAlreadyInitializedWithDifferentConfig() throws {
        ApproovService.resetForTesting()
        let differentConfig = "#cb-other#mAxOF0ekJUOC36J5XWmVmVipOcUoEdMjhPSp2FVtyTo="

        XCTAssertThrowsError(try ApproovService.initialize(config: differentConfig, comment: nil)) { error in
            guard case let ApproovError.initializationFailure(message) = error else {
                return XCTFail("Expected initializationFailure, got \(error)")
            }
            XCTAssertEqual(message, "Error initializing Approov SDK: Approov SDK already initialized with a different configuration")
        }

        XCTAssertFalse(ApproovService.isInitialized())
        XCTAssertFalse(ApproovService.isApproovEnabled())
    }

    // MARK: - §2 Request Processing & Token Behaviors
    // TESTING_REQUIREMENTS.md §2

    /// §2 Precheck Evaluation
    ///
    /// A call to precheck() should trigger a secure string fetch and evaluate
    /// UNKNOWN_KEY as a success path.
    func testPrecheckTreatsUnknownKeyAsSuccess() throws {
        XCTAssertNoThrow(try ApproovService.precheck())
    }

    /// §2 (Supporting test)
    ///
    /// Verifies the Mini SDK returns a stable device ID for the test environment.
    func testGetDeviceIDReturnsMiniSDKDeviceID() {
        XCTAssertEqual(ApproovService.getDeviceID(), "daIvmEWBA2gvZny7a/RC/w==")
    }

    /// §2 Protected Request Processing / Token Binding Hash
    ///
    /// A protected request is processed and modified by the service layer.
    /// The token's `pay` claim should contain the SHA256 hash of the binding header value.
    /// Also tests header and query parameter substitution.
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

    /// §2 Protected Request Processing
    ///
    /// Verifies that a protected request receives a signed token with expected
    /// standard claims (ip, did, mskid, arc, exp).
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

    /// §2 Missing Artifacts Fallback
    ///
    /// When the Approov service is unavailable (NO_APPROOV_SERVICE), the request
    /// should proceed without an Approov token or trace ID.
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

    /// §2 Exclusion URL Matching
    ///
    /// An excluded URL (using regular expression checks) should not be processed
    /// by the service layer.
    func testUpdateRequestCanIgnoreExcludedURL() throws {
        let exclusionStr = "^.*excluded.*$"
        ApproovService.addExclusionURLRegex(urlRegex: exclusionStr)

        let request = URLRequest(url: try XCTUnwrap(URL(string: "\(targetURLString)/excluded")))
        let reply = fetchNetworkReply(for: request)

        XCTAssertNotNil(reply, "Expected to receive a reply even for ignored domains")
        XCTAssertNil(getHeader(from: reply, key: "Approov-Token"))
    }

    /// §2 Token Fallback Status (error status mapping)
    ///
    /// NO_NETWORK → networkingError
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

    /// §2 Protected Request Processing (Combine publisher)
    ///
    /// Verifies that Combine's dataTaskPublisher correctly receives Approov-mutated
    /// request headers (token and trace ID).
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

    // MARK: - §3 Service Mutators & Decision Overrides
    // TESTING_REQUIREMENTS.md §3

    struct AlwaysProceedMutator: ApproovServiceMutator {
        func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult, url: String) throws -> Bool {
            return false // proceed without throwing
        }
    }

    /// §3 Custom Mutators / Decision Overrides
    ///
    /// Overriding the default fail-closed behavior for MITM_DETECTED via a custom
    /// ApproovServiceMutator allows the request to proceed without a token.
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

    // MARK: - §4 Pinning Configuration & Scenarios
    // TESTING_REQUIREMENTS.md §4

    /// §4 Accept Any Pins
    ///
    /// The SDK provides no specific pins for the API and suppresses the wildcard
    /// fallback pins, allowing the connection to succeed without pinning validation.
    func testPinningAcceptAny() throws {
        try reinitializeServiceWithTargetHost()
        
        MiniSDKAttesterProxyController.setNextPinningDirectiveJSON("{\"operation\": \"getPins\", \"acceptAny\": true}")
        
        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let reply = fetchNetworkReply(for: request)
        
        XCTAssertNotNil(reply, "Expected the request to succeed when acceptAny is used")
    }

    /// §4 Generate Invalid Pins
    ///
    /// When the SDK provides invalid (dummy) pins for the target host, the connection
    /// should fail with a pinning error.
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
    }

    /// §4 Dynamic Pinning Updates
    ///
    /// When pins are updated dynamically to an invalid state, subsequent requests
    /// on a new session should fail. Note: URLSession caches connections natively,
    /// so the session must be invalidated and a fresh one created.
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

    // MARK: - §5 Message Signing
    // TESTING_REQUIREMENTS.md §5

    /// §5 Install Signature Success / Single Signature Application
    /// §2 Unprotected Request Processing
    ///
    /// Install message signing successfully generates signature headers (install=...)
    /// only once per request. Unprotected requests receive no signature headers.
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

    /// §5 Account Message Signing
    ///
    /// Account message signing produces the expected signature headers (account=...).
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

    /// §5 Install Key Generation Failure / Signing Failure Fallback
    ///
    /// Install message signature fails if key pair generation fails; no signature
    /// headers are added to the request, but the request proceeds with a token.
    func testInstallMessageSigningFailsGracefullyIfKeyGenerationFails() throws {
        // Target host setup with no-install-key comment
        let targetHost = try XCTUnwrap(URL(string: targetURLString)?.host)
        let domainsJSON = "\"protectedDomains\": [\"\(targetHost)\"]"
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

    /// §5 Digest Body Application
    ///
    /// The digest body (Content-Digest) for an install message signature is present
    /// for POST, PUT, and PATCH requests when body digest is configured.
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
            let signatureInput = try XCTUnwrap(getHeader(from: protectedReply, key: "Signature-Input"), "Failed on \\\(method)")
            XCTAssertTrue(signatureInput.contains("content-digest"), "Signature-Input should include content-digest for \\\(method)")
            XCTAssertNotNil(getHeader(from: protectedReply, key: "Content-Digest"), "Content-Digest should be generated for \\\(method)")
        }
    }

    // MARK: - §6 Secure Strings & Custom JWT
    // TESTING_REQUIREMENTS.md §6

    /// §6 Valid Secure String Key
    ///
    /// Fetch a secure string using a valid key returns the expected value.
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

    /// §6 Non-existent Secure String Key
    ///
    /// Fetch a secure string using a non-existent key returns nil.
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

    /// §6 Empty Secure String Key
    ///
    /// Fetch a secure string using an empty key throws a permanent error.
    func testFetchSecureStringEmptyKeyRaisesPermanentError() throws {
        XCTAssertThrowsError(try ApproovService.fetchSecureString(key: "", newDef: nil)) { error in
            guard case let ApproovError.permanentError(message) = error else {
                return XCTFail("Expected permanentError, got \\\(error)")
            }
            XCTAssertTrue(message.contains("bad key"), "Expected bad key message")
        }
    }

    /// §6 Custom JWT Fetch
    ///
    /// Fetching a Custom JWT should accurately return the marshaled payload as a token.
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

    /// §6 Custom JWT Fetch (18KB payload)
    ///
    /// Fetching a Custom JWT with an 18KB JSON payload should work correctly.
    func testFetchCustomJWT18KBPayload() throws {
        let largePayload = String(repeating: "A", count: 18 * 1024)
        let payloadStruct = CustomPayload(data: largePayload)
        
        let jsonData = try JSONEncoder().encode(payloadStruct)
        let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        
        let jwt = try XCTUnwrap(ApproovService.fetchCustomJWT(payload: json))
        let payloadMap = try XCTUnwrap(decodeJWTBody(jwt))
        XCTAssertEqual(payloadMap["data"] as? String, largePayload)
    }

    /// §6 Custom JWT Fetch (disabled)
    ///
    /// Fetching a Custom JWT when the feature is disabled throws a permanent error.
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

    /// §6 Custom JWT Fetch (malformatted JSON)
    ///
    /// Fetching a Custom JWT with a malformatted JSON string throws a permanent error.
    func testFetchCustomJWTBadPayloadRaisesPermanentError() {
        XCTAssertThrowsError(try ApproovService.fetchCustomJWT(payload: "not-json")) { error in
            guard case let ApproovError.permanentError(message) = error else {
                return XCTFail("Expected permanentError, got \(error)")
            }
            XCTAssertEqual(message, "fetchCustomJWT: bad payload")
        }
    }

    /// §7 Failure Caching
    ///
    /// Verifies that SDK failures (e.g., NO_NETWORK) are cached and short-circuit
    /// subsequent requests within the TTL window without querying the SDK again.
    func testCachedFailureShortCircuitsSDKFetchWithinTTL() throws {
        try reinitializeServiceWithTargetHost()

        // 1. Force a NO_NETWORK failure which should populate the cache
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

        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let response1 = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        XCTAssertEqual(response1.decision, .ShouldRetry)
        XCTAssertEqual(response1.sdkMessage, "no network")

        // 2. Change the underlying directive to SUCCESS.
        // Since the cache is still valid, the SDK should be bypassed and
        // the response should still be the cached NO_NETWORK.
        setDirective(
            """
            {
              "operation": "fetchApproovToken",
              "response": {
                "status": "SUCCESS",
                "token": "fresh-token-that-should-be-ignored"
              }
            }
            """
        )

        let response2 = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        XCTAssertEqual(response2.decision, .ShouldRetry)
        XCTAssertEqual(response2.sdkMessage, "no network")
    }

    /// Verifies that concurrent requests share a cached failure once the first
    /// in-flight SDK fetch observes the failure.
    func testCachedFailureShortCircuitsConcurrentRequestsWithinTTL() throws {
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

        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let requestCount = 24
        let startGate = DispatchSemaphore(value: 0)
        let completionGroup = DispatchGroup()
        let responsesLock = NSLock()
        var responses: [ApproovUpdateResponse] = []

        for _ in 0..<requestCount {
            completionGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                startGate.wait()
                let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
                responsesLock.lock()
                responses.append(response)
                responsesLock.unlock()
                completionGroup.leave()
            }
        }

        for _ in 0..<requestCount {
            startGate.signal()
        }

        switch completionGroup.wait(timeout: .now() + 5.0) {
        case .success:
            break
        case .timedOut:
            XCTFail("Timed out waiting for concurrent cached-failure requests")
            return
        }

        XCTAssertEqual(responses.count, requestCount)
        for response in responses {
            XCTAssertEqual(response.decision, .ShouldRetry)
            XCTAssertEqual(response.sdkMessage, "no network")
        }
    }

    /// Verifies that the cached failure expires after the TTL.
    func testCachedFailureExpiresAfterTTL() throws {
        try reinitializeServiceWithTargetHost()

        // 1. Force a NO_NETWORK failure which should populate the cache
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

        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let response1 = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        XCTAssertEqual(response1.decision, .ShouldRetry)
        XCTAssertEqual(response1.sdkMessage, "no network")

        // 2. Change the underlying directive to SUCCESS.
        setDirective(
            """
            {
              "operation": "fetchApproovToken",
              "response": {
                "status": "SUCCESS",
                "token": "fresh-token-after-ttl"
              }
            }
            """
        )

        // 3. Sleep well beyond the 500ms TTL to avoid timing-related flakiness in CI.
        Thread.sleep(forTimeInterval: 1.0)

        let response2 = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        XCTAssertEqual(response2.decision, .ShouldProceed)
        XCTAssertEqual(response2.sdkMessage, "success")
    }

    // MARK: - Test Helpers

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
