// MIT License
//
// Copyright (c) 2025-present, Approov Ltd.
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

import CommonCrypto
import Foundation
import os.log

/**
 * Provides a base implementation of message signing for Approov when using
 * URLSession requests. This class provides mechanisms to configure and apply
 * message signatures to HTTP requests based on specified parameters and
 * algorithms.
 */
public class ApproovDefaultMessageSigning: ApproovServiceMutator, CustomStringConvertible {

    /**
     * Constant for the SHA-256 digest algorithm (used for body digests).
     */
    public static let DIGEST_SHA256 = "sha-256"

    /**
     * Constant for the SHA-512 digest algorithm (used for body digests).
     */
    public static let DIGEST_SHA512 = "sha-512"

    /**
     * Constant for the ECDSA P-256 with SHA-256 algorithm (used when signing with install private key).
     */
    public static let ALG_ES256 = "ecdsa-p256-sha256"

    /**
     * Constant for the HMAC with SHA-256 algorithm (used when signing with the account signing key).
     */
    public static let ALG_HS256 = "hmac-sha256"

    /**
     * Default factory for generating signature parameters.
     */
    private var defaultFactory: SignatureParametersFactory?

    /**
     * Host-specific factories for generating signature parameters.
     */
    private var hostFactories: [String: SignatureParametersFactory]

    /**
     * Initializer
     */
    public init() {
        hostFactories = [:]
    }

    public var description: String {
        return "ApproovDefaultMessageSigning"
    }

    /**
     * Sets the default factory for generating signature parameters.
     *
     * - Parameter factory: The factory to set as the default.
     * - Returns: The current instance for method chaining.
     */
    public func setDefaultFactory(_ factory: SignatureParametersFactory) -> ApproovDefaultMessageSigning {
        defaultFactory = factory
        return self
    }

    /**
     * Associates a specific host with a factory for generating signature parameters.
     *
     * - Parameters:
     *   - hostName: The host name.
     *   - factory: The factory to associate with the host.
     * - Returns: The current instance for method chaining.
     */
    public func putHostFactory(hostName: String, factory: SignatureParametersFactory) -> ApproovDefaultMessageSigning {
        hostFactories[hostName] = factory
        return self
    }

    /**
     * Builds the signature parameters for a given request.
     *
     * - Parameters:
     *   - provider: The component provider for the request.
     *   - changes: The request mutations to apply.
     * - Returns: The generated `SignatureParameters`, or `nil` if no factory is available.
     */
    private func buildSignatureParameters(provider: ApproovURLSessionComponentProvider, changes: ApproovRequestMutations) throws -> SignatureParameters? {
        let factory = hostFactories[provider.getAuthority()] ?? defaultFactory
        return try factory?.buildSignatureParameters(provider: provider, changes: changes)
    }

    /**
     * Processes a request to add message signature headers.
     *
     * - Parameters:
     *   - request: The original HTTP request.
     *   - changes: The request mutations that were applied by the Approov interceptor.
     * - Returns: The processed HTTP request with the signature headers added.
     * - Throws: An `ApproovError` if an error occurs during processing.
     */
    public func handleInterceptorProcessedRequest(_ request: URLRequest,
                                                  changes: ApproovRequestMutations) throws -> URLRequest {
        return try processedRequest(request, changes: changes)
    }

