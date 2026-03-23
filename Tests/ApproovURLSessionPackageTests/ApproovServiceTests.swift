import Approov
import XCTest
@testable import ApproovURLSessionPackage

final class ApproovServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ApproovService.resetForTesting()
    }

    override func tearDown() {
        ApproovService.resetForTesting()
        super.tearDown()
    }

    func testInitializeRejectsDifferentConfigWithoutReinitComment() throws {
        let sdkClient = FakeApproovSDKClient()
        ApproovService.setSDKClientForTesting(sdkClient)

        try ApproovService.initialize(config: "config-one", comment: "first-pass")

        XCTAssertThrowsError(try ApproovService.initialize(config: "config-two", comment: "ordinary comment")) { error in
            guard case ApproovError.configurationError(let message) = error else {
                return XCTFail("Expected configurationError, got \(error)")
            }
            XCTAssertTrue(message.contains("different configuration"))
        }
        XCTAssertEqual(sdkClient.initializedConfigs.count, 1)
        XCTAssertEqual(sdkClient.initializedConfigs.first?.0, "config-one")
    }

    func testUpdateRequestWithApproovAppliesTokenAndSubstitutions() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/path?a(b=query-placeholder"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(
            status: .success,
            token: "approov-token",
            traceID: "trace-123",
            isConfigChanged: true,
            loggableToken: "loggable-token"
        )
        sdkClient.secureStringResultsByKey["header-secret"] = FakeApproovTokenFetchResult(
            status: .success,
            secureString: "live-header-secret"
        )
        sdkClient.secureStringResultsByKey["query-placeholder"] = FakeApproovTokenFetchResult(
            status: .success,
            secureString: "live-query-secret"
        )

        let mutator = RecordingMutator()
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")
        ApproovService.setApproovHeader(header: "Approov-Token", prefix: "Bearer ")
        ApproovService.setBindingHeader(header: "Authorization")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: "Bearer ")
        ApproovService.addSubstitutionQueryParam(key: "a(b")
        ApproovService.setServiceMutator(mutator)

        var request = URLRequest(url: url)
        request.setValue("Bearer binding-value", forHTTPHeaderField: "Authorization")
        request.setValue("Bearer header-secret", forHTTPHeaderField: "Api-Key")

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.httpAdditionalHeaders = ["X-Session": "session-value"]

        let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: sessionConfig)

        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.sdkMessage, "SUCCESS")
        XCTAssertNil(response.error)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Approov-Token"), "Bearer approov-token")
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Approov-TraceID"), "trace-123")
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Api-Key"), "Bearer live-header-secret")
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "X-Mutated"), "true")
        XCTAssertTrue(response.request.url?.absoluteString.contains("live-query-secret") == true)
        XCTAssertEqual(sdkClient.dataHashes, ["Bearer binding-value"])
        XCTAssertEqual(sdkClient.fetchedConfigCount, 1)
        XCTAssertEqual(mutator.tokenHeaderKey, "Approov-Token")
        XCTAssertEqual(mutator.traceIDHeaderKey, "Approov-TraceID")
        XCTAssertEqual(mutator.substitutionHeaderKeys, ["Api-Key"])
        XCTAssertEqual(mutator.substitutionQueryParamKeys, ["a(b"])
        XCTAssertEqual(mutator.originalURL, url.absoluteString)
    }

    func testUpdateRequestWithApproovReturnsRetryForNoNetwork() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .noNetwork)
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldRetry)
        guard case ApproovError.networkingError(let message)? = response.error else {
            return XCTFail("Expected networking error, got \(String(describing: response.error))")
        }
        XCTAssertTrue(message.contains("Approov token fetch"))
    }

    func testUpdateRequestWithApproovIgnoresRequestsWhenNotInitialized() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldIgnore)
        XCTAssertNil(response.error)
    }

    func testUpdateRequestWithApproovIgnoresRequestWithoutURL() {
        var request = URLRequest(url: URL(string: "https://example.com/placeholder")!)
        request.url = nil

        let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldIgnore)
        XCTAssertNil(response.error)
    }

    func testUpdateRequestWithApproovIgnoresRequestWhenMutatorExcludesIt() throws {
        let sdkClient = FakeApproovSDKClient()
        let mutator = ConfigurableMutator()
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))
        mutator.shouldProcessRequest = { _ in false }
        ApproovService.setSDKClientForTesting(sdkClient)
        ApproovService.setServiceMutator(mutator)
        try ApproovService.initialize(config: "config")

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldIgnore)
        XCTAssertTrue(sdkClient.fetchedTokenURLs.isEmpty)
    }

    func testUpdateRequestWithApproovMapsMutatorShouldProcessErrors() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))

        let networkingMutator = ConfigurableMutator()
        networkingMutator.shouldProcessRequest = { _ in
            throw ApproovError.networkingError(message: "no network")
        }
        ApproovService.setSDKClientForTesting(sdkClient)
        ApproovService.setServiceMutator(networkingMutator)
        try ApproovService.initialize(config: "config")

        let retryResponse = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)
        XCTAssertEqual(retryResponse.decision, .ShouldRetry)

        ApproovService.resetForTesting()
        let failingMutator = ConfigurableMutator()
        failingMutator.shouldProcessRequest = { _ in
            throw ApproovError.permanentError(message: "bad request")
        }
        ApproovService.setSDKClientForTesting(sdkClient)
        ApproovService.setServiceMutator(failingMutator)
        try ApproovService.initialize(config: "config")

        let failResponse = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)
        XCTAssertEqual(failResponse.decision, .ShouldFail)
    }

    func testUpdateRequestWithApproovReturnsProceedWithoutMutationForUnknownURL() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/unprotected"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .unknownURL)
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertNil(response.request.value(forHTTPHeaderField: "Approov-Token"))
    }

    func testUpdateRequestWithApproovReturnsProceedWithoutMutationForNoApproovService() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/no-service"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .noApproovService)
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertNil(response.request.value(forHTTPHeaderField: "Approov-Token"))
    }

    func testUpdateRequestWithApproovReturnsProceedWithoutMutationForUnprotectedURL() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/public"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .unprotectedURL)
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertNil(response.request.value(forHTTPHeaderField: "Approov-Token"))
    }

    func testUpdateRequestWithApproovUsesStatusHeaderWhenTokenEmpty() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .success, token: "")
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")
        ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Approov-Token"), "SUCCESS")
    }

    func testUpdateRequestWithApproovOmitsTraceHeaderWhenDisabled() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(
            status: .success,
            token: "approov-token",
            traceID: "trace-123"
        )
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")
        ApproovService.setApproovTraceIDHeader(header: nil)

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertNil(response.request.value(forHTTPHeaderField: "Approov-TraceID"))
    }

    func testUpdateRequestWithApproovLeavesHeaderUnchangedWhenSecureStringUnknown() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .success, token: "approov-token")
        sdkClient.secureStringResultsByKey["header-secret"] = FakeApproovTokenFetchResult(status: .unknownKey)
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: "Bearer ")

        var request = URLRequest(url: url)
        request.setValue("Bearer header-secret", forHTTPHeaderField: "Api-Key")

        let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Api-Key"), "Bearer header-secret")
    }

    func testUpdateRequestWithApproovSubstitutesSessionConfigurationHeaderAndUsesSessionBindingHeader() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .success, token: "approov-token")
        sdkClient.secureStringResultsByKey["header-secret"] = FakeApproovTokenFetchResult(status: .success, secureString: "live-header-secret")
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")
        ApproovService.setBindingHeader(header: "Authorization")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: "Bearer ")

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.httpAdditionalHeaders = [
            "Authorization": "Bearer session-binding",
            "Api-Key": "Bearer header-secret"
        ]

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: sessionConfig)

        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Api-Key"), "Bearer live-header-secret")
        XCTAssertEqual(sdkClient.dataHashes, ["Bearer session-binding"])
    }

    func testUpdateRequestWithApproovFailsWhenHeaderSubstitutionReturnsNilString() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .success, token: "approov-token")
        sdkClient.secureStringResultsByKey["header-secret"] = FakeApproovTokenFetchResult(status: .success, secureString: nil)
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: "Bearer ")

        var request = URLRequest(url: url)
        request.setValue("Bearer header-secret", forHTTPHeaderField: "Api-Key")

        let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldFail)
        guard case ApproovError.permanentError(let message)? = response.error else {
            return XCTFail("Expected permanentError, got \(String(describing: response.error))")
        }
        XCTAssertTrue(message.contains("Header substitution"))
    }

    func testUpdateRequestWithApproovMapsHeaderSubstitutionMutatorErrors() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .success, token: "approov-token")
        sdkClient.secureStringResultsByKey["header-secret"] = FakeApproovTokenFetchResult(status: .success, secureString: "live-secret")

        let retryMutator = ConfigurableMutator()
        retryMutator.headerSubstitutionResult = { _, _ in
            throw ApproovError.networkingError(message: "retry")
        }
        ApproovService.setSDKClientForTesting(sdkClient)
        ApproovService.setServiceMutator(retryMutator)
        try ApproovService.initialize(config: "config")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: "Bearer ")

        var request = URLRequest(url: url)
        request.setValue("Bearer header-secret", forHTTPHeaderField: "Api-Key")

        let retryResponse = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        XCTAssertEqual(retryResponse.decision, .ShouldRetry)

        ApproovService.resetForTesting()
        let failMutator = ConfigurableMutator()
        failMutator.headerSubstitutionResult = { _, _ in
            throw ApproovError.permanentError(message: "fail")
        }
        ApproovService.setSDKClientForTesting(sdkClient)
        ApproovService.setServiceMutator(failMutator)
        try ApproovService.initialize(config: "config")
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: "Bearer ")

        request = URLRequest(url: url)
        request.setValue("Bearer header-secret", forHTTPHeaderField: "Api-Key")

        let failResponse = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        XCTAssertEqual(failResponse.decision, .ShouldFail)
    }

    func testUpdateRequestWithApproovLeavesQueryUnchangedWhenSecureStringUnknown() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/path?query=placeholder"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .success, token: "approov-token")
        sdkClient.secureStringResultsByKey["placeholder"] = FakeApproovTokenFetchResult(status: .unknownKey)
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")
        ApproovService.addSubstitutionQueryParam(key: "query")

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(response.request.url?.absoluteString, url.absoluteString)
    }

    func testUpdateRequestWithApproovSubstitutesRepeatedQueryParameters() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/path?query=first&query=second"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .success, token: "approov-token")
        sdkClient.secureStringResultsByKey["first"] = FakeApproovTokenFetchResult(status: .success, secureString: "first-live")
        sdkClient.secureStringResultsByKey["second"] = FakeApproovTokenFetchResult(status: .success, secureString: "second-live")
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")
        ApproovService.addSubstitutionQueryParam(key: "query")

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(
            response.request.url?.absoluteString,
            "https://example.com/path?query=first-live&query=second-live"
        )
    }

    func testUpdateRequestWithApproovPercentEncodesUnsafeQuerySubstitutionCharacters() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/path?query=placeholder"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .success, token: "approov-token")
        sdkClient.secureStringResultsByKey["placeholder"] = FakeApproovTokenFetchResult(status: .success, secureString: "\n")
        ApproovService.setSDKClientForTesting(sdkClient)
        try ApproovService.initialize(config: "config")
        ApproovService.addSubstitutionQueryParam(key: "query")

        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)

        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertNil(response.error)
        XCTAssertEqual(response.request.url?.absoluteString, "https://example.com/path?query=%0A")
    }

    func testUpdateRequestWithApproovMapsQuerySubstitutionMutatorErrors() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/path?query=placeholder"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .success, token: "approov-token")
        sdkClient.secureStringResultsByKey["placeholder"] = FakeApproovTokenFetchResult(status: .success, secureString: "live-query")

        let retryMutator = ConfigurableMutator()
        retryMutator.querySubstitutionResult = { _, _ in
            throw ApproovError.networkingError(message: "retry")
        }
        ApproovService.setSDKClientForTesting(sdkClient)
        ApproovService.setServiceMutator(retryMutator)
        try ApproovService.initialize(config: "config")
        ApproovService.addSubstitutionQueryParam(key: "query")

        let retryResponse = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)
        XCTAssertEqual(retryResponse.decision, .ShouldRetry)

        ApproovService.resetForTesting()
        let failMutator = ConfigurableMutator()
        failMutator.querySubstitutionResult = { _, _ in
            throw ApproovError.permanentError(message: "fail")
        }
        ApproovService.setSDKClientForTesting(sdkClient)
        ApproovService.setServiceMutator(failMutator)
        try ApproovService.initialize(config: "config")
        ApproovService.addSubstitutionQueryParam(key: "query")

        let failResponse = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)
        XCTAssertEqual(failResponse.decision, .ShouldFail)
    }

    func testUpdateRequestWithApproovMapsProcessedRequestMutatorErrors() throws {
        let sdkClient = FakeApproovSDKClient()
        let url = try XCTUnwrap(URL(string: "https://example.com/protected"))
        sdkClient.tokenResultsByURL[url.absoluteString] = FakeApproovTokenFetchResult(status: .success, token: "approov-token")

        let retryMutator = ConfigurableMutator()
        retryMutator.processedRequest = { _, _ in
            throw ApproovError.networkingError(message: "retry")
        }
        ApproovService.setSDKClientForTesting(sdkClient)
        ApproovService.setServiceMutator(retryMutator)
        try ApproovService.initialize(config: "config")

        let retryResponse = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)
        XCTAssertEqual(retryResponse.decision, .ShouldRetry)

        ApproovService.resetForTesting()
        let failMutator = ConfigurableMutator()
        failMutator.processedRequest = { _, _ in
            throw ApproovError.permanentError(message: "fail")
        }
        ApproovService.setSDKClientForTesting(sdkClient)
        ApproovService.setServiceMutator(failMutator)
        try ApproovService.initialize(config: "config")

        let failResponse = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)
        XCTAssertEqual(failResponse.decision, .ShouldFail)
    }
}

