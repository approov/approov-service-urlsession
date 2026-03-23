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

    func testHandleInterceptorFetchTokenResultReturnsFalseForUnknownURL() throws {
        let result = FakeApproovTokenFetchResult(status: .unknownURL)

        let shouldAddToken = try ApproovServiceMutatorDefault.shared.handleInterceptorFetchTokenResult(
            result,
            url: "https://example.com/unknown"
        )

        XCTAssertFalse(shouldAddToken)
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

    func testHandleInterceptorShouldProcessRequestHonorsExclusionRegex() throws {
        ApproovService.addExclusionURLRegex(urlRegex: "example\\.com/skip")
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/skip")))

        let shouldProcess = try ApproovServiceMutatorDefault.shared.handleInterceptorShouldProcessRequest(request)

        XCTAssertFalse(shouldProcess)
    }
}
