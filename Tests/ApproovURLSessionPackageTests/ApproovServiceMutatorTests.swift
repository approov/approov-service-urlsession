import XCTest
@testable import ApproovURLSessionPackage

final class ApproovServiceMutatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FixtureRunReporter.shared.installIfNeeded()
        ApproovService.resetForTesting()
    }

    override func tearDown() {
        ApproovService.resetForTesting()
        super.tearDown()
    }

    func testMutatorFixtures() throws {
        let suiteName = "service-mutator-fixtures.json"
        let harnessName = "ApproovServiceMutatorTests.testMutatorFixtures"
        let suite = try FixtureLoader.load(FixtureSuite<MutatorFixtureCase>.self, named: "service-mutator-fixtures.json")

        for fixture in suite.cases {
            try FixtureRunReporter.shared.runFixture(testCase: self, suite: suiteName, harness: harnessName, fixture: fixture.name) {
                ApproovService.resetForTesting()
                fixture.serviceSetup?.exclusionRegexes?.forEach { ApproovService.addExclusionURLRegex(urlRegex: $0) }

                let mutator = ApproovServiceMutatorDefault.shared
                let result = fixture.result.map(makeTokenFetchResult(from:))

                switch fixture.operation {
                case .precheck:
                    assertVoidResult(fixture.expected) {
                        try mutator.handlePrecheckResult(try XCTUnwrap(result))
                    }
                case .fetchToken:
                    assertVoidResult(fixture.expected) {
                        try mutator.handleFetchTokenResult(try XCTUnwrap(result))
                    }
                case .fetchSecureString:
                    assertVoidResult(fixture.expected) {
                        try mutator.handleFetchSecureStringResult(
                            try XCTUnwrap(result),
                            operation: try XCTUnwrap(fixture.operationName),
                            key: try XCTUnwrap(fixture.key)
                        )
                    }
                case .fetchCustomJwt:
                    assertVoidResult(fixture.expected) {
                        try mutator.handleFetchCustomJWTResult(try XCTUnwrap(result))
                    }
                case .interceptorFetchToken:
                    assertBoolResult(fixture.expected) {
                        try mutator.handleInterceptorFetchTokenResult(
                            try XCTUnwrap(result),
                            url: try XCTUnwrap(fixture.url)
                        )
                    }
                case .interceptorHeaderSubstitution:
                    assertBoolResult(fixture.expected) {
                        try mutator.handleInterceptorHeaderSubstitutionResult(
                            try XCTUnwrap(result),
                            header: try XCTUnwrap(fixture.header)
                        )
                    }
                case .interceptorQueryParamSubstitution:
                    assertBoolResult(fixture.expected) {
                        try mutator.handleInterceptorQueryParamSubstitutionResult(
                            try XCTUnwrap(result),
                            queryKey: try XCTUnwrap(fixture.queryKey)
                        )
                    }
                case .interceptorShouldProcessRequest:
                    let request: URLRequest
                    do {
                        request = try makeRequest(from: try XCTUnwrap(fixture.request)).0
                    } catch {
                        return XCTFail("Unable to build request for fixture \(fixture.name): \(error)")
                    }
                    assertBoolResult(fixture.expected) {
                        try mutator.handleInterceptorShouldProcessRequest(request)
                    }
                case .interceptorProcessedRequest:
                    let request: URLRequest
                    do {
                        request = try makeRequest(from: try XCTUnwrap(fixture.request)).0
                    } catch {
                        return XCTFail("Unable to build request for fixture \(fixture.name): \(error)")
                    }
                    XCTAssertNil(fixture.expected.error)
                    do {
                        let processed = try mutator.handleInterceptorProcessedRequest(request, changes: ApproovRequestMutations())
                        if fixture.expected.requestUnchanged == true {
                            XCTAssertEqual(processed.url, request.url)
                            XCTAssertEqual(processed.allHTTPHeaderFields, request.allHTTPHeaderFields)
                        }
                    } catch {
                        XCTFail("Unexpected error \(error)")
                    }
                case .pinningShouldProcessRequest:
                    let request: URLRequest
                    do {
                        request = try makeRequest(from: try XCTUnwrap(fixture.request)).0
                    } catch {
                        return XCTFail("Unable to build request for fixture \(fixture.name): \(error)")
                    }
                    XCTAssertNil(fixture.expected.error)
                    XCTAssertEqual(mutator.handlePinningShouldProcessRequest(request), fixture.expected.returnValue)
                }
            }
        }
    }

    private func assertVoidResult(_ expected: MutatorExpectation, operation: () throws -> Void) {
        if let errorExpectation = expected.error {
            XCTAssertThrowsError(try operation()) { error in
                assertError(error, matches: errorExpectation)
            }
        } else {
            XCTAssertNoThrow(try operation())
        }
    }

    private func assertBoolResult(_ expected: MutatorExpectation, operation: () throws -> Bool) {
        if let errorExpectation = expected.error {
            XCTAssertThrowsError(try operation()) { error in
                assertError(error, matches: errorExpectation)
            }
        } else {
            do {
                XCTAssertEqual(try operation(), expected.returnValue)
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
    }
}
