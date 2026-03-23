import XCTest
@testable import ApproovURLSessionPackage

final class ApproovServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FixtureRunReporter.shared.installIfNeeded()
        ApproovService.resetForTesting()
    }

    override func tearDown() {
        ApproovService.resetForTesting()
        super.tearDown()
    }

    func testInitializeFixtures() throws {
        let suiteName = "service-initialize-fixtures.json"
        let harnessName = "ApproovServiceTests.testInitializeFixtures"
        let suite = try FixtureLoader.load(FixtureSuite<InitializeFixtureCase>.self, named: "service-initialize-fixtures.json")

        for fixture in suite.cases {
            try FixtureRunReporter.shared.runFixture(testCase: self, suite: suiteName, harness: harnessName, fixture: fixture.name) {
                ApproovService.resetForTesting()
                let sdkClient = FakeApproovSDKClient()
                ApproovService.setSDKClientForTesting(sdkClient)

                for step in fixture.steps {
                    if let expectedError = step.expectedError {
                        XCTAssertThrowsError(try ApproovService.initialize(config: step.config, comment: step.comment)) { error in
                            assertError(error, matches: expectedError)
                        }
                    } else {
                        XCTAssertNoThrow(try ApproovService.initialize(config: step.config, comment: step.comment))
                    }
                }

                if let expectedInitializedConfigsCount = fixture.expectedInitializedConfigsCount {
                    XCTAssertEqual(sdkClient.initializedConfigs.count, expectedInitializedConfigsCount)
                }
                if let expectedInitializedConfigs = fixture.expectedInitializedConfigs {
                    XCTAssertEqual(sdkClient.initializedConfigs.count, expectedInitializedConfigs.count)
                    for (actual, expected) in zip(sdkClient.initializedConfigs, expectedInitializedConfigs) {
                        XCTAssertEqual(actual.0, expected.config)
                        if let updateConfig = expected.updateConfig {
                            XCTAssertEqual(actual.1, updateConfig)
                        }
                        if let comment = expected.comment {
                            XCTAssertEqual(actual.2, comment)
                        }
                    }
                }
            }
        }
    }

    func testUpdateRequestFixtures() throws {
        let suiteName = "service-update-request-fixtures.json"
        let harnessName = "ApproovServiceTests.testUpdateRequestFixtures"
        let suite = try FixtureLoader.load(FixtureSuite<UpdateRequestFixtureCase>.self, named: "service-update-request-fixtures.json")

        for fixture in suite.cases {
            try FixtureRunReporter.shared.runFixture(testCase: self, suite: suiteName, harness: harnessName, fixture: fixture.name) {
                ApproovService.resetForTesting()
                let sdkClient = FakeApproovSDKClient()
                configureSDK(sdkClient, with: fixture.sdk)
                ApproovService.setSDKClientForTesting(sdkClient)

                do {
                    try applyServiceSetup(fixture.setup)
                } catch {
                    return XCTFail("Unable to apply setup for fixture \(fixture.name): \(error)")
                }

                let recordingMutator: FixtureBackedMutator?
                if let mutatorFixture = fixture.mutator {
                    let mutator = FixtureBackedMutator(fixture: mutatorFixture)
                    recordingMutator = mutator
                    ApproovService.setServiceMutator(mutator)
                } else {
                    recordingMutator = nil
                }

                let requestAndSessionConfig: (URLRequest, URLSessionConfiguration?)
                do {
                    requestAndSessionConfig = try makeRequest(from: fixture.request)
                } catch {
                    return XCTFail("Unable to build request for fixture \(fixture.name): \(error)")
                }
                let (request, sessionConfig) = requestAndSessionConfig
                let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: sessionConfig)

                XCTAssertEqual(response.decision, fixture.expected.decision.toDecision())
                if let sdkMessage = fixture.expected.sdkMessage {
                    XCTAssertEqual(response.sdkMessage, sdkMessage)
                }
                assertError(response.error, matches: fixture.expected.error)

                if let requestUrl = fixture.expected.requestUrl {
                    XCTAssertEqual(response.request.url?.absoluteString, requestUrl)
                }
                if let requestUrlContains = fixture.expected.requestUrlContains {
                    XCTAssertTrue(response.request.url?.absoluteString.contains(requestUrlContains) == true)
                }
                fixture.expected.headerValues?.forEach { header, expectedValue in
                    XCTAssertEqual(response.request.value(forHTTPHeaderField: header), expectedValue)
                }
                fixture.expected.absentHeaders?.forEach { header in
                    XCTAssertNil(response.request.value(forHTTPHeaderField: header))
                }

                if let sdkExpectation = fixture.expected.sdk {
                    if let dataHashes = sdkExpectation.dataHashes {
                        XCTAssertEqual(sdkClient.dataHashes, dataHashes)
                    }
                    if let fetchedConfigCount = sdkExpectation.fetchedConfigCount {
                        XCTAssertEqual(sdkClient.fetchedConfigCount, fetchedConfigCount)
                    }
                    if let fetchedTokenUrls = sdkExpectation.fetchedTokenUrls {
                        XCTAssertEqual(sdkClient.fetchedTokenURLs, fetchedTokenUrls)
                    }
                    if let fetchedSecureStringKeys = sdkExpectation.fetchedSecureStringKeys {
                        let actual = sdkClient.fetchedSecureStringKeys.map { SecureStringFetchExpectation(key: $0.0, newDef: $0.1) }
                        XCTAssertEqual(actual, fetchedSecureStringKeys)
                    }
                }

                if let expectedMutations = fixture.expected.recordedMutations {
                    guard let actualMutations = recordingMutator?.recordedMutations else {
                        return XCTFail("Expected recorded mutations for fixture \(fixture.name)")
                    }
                    XCTAssertEqual(actualMutations.tokenHeaderKey, expectedMutations.tokenHeaderKey)
                    XCTAssertEqual(actualMutations.traceIdHeaderKey, expectedMutations.traceIdHeaderKey)
                    if let substitutionHeaderKeys = expectedMutations.substitutionHeaderKeys {
                        XCTAssertEqual(actualMutations.substitutionHeaderKeys, substitutionHeaderKeys.sorted())
                    }
                    if let substitutionQueryParamKeys = expectedMutations.substitutionQueryParamKeys {
                        XCTAssertEqual(actualMutations.substitutionQueryParamKeys, substitutionQueryParamKeys.sorted())
                    }
                    XCTAssertEqual(actualMutations.originalUrl, expectedMutations.originalUrl)
                }
            }
        }
    }
}
