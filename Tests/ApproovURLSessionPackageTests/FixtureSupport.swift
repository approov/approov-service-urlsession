import Approov
import Foundation
import XCTest
@testable import ApproovURLSessionPackage

enum FixtureLoader {
    private static let sharedFixturePathEnvironmentKey = "APPROOV_SHARED_TESTS_PATH"

    static func load<T: Decodable>(_ type: T.Type, named fileName: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: fixtureData(named: fileName))
    }

    private static func fixtureData(named fileName: String) throws -> Data {
        if let sharedFixtureRoot = ProcessInfo.processInfo.environment[sharedFixturePathEnvironmentKey],
           !sharedFixtureRoot.isEmpty {
            let fixtureURL = URL(fileURLWithPath: sharedFixtureRoot, isDirectory: true).appendingPathComponent(fileName)
            return try Data(contentsOf: fixtureURL)
        }

        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let fixtureURL = Bundle.module.url(forResource: baseName, withExtension: "json")
            ?? Bundle.module.url(forResource: baseName, withExtension: "json", subdirectory: "Fixtures")
        guard let fixtureURL else {
            throw NSError(domain: "FixtureLoader", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to load fixture file \(fileName)"
            ])
        }
        return try Data(contentsOf: fixtureURL)
    }
}

struct FixtureSuite<T: Decodable>: Decodable {
    let schemaVersion: Int
    let cases: [T]
}

struct InitializeFixtureCase: Decodable {
    let name: String
    let steps: [InitializeStep]
    let expectedInitializedConfigsCount: Int?
    let expectedInitializedConfigs: [InitializedConfigExpectation]?
}

struct InitializeStep: Decodable {
    let config: String
    let comment: String?
    let expectedError: ErrorExpectation?
}

struct InitializedConfigExpectation: Decodable {
    let config: String
    let updateConfig: String?
    let comment: String?
}

struct UpdateRequestFixtureCase: Decodable {
    let name: String
    let setup: ServiceSetupFixture?
    let request: RequestFixture
    let sdk: SDKFixture?
    let mutator: UpdateMutatorFixture?
    let expected: UpdateRequestExpectation
}

struct ServiceSetupFixture: Decodable {
    let initialize: InitializeCallFixture?
    let approovHeader: HeaderPrefixFixture?
    let disableTraceHeader: Bool?
    let useApproovStatusIfNoToken: Bool?
    let bindingHeader: String?
    let substitutionHeaders: [HeaderPrefixFixture]?
    let substitutionQueryParams: [String]?
    let exclusionRegexes: [String]?
}

struct InitializeCallFixture: Decodable {
    let config: String
    let comment: String?
}

struct HeaderPrefixFixture: Decodable {
    let header: String
    let prefix: String?
}

struct RequestFixture: Decodable {
    let url: String?
    let headers: [String: String]?
    let sessionHeaders: [String: String]?
}

struct SDKFixture: Decodable {
    let defaultTokenResult: TokenFetchResultFixture?
    let defaultSecureStringResult: TokenFetchResultFixture?
    let tokenResults: [TokenResultByURLFixture]?
    let secureStringResults: [TokenResultByKeyFixture]?
    let customJwtResult: TokenFetchResultFixture?
}

struct TokenResultByURLFixture: Decodable {
    let url: String
    let result: TokenFetchResultFixture
}

struct TokenResultByKeyFixture: Decodable {
    let key: String
    let result: TokenFetchResultFixture
}

struct TokenFetchResultFixture: Decodable {
    let status: TokenStatusFixture
    let token: String?
    let traceId: String?
    let secureString: String?
    let arc: String?
    let rejectionReasons: String?
    let isConfigChanged: Bool?
    let isForceApplyPins: Bool?
    let loggableToken: String?
}

enum TokenStatusFixture: String, Decodable {
    case success
    case noNetwork
    case mitmDetected
    case poorNetwork
    case noApproovService
    case badURL
    case unknownURL
    case unprotectedURL
    case notInitialized
    case rejected
    case disabled
    case unknownKey
    case badKey
    case badPayload
    case internalError

