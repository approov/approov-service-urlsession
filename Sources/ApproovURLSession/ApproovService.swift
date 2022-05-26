// MIT License
//
// Copyright (c) 2016-present, Critical Blue Ltd.
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

public enum ApproovFetchDecision {
    case ShouldProceed
    case ShouldRetry
    case ShouldFail
}
public struct ApproovUpdateResponse {
    var request:URLRequest
    var decision:ApproovFetchDecision
    var sdkMessage:String
    var error:Error?
}

public class ApproovService {
    /* Private initializer */
    fileprivate init(){}
    /* Status of Approov SDK initialisation */
    private static var approovServiceInitialised = false
    /* If we whouls proceed on network fail */
    private static var proceedOnNetworkFail = false
    /* The initial config string used to initialize */
    private static var configString:String?
    /* Binding header string */
    private static var bindHeader = ""
    /* Approov token default header */
    private static var approovTokenHeader = "Approov-Token"
    /* Approov token custom prefix: any prefix to be added such as "Bearer " */
    private static var approovTokenPrefix = ""
    /* The dispatch queue to manage serial access to intializer modified variables */
    private static let initializerQueue = DispatchQueue(label: "ApproovService.initializer")
    /* map of headers that should have their values substituted for secure strings, mapped to their
     * required prefixes
     */
    private static var substitutionHeaders:Dictionary<String,String> = Dictionary<String,String>()
    /* The dispatch queue to manage serial access to the substitution headers dictionary */
    private static let substitutionQueue = DispatchQueue(label: "ApproovService.substitution")
    /** Set of URL regexs that should be excluded from any Approov protection, mapped to the compiled Pattern */
    private static var exclusionURLRegexs: Dictionary<String, NSRegularExpression> = Dictionary<String, NSRegularExpression>();
    
    /* Initializer: config is obtained using `approov sdk -getConfigString`
     * Note the initializer function should only ever be called once. Subsequent calls will be ignored
     * since the ApproovSDK can only be intialized once; if however, an attempt is made to initialize
     * with a different configuration (config) we throw an ApproovException.configurationError
     * If the Approov SDk fails to be initialized for some other reason, an .initializationFailure is raised
     */
    public static func initialize(config: String) throws {
        try initializerQueue.sync  {
            // Check if we attempt to use a different configString
            if (approovServiceInitialised) {
                if (config != configString) {
                    // Throw exception indicating we are attempting to use different config
                    os_log("Approov: Attempting to initialize with different configuration", type: .error)
                    throw ApproovError.configurationError(message: "Attempting to initialize with a different configuration")
                }
                return
            }
            // Initialize Approov SDK
            do {
                if config.count > 0 {
                    // Allow empty config string to initialize
                    try Approov.initialize(config, updateConfig: "auto", comment: nil)
                }
                approovServiceInitialised = true
                ApproovService.configString = config
                Approov.setUserProperty("approov-service-urlsession")
            } catch let error {
                // Log error and throw exception
                os_log("Approov: Error initializing Approov SDK: %@", type: .error, error.localizedDescription)
                throw ApproovError.initializationFailure(message: "Error initializing Approov SDK: \(error.localizedDescription)")
            }
        }
    }// initialize func
    
