import Foundation
import StructuredFieldValues
import RawStructuredFieldValues

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
            if let componentValue = try ctx.getComponentValue(componentIdentifier: componentIdentifier) {
                // Write out the line to the base
                // TODO: Method on sigParams to serialize Item of componentIdentifier of type String or serialization method on componentIdentifier of type StringItem
                guard let compIdString = try SFV.serializeStringItem(item: componentIdentifier) else {
                    // TODO FIXME: Be more graceful about bailing
                    fatalError("Failed to serialize component identifier: \(componentIdentifier)")
                }
                base += "\(compIdString): \(componentValue)\n"
            } else {
                // TODO FIXME: Be more graceful about bailing
                fatalError("Couldn't find a value for required parameter: \(componentIdentifier)")
            }
        }

        // Add the signature parameters line
        // Serialize the signature parameters component identifier
        guard let sigParamsIdString = try SFV.serializeStringItem(item: sigParams.toComponentIdentifier()) else {
            // TODO FIXME: Be more graceful about bailing
            fatalError("Failed to serialize signature params component identifier")
        }

        // Serialize the signature params dictionary returned by toComponentValue()
        // TODO: Method on sigParams to serialize its component values
        guard let sigParamsString = try SFV.serializeList(list: sigParams.toComponentValue()) else {
            // TODO FIXME: Be more graceful about bailing
            fatalError("Failed to serialize signature parameters")
        }
        base += "\(sigParamsIdString): \(sigParamsString)"

        return base
    }
}