private final class RecordingMutator: ApproovServiceMutator {
    var tokenHeaderKey: String?
    var traceIDHeaderKey: String?
    var substitutionHeaderKeys: [String] = []
    var originalURL: String?
    var substitutionQueryParamKeys: [String] = []

    func handleInterceptorProcessedRequest(_ request: URLRequest,
                                           changes: ApproovRequestMutations) throws -> URLRequest {
        tokenHeaderKey = changes.getTokenHeaderKey()
        traceIDHeaderKey = changes.getTraceIDHeaderKey()
        substitutionHeaderKeys = changes.getSubstitutionHeaderKeys().sorted()
        originalURL = changes.getOriginalURL()
        substitutionQueryParamKeys = changes.getSubstitutionQueryParamKeys().sorted()

        var request = request
        request.setValue("true", forHTTPHeaderField: "X-Mutated")
        return request
    }
}

private final class ConfigurableMutator: ApproovServiceMutator {
    var shouldProcessRequest: ((URLRequest) throws -> Bool)?
    var headerSubstitutionResult: ((ApproovTokenFetchResult, String) throws -> Bool)?
    var querySubstitutionResult: ((ApproovTokenFetchResult, String) throws -> Bool)?
    var processedRequest: ((URLRequest, ApproovRequestMutations) throws -> URLRequest)?

    func handleInterceptorShouldProcessRequest(_ request: URLRequest) throws -> Bool {
        return try shouldProcessRequest?(request) ?? true
    }

    func handleInterceptorHeaderSubstitutionResult(_ approovResults: ApproovTokenFetchResult,
                                                   header: String) throws -> Bool {
        return try headerSubstitutionResult?(approovResults, header) ??
            ApproovServiceMutatorDefault.shared.handleInterceptorHeaderSubstitutionResult(approovResults, header: header)
    }

    func handleInterceptorQueryParamSubstitutionResult(_ approovResults: ApproovTokenFetchResult,
                                                       queryKey: String) throws -> Bool {
        return try querySubstitutionResult?(approovResults, queryKey) ??
            ApproovServiceMutatorDefault.shared.handleInterceptorQueryParamSubstitutionResult(approovResults, queryKey: queryKey)
    }

    func handleInterceptorProcessedRequest(_ request: URLRequest,
                                           changes: ApproovRequestMutations) throws -> URLRequest {
        return try processedRequest?(request, changes) ?? request
    }
}