    /**
     * @deprecated Use ApproovServiceMutator.handleInterceptorProcessedRequest instead.
     *
     *             Currently the method is implemented to maintain backwards
     *             compatibility. A future release will move the implementation
     *             to the ApproovServiceMutator.handleInterceptorProcessedRequest
     *             method.
     */
    @available(*, deprecated, message: "Use handleInterceptorProcessedRequest instead.")
    public func processedRequest(_ request: URLRequest, changes: ApproovRequestMutations) throws -> URLRequest {
        // If the request doesn't have an Approov token, we don't need to sign it
        if (request.allHTTPHeaderFields?[ApproovService.getApproovTokenHeader()]) != nil {
            // Generate and add a message signature
            let provider = ApproovURLSessionComponentProvider(request: request)
            guard let params = try buildSignatureParameters(provider: provider, changes: changes) else {
                // No signature to be added; proceed with the original request
                return request
            }

            // Unsupported signing algorithm is a developer misconfiguration: fail closed
            // (propagate) so it surfaces immediately, and is checked before the fail-open block
            // below so it cannot be swallowed.
            let alg = params.getAlg()
            guard alg == ApproovDefaultMessageSigning.ALG_ES256 || alg == ApproovDefaultMessageSigning.ALG_HS256 else {
                throw ApproovError.permanentError(message: "Unsupported algorithm identifier: \(alg ?? "unknown")")
            }

            // Message signing is fail-open from here (core-project-approov#564): any failure to
            // build the signature base, obtain/decode the SDK signature, decode the ES256
            // ASN.1/DER signature, or serialize the headers logs at error level and proceeds
            // UNSIGNED. The only fail-closed cases are a required body digest that cannot be
            // generated (handled in buildSignatureParameters above) and an unsupported algorithm
            // (checked above). The backend remains the enforcement point for message signatures.
            do {
                // Build the signature base
                let baseBuilder = SignatureBaseBuilder(sigParams: params, ctx: provider)
                let message = try baseBuilder.createSignatureBase()
                // WARNING never log the message as it contains an Approov token which provides access to your API.

                // Generate the signature
                let sigId: String
                let signature: Data
                if alg == ApproovDefaultMessageSigning.ALG_ES256 {
                    sigId = "install"
                    guard let base64Signature = ApproovService.getInstallMessageSignature(message: message),
                          let decodedSignature = Data(base64Encoded: base64Signature) else {
                        if ApproovService.loggingLevel >= .error {
                            os_log("ApproovService: install message signature unavailable, skipping signing", type: .error)
                        }
                        return request
                    }
                    // decode the signature from ASN.1 DER format (a malformed signature fails open via the catch)
                    signature = try ApproovDefaultMessageSigning.decodeASN_1_DER_ES256_Signature(decodedSignature)
                } else {
                    sigId = "account"
                    guard let base64Signature = ApproovService.getAccountMessageSignature(message: message),
                          let decodedSignature = Data(base64Encoded: base64Signature) else {
                        if ApproovService.loggingLevel >= .error {
                            os_log("ApproovService: account message signature unavailable, skipping signing", type: .error)
                        }
                        return request
                    }
                    signature = decodedSignature
                }

                // Create signature headers. A serialization failure (thrown or nil) fails open.
                guard let sigHeader = try SFV.serializeDictionary(key: sigId, data: signature),
                      let sigInputHeader = try SFV.serializeDictionary(key: sigId, innerList: params.toComponentValue()) else {
                    if ApproovService.loggingLevel >= .error {
                        os_log("ApproovService: failed to serialize signature headers, skipping signing", type: .error)
                    }
                    return request
                }

                // Add headers to the request
                var signedRequest = provider.getRequest()
                signedRequest.addValue(sigHeader, forHTTPHeaderField: "Signature")
                signedRequest.addValue(sigInputHeader, forHTTPHeaderField: "Signature-Input")

                if params.isDebugMode() {
                    let digest = ApproovDefaultMessageSigning.sha256(data: Data(message.utf8))
                    // The optional debug digest header must not drop a valid signature on failure.
                    if let sigBaseDigestHeader = try? SFV.serializeDictionary(key: "sha-256", data: digest) {
                        signedRequest.addValue(sigBaseDigestHeader, forHTTPHeaderField: "Signature-Base-Digest")
                    } else if ApproovService.loggingLevel >= .debug {
                        os_log("ApproovService: Failed to serialize Signature-Base-Digest header - no debug entry", type: .debug)
                    }
                }

                // WARNING never log the full request as it contains an Approov token which provides access to your API
                return signedRequest
            } catch {
                // Fail open: building the signature base, decoding the ES256 ASN.1/DER signature,
                // or serializing the headers failed. Log at error and proceed unsigned.
                if ApproovService.loggingLevel >= .error {
                    os_log("ApproovService: message signing failed, proceeding unsigned: %@", type: .error, error.localizedDescription)
                }
                return request
            }
        }

        return request
    }