    /**
     * Sets a flag indicating if the network interceptor should proceed anyway if it is
     * not possible to obtain an Approov token due to a networking failure. If this is set
     * then your backend API can receive calls without the expected Approov token header
     * being added, or without header/query parameter substitutions being made. Note that
     * this should be used with caution because it may allow a connection to be established
     * before any dynamic pins have been received via Approov, thus potentially opening the channel to a MitM.
     *
     * @param proceed is true if Approov networking fails should allow continuation
     */
    public static func setProceedOnNetworkFailure(proceed: Bool) {
        do {
            objc_sync_enter(ApproovService.proceedOnNetworkFail)
            defer { objc_sync_exit(ApproovService.proceedOnNetworkFail) }
            os_log("Approov: setProceedOnNetworkFailure ", type: .info, proceed)
            proceedOnNetworkFail = proceed
        }
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
    public static func setBindingHeader(header:String) {
        do {
            objc_sync_enter(ApproovService.bindHeader)
            defer { objc_sync_exit(ApproovService.bindHeader) }
            ApproovService.bindHeader = header
        }
    }
    
    /**
     * Sets the header that the Approov token is added on, as well as an optional
     * prefix String (such as "Bearer "). By default the token is provided on
     * "Approov-Token" with no prefix.
     *
     * @param header is the header to place the Approov token on
     * @param prefix is any prefix String for the Approov token header
     */
    public static func setApproovHeader(header: String, prefix: String) {
        do {
            objc_sync_enter(ApproovService.approovTokenHeader)
            defer { objc_sync_exit(ApproovService.approovTokenHeader) }
            ApproovService.approovTokenHeader = header
            ApproovService.approovTokenPrefix = prefix
        }
    }

    /*
     *  Allows token prefetch operation to be performed as early as possible. This
     *  permits a token or secure strings to be available while an application might
     *  be loading resources or is awaiting user input. Since the initial fetch is the
     *  most expensive the prefetch can hide the most latency.
     */
    public static let prefetch: Void = {
        initializerQueue.sync {
            if approovServiceInitialised {
                // We succeeded initializing Approov SDK, fetch a token
                Approov.fetchToken({(approovResult: ApproovTokenFetchResult) in
                    // Prefetch done, no need to process response
                }, "approov.io")
            }
        }
    }()
    
    /*
     * Convenience function fetching the Approov token and updating the request with it. This will also
     * perform header substitutions to include protected secrets.
     *
     * @param request is the original request to be made
     * @return ApproovUpdateResponse providing an updated requets, plus an errors and status
     */
    public static func updateRequestWithApproov(request: URLRequest) -> ApproovUpdateResponse {
        // Check if the URL matches one of the exclusion regexs and just proceed
        
        var returnData = ApproovUpdateResponse(request: request, decision: .ShouldFail, sdkMessage: "", error: nil)
        // Check if Bind Header is set to a non empty String
        if ApproovService.bindHeader != "" {
            /*  Query the URLSessionConfiguration for user set headers. They would be set like so:
             *  config.httpAdditionalHeaders = ["Authorization Bearer" : "token"]
             *  Since the URLSessionConfiguration is part of the init call and we store its reference
             *  we check for the presence of a user set header there.
             */
            if let aValue = request.value(forHTTPHeaderField: ApproovService.bindHeader) {
                // Add the Bind Header as a data hash to Approov token
                Approov.setDataHashInToken(aValue)
            }
        }
        // Invoke fetch token sync
        let approovResult = Approov.fetchTokenAndWait(request.url!.absoluteString)
        // Log result of token fetch
        let aHostname = hostnameFromURL(url: request.url!)
        os_log("Approov: updateRequest %@: %@", type: .info, aHostname, approovResult.loggableToken())
        // Update the message
        returnData.sdkMessage = Approov.string(from: approovResult.status)
        switch approovResult.status {
            case ApproovTokenFetchStatus.success:
                // Can go ahead and make the API call with the provided request object
                returnData.decision = .ShouldProceed
                // Set Approov-Token header
                returnData.request.setValue(ApproovService.approovTokenPrefix + approovResult.token, forHTTPHeaderField: ApproovService.approovTokenHeader)
            case ApproovTokenFetchStatus.noNetwork,
                 ApproovTokenFetchStatus.poorNetwork,
                 ApproovTokenFetchStatus.mitmDetected:
                 // Must not proceed with network request and inform user a retry is needed
                returnData.decision = .ShouldRetry
                let error = ApproovError.networkingError(message: returnData.sdkMessage)
                returnData.error = error
                return returnData
            case ApproovTokenFetchStatus.unprotectedURL,
                 ApproovTokenFetchStatus.unknownURL,
                 ApproovTokenFetchStatus.noApproovService:
                // We do NOT add the Approov-Token header to the request headers
                returnData.decision = .ShouldProceed
            default:
                let error = ApproovError.permanentError(message: returnData.sdkMessage)
                returnData.error = error
                returnData.decision = .ShouldFail
                return returnData
        }// switch
        
        // we now deal with any header substitutions, which may require further fetches but these
        // should be using cached results
        let isIllegalSubstitution = (approovResult.status == ApproovTokenFetchStatus.unknownURL)
        // Check for the presence of headers
        if let requestHeaders = returnData.request.allHTTPHeaderFields {
            // Make a copy of the original request so we can modify it
            var replacementRequest = returnData.request
            for (key, _) in substitutionHeaders {
                let header = key
                if let prefix = substitutionHeaders[key] {
                    if let value = requestHeaders[header]{
                        // Check if the request contains the header we want to replace
                        if ((value.hasPrefix(prefix)) && (value.count > prefix.count)){
                            let index = prefix.index(prefix.startIndex, offsetBy: prefix.count)
                            let approovResults = Approov.fetchSecureStringAndWait(String(value.suffix(from:index)), nil)
                            os_log("Approov: Substituting header: %@, %@", type: .info, header, Approov.string(from: approovResults.status))
                            // Process the result of the token fetch operation
                            if approovResults.status == ApproovTokenFetchStatus.success {
                                if isIllegalSubstitution {
                                    // don't allow substitutions on unadded API domains to prevent them accidentally being
                                    // subject to a Man-in-the-Middle (MitM) attack
                                    let error = ApproovError.configurationError(message: "Header substitution: API domain unknown")
                                    returnData.error = error
                                    return returnData
                                }
                                // We add the modified header to the new copy of request
                                if let secureStringResult = approovResults.secureString {
                                    replacementRequest.setValue(prefix + secureStringResult, forHTTPHeaderField: key)
                                } else {
                                    // Secure string is nil
                                    let error = ApproovError.permanentError(message: "Header substitution: key lookup error")
                                    returnData.error = error
                                    return returnData
                                }
                            } else if approovResults.status == ApproovTokenFetchStatus.rejected {
                                // if the request is rejected then we provide a special exception with additional information
                                let error = ApproovError.rejectionError(message: "Header substitution: rejected", ARC: approovResults.arc, rejectionReasons: approovResults.rejectionReasons)
                                returnData.error = error
                                return returnData
                            } else if approovResults.status == ApproovTokenFetchStatus.noNetwork ||
                                        approovResults.status == ApproovTokenFetchStatus.poorNetwork ||
                                        approovResults.status == ApproovTokenFetchStatus.mitmDetected {
                                // we are unable to get the secure string due to network conditions so the request can
                                // be retried by the user later
                                let error = ApproovError.networkingError(message: "Header substitution: network issue, retry needed")
                                returnData.error = error
                                return returnData
                            } else if approovResults.status != ApproovTokenFetchStatus.unknownKey {
                                // we have failed to get a secure string with a more serious permanent error
                                let error = ApproovError.permanentError(message: "Header substitution: " + Approov.string(from: approovResults.status))
                                returnData.error = error
                                return returnData
                            }
                        }// if (value)
                    } // if let value
                }// if let prefix
            }// for
            // Replace the modified request headers to the request
            returnData.request = replacementRequest
        }// if let
        
        return returnData
    }
    
    /*
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
        if approovServiceInitialised {
            ApproovService.substitutionQueue.sync {
                if prefix == nil {
                    ApproovService.substitutionHeaders[header] = ""
                } else {
                    ApproovService.substitutionHeaders[header] = prefix
                }
            }
        }
    }
    
    /*
     * Removes the name of a header if it exists from the secure strings substitution dictionary.
     */
    public static func removeSubstitutionHeader(header: String) {
        ApproovService.substitutionQueue.sync {
            if approovServiceInitialised {
                if ApproovService.substitutionHeaders[header] != nil {
                    ApproovService.substitutionHeaders.removeValue(forKey: header)
                }
            }
        }
    }
    
    /*
     * Fetches a secure string with the given key. If newDef is not nil then a secure string for
     * the particular app instance may be defined. In this case the new value is returned as the
     * secure string. Use of an empty string for newDef removes the string entry. Note that this
     * call may require network transaction and thus may block for some time, so should not be called
     * from the UI thread. If the attestation fails for any reason then an exception is raised. Note
     * that the returned string should NEVER be cached by your app, you should call this function when
     * it is needed. If the fetch fails for any reason an exception is thrown with description. Exceptions
     * could be due to the feature not being enabled from the CLI tools (ApproovError.configurationError
     * type raised), a rejection throws an Approov.rejectionError type which might include additional
     * information regarding the failure reason. An ApproovError.networkingError exception should allow a
     * retry operation to be performed and finally if some other error occurs an Approov.permanentError
     * is raised.
     *
     * @param key is the secure string key to be looked up
     * @param newDef is any new definition for the secure string, or nil for lookup only
     * @return secure string (should not be cached by your app) or nil if it was not defined or an error ocurred
     * @throws exception with description of cause
     */
    public static func fetchSecureString(key: String, newDef: String?) throws -> String? {
        // determine the type of operation as the values themselves cannot be logged
        var type = "lookup"
        if newDef == nil {
            type = "definition"
        }
        // invoke fetch secure string
        let approovResult = Approov.fetchSecureStringAndWait(key, newDef)
        os_log("Approov: fetchSecureString: %@: %@", type: .info, type, Approov.string(from: approovResult.status))
        // process the returned Approov status
        if approovResult.status == ApproovTokenFetchStatus.disabled {
            throw ApproovError.configurationError(message: "fetchSecureString: secure string feature disabled")
        } else if  approovResult.status == ApproovTokenFetchStatus.badKey {
            throw ApproovError.permanentError(message: "fetchSecureString: secure string unknown key")
        } else if approovResult.status == ApproovTokenFetchStatus.rejected {
            // if the request is rejected then we provide a special exception with additional information
            throw ApproovError.rejectionError(message: "fetchSecureString: rejected", ARC: approovResult.arc, rejectionReasons: approovResult.rejectionReasons)
        } else if approovResult.status == ApproovTokenFetchStatus.noNetwork ||
                    approovResult.status == ApproovTokenFetchStatus.poorNetwork ||
                    approovResult.status == ApproovTokenFetchStatus.mitmDetected {
            // we are unable to get the secure string due to network conditions so the request can
            // be retried by the user later
            throw ApproovError.networkingError(message: "fetchSecureString: network issue, retry needed")
        } else if ((approovResult.status != ApproovTokenFetchStatus.success) && (approovResult.status != ApproovTokenFetchStatus.unknownKey)){
            // we are unable to get the secure string due to a more permanent error
            throw ApproovError.permanentError(message: "fetchSecureString: " + Approov.string(from: approovResult.status))

        }
        return approovResult.secureString
    }// fetchSecureString
    
    /*
     * Fetches a custom JWT with the given payload. Note that this call will require network
     * transaction and thus will block for some time, so should not be called from the UI thread.
     * If the fetch fails for any reason an exception will be thrown. Exceptions could be due to
     * malformed JSON string provided (then a ApproovError.permanentError is raised), the feature not
     * being enabled from the CLI tools (ApproovError.configurationError type raised), a rejection throws
     * a ApproovError.rejectionError type which might include additional information regarding the failure
     * reason. An Approov.networkingError exception should allow a retry operation to be performed. Finally
     * if some other error occurs an Approov.permanentError is raised.
     *
     * @param payload is the marshaled JSON object for the claims to be included
     * @return custom JWT string or nil if an error occurred
     * @throws exception with description of cause
     */
    public static func fetchCustomJWT(payload: String) throws -> String? {
        // fetch the custom JWT
        let approovResult = Approov.fetchCustomJWTAndWait(payload)
        // log result of token fetch operation but do not log the value
        os_log("Approov: fetchCustomJWT: %@", type: .info, Approov.string(from: approovResult.status))
        // process the returned Approov status
        if approovResult.status == ApproovTokenFetchStatus.badPayload {
            throw ApproovError.permanentError(message: "fetchCustomJWT: malformed JSON")
        } else if  approovResult.status == ApproovTokenFetchStatus.disabled {
            throw ApproovError.configurationError(message: "fetchCustomJWT: feature not enabled")
        } else if approovResult.status == ApproovTokenFetchStatus.rejected {
            // if the request is rejected then we provide a special exception with additional information
            throw ApproovError.rejectionError(message: "fetchCustomJWT: rejected", ARC: approovResult.arc, rejectionReasons: approovResult.rejectionReasons)
        } else if approovResult.status == ApproovTokenFetchStatus.noNetwork ||
                    approovResult.status == ApproovTokenFetchStatus.poorNetwork ||
                    approovResult.status == ApproovTokenFetchStatus.mitmDetected {
            // we are unable to get the custom JWT due to network conditions so the request can
            // be retried by the user later
            throw ApproovError.networkingError(message: "fetchCustomJWT: network issue, retry needed")
        } else if (approovResult.status != ApproovTokenFetchStatus.success){
            // we are unable to get the custom JWT due to a more permanent error
            throw ApproovError.permanentError(message: "fetchCustomJWT: " + Approov.string(from: approovResult.status))
        }
        return approovResult.token
    }
    
    /*
     * Performs a precheck to determine if the app will pass attestation. This requires secure
     * strings to be enabled for the account, although no strings need to be set up. This will
     * likely require network access so may take some time to complete. It may throw an exception
     * if the precheck fails or if there is some other problem. Exceptions could be due to
     * a rejection (throws a ApproovError.rejectionError) type which might include additional
     * information regarding the rejection reason. An ApproovError.networkingError exception should
     * allow a retry operation to be performed and finally if some other error occurs an
     * ApproovError.permanentError is raised.
     */
    public static func precheck() throws {
        // try to fetch a non-existent secure string in order to check for a rejection
        let approovResults = Approov.fetchSecureStringAndWait("precheck-dummy-key", nil)
        // process the returned Approov status
        if approovResults.status == ApproovTokenFetchStatus.rejected {
            // if the request is rejected then we provide a special exception with additional information
            throw ApproovError.rejectionError(message: "precheck: rejected", ARC: approovResults.arc, rejectionReasons: approovResults.rejectionReasons)
        } else if approovResults.status == ApproovTokenFetchStatus.noNetwork ||
                    approovResults.status == ApproovTokenFetchStatus.poorNetwork ||
                    approovResults.status == ApproovTokenFetchStatus.mitmDetected {
            // we are unable to get the secure string due to network conditions so the request can
            // be retried by the user later
            throw ApproovError.networkingError(message: "precheck: network issue, retry needed")
        } else if (approovResults.status != ApproovTokenFetchStatus.success) && (approovResults.status != ApproovTokenFetchStatus.unknownKey){
            // we are unable to get the secure string due to a more permanent error
            throw ApproovError.permanentError(message: "precheck: " + Approov.string(from: approovResults.status))
        }
    }
    
    /**
     * Checks if the url matches one of the exclusion regexs
     *
     * @param headers is the collection of headers to be updated
     * @return headers passed in, or modified by adding an Approov token header and new header values if required
     * @throws ApproovError if it is not possible to obtain secure strings for substitution
     */

    public static func checkURLIsExcluded(url: URL) -> Bool {
        do {
            objc_sync_enter(ApproovService.exclusionURLRegexs)
            defer { objc_sync_exit(ApproovService.exclusionURLRegexs) }
            // Check if the URL matches one of the exclusion regexs and just return original headers if so
            for (_, regex) in ApproovService.exclusionURLRegexs {
                let urlString = url.absoluteString
                let urlStringRange = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
                let matches: [NSTextCheckingResult] = regex.matches(in: urlString, options: [], range: urlStringRange)
                if !matches.isEmpty {
                    return true;
                }
            }
        }
        return false
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
        do {
            objc_sync_enter(ApproovService.exclusionURLRegexs)
            defer { objc_sync_exit(ApproovService.exclusionURLRegexs) }
            let regex = try NSRegularExpression(pattern: urlRegex, options: [])
            ApproovService.exclusionURLRegexs[urlRegex] = regex
            os_log("Approov: addExclusionURLRegex: %@", type: .debug, urlRegex)
        } catch {
            // TODO wouldn't we rather throw?
            os_log("Approov: addExclusionURLRegex: %@ error: %@", type: .debug, urlRegex, error.localizedDescription)
        }
    }

    /**
     * Removes an exclusion URL regular expression previously added using addExclusionURLRegex.
     *
     * @param urlRegex is the regular expression that will be compared against URLs to exclude them
     */
    public static func removeExclusionURLRegex(urlRegex: String) {
        do {
            objc_sync_enter(ApproovService.exclusionURLRegexs)
            defer { objc_sync_exit(ApproovService.exclusionURLRegexs) }
            if ApproovService.exclusionURLRegexs[urlRegex] != nil {
                os_log("Approov: removeExclusionURLRegex: %@", type: .debug, urlRegex)
                ApproovService.exclusionURLRegexs.removeValue(forKey: urlRegex)
            }
        }
    }
    
    /**
     * Gets the device ID used by Approov to identify the particular device that the SDK is running on. Note
     * that different Approov apps on the same device will return a different ID. Moreover, the ID may be
     * changed by an uninstall and reinstall of the app.
     *
     * @return String of the device ID or nil in case of an error
     */
    public static func getDeviceID() -> String? {
        return Approov.getDeviceID()
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
        Approov.setDataHashInToken(data)
    }
    
    /**
     * Performs an Approov token fetch for the given URL. This should be used in situations where it
     * is not possible to use the networking interception to add the token. This will
     * likely require network access so may take some time to complete. If the attestation fails
     * for any reason then an ApproovException is thrown. This will be ApproovNetworkException for
     * networking issues wher a user initiated retry of the operation should be allowed. Note that
     * the returned token should NEVER be cached by your app, you should call this function when
     * it is needed.
     *
     * @param url is the URL giving the domain for the token fetch
     * @return String of the fetched token
     */
    public static func fetchToken(url: String) -> String {
        let result = Approov.fetchTokenAndWait(url)
        return result.token
    }
    
    /**
     * Gets the signature for the given message. This uses an account specific message signing key that is
     * transmitted to the SDK after a successful fetch if the facility is enabled for the account. Note
     * that if the attestation failed then the signing key provided is actually random so that the
     * signature will be incorrect. An Approov token should always be included in the message
     * being signed and sent alongside this signature to prevent replay attacks. If no signature is
     * available, because there has been no prior fetch or the feature is not enabled, then an
     * ApproovException is thrown.
     *
     * @param message is the message whose content is to be signed
     * @return String of the base64 encoded message signature
     */
    public static func getMessageSignature(message: String) -> String? {
        return Approov.getMessageSignature(message)
    }
} // ApproovService class

