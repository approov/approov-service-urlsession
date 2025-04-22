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
                base += "\(componentIdentifier.value): \(componentValue)\n"
            } else {
                // FIXME: Be more graceful about bailing
                fatalError("Couldn't find a value for required parameter: \(componentIdentifier)")
            }
        }

        // Add the signature parameters line
        base += "\(sigParams.toComponentIdentifier().value): "
        // Serialize the dictionary returned by toComponentValue()
        var serializer = StructuredFieldValueSerializer()
        let itemOrInnerList = ItemOrInnerList.innerList(sigParams.toComponentValue())
        let serializedValue = try serializer.writeListFieldValue([itemOrInnerList])
        if let serializedString = String(data: Data(serializedValue), encoding: .utf8) {
            base += serializedString
        } else {
            fatalError("Failed to serialize signature parameters")
        }

        return base
    }
}