    func toApproovStatus() -> ApproovTokenFetchStatus {
        switch self {
        case .success: return .success
        case .noNetwork: return .noNetwork
        case .mitmDetected: return .mitmDetected
        case .poorNetwork: return .poorNetwork
        case .noApproovService: return .noApproovService
        case .badURL: return .badURL
        case .unknownURL: return .unknownURL
        case .unprotectedURL: return .unprotectedURL
        case .notInitialized: return .notInitialized
        case .rejected: return .rejected
        case .disabled: return .disabled
        case .unknownKey: return .unknownKey
        case .badKey: return .badKey
        case .badPayload: return .badPayload
        case .internalError: return .internalError
        }
    }
}

enum DecisionFixture: String, Decodable {
    case proceed
    case retry
    case fail
    case ignore

    func toDecision() -> ApproovFetchDecision {
        switch self {
        case .proceed: return .ShouldProceed
        case .retry: return .ShouldRetry
        case .fail: return .ShouldFail
        case .ignore: return .ShouldIgnore
        }
    }
}

struct UpdateRequestExpectation: Decodable {
    let decision: DecisionFixture
    let sdkMessage: String?
    let error: ErrorExpectation?
    let requestUrl: String?
    let requestUrlContains: String?
    let headerValues: [String: String]?
    let absentHeaders: [String]?
    let sdk: SDKExpectation?
    let recordedMutations: RecordedMutationsExpectation?
}

struct SDKExpectation: Decodable {
    let dataHashes: [String]?
    let fetchedConfigCount: Int?
    let fetchedTokenUrls: [String]?
    let fetchedSecureStringKeys: [SecureStringFetchExpectation]?
}

struct SecureStringFetchExpectation: Decodable, Equatable {
    let key: String
    let newDef: String?
}

struct RecordedMutationsExpectation: Decodable {
    let tokenHeaderKey: String?
    let traceIdHeaderKey: String?
    let substitutionHeaderKeys: [String]?
    let substitutionQueryParamKeys: [String]?
    let originalUrl: String?
}

struct UpdateMutatorFixture: Decodable {
    let shouldProcessRequest: BoolActionFixture?
    let headerSubstitution: BoolActionFixture?
    let querySubstitution: BoolActionFixture?
    let processedRequest: ProcessedRequestActionFixture?
}

enum BoolActionFixture: Decodable {
    case returnValue(Bool)
    case throwError(ErrorExpectation)

    private enum CodingKeys: String, CodingKey {
        case mode
        case value
        case error
    }

    private enum Mode: String, Decodable {
        case returnValue
        case throwError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .returnValue:
            self = .returnValue(try container.decode(Bool.self, forKey: .value))
        case .throwError:
            self = .throwError(try container.decode(ErrorExpectation.self, forKey: .error))
        }
    }
}

enum ProcessedRequestActionFixture: Decodable {
    case recordAndAddHeader(String, String)
    case throwError(ErrorExpectation)

    private enum CodingKeys: String, CodingKey {
        case mode
        case header
        case value
        case error
    }

    private enum Mode: String, Decodable {
        case recordAndAddHeader
        case throwError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .recordAndAddHeader:
            self = .recordAndAddHeader(
                try container.decode(String.self, forKey: .header),
                try container.decode(String.self, forKey: .value)
            )
        case .throwError:
            self = .throwError(try container.decode(ErrorExpectation.self, forKey: .error))
        }
    }
}

struct MutatorFixtureCase: Decodable {
    let name: String
    let operation: MutatorOperationFixture
    let serviceSetup: MutatorServiceSetupFixture?
    let request: RequestFixture?
    let result: TokenFetchResultFixture?
    let operationName: String?
    let key: String?
    let url: String?
    let header: String?
    let queryKey: String?
    let expected: MutatorExpectation
}

enum MutatorOperationFixture: String, Decodable {
    case precheck
    case fetchToken
    case fetchSecureString
    case fetchCustomJwt
    case interceptorFetchToken
    case interceptorHeaderSubstitution
    case interceptorQueryParamSubstitution
    case interceptorShouldProcessRequest
    case interceptorProcessedRequest
    case pinningShouldProcessRequest
}