    /**
     * SHA256 of given input bytes.
     *
     * @param data is the input data
     * @return the hash data
     */
    static func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    // Decode ASN.1 DER encoded ES256 signature into "raw" signature format
    private static func decodeASN_1_DER_ES256_Signature(_ signature: Data) throws -> Data {
        // Work over a 0-based byte array so indexing is safe regardless of any Data slice bounds,
        // and read through a bounds-checked helper so malformed/truncated input THROWS (and is
        // handled fail-open by the caller) rather than triggering an out-of-bounds trap/crash.
        let bytes = [UInt8](signature)
        var offset = 0

        func nextByte() throws -> Int {
            guard offset < bytes.count else {
                throw ApproovError.permanentError(message: "Truncated ASN.1 DER signature")
            }
            let value = Int(bytes[offset])
            offset += 1
            return value
        }

        // Ensure the signature starts with a valid ASN.1 sequence
        guard try nextByte() == 0x30 else {
            throw ApproovError.permanentError(message: "Invalid ASN.1 DER sequence")
        }

        // Read the total length of the sequence
        let sequenceLength = try nextByte()
        guard sequenceLength == bytes.count - 2 else {
            throw ApproovError.permanentError(message: "Invalid ASN.1 DER sequence length")
        }

        // Decode the first integer (r)
        guard try nextByte() == 0x02 else {
            throw ApproovError.permanentError(message: "Invalid ASN.1 DER integer for r")
        }
        let rLength = try nextByte()
        guard rLength > 0, offset + rLength <= bytes.count else {
            throw ApproovError.permanentError(message: "Invalid ASN.1 DER length for r")
        }
        let rBytes = Data(bytes[offset..<(offset + rLength)])
        offset += rLength

        // Decode the second integer (s)
        guard try nextByte() == 0x02 else {
            throw ApproovError.permanentError(message: "Invalid ASN.1 DER integer for s")
        }
        let sLength = try nextByte()
        guard sLength > 0, offset + sLength <= bytes.count else {
            throw ApproovError.permanentError(message: "Invalid ASN.1 DER length for s")
        }
        let sBytes = Data(bytes[offset..<(offset + sLength)])
        offset += sLength

        // Ensure the entire signature has been processed
        guard offset == bytes.count else {
            throw ApproovError.permanentError(message: "Extra data in ASN.1 DER signature")
        }

        return try to32ByteData(bytes: rBytes) + to32ByteData(bytes: sBytes)
    }

    /**
     * Converts one part, encoded as an ASN1Integer, of an ASN.1 DER encoded ES256 signature to a byte array of
     * exactly 32 bytes. Throws IllegalArgumentException if this is not possible.
     *
     * @param bytesAsASN1Integer The ASN1Integer to convert.
     * @return A byte array of length 32, containing the raw bytes of the signature part.
     * @throws IllegalArgumentException if the ASN1Integer is not representing a 32 byte array.
     */
    private static func to32ByteData(bytes: Data) throws -> Data {
        if bytes.count < 32 {
            let padding = Data(repeating: 0, count: 32 - bytes.count)
            return padding + bytes
        } else if bytes.count == 32 {
            // Return as-is if the byte array is exactly 32 bytes
            return bytes
        } else if bytes.count == 33 && bytes.first == 0 {
            // Remove the leading zero if the byte array is 33 bytes and starts with 0
            return bytes.dropFirst()
        } else {
            // Throw an error if the byte array cannot be represented as 32 bytes
            throw ApproovError.permanentError(message: "Not an ASN.1 DER ES256 signature part")
        }
    }

