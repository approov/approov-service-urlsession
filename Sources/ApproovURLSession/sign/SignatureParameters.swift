import Foundation
import StructuredFieldValues

class SignatureParameters: CustomStringConvertible {
    private static let ALG = "alg"
    private static let CREATED = "created"
    private static let EXPIRES = "expires"
    private static let KEYID = "keyid"
    private static let NONCE = "nonce"
    private static let TAG = "tag"

    private var debugMode: Bool = false
    private var componentIdentifiers: [String] = [] // List of Strings
    private var parameters: [String: Any] = [:] // Dictionary with String keys and Any values

    // Default constructor creates an empty SignatureParameters ready to be populated.
    init() {
        self.componentIdentifiers = []
        self.parameters = [:]
    }

    init(base: SignatureParameters) {
        self.componentIdentifiers = base.componentIdentifiers // Copy the array
        self.parameters = base.parameters // Copy the dictionary
    }

    func getComponentIdentifiers() -> [String] {
        return componentIdentifiers
    }

    func getParameters() -> [String: Any] {
        return parameters
    }

    func setParameters(_ parameters: [String: Any]) -> SignatureParameters {
        self.parameters = parameters
        return self
    }

    func isDebugMode() -> Bool {
        return debugMode
    }

    func setDebugMode(_ debugMode: Bool) {
        self.debugMode = debugMode
    }

    func getAlg() -> String? {
        return parameters[Self.ALG] as? String
    }

    func setAlg(_ alg: String) -> SignatureParameters {
        parameters[Self.ALG] = alg
        return self
    }

    func getCreated() -> Int64? {
        return parameters[Self.CREATED] as? Int64
    }

    func setCreated(_ created: Int64) -> SignatureParameters {
        parameters[Self.CREATED] = created
        return self
    }

    func getExpires() -> Int64? {
        return parameters[Self.EXPIRES] as? Int64
    }

    func setExpires(_ expires: Int64) -> SignatureParameters {
        parameters[Self.EXPIRES] = expires
        return self
    }

    func getKeyid() -> String? {
        return parameters[Self.KEYID] as? String
    }

    func setKeyid(_ keyid: String) -> SignatureParameters {
        parameters[Self.KEYID] = keyid
        return self
    }

    func getNonce() -> String? {
        return parameters[Self.NONCE] as? String
    }

    func setNonce(_ nonce: String) -> SignatureParameters {
        parameters[Self.NONCE] = nonce
        return self
    }

    func getTag() -> String? {
        return parameters[Self.TAG] as? String
    }

    func setTag(_ tag: String) -> SignatureParameters {
        parameters[Self.TAG] = tag
        return self
    }

    func getCustomParameter(_ key: String) -> Any? {
        return parameters[key]
    }

    func setCustomParameter(_ key: String, value: Any) -> SignatureParameters {
        parameters[key] = value
        return self
    }

    func toComponentIdentifier() -> String {
        return "@signature-params"
    }

    func toComponentValue() -> [String: Any] {
        var parametersList: [String: Any] = [:]

        // Add component identifiers as a list
        parametersList["items"] = componentIdentifiers.map { DisplayString(rawValue: $0).rawValue }

        // Add parameters as key-value pairs
        for (key, value) in parameters {
            if let stringValue = value as? String {
                parametersList[key] = DisplayString(rawValue: stringValue).rawValue
            } else if let intValue = value as? Int64 {
                parametersList[key] = intValue
            } else {
                // Handle other types as needed
                fatalError("Unsupported parameter type for key: \(key)")
            }
        }

        return parametersList
    }

    func addComponentIdentifier(_ identifier: String) -> SignatureParameters {
        let normalizedIdentifier = identifier.starts(with: "@") ? identifier : identifier.lowercased()
        componentIdentifiers.append(normalizedIdentifier)
        return self
    }

    func containsComponentIdentifier(_ identifier: String) -> Bool {
        return componentIdentifiers.contains(identifier)
    }

    static func fromDictionaryEntry(_ signatureInput: [String: Any], sigId: String) -> SignatureParameters {
        guard let item = signatureInput[sigId] as? [String: Any] else {
            fatalError("Invalid syntax, identifier '\(sigId)' must be a dictionary")
        }

        let params = SignatureParameters()
        if let items = item["items"] as? [String] {
            for stringItem in items {
                params.addComponentIdentifier(stringItem)
            }
        }

        if let parameters = item["parameters"] as? [String: Any] {
            for (key, value) in parameters {
                switch key {
                case ALG:
                    params.setAlg(value as? String ?? "")
                case CREATED:
                    params.setCreated(value as? Int64 ?? 0)
                case EXPIRES:
                    params.setExpires(value as? Int64 ?? 0)
                case KEYID:
                    params.setKeyid(value as? String ?? "")
                case NONCE:
                    params.setNonce(value as? String ?? "")
                case TAG:
                    params.setTag(value as? String ?? "")
                default:
                    params.parameters[key] = value
                }
            }
        }

        return params
    }

    var description: String {
        return "SignatureParameters: \(toComponentValue())"
    }
}
