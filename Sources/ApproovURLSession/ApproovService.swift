// MIT License
//
// Copyright (c) 2016-present, Approov Ltd.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
// (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
// ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
// THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation
import Approov
import os.log

// Approov error conditions
public enum ApproovError: Error, LocalizedError {
    case initializationFailure(message: String)
    case configurationError(message: String)
    case pinningError(message: String)
    case networkingError(message: String)
    case permanentError(message: String)
    case rejectionError(message: String, ARC: String, rejectionReasons: String)
    public var localizedDescription: String {
        get {
            switch self {
            case let .initializationFailure(message),
                 let .configurationError(message),
                 let .pinningError(message),
                 let .networkingError(message),
                 let .permanentError(message):
                return message
            case let .rejectionError(message, ARC, rejectionReasons):
                var info: String = ""
                if ARC != "" {
                    info += ", ARC: " + ARC
                }
                if rejectionReasons != "" {
                    info += ", reasons: " + rejectionReasons
                }
                return message + info
            }
        }
    }
    public var errorDescription: String? {
        return localizedDescription
    }
}

// possible results from an Approov request update
public enum ApproovFetchDecision {
    case ShouldProceed      // Proceed with request
    case ShouldRetry        // User can retry request
    case ShouldFail         // Request should not be made
    case ShouldIgnore       // Do not process request
}

// result from adding Approov protection to a request
public struct ApproovUpdateResponse {
    public internal(set) var request: URLRequest
    public internal(set) var decision: ApproovFetchDecision
    public internal(set) var sdkMessage: String
    public internal(set) var error: Error?
}

