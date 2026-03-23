import Approov
import Foundation
@testable import ApproovURLSessionPackage

final class FakeApproovTokenFetchResult: ApproovTokenFetchResult {
    private let fakeStatus: ApproovTokenFetchStatus
    private let fakeToken: String
    private let fakeTraceID: String
    private let fakeSecureString: String?
    private let fakeARC: String
    private let fakeRejectionReasons: String
    private let fakeConfigChanged: Bool
    private let fakeForceApplyPins: Bool
    private let fakeMeasurementConfig: Data?
    private let fakeLoggableToken: String

    init(status: ApproovTokenFetchStatus,
         token: String = "",
         traceID: String = "",
         secureString: String? = nil,
         arc: String = "",
         rejectionReasons: String = "",
         isConfigChanged: Bool = false,
         isForceApplyPins: Bool = false,
         measurementConfig: Data? = nil,
         loggableToken: String? = nil) {
        self.fakeStatus = status
        self.fakeToken = token
        self.fakeTraceID = traceID
        self.fakeSecureString = secureString
        self.fakeARC = arc
        self.fakeRejectionReasons = rejectionReasons
        self.fakeConfigChanged = isConfigChanged
        self.fakeForceApplyPins = isForceApplyPins
        self.fakeMeasurementConfig = measurementConfig
        self.fakeLoggableToken = loggableToken ?? token
        super.init()
    }

    override var status: ApproovTokenFetchStatus { fakeStatus }
    override var token: String { fakeToken }
    override var traceID: String { fakeTraceID }
    override var secureString: String? { fakeSecureString }
    override var arc: String { fakeARC }
    override var rejectionReasons: String { fakeRejectionReasons }
    override var isConfigChanged: Bool { fakeConfigChanged }
    override var isForceApplyPins: Bool { fakeForceApplyPins }
    override var measurementConfig: Data? { fakeMeasurementConfig }

    override func loggableToken() -> String {
        return fakeLoggableToken
    }
}

final class FakeApproovSDKClient: ApproovSDKClient {
    var pins: [String: [String]]?
    var tokenResultsByURL: [String: ApproovTokenFetchResult] = [:]
    var secureStringResultsByKey: [String: ApproovTokenFetchResult] = [:]
    var defaultTokenResult: ApproovTokenFetchResult = FakeApproovTokenFetchResult(status: .success)
    var defaultSecureStringResult: ApproovTokenFetchResult = FakeApproovTokenFetchResult(status: .unknownKey)
    var customJWTResult: ApproovTokenFetchResult = FakeApproovTokenFetchResult(status: .success)
    var initializeError: Error?
    var fetchedTokenURLs: [String] = []
    var fetchedAsyncTokenURLs: [String] = []
    var fetchedSecureStringKeys: [(String, String?)] = []
    var fetchedCustomJWTPayloads: [String] = []
    var initializedConfigs: [(String, String?, String?)] = []
    var fetchedConfigCount = 0
    var userProperties: [String?] = []
    var devKeys: [String?] = []
    var dataHashes: [String] = []
    var deviceID: String?
    var accountMessageSignature: String?
    var installMessageSignature: String?

    func getPins(_ pinType: String) -> [String: [String]]? {
        return pins
    }

    func fetchToken(_ callbackHandler: @escaping (ApproovTokenFetchResult) -> Void, _ url: String) {
        fetchedAsyncTokenURLs.append(url)
        callbackHandler(tokenResultsByURL[url] ?? defaultTokenResult)
    }

    func fetchTokenAndWait(_ url: String) -> ApproovTokenFetchResult {
        fetchedTokenURLs.append(url)
        return tokenResultsByURL[url] ?? defaultTokenResult
    }

    func initialize(_ initialConfig: String, updateConfig: String?, comment: String?) throws {
        initializedConfigs.append((initialConfig, updateConfig, comment))
        if let initializeError {
            throw initializeError
        }
    }

    func fetchConfig() -> String? {
        fetchedConfigCount += 1
        return nil
    }

    func fetchSecureStringAndWait(_ key: String, _ newDef: String?) -> ApproovTokenFetchResult {
        fetchedSecureStringKeys.append((key, newDef))
        return secureStringResultsByKey[key] ?? defaultSecureStringResult
    }

    func fetchCustomJWTAndWait(_ payload: String) -> ApproovTokenFetchResult {
        fetchedCustomJWTPayloads.append(payload)
        return customJWTResult
    }

    func setUserProperty(_ property: String?) {
        userProperties.append(property)
    }

    func setDevKey(_ key: String?) {
        devKeys.append(key)
    }

    func setDataHashInToken(_ data: String) {
        dataHashes.append(data)
    }

    func getDeviceID() -> String? {
        return deviceID
    }

    func getMessageSignature(_ message: String) -> String? {
        return accountMessageSignature
    }

    func getInstallMessageSignature(_ message: String) -> String? {
        return installMessageSignature
    }

    func string(from status: ApproovTokenFetchStatus) -> String {
        switch status {
        case .success:
            return "SUCCESS"
        case .noNetwork:
            return "NO_NETWORK"
        case .mitmDetected:
            return "MITM_DETECTED"
        case .poorNetwork:
            return "POOR_NETWORK"
        case .noApproovService:
            return "NO_APPROOV_SERVICE"
        case .badURL:
            return "BAD_URL"
        case .unknownURL:
            return "UNKNOWN_URL"
        case .unprotectedURL:
            return "UNPROTECTED_URL"
        case .notInitialized:
            return "NOT_INITIALIZED"
        case .rejected:
            return "REJECTED"
        case .disabled:
            return "DISABLED"
        case .unknownKey:
            return "UNKNOWN_KEY"
        case .badKey:
            return "BAD_KEY"
        case .badPayload:
            return "BAD_PAYLOAD"
        case .internalError:
            return "INTERNAL_ERROR"
        @unknown default:
            return "UNKNOWN_STATUS"
        }
    }
}
