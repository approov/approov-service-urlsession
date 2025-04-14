import Foundation
import StructuredFieldValues

class SignatureBaseBuilder {
    private let sigParams: SignatureParameters
    private let ctx: ComponentProvider

    init(sigParams: SignatureParameters, ctx: ComponentProvider) {
        self.sigParams = sigParams
        self.ctx = ctx
    }

    func createSignatureBase() -> String {
        var base = ""

        for componentIdentifier in sigParams.getComponentIdentifiers() {
            if let componentValue = ctx.getComponentValue(componentIdentifier: componentIdentifier) {
                // Write out the line to the base
                base += "\(componentIdentifier): \(componentValue)\n"
            } else {
                // FIXME: Be more graceful about bailing
                fatalError("Couldn't find a value for required parameter: \(componentIdentifier)")
            }
        }

        // Add the signature parameters line
        base += "\(sigParams.toComponentIdentifier()): "
        // Serialize the dictionary returned by toComponentValue()
        if let serializedValue = try? JSONSerialization.data(withJSONObject: sigParams.toComponentValue(), options: []),
        let serializedString = String(data: serializedValue, encoding: .utf8) {
            base += serializedString
        } else {
            fatalError("Failed to serialize signature parameters")
        }

        return base
    }
}