// Log level for controlling the verbosity of os_log output from the ApproovService
public enum ApproovLogLevel: Int, Comparable {
    case off = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4
    public static func < (lhs: ApproovLogLevel, rhs: ApproovLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// ApproovService provides a mediation layer to the Approov SDK itself
public class ApproovService {
    // private initializer
    private init() {}

    // the dispatch queue to manage serial access to intializer-modified variables
    private static let initializerQueue = DispatchQueue(label: "ApproovService.initializer", qos: .userInitiated)

    // configuration string used for initialization
    private static var configString: String?

    // status of Approov SDK initialization
    private static var serviceIsInitialized = false

    // the dispatch queue to manage serial access to other ApproovService state
    private static let stateQueue = DispatchQueue(label: "ApproovService.state", qos: .userInitiated)

    // binding header name
    private static var bindingHeader = ""

    // Approov token default header
    private static var approovTokenHeader = "Approov-Token"

    // Approov token custom prefix: any prefix to be added such as "Bearer "
    private static var approovTokenPrefix = ""

    // Approov TraceID optional header
    private static var approovTraceIDHeader: String? = "Approov-TraceID"

    // The mutator instance used to control ApproovService behavior at key points in the flow.
    // Unless set using the ApproovService.setServiceMutator() method, the default
    // behaviour defined in the default implementation of ApproovServiceMutator will be used.
    private static var serviceMutator: ApproovServiceMutator = ApproovCloseFailureMutator.instance

    // dedicated queue for thread-safe access to the logging level (separate from stateQueue to
    // avoid nested sync deadlocks when logging is checked inside stateQueue-protected methods)
    private static let loggingQueue = DispatchQueue(label: "ApproovService.logging", qos: .userInitiated)
    private static var _loggingLevel: ApproovLogLevel = .info

    // the current logging level for os_log output from the ApproovService
    static var loggingLevel: ApproovLogLevel {
        get { loggingQueue.sync { _loggingLevel } }
        set { loggingQueue.sync { _loggingLevel = newValue } }
    }

    // receives every line the layer writes, with its level, for tests
    private static var _logSink: ((ApproovLogLevel, String) -> Void)?
    static var logSink: ((ApproovLogLevel, String) -> Void)? {
        get { loggingQueue.sync { _logSink } }
        set { loggingQueue.sync { _logSink = newValue } }
    }

    /**
     * Writes one line of the layer's log, if the logging level allows its level. Every line the layer
     * writes goes through here, so OFF silences the layer completely.
     *
     * @param level is the severity of the line
     * @param message is the line, built only if it is written
     */
    static func log(_ level: ApproovLogLevel, _ message: @autoclosure () -> String) {
        guard level != .off, loggingLevel >= level else {
            return
        }
        let line = message()
        logSink?(level, line)
        let type: OSLogType
        switch level {
        case .error: type = .error
        case .info: type = .info
        case .debug: type = .debug
        default: type = .default
        }
        os_log("%{public}@", type: type, line)
    }

    // map of headers that should have their values substituted for secure strings, mapped to their
    // required prefixes
    private static var substitutionHeaders: Dictionary<String, String> = Dictionary()

    // set of query parameters that may be substituted, specified by the key name
    private static var substitutionQueryParams: Set<String> = Set()

    // map of URL regexs that should be excluded from any Approov protection, mapped to the compiled Pattern
    private static var exclusionURLRegexs: Dictionary<String, NSRegularExpression> = Dictionary()

    // the ARC of the most recent fetch the layer made, from the request path or a direct method,
    // protected by lastARCQueue
    private static let lastARCQueue = DispatchQueue(label: "ApproovService.lastARC", qos: .userInitiated)
    private static var lastARC = ""


    
    /**
     * Gets the Attestation Response Code (ARC) from the most recent token, secure string or custom JWT
     * fetch made by this layer, either for a request or by a direct method. It performs no fetch of its
     * own, so it can be read after a rejected request to correlate with your backend API. An empty
     * string is returned if no fetch has been made since initialization, if the last fetch carried no
     * ARC, or if ARC is not enabled for the account.
     *
     * @return the ARC of the most recent fetch, or an empty string
     */
    public static func getLastARC() -> String {
        return lastARCQueue.sync { lastARC }
    }

    /**
     * Records the ARC of a fetch result as the most recent one. An empty ARC clears the previous
     * value, as the ARC belongs to the last fetch.
     *
     * @param result is the fetch result
     */
    private static func recordLastARC(_ result: ApproovTokenFetchResult) {
        lastARCQueue.sync { lastARC = result.arc }
    }

    /**
     * Initializes the ApproovService with the config obtained using `approov sdk -getConfigString`
     * or in the original onboarding email. The service layer resets its own configuration state
     * on a successful call, including any custom service mutator and the status-if-no-token
     * setting. If using a non-empty config, the platform SDK is contacted first; state is
     * only modified after the SDK confirms success, preserving the current operating mode
     * (protected or bypass) if the call fails.
     *
     * @param config is the configuration to be used, or an empty string to bypass the actual initialization
     * @param comment is an optional comment to be passed to the SDK
     * @throws ApproovError if there was a problem
     */
    public static func initialize(config: String, comment: String? = nil) throws {
        try initializerQueue.sync {
            // If we are already initialized with a valid config, ignore any subsequent
            // empty config initialization
            if isApproovEnabledInternal && config.isEmpty {
                log(.info, "ApproovService already initialized with a valid config; ignoring empty configuration")
                return
            }

            // Initialize the platform SDK if not in bypass mode (empty config).
            // State is only modified after the SDK confirms success, preserving the
            // current operating mode (protected or bypass) if the call fails.
            if !config.isEmpty {
                do {
                    // Approov.initialize is an ObjC BOOL-returning method bridged to Swift as throwing.
                    // BOOL=YES (first init)  → no throw  → SDK was just initialized.
                    // BOOL=NO, no NSError   → Foundation._GenericObjCError code 0
                    //                       → SDK already initialized — equivalent to boolean
                    //                         false return on Android; log and continue.
                    // Any other error       → genuine failure → re-throw.
                    try Approov.initialize(config, updateConfig: "auto", comment: comment)
                    log(.info, "ApproovService: Approov SDK initialized")
                } catch let error {
                    // If the error is due to the SDK being initialized already, we ignore it otherwise we throw.
                    // This is an ObjC/Swift interop artifact: ObjC BOOL return of NO without an NSError
                    // is bridged as Foundation._GenericObjCError with code 0.
                    let nsError = error as NSError
                    if nsError.code == 0, nsError.domain == "Foundation._GenericObjCError" {
                        log(.info, "ApproovService: Approov SDK already initialized")
                    } else {
                        // service-layer state NOT modified — prior operating mode preserved
                        throw ApproovError.initializationFailure(message: "Error initializing Approov SDK: \(nsError.localizedDescription)")
                    }
                }
            }
            // SDK succeeded (or bypass) — now reset and commit new service-layer state.
            serviceIsInitialized = false
            configString = config
            stateQueue.sync {
                bindingHeader = ""
                approovTokenHeader = "Approov-Token"
                approovTokenPrefix = ""
                approovTraceIDHeader = "Approov-TraceID"
                serviceMutator = ApproovCloseFailureMutator.instance
                substitutionHeaders = Dictionary()
                substitutionQueryParams = Set()
                exclusionURLRegexs = Dictionary()
                useApproovStatusIfNoToken = false
            }
            lastARCQueue.sync { lastARC = "" }
            serviceIsInitialized = true
            if !config.isEmpty {
                // Must match the top CHANGELOG entry (in lock-step with Package.swift releaseTAG
                // and the podspec s.version); bump all three in a PR before tagging a release.
                Approov.setUserProperty("approov-service-urlsession/3.7.0")
            }
        }
    }

    /**
     * Indicates whether the service layer has been initialized.
     *
     * When initialized with an empty config string this still returns true, even
     * though Approov SDK calls are bypassed and networking proceeds without
     * Approov protection.
     *
     * @return true if the service layer has been initialized, false otherwise
     */
    public static func isInitialized() -> Bool {
        initializerQueue.sync {
            serviceIsInitialized
        }
    }

    private static var isApproovEnabledInternal: Bool {
        serviceIsInitialized && !(configString?.isEmpty ?? true)
    }

    /**
     * Indicates whether Approov protection is enabled for this service layer
     * instance. If initialization used an empty config string then the layer is
     * initialized but Approov protection is bypassed.
     *
     * @return true if Approov protection is enabled, false otherwise
     */
    public static func isApproovEnabled() -> Bool {
        initializerQueue.sync {
            isApproovEnabledInternal
        }
    }

    /**
     * Indicates whether the service layer has been initialized and processes requests. This is
     * true in bypass mode too. It is the same as isInitialized().
     *
     * @return true if the service layer has been initialized, false otherwise
     */
    public static func isApproovServiceEnabled() -> Bool {
        return isInitialized()
    }

    /**
     * Indicates whether Approov protection is enabled, false in bypass mode or before
     * initialization. It is the same as isApproovEnabled().
     *
     * @return true if Approov protection is enabled, false otherwise
     */
    public static func isApproovProtectionEnabled() -> Bool {
        return isApproovEnabled()
    }

    /**
     * Sets a development key indicating that the app is a development version and it should
     * pass attestation even if the app is not registered or it is running on an emulator. The
     * development key value can be rotated at any point in the account if a version of the app
     * containing the development key is accidentally released. This is primarily
     * used for situations where the app package must be modified or resigned in
     * some way as part of the testing process.
     *
     * @param devKey is the development key to be used
     */
    public static func setDevKey(devKey: String) {
        if !isApproovEnabled() {
            log(.error, "ApproovService: setDevKey: SDK not initialized")
            return
        }
        stateQueue.sync {
            Approov.setDevKey(devKey)
            log(.debug, "ApproovService: setDevKey")
        }
    }

    /**
     * Sets the header that the Approov token is added on, as well as an optional
     * prefix String (such as "Bearer "). By default the token is provided on
     * "Approov-Token" with no prefix.
     *
     * @param header is the header to place the Approov token on
     * @param prefix is any prefix String for the Approov token header, or nil for no prefix
     */
    public static func setTokenHeader(header: String, prefix: String?) {
        stateQueue.sync {
            approovTokenHeader = header
            approovTokenPrefix = prefix ?? ""
            log(.debug, "ApproovService: setTokenHeader: \(header) \(prefix ?? "")")
        }
    }

    /**
     * Gets the header that is used to add the Approov token.
     *
     * @return the name of the header used for the Approov token
     */
    public static func getTokenHeader() -> String {
        return stateQueue.sync {
            return approovTokenHeader
        }
    }

    /**
     * Gets the prefix added before the Approov token in its header.
     *
     * @return the prefix, or the empty string for none
     */
    public static func getTokenPrefix() -> String {
        return stateQueue.sync {
            return approovTokenPrefix
        }
    }

    /**
     * Sets the header name used to provide the optional Approov TraceID debug value. Passing
     * nil disables the TraceID header.
     *
     * @param header is the header to place the Approov TraceID on, or nil to disable it
     */
    public static func setTraceIDHeader(header: String?) {
        stateQueue.sync {
            approovTraceIDHeader = header
            log(.debug, "ApproovService: setTraceIDHeader: \(header ?? "nil")")
        }
    }

    /**
     * Gets the header that is used to add the optional Approov TraceID debug value.
     *
     * @return the name of the header used for the Approov TraceID, or nil if disabled
     */
    public static func getTraceIDHeader() -> String? {
        return stateQueue.sync {
            return approovTraceIDHeader
        }
    }

    /**
     * Sets the Approov token header and prefix.
     */
    @available(*, deprecated, renamed: "setTokenHeader(header:prefix:)")
    public static func setApproovHeader(header: String, prefix: String) {
        setTokenHeader(header: header, prefix: prefix)
    }

    /**
     * Gets the Approov token header.
     */
    @available(*, deprecated, renamed: "getTokenHeader()")
    public static func getApproovTokenHeader() -> String {
        return getTokenHeader()
    }

    /**
     * Sets the Approov TraceID header, nil to disable it.
     */
    @available(*, deprecated, renamed: "setTraceIDHeader(header:)")
    public static func setApproovTraceIDHeader(header: String?) {
        setTraceIDHeader(header: header)
    }

    /**
     * Gets the Approov TraceID header, nil if disabled.
     */
    @available(*, deprecated, renamed: "getTraceIDHeader()")
    public static func getApproovTraceIDHeader() -> String? {
        return getTraceIDHeader()
    }

    /**
     * Sets a binding header that must be present on all requests using the Approov service. A
     * header should be chosen whose value is unchanging for most requests (such as an
     * Authorization header). A hash of the header value is included in the issued Approov tokens
     * to bind them to the value. This may then be verified by the backend API integration. This
     * method should typically only be called once.
     *
     * @param header is the header to use for Approov token binding
     */
    public static func setBindingHeader(header: String) {
        stateQueue.sync {
            bindingHeader = header
            log(.debug, "ApproovService: setBindingHeader: \(header)")
        }
    }

    // Indicates if the Approov fetch status should be used as the token header value if the token is empty
    private static var useApproovStatusIfNoToken: Bool = false

    /**
     * Sets a flag indicating if the Approov fetch status (e.g. "NO_NETWORK", "MITM_DETECTED")
     * should be used as the token header value if the actual token fetch fails or returns an empty token.
     * This allows passing error condition information to the backend via the Approov-Token header,
     * which might otherwise be empty or missing.
     *
     * @param shouldUse is true if the status should be used as the token value
     */
    public static func setUseApproovStatusIfNoToken(shouldUse: Bool) {
        stateQueue.sync {
            useApproovStatusIfNoToken = shouldUse
            log(.debug, "ApproovService: setUseApproovStatusIfNoToken: \(String(shouldUse))")
        }
    }

    /**
     * Gets whether the Approov fetch status is used as the token header value when no token was
     * obtained.
     *
     * @return true if the status is used, false (the default) for an empty token
     */
    public static func getUseApproovStatusIfNoToken() -> Bool {
        return stateQueue.sync {
            return useApproovStatusIfNoToken
        }
    }

    /**
     * Sets the service-layer logging level.
     *
     * This controls all logging emitted by the ApproovService layer. Set to `.debug`
     * when collecting diagnostics for customer issues.
     *
     * @param level the desired severity level
     */
    public static func setLoggingLevel(_ level: ApproovLogLevel) {
        loggingLevel = level
        log(.info, "ApproovService: logging level set to \(level.rawValue)")
    }

    /**
     * Sets the ApproovServiceMutator instance to handle callbacks from the
     * ApproovService implementation. This facility enables customization of
     * ApproovService operations at key points in the configuration and
     * attestation flows. It should reduce the number of times this service
     * layer implementation needs to be forked in order to introduce custom
     * behavior.
     *
     * @param mutator is the ApproovServiceMutator with callback handlers that may
     *              override the default behavior of the ApproovService singleton.
     *              Passing nil to this method will reinstate the default behavior.
     */
    public static func setServiceMutator(_ mutator: ApproovServiceMutator?) {
        let appliedMutator = mutator ?? ApproovCloseFailureMutator.instance
        log(.debug, "Applied ApproovServiceMutator: \(String(describing: appliedMutator))")
        stateQueue.sync {
            serviceMutator = appliedMutator
        }
    }

    /**
     * Gets the active service mutator instance that is handling callbacks from ApproovService.
     *
     * @return the service mutator instance (never nil)
     */
    public static func getServiceMutator() -> ApproovServiceMutator {
        return stateQueue.sync {
            return serviceMutator
        }
    }

    /**
     * Adds the name of a header which should be subject to secure strings substitution. This
     * means that if the header is present then the value will be used as a key to look up a
     * secure string value which will be substituted into the header value instead. This allows
     * easy migration to the use of secure strings. A required prefix may be specified to deal
     * with cases such as the use of "Bearer " prefixed before values in an authorization header.
     *
     * @param header is the header to be marked for substitution
     * @param prefix is any required prefix to the value being substituted or nil if not required
     */
    public static func addSubstitutionHeader(header: String, prefix: String?) {
        stateQueue.sync {
            if prefix == nil {
                substitutionHeaders[header] = ""
                log(.debug, "ApproovService: addSubstitutionHeader: \(header)")
            } else {
                substitutionHeaders[header] = prefix
                log(.debug, "ApproovService: addSubstitutionHeader: \(header) \(prefix!)")
            }
        }
    }

    /**
     * Removes the name of a header if it exists from the secure strings substitution dictionary.
     *
     * @param header is the name of the header to be removed from substitution
     */
    public static func removeSubstitutionHeader(header: String) {
        stateQueue.sync {
            if substitutionHeaders[header] != nil {
                substitutionHeaders.removeValue(forKey: header)
            }
            log(.debug, "ApproovService: removeSubstitutionHeader: \(header)")
        }
    }

    /**
     * Gets the map of headers that are subject to substitution.
     *
     * @return Dictionary of headers that are subject to substitution, mapped to the required prefix
     */
    public static func getSubstitutionHeaders() -> Dictionary<String, String> {
        return stateQueue.sync {
            return substitutionHeaders
        }
    }

    /**
     * Adds a key name for a query parameter that should be subject to secure strings substitution.
     * This means that if the query parameter is present in a URL then the value will be used as a
     * key to look up a secure string value which will be substituted as the query parameter value
     * instead. This allows easy migration to the use of secure strings. 
     *
     * @param key is the query parameter key name to be added for substitution
     */
    public static func addSubstitutionQueryParam(key: String) {
        stateQueue.sync {
            substitutionQueryParams.insert(key)
            log(.debug, "ApproovService: addSubstitutionQueryParam: \(key)")
        }
    }

    /**
     * Removes a query parameter key name previously added using addSubstitutionQueryParam.
     *
     * @param key is the query parameter key name to be removed for substitution
     */
    public static func removeSubstitutionQueryParam(key: String) {
        stateQueue.sync {
            substitutionQueryParams.remove(key)
            log(.debug, "ApproovService: removeSubstitutionQueryParam: \(key)")
        }
    }

    /**
     * Gets the set of substitution query parameters.
     *
     * @return Set of query parameters to be substituted
     */
    public static func getSubstitutionQueryParams() -> Set<String> {
        return stateQueue.sync {
            return substitutionQueryParams
        }
    }

    /**
     * Adds an exclusion URL regular expression. If a URL for a request matches this regular expression
     * then it will not be subject to any Approov protection. Note that this facility must be used with
     * EXTREME CAUTION due to the impact of dynamic pinning. Pinning may be applied to all domains added
     * using Approov, and updates to the pins are received when an Approov fetch is performed. If you
     * exclude some URLs on domains that are protected with Approov, then these will be protected with
     * Approov pins but without a path to update the pins until a URL is used that is not excluded. Thus
     * you are responsible for ensuring that there is always a possibility of calling a non-excluded
     * URL, or you should make an explicit call to fetchToken if there are persistent pinning failures.
     * Conversely, use of those option may allow a connection to be established before any dynamic pins
     * have been received via Approov, thus potentially opening the channel to a MitM.
     *
     * @param urlRegex is the regular expression that will be compared against URLs to exclude them
     */
    public static func addExclusionURLRegex(urlRegex: String) {
        stateQueue.sync {
            do {
                let regex = try NSRegularExpression(pattern: urlRegex, options: [])
                exclusionURLRegexs[urlRegex] = regex
                log(.debug, "ApproovService: addExclusionURLRegex: \(urlRegex)")
            } catch {
                log(.error, "ApproovService: addExclusionURLRegex: \(urlRegex) error: \(error.localizedDescription)")
            }
        }
    }

    /**
     * Removes an exclusion URL regular expression previously added using addExclusionURLRegex.
     *
     * @param urlRegex is the regular expression that will be compared against URLs to exclude them
     */
    public static func removeExclusionURLRegex(urlRegex: String) {
        stateQueue.sync {
            if exclusionURLRegexs[urlRegex] != nil {
                exclusionURLRegexs.removeValue(forKey: urlRegex)
                log(.debug, "ApproovService: removeExclusionURLRegex: \(urlRegex)")
            }
        }
    }

    /**
     * Gets a copy of the current exclusion URL regexs.
     *
     * @return Dictionary of the exclusion regexs to their respective patterns.
     */
    public static func getExclusionURLRegexs() -> Dictionary<String, NSRegularExpression> {
        return stateQueue.sync {
            return exclusionURLRegexs
        }
    }

    /**
     * Performs a precheck to determine if the app will pass attestation. This requires secure
     * strings to be enabled for the account, although no strings need to be set up. This will
     * likely require network access so may take some time to complete. It may throw an exception
     * if the precheck fails or if there is some other problem. Exceptions could be due to
     * a rejection (throws a ApproovError.rejectionError) type which might include additional
     * information regarding the rejection reason. An ApproovError.networkingError exception should
     * allow a retry operation to be performed and finally if some other error occurs an
     * ApproovError.permanentError is raised. Useful during development to check if the app will pass attestation.
     *
     * @throws ApproovError if there was a problem
     */
    public static func precheck() throws {
        if !isApproovEnabled() {
            log(.error, "ApproovService: precheck: SDK not initialized")
            throw ApproovError.permanentError(message: "precheck: SDK not initialized")
        }
        // try to fetch a non-existent secure string in order to check for a rejection
        let approovResults = Approov.fetchSecureStringAndWait("precheck-dummy-key", nil)
        recordLastARC(approovResults)
        if approovResults.status == ApproovTokenFetchStatus.unknownKey {
            log(.debug, "ApproovService: precheck: success")
        } else {
            log(.debug, "ApproovService: precheck: \(statusName(approovResults.status))")
        }

        // process the returned Approov status using decision maker
        try getServiceMutator().handlePrecheckResult(approovResults)
    }

    /**
     * Gets the device ID used by Approov to identify the particular device that the SDK is running on. Note
     * that different Approov apps on the same device will return a different ID. Moreover, the ID may be
     * changed by an uninstall and reinstall of the app.
     *
     * @return String of the device ID or nil in case of an error
     */
    public static func getDeviceID() -> String? {
        if !isApproovEnabled() {
            log(.error, "ApproovService: getDeviceID: SDK not initialized")
            return nil
        }
        let deviceID = Approov.getDeviceID()
        if (deviceID != nil) {
            log(.debug, "ApproovService: getDeviceID \(deviceID!)")
        }
        return deviceID
    }

    /**
     * Directly sets the data hash to be included in subsequently fetched Approov tokens. If the hash is
     * different from any previously set value then this will cause the next token fetch operation to
     * fetch a new token with the correct payload data hash. The hash appears in the
     * 'pay' claim of the Approov token as a base64 encoded string of the SHA256 hash of the
     * data. Note that the data is hashed locally and never sent to the Approov cloud service.
     *
     * @param data is the data to be hashed and set in the token
     */
    public static func setDataHashInToken(data: String) {
        if !isApproovEnabled() {
            log(.error, "ApproovService: setDataHashInToken: SDK not initialized")
            return
        }
        log(.debug, "ApproovService: setDataHashInToken")
        Approov.setDataHashInToken(data)
    }

    /**
     * Sets the install attributes for this app installation, a signed JWT that is sent with future
     * Approov token fetches and appears in later tokens. The server accepts them only if they are
     * signed, within their expiry and bound to this device ID.
     *
     * @param attrs is the signed JWT holding the new install attributes
     * @throws ApproovError if Approov protection is not enabled
     */
    public static func setInstallAttributes(_ attrs: String) throws {
        if !isApproovEnabled() {
            log(.error, "ApproovService: setInstallAttributes: SDK not initialized")
            throw ApproovError.permanentError(message: "setInstallAttributes: SDK not initialized")
        }
        log(.debug, "ApproovService: setInstallAttributes")
        Approov.setInstallAttrsInToken(attrs)
    }

    /**
     * Performs an Approov token fetch for the given URL. This should be used in situations where it
     * is not possible to use the networking interception to add the token. This will
     * likely require network access so may take some time to complete. If the attestation fails
     * for any reason then an ApproovError is thrown. This will be ApproovNetworkException for
     * networking issues where a user initiated retry of the operation should be allowed. Note that
     * the returned token should NEVER be cached by your app, you should call this function when
     * it is needed.
     *
     * @param url is the full URL (including path) for the token fetch
     * @return String of the fetched token
     * @throws ApproovError if there was a problem
     */
    public static func fetchToken(url: String) throws -> String {
        if !isApproovEnabled() {
            log(.error, "ApproovService: fetchToken: SDK not initialized")
            throw ApproovError.permanentError(message: "fetchToken: SDK not initialized")
        }
        // fetch the Approov token
        let result: ApproovTokenFetchResult = Approov.fetchTokenAndWait(url)
        recordLastARC(result)
        log(.debug, "ApproovService: fetchToken: \(statusName(result.status))")

        // process the status
        try getServiceMutator().handleFetchTokenResult(result)

        // provide the Approov token result
        return result.token
    }

    /**
     * Gets the signature for the given message. This method is obsolete and will return
     * the account-specific message signature.
     *
     * @param message is the message whose content is to be signed
     * @return String of the base64 encoded message signature
     */
    @available(*, deprecated, message: "Use getAccountMessageSignature or getInstallMessageSignature instead.")
    public static func getMessageSignature(message: String) -> String? {
        let firstCall: Bool = loggingQueue.sync {
            defer { messageSignatureWarned = true }
            return !messageSignatureWarned
        }
        if firstCall {
            log(.warning, "ApproovService: getMessageSignature is deprecated, use getAccountMessageSignature")
        }
        return getAccountMessageSignature(message: message)
    }

    /**
     * Gets the name of a token fetch status, as the Android SDK names it, for the token header,
     * error messages and logs. The iOS SDK gives prose rather than the name, so the layer holds the
     * names. A status this table does not know keeps the SDK's own text.
     *
     * @param status is the token fetch status
     * @return the status name, such as "NO_NETWORK"
     */
    static func statusName(_ status: ApproovTokenFetchStatus) -> String {
        switch status {
        case .success: return "SUCCESS"
        case .noNetwork: return "NO_NETWORK"
        case .mitmDetected: return "MITM_DETECTED"
        case .poorNetwork: return "POOR_NETWORK"
        case .noApproovService: return "NO_APPROOV_SERVICE"
        case .badURL: return "BAD_URL"
        case .unknownURL: return "UNKNOWN_URL"
        case .unprotectedURL: return "UNPROTECTED_URL"
        case .notInitialized: return "NOT_INITIALIZED"
        case .rejected: return "REJECTED"
        case .disabled: return "DISABLED"
        case .unknownKey: return "UNKNOWN_KEY"
        case .badKey: return "BAD_KEY"
        case .badPayload: return "BAD_PAYLOAD"
        case .internalError: return "INTERNAL_ERROR"
        @unknown default: return Approov.string(from: status)
        }
    }

    /**
     * Gets the current time corrected to the Approov servers' clock, in milliseconds since the epoch.
     * Message signatures take their created and expires times from it. With an Approov SDK that does not
     * provide this time, it is the device clock.
     *
     * @return the current time in milliseconds, adjusted to the Approov servers' clock
     * @throws ApproovError if Approov protection is not enabled
     */
    public static func getServerAdjustedCurrentTimeMS() throws -> Int64 {
        if !isApproovEnabled() {
            log(.error, "ApproovService: getServerAdjustedCurrentTimeMS: SDK not initialized")
            throw ApproovError.permanentError(message: "getServerAdjustedCurrentTimeMS: SDK not initialized")
        }
        return serverAdjustedTimeMS()
    }

    // whether the device clock warning has been written in this process, protected by loggingQueue
    private static var deviceClockWarned = false

    /**
     * Gets the current time from the Approov SDK, corrected to the Approov servers' clock. An SDK that
     * does not provide it gives the device clock, with one warning.
     *
     * @return the current time in milliseconds since the epoch
     */
    static func serverAdjustedTimeMS() -> Int64 {
        let selector = NSSelectorFromString("getServerAdjustedCurrentTimeMS")
        let sdk: AnyObject = Approov.self
        if sdk.responds(to: selector), let implementation = sdk.method(for: selector) {
            typealias ServerAdjustedTime = @convention(c) (AnyObject, Selector) -> Int64
            let time = unsafeBitCast(implementation, to: ServerAdjustedTime.self)(sdk, selector)
            if time > 0 {
                return time
            }
        }
        let firstUse: Bool = loggingQueue.sync {
            defer { deviceClockWarned = true }
            return !deviceClockWarned
        }
        if firstUse {
            log(.warning, "ApproovService: the Approov servers' time is unavailable, using the device clock")
        }
        return Int64(Date().timeIntervalSince1970 * 1000)
    }

    // the request property holding what the layer changed on a request, which never holds a value the
    // layer installed, only its digest
    private static let protectionKey = "io.approov.service.urlsession.protection"

    // a digest of a header value as the network stack keeps it, trimmed of surrounding whitespace
    private static func headerDigest(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return ApproovDefaultMessageSigning.sha256(data: Data(trimmed.utf8)).base64EncodedString()
    }

    // a copy of a request with the protection record set, or removed when it is nil
    private static func settingProtection(_ record: [String: Any]?, on request: URLRequest) -> URLRequest {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return request
        }
        if let record {
            URLProtocol.setProperty(record, forKey: protectionKey, in: mutable)
        } else {
            URLProtocol.removeProperty(forKey: protectionKey, in: mutable)
        }
        return mutable as URLRequest
    }

    /**
     * Gets the record of what the layer changed on a request it protected.
     *
     * @param request is the request
     * @return the record, or nil if the layer did not protect the request
     */
    static func protectionRecord(of request: URLRequest?) -> [String: Any]? {
        guard let request else {
            return nil
        }
        return URLProtocol.property(forKey: protectionKey, in: request) as? [String: Any]
    }

    /**
     * Records on the protected request what the layer changed from the app's request: each header it
     * added or changed, with the app's own value and a digest of the installed one, and the URL before and
     * after query substitution.
     *
     * @param original is the request as the app made it
     * @param protected is the request the layer protected
     * @return the protected request carrying the record
     */
    private static func recordingProtection(of original: URLRequest, in protected: URLRequest) -> URLRequest {
        let before = original.allHTTPHeaderFields ?? [:]
        var headers: [[String: Any]] = []
        for (name, value) in protected.allHTTPHeaderFields ?? [:] {
            let appValue = before.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
            if appValue == value {
                continue
            }
            var entry: [String: Any] = ["name": name, "installed": headerDigest(value)]
            if let appValue {
                entry["app"] = appValue
            }
            headers.append(entry)
        }
        var record: [String: Any] = ["headers": headers]
        if let originalURL = original.url, let protectedURL = protected.url, originalURL != protectedURL {
            record["originalURL"] = originalURL.absoluteString
            record["protectedURL"] = protectedURL.absoluteString
        }
        if headers.isEmpty && record["protectedURL"] == nil {
            return protected
        }
        return settingProtection(record, on: protected)
    }

    /**
     * Strips what the layer added to a request it protected. A header still holding the value the layer
     * installed is restored to the app's own value, or removed if the app had none, while a header the app
     * changed since is kept. A substituted query is restored to the app's placeholder only if the URL is
     * still the one the protection was applied to; any other URL is left exactly as it is.
     *
     * @param request is the request, which may be a later attempt of a protected request
     * @param record is the record of the protection, by default the one the request carries
     * @return the request without the layer's protection
     */
    static func stripProtection(_ request: URLRequest, record: [String: Any]? = nil) -> URLRequest {
        guard let record = record ?? protectionRecord(of: request) else {
            return request
        }
        var stripped = request
        for entry in record["headers"] as? [[String: Any]] ?? [] {
            guard let name = entry["name"] as? String, let installed = entry["installed"] as? String,
                  let current = stripped.value(forHTTPHeaderField: name), headerDigest(current) == installed else {
                continue
            }
            stripped.setValue(entry["app"] as? String, forHTTPHeaderField: name)
        }
        if let protectedURL = record["protectedURL"] as? String, stripped.url?.absoluteString == protectedURL,
           let originalURL = (record["originalURL"] as? String).flatMap({ URL(string: $0) }) {
            stripped.url = originalURL
        }
        return settingProtection(nil, on: stripped)
    }

    // whether the getMessageSignature deprecation warning has been written in this process,
    // protected by loggingQueue
    private static var messageSignatureWarned = false

    /**
     * Gets the signature for the given message using the account-specific signing key.
     * This key is transmitted to the SDK after a successful fetch if the feature is enabled.
     *
     * @param message is the message whose content is to be signed
     * @return String of the base64 encoded message signature
     */
    public static func getAccountMessageSignature(message: String) -> String? {
        if !isApproovEnabled() {
            log(.error, "ApproovService: getAccountMessageSignature: SDK not initialized")
            return nil
        }
        log(.debug, "ApproovService: getAccountMessageSignature")
        return Approov.getMessageSignature(message)
    }

    /**
     * Gets the signature for the given message using the install-specific signing key.
     * This key is tied to the specific app installation and is transmitted after a successful fetch.
     *
     * @param message is the message whose content is to be signed
     * @return String of the base64 encoded message signature
     */
    public static func getInstallMessageSignature(message: String) -> String? {
        if !isApproovEnabled() {
            log(.error, "ApproovService: getInstallMessageSignature: SDK not initialized")
            return nil
        }
        log(.debug, "ApproovService: getInstallMessageSignature")
        return Approov.getInstallMessageSignature(message)
    }

    /**
     * Fetches a secure string with the given key. If newDef is not nil then a secure string for
     * the particular app instance may be defined. In this case the new value is returned as the
     * secure string. Use of an empty string for newDef removes the string entry. Note that this
     * call may require network transaction and thus may block for some time, so should not be called
     * from the UI thread. If the attestation fails for any reason then an exception is raised. Note
     * that the returned string should NEVER be cached by your app, you should call this function when
     * it is needed. If the fetch fails for any reason an exception is thrown with description.
     * A rejection throws an Approov.rejectionError type which might include additional information
     * regarding the failure reason.
     * An ApproovError.networkingError exception should allow a retry operation to be performed and finally,
     * if some other error occurs, an Approov.permanentError is raised.
     *
     * @param key is the secure string key to be looked up
     * @param newDef is any new definition for the secure string, or nil for lookup only
     * @return secure string (should not be cached by your app) or nil if it was not defined or an error occurred
     * @throws ApproovError if there was a problem
     */
    public static func fetchSecureString(key: String, newDef: String?) throws -> String? {
        if !isApproovEnabled() {
            log(.error, "ApproovService: fetchSecureString: SDK not initialized")
            throw ApproovError.permanentError(message: "fetchSecureString: SDK not initialized")
        }
        // determine the type of operation as the values themselves cannot be logged
        var type = "lookup"
        if newDef != nil {
            type = "definition"
        }

        // try and fetch the secure string
        let approovResult = Approov.fetchSecureStringAndWait(key, newDef)
        recordLastARC(approovResult)
        log(.info, "ApproovService: fetchSecureString: \(type): \(statusName(approovResult.status))")

        // process the returned Approov status using decision maker
        try getServiceMutator().handleFetchSecureStringResult(approovResult, operation: type, key: key)
        return approovResult.secureString
    }

    /**
     * Fetches a custom JWT with the given payload. Note that this call will require network
     * transaction and thus will block for some time, so should not be called from the UI thread.
     * If the fetch fails for any reason an exception will be thrown. Exceptions could be due to
     * malformed JSON string provided (then an `ApproovError.permanentError` is raised), a rejection throws
     * an `ApproovError.rejectionError` type which might include additional information regarding the failure
     * reason. An `ApproovError.networkingError` exception should allow a retry operation to be performed. If
     * some other error occurs an `ApproovError.permanentError` is raised.
     *
     * @param payload is the marshaled JSON object for the claims to be included
     * @return custom JWT string or nil if an error occurred
     * @throws ApproovError if there was a problem
     */
    public static func fetchCustomJWT(payload: String) throws -> String? {
        if !isApproovEnabled() {
            log(.error, "ApproovService: fetchCustomJWT: SDK not initialized")
            throw ApproovError.permanentError(message: "fetchCustomJWT: SDK not initialized")
        }
        // fetch the custom JWT
        let approovResult = Approov.fetchCustomJWTAndWait(payload)
        recordLastARC(approovResult)
        log(.info, "ApproovService: fetchCustomJWT: \(statusName(approovResult.status))")

        // process the returned Approov status using decision maker
        try getServiceMutator().handleFetchCustomJWTResult(approovResult)
        return approovResult.token
    }

    /**
     * Resolves the host of a URL, which Foundation only populates when the string carries a scheme.
     * Callers sometimes pass a bare host name, so that case is handled by parsing it with a scheme
     * added.
     *
     * Matching on an "https" prefix was wrong for every other scheme: "http://example.com" and
     * "wss://example.com" both took the bare-name branch and were rewritten to
     * "https://http://example.com", whose host is not the real one, so the host came back empty or
     * wrong. A non-empty host is now required at each step, because Foundation returns an empty
     * string rather than nil for some malformed inputs and an empty host is not a resolution.
     *
     * Used for logging only. The token fetch is driven from the full URL string, so this does not
     * decide whether a host is protected.
     *
     * @param url is the URL being handled
     * @return the host name, or an empty string when none can be resolved
     */
    // internal rather than private so the resolution can be tested directly. Not part of the public API.
    static func hostnameFromURL(url: URL) -> String {
        // Already a complete URL: use its host as it stands.
        if url.scheme != nil, let host = url.host, !host.isEmpty {
            return host
        }
        // No scheme, so treat the string as a bare host name, which needs one before it will parse.
        if let host = URL(string: "https://" + url.absoluteString)?.host, !host.isEmpty {
            return host
        }
        return ""
    }

    // maps an error from a hook call into the decision: a standard decision keeps its ApproovError, with a
    // retry for a network failure, while any other error is already a URLError and fails the request
    private static func applyMutatorError(_ error: Error,
                                          response: inout ApproovUpdateResponse,
                                          context: String) {
        response.error = error
        if case .networkingError? = error as? ApproovError {
            response.decision = .ShouldRetry
        } else {
            response.decision = .ShouldFail
        }
    }

    /**
     * Convenience function fetching the Approov token and updating the request with it. This will also
     * perform header or query parameter substitutions to include protected secrets.
     *
     * @param request is the original request to be made
     * @param sessionConfig is any URLSessionConfiguration whose httpAdditionalHeaders are consulted for token binding and header substitution lookups (these headers are not merged into the returned request)
     * @return ApproovUpdateResponse providing an updated request, plus any error and status
     */
    public static func updateRequestWithApproov(request: URLRequest, sessionConfig: URLSessionConfiguration?) -> ApproovUpdateResponse {
        return updateRequestWithApproov(request: request, sessionConfig: sessionConfig, mutator: nil)
    }

    /**
     * Updates a request with Approov as the public form does, deciding it with the given mutator, the one
     * the request started with, or with the current one if it is nil.
     */
    static func updateRequestWithApproov(request: URLRequest, sessionConfig: URLSessionConfiguration?,
                                         mutator: ApproovServiceMutator?) -> ApproovUpdateResponse {
        // a request the layer already protected, sent again, is first put back as the app wrote it, so
        // that a substituted secret is never looked up as a key and nothing is added twice
        let request = stripProtection(request)
        var changes = ApproovRequestMutations()
        guard let url = request.url else {
            log(.info, "ApproovService: no url provided")
            return ApproovUpdateResponse(request: request, decision: .ShouldIgnore, sdkMessage: "", error: nil)
        }
        if !isApproovEnabled() {
            log(.debug, "ApproovService: Approov unavailable, forwarding: \(url.host ?? "")")
            return ApproovUpdateResponse(request: request, decision: .ShouldIgnore, sdkMessage: "", error: nil)
        }

        let mutator = mutator ?? getServiceMutator()
        do {
            if try !ApproovRequestPathError.callHook("handleInterceptorShouldProcessRequest", { try mutator.handleInterceptorShouldProcessRequest(request) }) {
                log(.debug, "ApproovService: excluded, forwarding: \(url.host ?? "")")
                return ApproovUpdateResponse(request: request, decision: .ShouldIgnore, sdkMessage: "", error: nil)
            }
        } catch {
            var response = ApproovUpdateResponse(request: request, decision: .ShouldFail, sdkMessage: "", error: nil)
            applyMutatorError(error, response: &response, context: "Interceptor should process request")
            return response
        }

        // we construct a response to return
        var response = ApproovUpdateResponse(request: request, decision: .ShouldFail, sdkMessage: "", error: nil)

        // get all of the headers including those from the session configuration
        var allHeaders: [String: String] = Dictionary()
        if (sessionConfig != nil) && (sessionConfig!.httpAdditionalHeaders != nil) {
            for (key, value) in sessionConfig!.httpAdditionalHeaders! {
                if (key is String) && (value is String) {
                    allHeaders[key as! String] = value as? String
                }
            }
        }
        if (request.allHTTPHeaderFields != nil) {
            for (key, value) in request.allHTTPHeaderFields! {
                allHeaders[key] = value
            }
        }

        // check if Bind Header is set to a non empty String
        let bindHeader = stateQueue.sync {
            return bindingHeader
        }
        if bindHeader != "" {
            // see if the binding header is present
            if let value = allHeaders[bindHeader] {
                // add the binding header value as a data hash to Approov token
                Approov.setDataHashInToken(value)
            }
        }

        // Fetch an Approov token, coalescing concurrent cache misses so a sustained
        // platform failure is cached before the same launch burst makes redundant SDK calls.
        let approovResult = Approov.fetchTokenAndWait(url.absoluteString)
        recordLastARC(approovResult)
        let hostname = hostnameFromURL(url: url)
        log(.debug, "ApproovService: updateRequest \(hostname): \(approovResult.loggableToken())")
        // log if a configuration update is received and call fetchConfig to clear the update state
        if approovResult.isConfigChanged {
            Approov.fetchConfig()
            log(.info, "ApproovService: dynamic configuration update received")
        }
        response.sdkMessage = Approov.string(from: approovResult.status)

        // a protected channel, which may carry secrets, is a token-protected API (SUCCESS) or a
        // secrets-only API (UNPROTECTED_URL) reached over https; any status but these and UNKNOWN_URL is a
        // failure status, which says nothing about the host, so there the pin set decides
        let status = approovResult.status
        let isHTTPS = url.scheme?.lowercased() == "https"
        let isFailure = status != .success && status != .unprotectedURL && status != .unknownURL
        let isProtectedChannel = isHTTPS && (status == .success || status == .unprotectedURL)

        // a failure for a host that is not listed goes out untouched: a standard decision is ignored, and
        // only the app's own throw aborts it
        if isFailure && !isListedHost(url.host) {
            do {
                _ = try ApproovRequestPathError.callHookIgnoringStandardDecisions("handleInterceptorFetchTokenResult") {
                    try mutator.handleInterceptorFetchTokenResult(approovResult, url: url.absoluteString)
                }
            } catch {
                applyMutatorError(error, response: &response, context: "Approov token fetch")
                return response
            }
            warnOfPlaceholdersLeft(in: request, url: url, headers: allHeaders, isHTTPS: isHTTPS, status: status)
            response.decision = .ShouldProceed
            return response
        }

        let shouldAddToken: Bool
        do {
            shouldAddToken = try ApproovRequestPathError.callHook("handleInterceptorFetchTokenResult") {
                try mutator.handleInterceptorFetchTokenResult(approovResult, url: url.absoluteString)
            }
        } catch {
            applyMutatorError(error, response: &response, context: "Approov token fetch")
            return response
        }
        response.decision = .ShouldProceed
        if !isProtectedChannel {
            warnOfPlaceholdersLeft(in: request, url: url, headers: allHeaders, isHTTPS: isHTTPS, status: status)
        }
        if !shouldAddToken && !isProtectedChannel {
            // nothing to add: a host not added to Approov, or a request the mutator sends without headers
            return response
        }

        // the token and trace headers, holding an empty token or the status name after a failure status
        if shouldAddToken && status != .unknownURL && status != .unprotectedURL {
            let (tokenHeader, tokenPrefix, useStatus, traceHeader) = stateQueue.sync {
                (approovTokenHeader, approovTokenPrefix, useApproovStatusIfNoToken, approovTraceIDHeader)
            }
            let token = (approovResult.token.isEmpty && useStatus) ? statusName(status) : approovResult.token
            guard isHeaderCarriable(tokenPrefix) else {
                response.decision = .ShouldFail
                response.error = ApproovRequestPathError.configuration("Approov header \(tokenHeader): invalid character in the token prefix")
                return response
            }
            guard isHeaderCarriable(token) else {
                response.decision = .ShouldFail
                response.error = ApproovRequestPathError.sdkValue("token", header: tokenHeader)
                return response
            }
            response.request.setValue(tokenPrefix + token, forHTTPHeaderField: tokenHeader)
            changes.setTokenHeaderKey(tokenHeader)
            let traceID = approovResult.traceID
            if let traceHeader, !traceHeader.isEmpty, !traceID.isEmpty {
                guard isHeaderCarriable(traceID) else {
                    response.decision = .ShouldFail
                    response.error = ApproovRequestPathError.sdkValue("trace ID", header: traceHeader)
                    return response
                }
                response.request.setValue(traceID, forHTTPHeaderField: traceHeader)
                changes.setTraceIDHeaderKey(traceHeader)
            }
        }

        // secure strings only on a protected channel, every placeholder ending as its value, its status
        // name, or as the app wrote it when the value cannot be carried or the mutator declined it
        if isProtectedChannel {
            do {
                try substituteHeaders(&response.request, headers: allHeaders, mutator: mutator, changes: changes)
                try substituteQueryParams(&response.request, mutator: mutator, changes: changes)
            } catch {
                applyMutatorError(error, response: &response, context: "Secure string substitution")
                return response
            }
        }

        // call the processed request callback
        do {
            response.request = try ApproovRequestPathError.callHook("handleInterceptorProcessedRequest") { try mutator.handleInterceptorProcessedRequest(response.request, changes: changes) }
        } catch {
            applyMutatorError(error, response: &response, context: "Interceptor processed request")
            return response
        }

        response.request = recordingProtection(of: request, in: response.request)
        return response
    }

    /**
     * Determines whether a host is listed, a key of the SDK pin set other than the Managed Trust Roots
     * key "*", compared without regard to case or a trailing dot. While the pins cannot be read, or the
     * pin set is empty, no host is listed.
     *
     * @param host is the request host
     * @return true if the host is listed, false otherwise
     */
    static func isListedHost(_ host: String?) -> Bool {
        guard let host = host, let pins = Approov.getPins("public-key-sha256") else {
            return false
        }
        let wanted = normalisedHost(host)
        return pins.keys.contains { $0 != "*" && normalisedHost($0) == wanted }
    }

    // a host as pins are looked up: lower case, with no trailing dot
    static func normalisedHost(_ host: String) -> String {
        var normalised = host.lowercased()
        if normalised.hasSuffix(".") {
            normalised.removeLast()
        }
        return normalised
    }

    // true if a header can carry the value unchanged: tab and printable ASCII only
    static func isHeaderCarriable(_ value: String) -> Bool {
        return value.unicodeScalars.allSatisfy { $0 == "\t" || ($0.value >= 0x20 && $0.value <= 0x7E) }
    }

    /**
     * Logs a warning for each substitution header or query parameter a request carries that will go out
     * as the app wrote it because the request is not https or its token fetch returned BAD_URL. The field
     * is named, never its value.
     */
    private static func warnOfPlaceholdersLeft(in request: URLRequest, url: URL, headers: [String: String],
                                               isHTTPS: Bool, status: ApproovTokenFetchStatus) {
        guard !isHTTPS || status == .badURL else {
            return
        }
        let reason = isHTTPS ? "BAD_URL" : "not https"
        for (header, _) in getSubstitutionHeaders() where headerValue(header, in: headers) != nil {
            log(.warning, "ApproovService: secure string header \(header) not substituted: \(reason)")
        }
        let present = Set(queryOccurrences(in: url.absoluteString).map { $0.name })
        for key in getSubstitutionQueryParams() where present.contains(key) {
            log(.warning, "ApproovService: secure string query parameter \(key) not substituted: \(reason)")
        }
    }

    // a header value from the request and session headers, matched without regard to case
    private static func headerValue(_ header: String, in headers: [String: String]) -> String? {
        if let value = headers[header] {
            return value
        }
        return headers.first { $0.key.caseInsensitiveCompare(header) == .orderedSame }?.value
    }

    /**
     * Substitutes the secure strings named by the substitution headers of a request on a protected
     * channel. A SUCCESS the mutator accepts replaces the placeholder if a header can carry the value,
     * otherwise the placeholder stays with a warning; a SUCCESS the mutator declines leaves it; any other
     * status replaces it with the status name after the prefix.
     */
    private static func substituteHeaders(_ request: inout URLRequest, headers: [String: String],
                                          mutator: ApproovServiceMutator,
                                          changes: ApproovRequestMutations) throws {
        var substituted: [String] = []
        for (header, prefix) in getSubstitutionHeaders() {
            guard let value = headerValue(header, in: headers), value.hasPrefix(prefix), value.count > prefix.count else {
                continue
            }
            let key = String(value.dropFirst(prefix.count))
            let result = Approov.fetchSecureStringAndWait(key, nil)
            recordLastARC(result)
            log(.debug, "ApproovService: header substitution: \(header), \(statusName(result.status)), ARC: \(result.arc)")
            let accepted = try ApproovRequestPathError.callHook("handleInterceptorHeaderSubstitutionResult") {
                try mutator.handleInterceptorHeaderSubstitutionResult(result, header: header)
            }
            if result.status == .success {
                guard accepted, let secret = result.secureString else {
                    continue
                }
                if isHeaderCarriable(secret) {
                    request.setValue(prefix + secret, forHTTPHeaderField: header)
                    substituted.append(header)
                } else {
                    log(.warning, "ApproovService: secure string header \(header) not substituted: the value cannot be carried in a header")
                }
            } else {
                request.setValue(prefix + statusName(result.status), forHTTPHeaderField: header)
            }
        }
        if !substituted.isEmpty {
            changes.setSubstitutionHeaderKeys(substituted)
        }
    }

    // an occurrence of a query parameter: its name and the range of its value in the URL string, both
    // as they are written in the URL
    struct QueryOccurrence {
        let name: String
        let value: Range<String.Index>
    }

    /**
     * Finds every query parameter in a URL string as it is written, without decoding or re-encoding it.
     *
     * @param urlString is the URL string
     * @return the occurrences in order
     */
    static func queryOccurrences(in urlString: String) -> [QueryOccurrence] {
        guard let queryStart = urlString.firstIndex(of: "?") else {
            return []
        }
        let queryEnd = urlString[queryStart...].firstIndex(of: "#") ?? urlString.endIndex
        var occurrences: [QueryOccurrence] = []
        var fieldStart = urlString.index(after: queryStart)
        while fieldStart <= queryEnd {
            let fieldEnd = urlString[fieldStart..<queryEnd].firstIndex(of: "&") ?? queryEnd
            if let equals = urlString[fieldStart..<fieldEnd].firstIndex(of: "=") {
                let name = String(urlString[fieldStart..<equals])
                occurrences.append(QueryOccurrence(name: name, value: urlString.index(after: equals)..<fieldEnd))
            }
            if fieldEnd == queryEnd {
                break
            }
            fieldStart = urlString.index(after: fieldEnd)
        }
        return occurrences
    }

    // the value of the query occurrence at a position, as written, if the URL still has the same
    // occurrences with the same name there
    private static func readBack(of name: String, at position: Int, count: Int, in urlString: String) -> String? {
        let found = queryOccurrences(in: urlString)
        guard found.count == count, found[position].name == name else {
            return nil
        }
        return String(urlString[found[position].value])
    }

    /**
     * Substitutes the secure strings named by every occurrence of each substitution query parameter of a
     * request on a protected channel, each with its own outcome as for headers. A value is used only if
     * the URL carries it unchanged: the candidate URL must parse and give the value back, as written or
     * percent-decoded, in the same place. The key is matched as a literal string, and nothing else in
     * the URL is changed.
     */
    private static func substituteQueryParams(_ request: inout URLRequest, mutator: ApproovServiceMutator,
                                              changes: ApproovRequestMutations) throws {
        guard let original = request.url?.absoluteString else {
            return
        }
        let keys = getSubstitutionQueryParams()
        var urlString = original
        var substituted: [String] = []
        var index = 0
        while true {
            let occurrences = queryOccurrences(in: urlString)
            guard index < occurrences.count else {
                break
            }
            let occurrence = occurrences[index]
            index += 1
            guard keys.contains(occurrence.name) else {
                continue
            }
            let written = String(urlString[occurrence.value])
            guard !written.isEmpty else {
                continue
            }
            let result = Approov.fetchSecureStringAndWait(written.removingPercentEncoding ?? written, nil)
            recordLastARC(result)
            log(.debug, "ApproovService: query parameter substitution: \(occurrence.name), \(statusName(result.status)), ARC: \(result.arc)")
            let accepted = try ApproovRequestPathError.callHook("handleInterceptorQueryParamSubstitutionResult") {
                try mutator.handleInterceptorQueryParamSubstitutionResult(result, queryKey: occurrence.name)
            }
            let replacement: String
            if result.status == .success {
                guard accepted, let secret = result.secureString else {
                    continue
                }
                replacement = secret
            } else {
                replacement = statusName(result.status)
            }
            var candidate = urlString
            candidate.replaceSubrange(occurrence.value, with: replacement)
            guard let carried = URL(string: candidate)?.absoluteString,
                  readBack(of: occurrence.name, at: index - 1, count: occurrences.count, in: carried)
                    .map({ $0 == replacement || $0.removingPercentEncoding == replacement }) == true else {
                log(.warning, "ApproovService: secure string query parameter \(occurrence.name) not substituted: the value cannot be carried in the URL")
                continue
            }
            urlString = carried
            if result.status == .success {
                substituted.append(occurrence.name)
            }
        }
        if urlString != original, let url = URL(string: urlString) {
            request.url = url
            changes.setSubstitutionQueryParamResults(originalURL: original, substitutionQueryParamKeys: substituted)
        }
    }

    /**
     * Convenience method that applies Approov protection to a URLRequest and returns the
     * protected request directly. This is intended for use with HTTP transports that own their
     * own URLSession (e.g. Apollo iOS, gRPC-Swift) where substituting ApproovURLSession is
     * not possible.
     *
     * The method calls `updateRequestWithApproov` internally and interprets the decision:
     * - `.ShouldProceed`: returns the updated (protected) request.
     * - `.ShouldIgnore`: returns the original request unchanged.
     * - `.ShouldRetry`: throws `ApproovError.networkingError` so the caller can retry.
     * - `.ShouldFail`: throws the underlying error (or `ApproovError.permanentError`).
     *
     * Note: This method performs a synchronous Approov token fetch and may block briefly
     * while the SDK contacts the Approov cloud. Call it from a background thread or async
     * context to avoid blocking the main thread.
     *
     * Example usage with Apollo iOS:
     * ```swift
     * let protected = try ApproovService.signRequest(original)
     * // hand `protected` to your Apollo NetworkTransport
     * ```
     *
     * @param request the original URLRequest to be protected
     * @param sessionConfig optional URLSessionConfiguration whose httpAdditionalHeaders are consulted for token binding and header substitution lookups (these headers are not merged into the returned request)
     * @return the URLRequest with Approov token and substitutions applied (message signing included when configured)
     * @throws Error if the request should not proceed: an `ApproovError` for a decision of the standard
     *         mutators (`ApproovError.networkingError` for a network failure the user may retry), the
     *         `URLError` a custom mutator threw to abort the request, or a `URLError` for any other
     *         failure of a mutator hook (the original as its underlying error) or a configuration error
     *         such as a required body digest that cannot be generated
     *
     * Note: In bypass mode (service layer initialized with an empty config string,
     * isApproovEnabled() == false), this method returns the original request unchanged without
     * Approov protection and without throwing. Callers that must enforce protection should
     * check ApproovService.isApproovEnabled() before calling signRequest.
     */
    public static func signRequest(_ request: URLRequest, sessionConfig: URLSessionConfiguration? = nil) throws -> URLRequest {
        let response = updateRequestWithApproov(request: request, sessionConfig: sessionConfig)
        switch response.decision {
        case .ShouldProceed:
            return response.request
        case .ShouldIgnore:
            return request
        case .ShouldRetry:
            throw response.error ?? ApproovError.networkingError(
                message: "Approov token fetch failed with a retryable error: \(response.sdkMessage)")
        case .ShouldFail:
            throw response.error ?? ApproovError.permanentError(
                message: "Approov token fetch failed: \(response.sdkMessage)")
        }
    }

    static func resetForTesting() {
        PinningURLSessionDelegate.resetForTesting()
        lastARCQueue.sync { lastARC = "" }
        loggingQueue.sync { messageSignatureWarned = false }
        initializerQueue.sync {
            serviceIsInitialized = false
            configString = nil
        }
        stateQueue.sync {
            bindingHeader = ""
            approovTokenHeader = "Approov-Token"
            approovTokenPrefix = ""
            approovTraceIDHeader = "Approov-TraceID"
            serviceMutator = ApproovCloseFailureMutator.instance
            substitutionHeaders = Dictionary()
            substitutionQueryParams = Set()
            exclusionURLRegexs = Dictionary()
            useApproovStatusIfNoToken = false
        }
        loggingLevel = .info
    }
}
