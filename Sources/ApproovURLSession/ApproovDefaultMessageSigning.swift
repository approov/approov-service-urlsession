
import CommonCrypto
import Foundation
import os.log
import RawStructuredFieldValues

/**
 * Provides a base implementation of message signing for Approov when using
 * URLSession requests. This class provides mechanisms to configure and apply
 * message signatures to HTTP requests based on specified parameters and
 * algorithms.
 */
public class ApproovDefaultMessageSigning: ApproovInterceptorExtensions {

    /**
     * Constant for the SHA-256 digest algorithm (used for body digests).
     */
    static let DIGEST_SHA256 = "sha-256"

    /**
     * Constant for the SHA-512 digest algorithm (used for body digests).
     */
    static let DIGEST_SHA512 = "sha-512"

    /**
     * Constant for the ECDSA P-256 with SHA-256 algorithm (used when signing with install private key).
     */
    static let ALG_ES256 = "ecdsa-p256-sha256"

    /**
     * Constant for the HMAC with SHA-256 algorithm (used when signing with the account signing key).
     */
    static let ALG_HS256 = "hmac-sha256"

    /**
     * Default factory for generating signature parameters.
     */
    private static var defaultFactory: SignatureParametersFactory?

    /**
     * Host-specific factories for generating signature parameters.
     */
    private static var hostFactories: [String: SignatureParametersFactory] = [:]

    /**
     * Sets the default factory for generating signature parameters.
     *
     * - Parameter factory: The factory to set as the default.
     * - Returns: The current instance for method chaining.
     */
    public static func setDefaultFactory(_ factory: SignatureParametersFactory) -> ApproovDefaultMessageSigning {
        self.defaultFactory = factory
        return ApproovDefaultMessageSigning()
    }

    /**
     * Associates a specific host with a factory for generating signature parameters.
     *
     * - Parameters:
     *   - hostName: The host name.
     *   - factory: The factory to associate with the host.
     * - Returns: The current instance for method chaining.
     */
    public static func putHostFactory(hostName: String, factory: SignatureParametersFactory) -> ApproovDefaultMessageSigning {
        self.hostFactories[hostName] = factory
        return ApproovDefaultMessageSigning()
    }

    /**
     * Builds the signature parameters for a given request.
     *
     * - Parameters:
     *   - provider: The component provider for the request.
     *   - changes: The request mutations to apply.
     * - Returns: The generated `SignatureParameters`, or `nil` if no factory is available.
     */
    private func buildSignatureParameters(provider: ApproovURLSessionComponentProvider, changes: ApproovRequestMutations) -> SignatureParameters? {
        let factory = ApproovDefaultMessageSigning.hostFactories[provider.getAuthority()] ?? ApproovDefaultMessageSigning.defaultFactory
        return factory?.buildSignatureParameters(provider: provider, changes: changes)
    }

    // UNUSED
    // /**
    //  * Converts one part of an ASN.1 DER encoded ES256 signature to a byte array of exactly 32 bytes.
    //  *
    //  * - Parameter bytesAsBigInt: The BigInt representation of the ASN.1 integer.
    //  * - Returns: A byte array of length 32.
    //  * - Throws: An error if the integer cannot be represented as a 32-byte array.
    //  */
    // private func to32ByteArray(bytesAsBigInt: Data) throws -> Data {
    //     var bytes = bytesAsBigInt
    //     if bytes.count < 32 {
    //         let padding = Data(repeating: 0, count: 32 - bytes.count)
    //         return padding + bytes
    //     } else if bytes.count == 32 {
    //         return bytes
    //     } else if bytes.count == 33 && bytes.first == 0 {
    //         return bytes.dropFirst()
    //     } else {
    //         throw ApproovError.permanentError(message: "Not an ASN.1 DER ES256 signature part")
    //     }
    // }

