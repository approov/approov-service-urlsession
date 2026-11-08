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

import Approov
import Foundation

/**
 * ApproovServiceMutator provides an interface for modifying the behavior of
 * the ApproovService class by overriding the default implementations of the
 * defined callbacks. Opportunities to modify behavior are offered at key
 * points in the service and attestation flows.
 *
 * The protocol provides default implementations for all methods, so
 * implementing classes can choose to override only the methods they are
 * interested in. The default implementations provide standard behavior
 * that is suitable for most use cases and provides backwards compatibility
 * with previous versions of this Approov service layer.
 */
public protocol ApproovServiceMutator {
    /**
     * Decides how to handle the token fetch result from an
     * ApproovService.precheck() operation.
     */
    func handlePrecheckResult(_ approovResults: ApproovTokenFetchResult) throws

    /**
     * Decides how to handle the token fetch result from an
     * ApproovService.fetchToken() operation.
     */
    func handleFetchTokenResult(_ approovResults: ApproovTokenFetchResult) throws

    /**
     * Decides how to handle the token fetch result from an
     * ApproovService.fetchSecureString() operation.
     */
    func handleFetchSecureStringResult(_ approovResults: ApproovTokenFetchResult,
                                       operation: String,
                                       key: String) throws

    /**
     * Decides how to handle the token fetch result from an
     * ApproovService.fetchCustomJWT() operation.
     */
    func handleFetchCustomJWTResult(_ approovResults: ApproovTokenFetchResult) throws

    /**
     * Decides whether a request should be processed in the interceptor or not.
     * Called at the start of the ApproovService interceptor processing.
     */
    func handleInterceptorShouldProcessRequest(_ request: URLRequest) throws -> Bool

    /**
     * Decides how to handle the token fetch result from a call to
     * Approov.fetchTokenAndWait() from within the interceptor.
     */
    func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult,
                                           url: String) throws -> Bool

    /**
     * Decides how to handle the token fetch result while substituting headers
     * from within the interceptor.
     */
    func handleInterceptorHeaderSubstitutionResult(_ approovResults: ApproovTokenFetchResult,
                                                   header: String) throws -> Bool

    /**
     * Decides how to handle the token fetch result while substituting query params
     * from within the interceptor.
     */
    func handleInterceptorQueryParamSubstitutionResult(_ approovResults: ApproovTokenFetchResult,
                                                       queryKey: String) throws -> Bool

    /**
     * Called after Approov has processed a network request, allowing further
     * modifications.
     */
    func handleInterceptorProcessedRequest(_ request: URLRequest,
                                           changes: ApproovRequestMutations) throws -> URLRequest

    /**
     * Decides whether certificate pinning should be applied to a request or not.
     * Called at the start of the ApproovService pinning processing.
     */
    func handlePinningShouldProcessRequest(_ request: URLRequest) -> Bool
}

public extension ApproovServiceMutator {
    func handlePrecheckResult(_ approovResults: ApproovTokenFetchResult) throws {
        let status = approovResults.status
        switch status {
        case .rejected:
            throw ApproovError.rejectionError(message: "precheck: REJECTED",
                                              ARC: approovResults.arc,
                                              rejectionReasons: approovResults.rejectionReasons)
        case .noNetwork,
             .poorNetwork,
             .mitmDetected:
            throw ApproovError.networkingError(message: "precheck network error: " + ApproovService.statusName(status))
        case .success,
             .unknownKey:
            return
        default:
            throw ApproovError.permanentError(message: "precheck: " + ApproovService.statusName(status))
        }
    }

    func handleFetchTokenResult(_ approovResults: ApproovTokenFetchResult) throws {
        let status = approovResults.status
        switch status {
        case .success:
            return
        case .noNetwork,
             .poorNetwork,
             .mitmDetected:
            throw ApproovError.networkingError(message: "fetchToken network error: " + ApproovService.statusName(status))
        default:
            throw ApproovError.permanentError(message: "fetchToken: " + ApproovService.statusName(status))
        }
    }

    func handleFetchSecureStringResult(_ approovResults: ApproovTokenFetchResult,
                                       operation: String,
                                       key: String) throws {
        let status = approovResults.status
        switch status {
        case .rejected:
            throw ApproovError.rejectionError(message: "fetchSecureString \(operation) for \(key): REJECTED",
                                              ARC: approovResults.arc,
                                              rejectionReasons: approovResults.rejectionReasons)
        case .noNetwork,
             .poorNetwork,
             .mitmDetected:
            throw ApproovError.networkingError(message: "fetchSecureString \(operation) for \(key): " +
                                               ApproovService.statusName(status))
        case .success,
             .unknownKey:
            return
        default:
            throw ApproovError.permanentError(message: "fetchSecureString \(operation) for \(key): " +
                                              ApproovService.statusName(status))
        }
    }

    func handleFetchCustomJWTResult(_ approovResults: ApproovTokenFetchResult) throws {
        let status = approovResults.status
        switch status {
        case .rejected:
            throw ApproovError.rejectionError(message: "fetchCustomJWT: REJECTED",
                                              ARC: approovResults.arc,
                                              rejectionReasons: approovResults.rejectionReasons)
        case .noNetwork,
             .poorNetwork,
             .mitmDetected:
            throw ApproovError.networkingError(message: "fetchCustomJWT network error: " + ApproovService.statusName(status))
        case .success:
            return
        default:
            throw ApproovError.permanentError(message: "fetchCustomJWT: " + ApproovService.statusName(status))
        }
    }