    /**
     * Generates a default `SignatureParametersFactory` with predefined settings and optional base parameters.
     *
     * - Parameter baseParametersOverride: The base parameters to override, or `nil` to use defaults.
     * - Returns: A new instance of `SignatureParametersFactory`.
     */
    public static func generateDefaultSignatureParametersFactory(baseParametersOverride: SignatureParameters? = nil) -> SignatureParametersFactory {
        // Default expiry seconds - must encompass worst-case request retry time and clock skew
        let defaultExpiresLifetime: Int64 = 15
        let baseParameters: SignatureParameters

        if let override = baseParametersOverride {
            baseParameters = override
        } else {
            baseParameters = SignatureParameters()
                .addComponentIdentifier(ApproovURLSessionComponentProvider.DC_METHOD)
                .addComponentIdentifier(ApproovURLSessionComponentProvider.DC_TARGET_URI)
        }

        let defaultSignatureParametersFactory = SignatureParametersFactory()
            .setBaseParameters(baseParameters)
            .setUseInstallMessageSigning()
            .setAddCreated(true)
            .setExpiresLifetime(defaultExpiresLifetime)
            .setAddApproovTokenHeader(true)
            .setAddApproovTraceIDHeader(true)
            .addOptionalHeaders(["Authorization", "Content-Length", "Content-Type"])
        do {
            try defaultSignatureParametersFactory.setBodyDigestConfig(ApproovDefaultMessageSigning.DIGEST_SHA256, required: false)
        } catch {
            // ApproovDefaultMessageSigning.DIGEST_SHA256 is a supported body digest algorithm - will never throw
            if ApproovService.loggingLevel >= .error {
                os_log("ApproovDefaultMessageSigning - generateDefaultSignatureParametersFactory: Failed to set default body digest algorithm", type: .error)
            }
        }
        return defaultSignatureParametersFactory
    }
}

/**
 * Factory class for creating pre-request `SignatureParameters` with configurable settings.
 * Each request passed to the factory builds a new `SignatureParameters` instance based on
 * the configured settings and specific for the request.
 */
public class SignatureParametersFactory {
    private var baseParameters: SignatureParameters?
    private var bodyDigestAlgorithm: String?
    private var bodyDigestRequired: Bool = false
    private var useAccountMessageSigning: Bool = false
    private var addCreated: Bool = false
    private var expiresLifetime: Int64 = 0
    private var addApproovTokenHeader: Bool = false
    private var addApproovTraceIDHeader: Bool = false
    private var optionalHeaders: [String] = []
    private var algorithmOverrideForTesting: String?

    /**
     * Sets the base parameters for the factory.
     *
     * - Parameter baseParameters: The base parameters to set.
     * - Returns: The current instance for method chaining.
     */
    public func setBaseParameters(_ baseParameters: SignatureParameters) -> SignatureParametersFactory {
        self.baseParameters = baseParameters
        return self
    }

    /**
     * Configures the body digest settings for the factory.
     *
     * - Parameters:
     *   - bodyDigestAlgorithm: The digest algorithm to use, or `nil` to disable.
     *   - required: Whether the body digest is required.
     * - Returns: The current instance for method chaining.
     * - Throws: An error if an unsupported algorithm is specified.
     */
    public func setBodyDigestConfig(_ bodyDigestAlgorithm: String?, required: Bool) throws -> SignatureParametersFactory {
        if let algorithm = bodyDigestAlgorithm {
            guard algorithm == ApproovDefaultMessageSigning.DIGEST_SHA256 ||
                  algorithm == ApproovDefaultMessageSigning.DIGEST_SHA512 else {
                throw ApproovError.permanentError(message: "Unsupported body digest algorithm: \(algorithm)")
            }
            self.bodyDigestAlgorithm = algorithm
            self.bodyDigestRequired = required
        } else {
            self.bodyDigestRequired = false
        }
        return self
    }

    /**
     * Configures the factory to use device message signing.
     *
     * - Returns: The current instance for method chaining.
     */
    public func setUseInstallMessageSigning() -> SignatureParametersFactory {
        self.useAccountMessageSigning = false
        return self
    }

    /**
     * Configures the factory to use account message signing.
     *
     * - Returns: The current instance for method chaining.
     */
    public func setUseAccountMessageSigning() -> SignatureParametersFactory {
        self.useAccountMessageSigning = true
        return self
    }

    func setAlgorithmOverrideForTesting(_ algorithm: String?) -> SignatureParametersFactory {
        self.algorithmOverrideForTesting = algorithm
        return self
    }

    /**
     * Sets whether the "created" field should be added to the signature parameters.
     *
     * - Parameter addCreated: Whether to add the "created" field.
     * - Returns: The current instance for method chaining.
     */
    public func setAddCreated(_ addCreated: Bool) -> SignatureParametersFactory {
        self.addCreated = addCreated
        return self
    }