    /**
     * Processes a request to add message signature headers.
     *
     * - Parameters:
     *   - request: The original HTTP request.
     *   - changes: The request mutations that were applied by the Approov interceptor.
     * - Returns: The processed HTTP request with the signature headers added.
     * - Throws: An `ApproovError` if an error occurs during processing.
     */
    public func processedRequest(_ request: URLRequest, changes: ApproovRequestMutations) throws -> URLRequest {
        // If the request doesn't have an Approov token, we don't need to sign it
        if (request.allHTTPHeaderFields?["Approov-Token"]) != nil {
            // Generate and add a message signature
            let provider = ApproovURLSessionComponentProvider(request: request)
            guard let params = ApproovDefaultMessageSigning.generateSignatureParameters(provider: provider) else {
                // No signature to be added; proceed with the original request
                return request
            }

            // Build the signature base
            let baseBuilder = SignatureBaseBuilder(sigParams: params, ctx: provider)
            let message = try baseBuilder.createSignatureBase()

            // WARNING: Never log the message as it contains sensitive information
            // TODO Log what we are doing

            // Generate the signature
            let sigId: String
            let signature: Data
            switch params.getAlg() {
            case "ecdsa-p256-sha256":
                sigId = "install"
                guard let base64Signature = ApproovService.getInstallMessageSignature(message: message),
                      let decodedSignature = Data(base64Encoded: base64Signature) else {
                    throw ApproovError.permanentError(message: "Failed to generate ES256 signature")
                }
                // decode the signature from ASN.1 DER format
                signature = try ApproovDefaultMessageSigning.decodeES256Signature(decodedSignature)
            case "hmac-sha256":
                sigId = "account"
                guard let base64Signature = ApproovService.getAccountMessageSignature(message: message),
                      let decodedSignature = Data(base64Encoded: base64Signature) else {
                    throw ApproovError.permanentError(message: "Failed to generate HMAC signature")
                }
                signature = decodedSignature
            default:
                throw ApproovError.permanentError(message: "Unsupported algorithm identifier: \(params.getAlg() ?? "unknown")")
            }

            // Create signature headers
            let sigHeaderDictionary: [String: String] = [sigId: signature.base64EncodedString()]
            let sigInputDictionary: [String: Any] = [sigId: params.toComponentValue()]

            // Serialize the sigHeader dictionary
            guard let sigHeaderData = try? JSONSerialization.data(withJSONObject: sigHeaderDictionary, options: []),
                  let sigHeader = String(data: sigHeaderData, encoding: .utf8) else {
                throw ApproovError.permanentError(message: "Failed to serialize signature header")
            }

            // Serialize the sigInput dictionary
            guard let sigInputData = try? JSONSerialization.data(withJSONObject: sigInputDictionary, options: []),
                  let sigInputHeader = String(data: sigInputData, encoding: .utf8) else {
                throw ApproovError.permanentError(message: "Failed to serialize signature input header")
            }

            // Add headers to the request
            var signedRequest = request
            signedRequest.addValue(sigHeader, forHTTPHeaderField: "Signature")
            signedRequest.addValue(sigInputHeader, forHTTPHeaderField: "Signature-Input")

            if params.isDebugMode() {
                let digest = ApproovDefaultMessageSigning.sha256(data: Data(message.utf8))
                let digestData = Data(digest) // Convert digest to Data
                let digestDictionary: [String: String] = ["sha-256": digestData.base64EncodedString()]
                // Serialize the dictionary to JSON
                if let serializedDigest = try? JSONSerialization.data(withJSONObject: digestDictionary, options: []),
                   let serializedString = String(data: serializedDigest, encoding: .utf8) {
                    // Add the serialized digest to the request headers
                    signedRequest.addValue(serializedString, forHTTPHeaderField: "Signature-Base-Digest")
                } else {
                    os_log("ApproovService: Failed to get digest algorithm - no debug entry", type: .debug)
                    // TODO Remove this call
                    fatalError("Failed to serialize the digest dictionary")
                }
            }

            // WARNING: Never log the full request as it contains sensitive information
            // TODO FIXME Don't log here!
            print("Signed Request: \(signedRequest)")
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



    private static func generateSignatureParameters(provider: ApproovURLSessionComponentProvider) -> SignatureParameters? {
        // Generate signature parameters based on the request
        //        let params = SignatureParameters()
        //        params.setAlg("ecdsa-p256-sha256")
        //        params.addComponentIdentifier("@method")
        //        params.addComponentIdentifier("@target-uri")
        //        return params
        return SignatureParameters().setAlg("ecdsa-p256-sha256").addComponentIdentifier("@method").addComponentIdentifier("@target-uri")
    }

    private static func decodeES256Signature(_ signature: Data) throws -> Data {
        // Decode ASN.1 DER encoded ES256 signature into raw r and s values
        var offset = 0

        // Ensure the signature starts with a valid ASN.1 sequence
        guard signature[offset] == 0x30 else {
            throw ApproovError.permanentError(message: "Invalid ASN.1 DER sequence")
        }
        offset += 1

        // Read the total length of the sequence
        let sequenceLength = Int(signature[offset])
        offset += 1

        guard sequenceLength == signature.count - 2 else {
            throw ApproovError.permanentError(message: "Invalid ASN.1 DER sequence length")
        }

        // Decode the first integer (r)
        guard signature[offset] == 0x02 else {
            throw ApproovError.permanentError(message: "Invalid ASN.1 DER integer for r")
        }
        offset += 1

        let rLength = Int(signature[offset])
        offset += 1

        let rBytes = signature[offset..<(offset + rLength)]
        offset += rLength

        // Decode the second integer (s)
        guard signature[offset] == 0x02 else {
            throw ApproovError.permanentError(message: "Invalid ASN.1 DER integer for s")
        }
        offset += 1

        let sLength = Int(signature[offset])
        offset += 1

        let sBytes = signature[offset..<(offset + sLength)]
        offset += sLength

        // Ensure the entire signature has been processed
        guard offset == signature.count else {
            throw ApproovError.permanentError(message: "Extra data in ASN.1 DER signature")
        }

        // TODO What about integer encodings that have more than 32 bytes?

        // Pad r and s to 32 bytes if necessary
        let rPadded = rBytes.count < 32 ? Data(repeating: 0, count: 32 - rBytes.count) + rBytes : rBytes
        let sPadded = sBytes.count < 32 ? Data(repeating: 0, count: 32 - sBytes.count) + sBytes : sBytes

        return rPadded + sPadded
    }

    /**
     * Generates a default `SignatureParametersFactory` with predefined settings.
     *
     * - Returns: A new instance of `SignatureParametersFactory`.
     */
    public static func generateDefaultSignatureParametersFactory() -> SignatureParametersFactory {
        return generateDefaultSignatureParametersFactory(baseParametersOverride: nil)
    }

    /**
     * Generates a default `SignatureParametersFactory` with optional base parameters.
     *
     * - Parameter baseParametersOverride: The base parameters to override, or `nil` to use defaults.
     * - Returns: A new instance of `SignatureParametersFactory`.
     */
    public static func generateDefaultSignatureParametersFactory(baseParametersOverride: SignatureParameters?) -> SignatureParametersFactory {
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

        return SignatureParametersFactory()
            .setBaseParameters(baseParameters)
            .setUseDeviceMessageSigning()
            .setAddCreated(true)
            .setExpiresLifetime(defaultExpiresLifetime)
            .setAddApproovTokenHeader(true)
            .addOptionalHeaders(["Authorization", "Content-Length", "Content-Type"])
            .setBodyDigestConfig(ApproovDefaultMessageSigning.DIGEST_SHA256, required: false)
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
    private var optionalHeaders: [String] = []

    /**
     * Sets the base parameters for the factory.
     *
     * - Parameter baseParameters: The base parameters to set.
     * - Returns: The current instance for method chaining.
     */
    func setBaseParameters(_ baseParameters: SignatureParameters) -> SignatureParametersFactory {
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
    func setBodyDigestConfig(_ bodyDigestAlgorithm: String?, required: Bool) -> SignatureParametersFactory {
        if let algorithm = bodyDigestAlgorithm {
            guard algorithm == ApproovDefaultMessageSigning.DIGEST_SHA256 ||
                  algorithm == ApproovDefaultMessageSigning.DIGEST_SHA512 else {
                fatalError("Unsupported body digest algorithm: \(algorithm)")
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
    func setUseDeviceMessageSigning() -> SignatureParametersFactory {
        self.useAccountMessageSigning = false
        return self
    }

    /**
     * Configures the factory to use account message signing.
     *
     * - Returns: The current instance for method chaining.
     */
    func setUseAccountMessageSigning() -> SignatureParametersFactory {
        self.useAccountMessageSigning = true
        return self
    }

    /**
     * Sets whether the "created" field should be added to the signature parameters.
     *
     * - Parameter addCreated: Whether to add the "created" field.
     * - Returns: The current instance for method chaining.
     */
    func setAddCreated(_ addCreated: Bool) -> SignatureParametersFactory {
        self.addCreated = addCreated
        return self
    }

    /**
     * Sets the expiration lifetime for the signature parameters.
     *
     * - Parameter expiresLifetime: The expiration lifetime in seconds. If <=0, no expiration is added.
     * - Returns: The current instance for method chaining.
     */
    func setExpiresLifetime(_ expiresLifetime: Int64) -> SignatureParametersFactory {
        self.expiresLifetime = expiresLifetime
        return self
    }

    /**
     * Sets whether the Approov token header should be added to the signature parameters.
     *
     * - Parameter addApproovTokenHeader: Whether to add the Approov token header.
     * - Returns: The current instance for method chaining.
     */
    func setAddApproovTokenHeader(_ addApproovTokenHeader: Bool) -> SignatureParametersFactory {
        self.addApproovTokenHeader = addApproovTokenHeader
        return self
    }

    /**
     * Adds optional headers to the signature parameters.
     *
     * - Parameter headers: The headers to add.
     * - Returns: The current instance for method chaining.
     */
    func addOptionalHeaders(_ headers: [String]) -> SignatureParametersFactory {
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
    func buildSignatureParameters(provider: ApproovURLSessionComponentProvider, changes: ApproovRequestMutations) -> SignatureParameters {
        // init(base: SignatureParameters) {
        //     private var baseParameters: SignatureParameters?
        var requestParameters: SignatureParameters
        if baseParameters == nil {
            requestParameters = SignatureParameters()
        } else {
            requestParameters = SignatureParameters(base: baseParameters!) // Safe to unwrap, cannot be nil
        }
        requestParameters.setAlg(useAccountMessageSigning ? ApproovDefaultMessageSigning.ALG_HS256 : ApproovDefaultMessageSigning.ALG_ES256)

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

        for headerName in optionalHeaders {
            if provider.hasField(name: headerName) {
                requestParameters.addComponentIdentifier(headerName)
            }
        }

        if let algorithm = bodyDigestAlgorithm {
            if !generateBodyDigest(provider: provider, requestParameters: requestParameters) && bodyDigestRequired {
                fatalError("Failed to create required body digest")
            }
        }

        return requestParameters
    }

    /**
     * Generates a body digest for the request if possible.
     *
     * - Parameters:
     *   - provider: The component provider for the request.
     *   - requestParameters: The signature parameters to update.
     * - Returns: `true` if the body digest was successfully generated, `false` otherwise.
     */
    private func generateBodyDigest(provider: ApproovURLSessionComponentProvider, requestParameters: SignatureParameters) -> Bool {
        var request = provider.getRequest()

        // If there is no body, we don't generate a digest
        guard let body = provider.getRequest().httpBody else {
            return false
        }

        // TODO: Check if the body is a stream and handle it accordingly

        // If no body digest algorithm has been set, we don't generate a digest
        guard let bodyDigestAlg = bodyDigestAlgorithm else {
            return false
        }

        let digest: Data
        switch bodyDigestAlg {
        case ApproovDefaultMessageSigning.DIGEST_SHA256:
            digest = ApproovDefaultMessageSigning.sha256(data: body)
        case ApproovDefaultMessageSigning.DIGEST_SHA512:
            digest = SignatureParametersFactory.sha512(data: body)
        default:
            return false
        }

        let digestBase64 = digest.base64EncodedString()
        let itemOrInnerList = ItemOrInnerList.item(Item(bareItem: BareItem.string(digestBase64), parameters: [:]))
        let digestHeader: OrderedMap<String, ItemOrInnerList> = [bodyDigestAlg: itemOrInnerList]
        do {
            var serializer = StructuredFieldValueSerializer()
            let serializedValue = try serializer.writeDictionaryFieldValue(digestHeader)
            guard let digestHeader = String(data: Data(serializedValue), encoding: .utf8) else
            {
                return false
            }
            request.addValue(digestHeader, forHTTPHeaderField: "Content-Digest")
        } catch {
            fatalError("Failed to serialize Content-Digest header: \(error)")
        }
        requestParameters.addComponentIdentifier("Content-Digest")
        return true
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
    private var url: URL

    init(request: URLRequest) {
        self.request = request
        guard let url = request.url else {
            fatalError("URL is required for the request")
        }
        self.url = url
    }

    func getRequest() -> URLRequest {
        return request
    }

    func setRequest(_ newRequest: URLRequest) {
        self.request = newRequest
        guard let newUrl = newRequest.url else {
            fatalError("URL is required for the request")
        }
        self.url = newUrl
    }

    func getMethod() -> String {
        return request.httpMethod ?? "GET"
    }

    func getAuthority() -> String {
        return url.host ?? ""
    }

    func getScheme() -> String {
        return url.scheme ?? "http"
    }

    func getTargetUri() -> String {
        return url.absoluteString
    }

    func getRequestTarget() -> String {
        var target = url.path
        if let query = url.query {
            target += "?\(query)"
        }
        return target
    }

    func getPath() -> String {
        return url.path
    }

    func getQuery() -> String {
        return url.query ?? ""
    }

    func getQueryParam(name: String) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
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

    func getStatus() -> String {
        fatalError("Only requests are supported")
    }

    func hasField(name: String) -> Bool {
        return request.value(forHTTPHeaderField: name) != nil
    }

    func getField(name: String) -> String? {
        guard let value = request.value(forHTTPHeaderField: name) else {
            return nil
        }
        return ApproovURLSessionComponentProvider.combineFieldValues(fields: [value])
    }

    func hasBody() -> Bool {
        return request.httpBody != nil || request.httpBodyStream != nil
    }
}
