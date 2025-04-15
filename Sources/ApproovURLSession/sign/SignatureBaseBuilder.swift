import Foundation
import StructuredFieldValues

class SignatureBaseBuilder {
    private let sigParams: SignatureParameters
    private let ctx: ComponentProvider

    init(sigParams: SignatureParameters, ctx: ComponentProvider) {
        self.sigParams = sigParams
        self.ctx = ctx
    }

    func createSignatureBase() throws -> String {
        var base = ""

        for componentIdentifier in sigParams.getComponentIdentifiers() {
            if let componentValue = ctx.getComponentValue(componentIdentifier: componentIdentifier) {
                // Write out the line to the base
                base += "\(componentIdentifier): \(componentValue)\n"
            } else {
                throw SignatureBaseBuilderError.missingComponentValue(identifier: componentIdentifier)
            }
        }

        // Add the signature parameters line
        base += "\(sigParams.toComponentIdentifier()): "
        do {
            // Serialize the dictionary returned by toComponentValue()
            let serializedValue = try JSONSerialization.data(withJSONObject: sigParams.toComponentValue(), options: [])
            if let serializedString = String(data: serializedValue, encoding: .utf8) {
                base += serializedString
            } else {
                throw SignatureBaseBuilderError.serializationFailed(reason: "Failed to convert serialized signature parameters to String")
            }
        } catch {
            throw SignatureBaseBuilderError.serializationFailed(reason: error.localizedDescription)
        }

        return base
    }
}

enum SignatureBaseBuilderError: Error {
    case missingComponentValue(identifier: String)
    case serializationFailed(reason: String)
}