struct MutatorServiceSetupFixture: Decodable {
    let exclusionRegexes: [String]?
}

struct MutatorExpectation: Decodable {
    let returnValue: Bool?
    let error: ErrorExpectation?
    let requestUnchanged: Bool?
}

struct ErrorExpectation: Decodable {
    let kind: ErrorKindFixture
    let messageContains: String?
    let arc: String?
    let rejectionReasons: String?
}

enum ErrorKindFixture: String, Decodable {
    case initializationFailure
    case configurationError
    case pinningError
    case networkingError
    case permanentError
    case rejectionError
}

final class FixtureBackedMutator: ApproovServiceMutator {
    private let fixture: UpdateMutatorFixture
    private(set) var recordedMutations = RecordedMutations()

    init(fixture: UpdateMutatorFixture) {
        self.fixture = fixture
    }

    func handleInterceptorShouldProcessRequest(_ request: URLRequest) throws -> Bool {
        if let action = fixture.shouldProcessRequest {
            return try resolve(action: action)
        }
        return try ApproovServiceMutatorDefault.shared.handleInterceptorShouldProcessRequest(request)
    }

    func handleInterceptorHeaderSubstitutionResult(_ approovResults: ApproovTokenFetchResult,
                                                   header: String) throws -> Bool {
        if let action = fixture.headerSubstitution {
            return try resolve(action: action)
        }
        return try ApproovServiceMutatorDefault.shared.handleInterceptorHeaderSubstitutionResult(approovResults, header: header)
    }

    func handleInterceptorQueryParamSubstitutionResult(_ approovResults: ApproovTokenFetchResult,
                                                       queryKey: String) throws -> Bool {
        if let action = fixture.querySubstitution {
            return try resolve(action: action)
        }
        return try ApproovServiceMutatorDefault.shared.handleInterceptorQueryParamSubstitutionResult(approovResults, queryKey: queryKey)
    }

    func handleInterceptorProcessedRequest(_ request: URLRequest,
                                           changes: ApproovRequestMutations) throws -> URLRequest {
        switch fixture.processedRequest {
        case .recordAndAddHeader(let header, let value):
            recordedMutations = RecordedMutations(changes: changes)
            var request = request
            request.setValue(value, forHTTPHeaderField: header)
            return request
        case .throwError(let errorExpectation):
            throw makeError(from: errorExpectation)
        case .none:
            return request
        }
    }

    private func resolve(action: BoolActionFixture) throws -> Bool {
        switch action {
        case .returnValue(let value):
            return value
        case .throwError(let errorExpectation):
            throw makeError(from: errorExpectation)
        }
    }
}

struct RecordedMutations {
    let tokenHeaderKey: String?
    let traceIdHeaderKey: String?
    let substitutionHeaderKeys: [String]
    let substitutionQueryParamKeys: [String]
    let originalUrl: String?

    init() {
        self.tokenHeaderKey = nil
        self.traceIdHeaderKey = nil
        self.substitutionHeaderKeys = []
        self.substitutionQueryParamKeys = []
        self.originalUrl = nil
    }

    init(changes: ApproovRequestMutations) {
        self.tokenHeaderKey = changes.getTokenHeaderKey()
        self.traceIdHeaderKey = changes.getTraceIDHeaderKey()
        self.substitutionHeaderKeys = changes.getSubstitutionHeaderKeys().sorted()
        self.substitutionQueryParamKeys = changes.getSubstitutionQueryParamKeys().sorted()
        self.originalUrl = changes.getOriginalURL()
    }
}

func makeTokenFetchResult(from fixture: TokenFetchResultFixture) -> ApproovTokenFetchResult {
    FakeApproovTokenFetchResult(
        status: fixture.status.toApproovStatus(),
        token: fixture.token ?? "",
        traceID: fixture.traceId ?? "",
        secureString: fixture.secureString,
        arc: fixture.arc ?? "",
        rejectionReasons: fixture.rejectionReasons ?? "",
        isConfigChanged: fixture.isConfigChanged ?? false,
        isForceApplyPins: fixture.isForceApplyPins ?? false,
        loggableToken: fixture.loggableToken
    )
}

