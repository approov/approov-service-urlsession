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