    func handleInterceptorShouldProcessRequest(_ request: URLRequest) throws -> Bool {
        guard let url = request.url else {
            throw ApproovStandardDecisions.made(.permanentError(message: "handleInterceptorShouldProcessRequest received a request with no URL"))
        }
        let urlString = url.absoluteString
        let urlStringRange = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
        for (_, regex) in ApproovService.getExclusionURLRegexs() {
            if regex.firstMatch(in: urlString, options: [], range: urlStringRange) != nil {
                return false
            }
        }
        return true
    }

    func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult,
                                           url: String) throws -> Bool {
        let status = approovResults.status
        switch status {
        case .success,
             .noApproovService:
            // NO_APPROOV_SERVICE proceeds with an empty token header (or the status) and any trace ID, as
            // evidence that Approov processing occurred
            return true
        case .unknownURL,
             .unprotectedURL:
            // no Approov headers, as an UNKNOWN_URL host is not added to Approov and an UNPROTECTED_URL
            // host is a secrets-only API that needs no token
            return false
        case .noNetwork,
             .poorNetwork,
             .mitmDetected:
            // a network failure proceeds if the status is to be sent in the token header instead
            if ApproovService.getUseApproovStatusIfNoToken() {
                return true
            }
            throw ApproovStandardDecisions.made(.networkingError(message: "Approov token fetch for \(url): " +
                                                                 ApproovService.statusName(status)))
        default:
            throw ApproovStandardDecisions.made(.permanentError(message: "Approov token fetch for \(url): " +
                                                                ApproovService.statusName(status)))
        }
    }

    func handleInterceptorHeaderSubstitutionResult(_ approovResults: ApproovTokenFetchResult,
                                                   header: String) throws -> Bool {
        return standardSubstitution(approovResults)
    }

    func handleInterceptorQueryParamSubstitutionResult(_ approovResults: ApproovTokenFetchResult,
                                                       queryKey: String) throws -> Bool {
        return standardSubstitution(approovResults)
    }

    func handleInterceptorProcessedRequest(_ request: URLRequest,
                                           changes: ApproovRequestMutations) throws -> URLRequest {
        return request
    }

    func handlePinningShouldProcessRequest(_ request: URLRequest) -> Bool {
        return true
    }
}

// the substitution decision of both standard mutators, which substitutes on SUCCESS and never aborts a
// request because of a secure string
private func standardSubstitution(_ approovResults: ApproovTokenFetchResult) -> Bool {
    return approovResults.status == .success
}

// ApproovCloseFailureMutator makes the 3.5.x token decisions, which are also the default implementations: a
// request proceeds on SUCCESS and NO_APPROOV_SERVICE and fails with an ApproovError on any other failure
public final class ApproovCloseFailureMutator: ApproovServiceMutator, CustomStringConvertible {
    static let instance = ApproovCloseFailureMutator()

    private init() {}

    public var description: String {
        return "ApproovServiceMutator.CLOSE_FAILURE"
    }
}

// ApproovAlwaysProceedMutator makes decisions that never abort a request, leaving your backend to decide
public final class ApproovAlwaysProceedMutator: ApproovServiceMutator, CustomStringConvertible {
    static let instance = ApproovAlwaysProceedMutator()

    private init() {}

    public var description: String {
        return "ApproovServiceMutator.ALWAYS_PROCEED"
    }

    public func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult,
                                                  url: String) throws -> Bool {
        switch approovResults.status {
        case .unknownURL, .unprotectedURL:
            // no Approov headers for a host not added to Approov or a secrets-only API
            return false
        default:
            // SUCCESS adds the token, while any failure proceeds with an empty token header or the status
            return true
        }
    }
}

// the standard mutators are static members constrained to their concrete type, since Swift cannot hold a
// static on the protocol type, so they can be written as .CLOSE_FAILURE wherever a mutator is expected
public extension ApproovServiceMutator where Self == ApproovCloseFailureMutator {
    // the 3.5.x decisions, named for decisions that stay fixed
    static var CLOSE_FAILURE: ApproovCloseFailureMutator {
        return ApproovCloseFailureMutator.instance
    }

    // the default decisions of the release, declared as the protocol so stored values keep compiling
    // when it points elsewhere; the Self constraint only lets it be written as .DEFAULT
    static var DEFAULT: ApproovServiceMutator {
        return ApproovCloseFailureMutator.instance
    }
}

public extension ApproovServiceMutator where Self == ApproovAlwaysProceedMutator {
    // the decisions that never abort a request
    static var ALWAYS_PROCEED: ApproovAlwaysProceedMutator {
        return ApproovAlwaysProceedMutator.instance
    }
}

@available(*, deprecated, message: "Use ApproovServiceMutator.DEFAULT or .CLOSE_FAILURE.")
public struct ApproovServiceMutatorDefault: ApproovServiceMutator, CustomStringConvertible {
    public static let shared = ApproovServiceMutatorDefault()

    public var description: String {
        return "ApproovServiceMutator.DEFAULT"
    }

    private init() {}
}