    /**
     * Sets the expiration lifetime for the signature parameters.
     *
     * - Parameter expiresLifetime: The expiration lifetime in seconds. If <=0, no expiration is added.
     * - Returns: The current instance for method chaining.
     */
    public func setExpiresLifetime(_ expiresLifetime: Int64) -> SignatureParametersFactory {
        self.expiresLifetime = expiresLifetime
        return self
    }

    /**
     * Sets whether the Approov token header should be added to the signature parameters.
     *
     * - Parameter addApproovTokenHeader: Whether to add the Approov token header.
     * - Returns: The current instance for method chaining.
     */
    public func setAddApproovTokenHeader(_ addApproovTokenHeader: Bool) -> SignatureParametersFactory {
        self.addApproovTokenHeader = addApproovTokenHeader
        return self
    }

    /**
     * Sets whether the Approov TraceID header should be added to the signature parameters.
     *
     * - Parameter addApproovTraceIDHeader: Whether to add the Approov TraceID header.
     * - Returns: The current instance for method chaining.
     */
    public func setAddApproovTraceIDHeader(_ addApproovTraceIDHeader: Bool) -> SignatureParametersFactory {
        self.addApproovTraceIDHeader = addApproovTraceIDHeader
        return self
    }

    /**
     * Adds optional headers to the signature parameters.
     *
     * - Parameter headers: The headers to add.
     * - Returns: The current instance for method chaining.
     */
    public func addOptionalHeaders(_ headers: [String]) -> SignatureParametersFactory {
        self.optionalHeaders.append(contentsOf: headers)
        return self
    }

    /**
     * Builds the signature parameters for a given request.
     *
     * - Parameters:
     *   - provider: The component provider for the request.
     *   - changes: The request mutations to apply.
     * - Returns: The generated `SignatureParameters`.
     * - Throws: An error if required parameters cannot be generated.
     */
    func buildSignatureParameters(provider: ApproovURLSessionComponentProvider, changes: ApproovRequestMutations) throws -> SignatureParameters {
        var requestParameters: SignatureParameters
        if baseParameters == nil {
            requestParameters = SignatureParameters()
        } else {
            requestParameters = SignatureParameters(base: baseParameters!) // Safe to unwrap, cannot be nil
        }
        requestParameters.setAlg(algorithmOverrideForTesting ?? (useAccountMessageSigning ? ApproovDefaultMessageSigning.ALG_HS256 : ApproovDefaultMessageSigning.ALG_ES256))

        if addCreated || expiresLifetime > 0 {
            let currentTime = Int64(Date().timeIntervalSince1970)
            if addCreated {
                requestParameters.setCreated(currentTime)
            }
            if expiresLifetime > 0 {
                requestParameters.setExpires(currentTime + expiresLifetime)
            }
        }

        if addApproovTokenHeader, let tokenHeaderKey = changes.getTokenHeaderKey() {
            requestParameters.addComponentIdentifier(tokenHeaderKey)
        }

        if addApproovTraceIDHeader, let traceIDHeaderKey = changes.getTraceIDHeaderKey() {
            requestParameters.addComponentIdentifier(traceIDHeaderKey)
        }

        for headerName in optionalHeaders {
            if provider.hasField(name: headerName) {
                requestParameters.addComponentIdentifier(headerName)
            }
        }

        if bodyDigestAlgorithm != nil {
            let bodyDigestCreated = try generateBodyDigest(provider: provider, requestParameters: requestParameters)
            if !bodyDigestCreated && bodyDigestRequired {
                throw ApproovError.permanentError(message: "Failed to create required body digest")
            }
        }

        return requestParameters
    }

