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
                // TODO this is needlessly complicated - it converts a StringItem to a String to an Item and then serializes this into a String.
                // It should either just serialize the StringItem (needs support in class StringItem) or sigParams.getComponentIdentifiers()
                // should return the component identifiers as already correctly serialized strings (needs support in getComponentValue()).
                var serializer = StructuredFieldValueSerializer()
                let stringItem = Item(bareItem: RFC9651BareItem.string(componentIdentifier.value), parameters: [:])
                let serializedValue = try serializer.writeItemFieldValue(stringItem)
                guard let compIdString = String(data: Data(serializedValue), encoding: .utf8) else {
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
        var serializer = StructuredFieldValueSerializer()
        // Serialize the signature parameters component identifier
        // TODO this is needlessly complicated - it converts a StringItem to a String to an Item and then serializes this into a String.
        let stringItem = Item(bareItem: RFC9651BareItem.string(sigParams.toComponentIdentifier().value), parameters: [:])
        let serializedSigParamsId = try serializer.writeItemFieldValue(stringItem)
        guard let sigParamsIdString = String(data: Data(serializedSigParamsId), encoding: .utf8) else {
            // TODO FIXME: Be more graceful about bailing
            fatalError("Failed to serialize signature params component identifier")
        }

        // Serialize the signature params dictionary returned by toComponentValue()
        let itemOrInnerList = ItemOrInnerList.innerList(sigParams.toComponentValue())
        let serializedSigParams = try serializer.writeListFieldValue([itemOrInnerList])
        guard let sigParamsString = String(data: Data(serializedSigParams), encoding: .utf8) else {
            // TODO FIXME: Be more graceful about bailing
            fatalError("Failed to serialize signature parameters")
        }
        base += "\(sigParamsIdString): \(sigParamsString)"

        return base
    }
}
