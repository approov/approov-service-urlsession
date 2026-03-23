import XCTest
@testable import ApproovURLSessionPackage

final class ApproovServiceMutatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ApproovService.resetForTesting()
    }

    override func tearDown() {
        ApproovService.resetForTesting()
        super.tearDown()
    }

    func testHandleFetchTokenResultThrowsNetworkingErrorForNoNetwork() {
        let result = FakeApproovTokenFetchResult(status: .noNetwork)

        XCTAssertThrowsError(try ApproovServiceMutatorDefault.shared.handleFetchTokenResult(result)) { error in
            guard case ApproovError.networkingError(let message) = error else {
                return XCTFail("Expected networkingError, got \(error)")
            }
            XCTAssertTrue(message.contains("fetchToken network error"))
        }
    }

    func testHandlePrecheckResultAllowsSuccessAndUnknownKey() throws {
        try ApproovServiceMutatorDefault.shared.handlePrecheckResult(FakeApproovTokenFetchResult(status: .success))
        try ApproovServiceMutatorDefault.shared.handlePrecheckResult(FakeApproovTokenFetchResult(status: .unknownKey))
    }

    func testHandlePrecheckResultThrowsRejectionError() {
        let result = FakeApproovTokenFetchResult(status: .rejected, arc: "arc", rejectionReasons: "reason")

        XCTAssertThrowsError(try ApproovServiceMutatorDefault.shared.handlePrecheckResult(result)) { error in
            guard case ApproovError.rejectionError(let message, let arc, let reasons) = error else {
                return XCTFail("Expected rejectionError, got \(error)")
            }
            XCTAssertTrue(message.contains("precheck"))
            XCTAssertEqual(arc, "arc")
            XCTAssertEqual(reasons, "reason")
        }
    }

    func testHandlePrecheckResultThrowsPermanentErrorForUnhandledStatus() {
        let result = FakeApproovTokenFetchResult(status: .badURL)

        XCTAssertThrowsError(try ApproovServiceMutatorDefault.shared.handlePrecheckResult(result)) { error in
            guard case ApproovError.permanentError(let message) = error else {
                return XCTFail("Expected permanentError, got \(error)")
            }
            XCTAssertTrue(message.contains("precheck"))
        }
    }

    func testHandleFetchTokenResultAllowsSuccess() throws {
        try ApproovServiceMutatorDefault.shared.handleFetchTokenResult(FakeApproovTokenFetchResult(status: .success))
    }

    func testHandleFetchTokenResultThrowsPermanentErrorForUnhandledStatus() {
        let result = FakeApproovTokenFetchResult(status: .badURL)

        XCTAssertThrowsError(try ApproovServiceMutatorDefault.shared.handleFetchTokenResult(result)) { error in
            guard case ApproovError.permanentError(let message) = error else {
                return XCTFail("Expected permanentError, got \(error)")
            }
            XCTAssertTrue(message.contains("fetchToken"))
        }
    }

    func testHandleFetchSecureStringResultAllowsSuccessAndUnknownKey() throws {
        try ApproovServiceMutatorDefault.shared.handleFetchSecureStringResult(
            FakeApproovTokenFetchResult(status: .success),
            operation: "lookup",
            key: "secret"
        )
        try ApproovServiceMutatorDefault.shared.handleFetchSecureStringResult(
            FakeApproovTokenFetchResult(status: .unknownKey),
            operation: "lookup",
            key: "secret"
        )
    }

    func testHandleFetchSecureStringResultThrowsNetworkingError() {
        let result = FakeApproovTokenFetchResult(status: .poorNetwork)

        XCTAssertThrowsError(
            try ApproovServiceMutatorDefault.shared.handleFetchSecureStringResult(result, operation: "lookup", key: "secret")
        ) { error in
            guard case ApproovError.networkingError(let message) = error else {
                return XCTFail("Expected networkingError, got \(error)")
            }
            XCTAssertTrue(message.contains("fetchSecureString lookup for secret"))
        }
    }

    func testHandleFetchSecureStringResultThrowsRejectionError() {
        let result = FakeApproovTokenFetchResult(status: .rejected, arc: "arc", rejectionReasons: "reasons")

        XCTAssertThrowsError(
            try ApproovServiceMutatorDefault.shared.handleFetchSecureStringResult(result, operation: "definition", key: "secret")
        ) { error in
            guard case ApproovError.rejectionError(let message, let arc, let reasons) = error else {
                return XCTFail("Expected rejectionError, got \(error)")
            }
            XCTAssertTrue(message.contains("fetchSecureString definition for secret"))
            XCTAssertEqual(arc, "arc")
            XCTAssertEqual(reasons, "reasons")
        }
    }

    func testHandleFetchCustomJWTResultAllowsSuccess() throws {
        try ApproovServiceMutatorDefault.shared.handleFetchCustomJWTResult(FakeApproovTokenFetchResult(status: .success))
    }

    func testHandleFetchCustomJWTResultThrowsNetworkingError() {
        let result = FakeApproovTokenFetchResult(status: .mitmDetected)

        XCTAssertThrowsError(try ApproovServiceMutatorDefault.shared.handleFetchCustomJWTResult(result)) { error in
            guard case ApproovError.networkingError(let message) = error else {
                return XCTFail("Expected networkingError, got \(error)")
            }
            XCTAssertTrue(message.contains("fetchCustomJWT network error"))
        }
    }

    func testHandleFetchCustomJWTResultThrowsRejectionError() {
        let result = FakeApproovTokenFetchResult(status: .rejected, arc: "arc", rejectionReasons: "reasons")

        XCTAssertThrowsError(try ApproovServiceMutatorDefault.shared.handleFetchCustomJWTResult(result)) { error in
            guard case ApproovError.rejectionError(let message, let arc, let reasons) = error else {
                return XCTFail("Expected rejectionError, got \(error)")
            }
            XCTAssertTrue(message.contains("fetchCustomJWT"))
            XCTAssertEqual(arc, "arc")
            XCTAssertEqual(reasons, "reasons")
        }
    }

    func testHandleInterceptorFetchTokenResultReturnsFalseForUnknownURL() throws {
        let result = FakeApproovTokenFetchResult(status: .unknownURL)

        let shouldAddToken = try ApproovServiceMutatorDefault.shared.handleInterceptorFetchTokenResult(
            result,
            url: "https://example.com/unknown"
        )

        XCTAssertFalse(shouldAddToken)
    }

    func testHandleInterceptorFetchTokenResultAllowsSuccess() throws {
        let result = FakeApproovTokenFetchResult(status: .success)

        let shouldAddToken = try ApproovServiceMutatorDefault.shared.handleInterceptorFetchTokenResult(
            result,
            url: "https://example.com/protected"
        )

        XCTAssertTrue(shouldAddToken)
    }

    func testHandleInterceptorFetchTokenResultThrowsNetworkingError() {
        let result = FakeApproovTokenFetchResult(status: .poorNetwork)

        XCTAssertThrowsError(
            try ApproovServiceMutatorDefault.shared.handleInterceptorFetchTokenResult(result, url: "https://example.com/protected")
        ) { error in
            guard case ApproovError.networkingError(let message) = error else {
                return XCTFail("Expected networkingError, got \(error)")
            }
            XCTAssertTrue(message.contains("Approov token fetch for https://example.com/protected"))
        }
    }

    func testHandleInterceptorFetchTokenResultThrowsPermanentError() {
        let result = FakeApproovTokenFetchResult(status: .badURL)

        XCTAssertThrowsError(
            try ApproovServiceMutatorDefault.shared.handleInterceptorFetchTokenResult(result, url: "https://example.com/protected")
        ) { error in
            guard case ApproovError.permanentError(let message) = error else {
                return XCTFail("Expected permanentError, got \(error)")
            }
            XCTAssertTrue(message.contains("Approov token fetch"))
        }
    }

    func testHandleInterceptorHeaderSubstitutionResultThrowsRejectionError() {
        let result = FakeApproovTokenFetchResult(
            status: .rejected,
            arc: "arc-code",
            rejectionReasons: "rooted,hooked"
        )

        XCTAssertThrowsError(
            try ApproovServiceMutatorDefault.shared.handleInterceptorHeaderSubstitutionResult(result, header: "Api-Key")
        ) { error in
            guard case ApproovError.rejectionError(let message, let arc, let reasons) = error else {
                return XCTFail("Expected rejectionError, got \(error)")
            }
            XCTAssertTrue(message.contains("Header substitution"))
            XCTAssertEqual(arc, "arc-code")
            XCTAssertEqual(reasons, "rooted,hooked")
        }
    }

    func testHandleInterceptorHeaderSubstitutionResultAllowsSuccess() throws {
        let result = FakeApproovTokenFetchResult(status: .success)

        let shouldSubstitute = try ApproovServiceMutatorDefault.shared.handleInterceptorHeaderSubstitutionResult(
            result,
            header: "Api-Key"
        )

        XCTAssertTrue(shouldSubstitute)
    }

    func testHandleInterceptorHeaderSubstitutionResultReturnsFalseForUnknownKey() throws {
        let result = FakeApproovTokenFetchResult(status: .unknownKey)

        let shouldSubstitute = try ApproovServiceMutatorDefault.shared.handleInterceptorHeaderSubstitutionResult(
            result,
            header: "Api-Key"
        )

        XCTAssertFalse(shouldSubstitute)
    }

    func testHandleInterceptorHeaderSubstitutionResultThrowsNetworkingError() {
        let result = FakeApproovTokenFetchResult(status: .noNetwork)

        XCTAssertThrowsError(
            try ApproovServiceMutatorDefault.shared.handleInterceptorHeaderSubstitutionResult(result, header: "Api-Key")
        ) { error in
            guard case ApproovError.networkingError(let message) = error else {
                return XCTFail("Expected networkingError, got \(error)")
            }
            XCTAssertTrue(message.contains("Header substitution for Api-Key"))
        }
    }

    func testHandleInterceptorHeaderSubstitutionResultThrowsPermanentError() {
        let result = FakeApproovTokenFetchResult(status: .badKey)

        XCTAssertThrowsError(
            try ApproovServiceMutatorDefault.shared.handleInterceptorHeaderSubstitutionResult(result, header: "Api-Key")
        ) { error in
            guard case ApproovError.permanentError(let message) = error else {
                return XCTFail("Expected permanentError, got \(error)")
            }
            XCTAssertTrue(message.contains("Header substitution for Api-Key"))
        }
    }

    func testHandleInterceptorQueryParamSubstitutionResultAllowsSuccessAndUnknownKey() throws {
        let success = try ApproovServiceMutatorDefault.shared.handleInterceptorQueryParamSubstitutionResult(
            FakeApproovTokenFetchResult(status: .success),
            queryKey: "query"
        )
        let skipped = try ApproovServiceMutatorDefault.shared.handleInterceptorQueryParamSubstitutionResult(
            FakeApproovTokenFetchResult(status: .unknownKey),
            queryKey: "query"
        )

        XCTAssertTrue(success)
        XCTAssertFalse(skipped)
    }

    func testHandleInterceptorQueryParamSubstitutionResultThrowsRejectionError() {
        let result = FakeApproovTokenFetchResult(status: .rejected, arc: "arc", rejectionReasons: "reasons")

        XCTAssertThrowsError(
            try ApproovServiceMutatorDefault.shared.handleInterceptorQueryParamSubstitutionResult(result, queryKey: "query")
        ) { error in
            guard case ApproovError.rejectionError(let message, let arc, let reasons) = error else {
                return XCTFail("Expected rejectionError, got \(error)")
            }
            XCTAssertTrue(message.contains("Query parameter substitution for query"))
            XCTAssertEqual(arc, "arc")
            XCTAssertEqual(reasons, "reasons")
        }
    }

    func testHandleInterceptorQueryParamSubstitutionResultThrowsNetworkingAndPermanentErrors() {
        XCTAssertThrowsError(
            try ApproovServiceMutatorDefault.shared.handleInterceptorQueryParamSubstitutionResult(
                FakeApproovTokenFetchResult(status: .poorNetwork),
                queryKey: "query"
            )
        ) { error in
            guard case ApproovError.networkingError(let message) = error else {
                return XCTFail("Expected networkingError, got \(error)")
            }
            XCTAssertTrue(message.contains("Query parameter substitution for query"))
        }

        XCTAssertThrowsError(
            try ApproovServiceMutatorDefault.shared.handleInterceptorQueryParamSubstitutionResult(
                FakeApproovTokenFetchResult(status: .badKey),
                queryKey: "query"
            )
        ) { error in
            guard case ApproovError.permanentError(let message) = error else {
                return XCTFail("Expected permanentError, got \(error)")
            }
            XCTAssertTrue(message.contains("Query parameter substitution for query"))
        }
    }

    func testHandleInterceptorShouldProcessRequestHonorsExclusionRegex() throws {
        ApproovService.addExclusionURLRegex(urlRegex: "example\\.com/skip")
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/skip")))

        let shouldProcess = try ApproovServiceMutatorDefault.shared.handleInterceptorShouldProcessRequest(request)

        XCTAssertFalse(shouldProcess)
    }

    func testHandleInterceptorShouldProcessRequestThrowsForMissingURL() {
        var request = URLRequest(url: URL(string: "https://example.com/placeholder")!)
        request.url = nil

        XCTAssertThrowsError(try ApproovServiceMutatorDefault.shared.handleInterceptorShouldProcessRequest(request)) { error in
            guard case ApproovError.permanentError(let message) = error else {
                return XCTFail("Expected permanentError, got \(error)")
            }
            XCTAssertTrue(message.contains("no URL"))
        }
    }

    func testHandleInterceptorShouldProcessRequestReturnsTrueWhenNoExclusionMatches() throws {
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/path")))

        let shouldProcess = try ApproovServiceMutatorDefault.shared.handleInterceptorShouldProcessRequest(request)

        XCTAssertTrue(shouldProcess)
    }

    func testHandleInterceptorProcessedRequestReturnsOriginalRequest() throws {
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/path")))

        let processed = try ApproovServiceMutatorDefault.shared.handleInterceptorProcessedRequest(
            request,
            changes: ApproovRequestMutations()
        )

        XCTAssertEqual(processed.url, request.url)
        XCTAssertEqual(processed.allHTTPHeaderFields, request.allHTTPHeaderFields)
    }

    func testHandlePinningShouldProcessRequestReturnsTrue() throws {
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/path")))

        XCTAssertTrue(ApproovServiceMutatorDefault.shared.handlePinningShouldProcessRequest(request))
    }
}