    /**
     * Generates a body digest for the request if possible.
     *
     * Warning: This method updates the provider's request with the generated body digest in the header "Content-Digest".
     *
     * - Parameters:
     *   - provider: The component provider for the request.
     *   - requestParameters: The signature parameters to update.
     * - Returns: `true` if the body digest was successfully generated, `false` otherwise.
     */
    private func generateBodyDigest(provider: ApproovURLSessionComponentProvider, requestParameters: SignatureParameters) throws -> Bool {
        var request = provider.getRequest()

        guard let body = SignatureParametersFactory.getHTTPBody(request) else {
            // If there is no body, we can't generate a digest
            return false
        }

        // If no body digest algorithm has been set, we don't generate a digest
        guard let bodyDigestAlg = bodyDigestAlgorithm else {
            return false
        }

        // Generate the digest
        let digest: Data
        switch bodyDigestAlg {
        case ApproovDefaultMessageSigning.DIGEST_SHA256:
            digest = ApproovDefaultMessageSigning.sha256(data: body)
        case ApproovDefaultMessageSigning.DIGEST_SHA512:
            digest = SignatureParametersFactory.sha512(data: body)
        default:
            throw ApproovError.permanentError(message: "Unsupported body digest algorithm: \(bodyDigestAlg)")
        }

        // Add the digest header to the request
        do {
            guard let digestHeader = try SFV.serializeDictionary(key: bodyDigestAlg, data: digest) else {
                throw ApproovError.permanentError(message: "Failed to serialize Content-Digest header")
            }
            request.addValue(digestHeader, forHTTPHeaderField: "Content-Digest")
            provider.setRequest(request)
        } catch let error {
            throw ApproovError.permanentError(message: "Failed to serialize Content-Digest header: \(error)")
        }
        requestParameters.addComponentIdentifier("Content-Digest")
        return true
    }

    /**
     * Gets the HTTP body from the request, either from httpBody or httpBodyStream.
     * 
     * @param request is the URLRequest to extract the body from.
     * @return the HTTP body as Data, or nil if not available.
     */
    private static func getHTTPBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        } else if request.httpBodyStream != nil {
            // httpBodyStream is a one-shot stream; consuming it here would exhaust it
            // before URLSession can send the request body. Return nil to skip digesting
            // stream bodies gracefully rather than silently corrupting the upload.
            return nil
        }
        // No body present — return nil so no Content-Digest is added.
        return nil
    }

    /**
     * SHA512 of given input bytes.
     *
     * @param data is the input data
     * @return the hash data
     */
    private static func sha512(data: Data) -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA512_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA512($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}

/**
 * ApproovURLSessionComponentProvider implements the ComponentProvider protocol for URLSession requests.
 */
class ApproovURLSessionComponentProvider: ComponentProvider {

    private var request: URLRequest

    init(request: URLRequest) {
        self.request = request
    }

    public func getRequest() -> URLRequest {
        return request
    }

    public func setRequest(_ newRequest: URLRequest) {
        self.request = newRequest
    }

    public func getMethod() -> String {
        return request.httpMethod ?? "GET"
    }

    public func getAuthority() -> String {
        return request.url?.host ?? ""
    }

    public func getScheme() -> String {
        return request.url?.scheme ?? "http"
    }

    public func getTargetUri() -> String {
        return request.url?.absoluteString ?? ""
    }

    public func getRequestTarget() -> String {
        var target = getPath()
        if let query = request.url?.query {
            target += "?\(query)"
        }
        return target
    }

    public func getPath() -> String {
        return request.url?.path ?? ""
    }

    public func getQuery() -> String {
        return request.url?.query ?? ""
    }

    public func getQueryParam(name: String) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        let values = queryItems.filter { $0.name == name }.compactMap { $0.value }
        if values.count > 1 {
            // From Section 2.2.8 of the spec: If a parameter name occurs multiple times in a request, the named query
            // parameter MUST NOT be included.
            // If multiple parameters are common within an application, it is RECOMMENDED to sign the entire query
            // string using the @query component identifier defined in Section 2.2.7.
            // To indicate that a query param must not be included, we return nil.
            return nil
        }
        return values.first
    }

    public func hasField(name: String) -> Bool {
        return request.value(forHTTPHeaderField: name) != nil
    }

    public func getField(name: String) -> String? {
        guard let value = request.value(forHTTPHeaderField: name) else {
            return nil
        }
        return ApproovURLSessionComponentProvider.combineFieldValues(fields: [value])
    }

    public func hasBody() -> Bool {
        return request.httpBody != nil || request.httpBodyStream != nil
    }
}

@available(*, deprecated, message: "Use ApproovServiceMutator instead.")
extension ApproovDefaultMessageSigning: ApproovInterceptorExtensions {}