func configureSDK(_ sdkClient: FakeApproovSDKClient, with fixture: SDKFixture?) {
    guard let fixture else {
        return
    }
    if let defaultTokenResult = fixture.defaultTokenResult {
        sdkClient.defaultTokenResult = makeTokenFetchResult(from: defaultTokenResult)
    }
    if let defaultSecureStringResult = fixture.defaultSecureStringResult {
        sdkClient.defaultSecureStringResult = makeTokenFetchResult(from: defaultSecureStringResult)
    }
    if let customJwtResult = fixture.customJwtResult {
        sdkClient.customJWTResult = makeTokenFetchResult(from: customJwtResult)
    }
    fixture.tokenResults?.forEach { entry in
        sdkClient.tokenResultsByURL[entry.url] = makeTokenFetchResult(from: entry.result)
    }
    fixture.secureStringResults?.forEach { entry in
        sdkClient.secureStringResultsByKey[entry.key] = makeTokenFetchResult(from: entry.result)
    }
}

func applyServiceSetup(_ setup: ServiceSetupFixture?) throws {
    guard let setup else {
        return
    }
    setup.exclusionRegexes?.forEach { ApproovService.addExclusionURLRegex(urlRegex: $0) }
    if let initialize = setup.initialize {
        try ApproovService.initialize(config: initialize.config, comment: initialize.comment)
    }
    if let approovHeader = setup.approovHeader {
        ApproovService.setApproovHeader(header: approovHeader.header, prefix: approovHeader.prefix ?? "")
    }
    if setup.disableTraceHeader == true {
        ApproovService.setApproovTraceIDHeader(header: nil)
    }
    if let useApproovStatusIfNoToken = setup.useApproovStatusIfNoToken {
        ApproovService.setUseApproovStatusIfNoToken(shouldUse: useApproovStatusIfNoToken)
    }
    if let bindingHeader = setup.bindingHeader {
        ApproovService.setBindingHeader(header: bindingHeader)
    }
    setup.substitutionHeaders?.forEach {
        ApproovService.addSubstitutionHeader(header: $0.header, prefix: $0.prefix ?? "")
    }
    setup.substitutionQueryParams?.forEach {
        ApproovService.addSubstitutionQueryParam(key: $0)
    }
}

func makeRequest(from fixture: RequestFixture) throws -> (URLRequest, URLSessionConfiguration?) {
    let placeholderURL = try XCTUnwrap(URL(string: fixture.url ?? "https://example.com/placeholder"))
    var request = URLRequest(url: placeholderURL)
    fixture.headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    if fixture.url == nil {
        request.url = nil
    }

    let sessionConfig: URLSessionConfiguration?
    if let sessionHeaders = fixture.sessionHeaders {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = sessionHeaders
        sessionConfig = config
    } else {
        sessionConfig = nil
    }

    return (request, sessionConfig)
}

func assertError(_ error: Error?, matches expectation: ErrorExpectation?, file: StaticString = #filePath, line: UInt = #line) {
    guard let expectation else {
        XCTAssertNil(error, file: file, line: line)
        return
    }

    guard let error else {
        XCTFail("Expected error \(expectation.kind.rawValue) but got nil", file: file, line: line)
        return
    }

    switch (expectation.kind, error) {
    case let (.initializationFailure, ApproovError.initializationFailure(message)),
         let (.configurationError, ApproovError.configurationError(message)),
         let (.pinningError, ApproovError.pinningError(message)),
         let (.networkingError, ApproovError.networkingError(message)),
         let (.permanentError, ApproovError.permanentError(message)):
        if let messageContains = expectation.messageContains {
            XCTAssertTrue(message.contains(messageContains), file: file, line: line)
        }
    case let (.rejectionError, ApproovError.rejectionError(message, arc, rejectionReasons)):
        if let messageContains = expectation.messageContains {
            XCTAssertTrue(message.contains(messageContains), file: file, line: line)
        }
        if let expectedArc = expectation.arc {
            XCTAssertEqual(arc, expectedArc, file: file, line: line)
        }
        if let expectedReasons = expectation.rejectionReasons {
            XCTAssertEqual(rejectionReasons, expectedReasons, file: file, line: line)
        }
    default:
        XCTFail("Unexpected error \(error)", file: file, line: line)
    }
}

func makeError(from expectation: ErrorExpectation) -> ApproovError {
    switch expectation.kind {
    case .initializationFailure:
        return .initializationFailure(message: expectation.messageContains ?? "fixture initialization failure")
    case .configurationError:
        return .configurationError(message: expectation.messageContains ?? "fixture configuration error")
    case .pinningError:
        return .pinningError(message: expectation.messageContains ?? "fixture pinning error")
    case .networkingError:
        return .networkingError(message: expectation.messageContains ?? "fixture networking error")
    case .permanentError:
        return .permanentError(message: expectation.messageContains ?? "fixture permanent error")
    case .rejectionError:
        return .rejectionError(
            message: expectation.messageContains ?? "fixture rejection error",
            ARC: expectation.arc ?? "",
            rejectionReasons: expectation.rejectionReasons ?? ""
        )
    }
}

struct FixtureRunEntry: Codable {
    let suite: String
    let harness: String
    let fixture: String
    let status: String
    let durationSeconds: Double
    let failures: [String]
}

struct FixtureRunReport: Codable {
    let fixtures: [FixtureRunEntry]
}

final class FixtureRunReporter: NSObject, XCTestObservation {
    static let shared = FixtureRunReporter()
    private static let outputPrefix = "APPROOV_FIXTURE_RESULT "

    private struct InFlightFixture {
        let id: UUID
        let suite: String
        let harness: String
        let fixture: String
        let startDate: Date
    }

    private let lock = NSLock()
    private var installed = false
    private var currentFixture: InFlightFixture?
    private var failuresByFixture: [UUID: [String]] = [:]
    private var reportEntries: [FixtureRunEntry] = []

    private override init() {
        super.init()
    }

    func installIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else {
            return
        }
        installed = true
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func runFixture<T>(testCase _: XCTestCase,
                       suite: String,
                       harness: String,
                       fixture: String,
                       block: () throws -> T) throws -> T {
        installIfNeeded()
        let id = UUID()
        let inFlight = InFlightFixture(id: id, suite: suite, harness: harness, fixture: fixture, startDate: Date())
        begin(inFlight)
        do {
            let result = try XCTContext.runActivity(named: fixture) { _ in
                try block()
            }
            finish(id: id, thrownError: nil)
            return result
        } catch {
            finish(id: id, thrownError: error)
            throw error
        }
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        lock.lock()
        reportEntries = []
        failuresByFixture = [:]
        currentFixture = nil
        lock.unlock()
    }

    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        lock.lock()
        defer { lock.unlock() }
        guard let currentFixture else {
            return
        }
        failuresByFixture[currentFixture.id, default: []].append(issue.compactDescription)
    }

    private func begin(_ fixture: InFlightFixture) {
        lock.lock()
        currentFixture = fixture
        failuresByFixture[fixture.id] = []
        lock.unlock()
    }

    private func finish(id: UUID, thrownError: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard let currentFixture, currentFixture.id == id else {
            return
        }
        var failures = failuresByFixture[id] ?? []
        if let thrownError {
            failures.append(String(describing: thrownError))
        }
        let duration = Date().timeIntervalSince(currentFixture.startDate)
        let entry = FixtureRunEntry(
            suite: currentFixture.suite,
            harness: currentFixture.harness,
            fixture: currentFixture.fixture,
            status: failures.isEmpty ? "passed" : "failed",
            durationSeconds: duration,
            failures: failures
        )
        reportEntries.append(entry)
        emit(entry)
        failuresByFixture.removeValue(forKey: id)
        self.currentFixture = nil
    }

    private func emit(_ entry: FixtureRunEntry) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(entry),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        print("\(Self.outputPrefix)\(json)")
    }
}
