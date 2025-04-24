//
//  HTTP-SFV.swift
//  ApproovURLSession
//
//  Created by Johannes Schneiders on 24/04/2025.
//

import RawStructuredFieldValues
import Foundation

public class SFV {

    static func serializeStringItem(item: StringItem) throws -> String? {
        var serializer = StructuredFieldValueSerializer()
        let serialized = try serializer.writeItemFieldValue(item.item)
        let string = try String(data: Data(serialized), encoding: .utf8)
        return string
    }

    static func serializeList(list: InnerList) throws -> String? {
        var serializer = StructuredFieldValueSerializer()
        let itemOrInnerList = ItemOrInnerList.innerList(list)
        let serialized = try serializer.writeListFieldValue([itemOrInnerList])
        let string = try String(data: Data(serialized), encoding: .utf8)
        return string
    }

    // Method to serialize dictionary entry of sigId: signatureBase64 of type String: UndecodedByteSequence
    static func serializeDictionary(key: String, data: Data) throws -> String?
    {
        var serializer = StructuredFieldValueSerializer()
        let dataBase64: String = data.base64EncodedString()
        let dictionary: OrderedMap<String, ItemOrInnerList> =
            [key: ItemOrInnerList.item(Item(bareItem: RFC9651BareItem.undecodedByteSequence(dataBase64), parameters: [:]))]
        let serialized: [UInt8] = try serializer.writeDictionaryFieldValue(dictionary)
        let string = try String(data: Data(serialized), encoding: .utf8)
        return string
    }

    // Method to serialize dictionary entry of key: sigParams of type String: InnerList
    static func serializeDictionary(key: String, innerList: InnerList) throws -> String? {
        var serializer = StructuredFieldValueSerializer()
        let dictionary: OrderedMap<String, ItemOrInnerList> = [key: ItemOrInnerList.innerList(innerList)]
        let serialized = try serializer.writeDictionaryFieldValue(dictionary)
        let string = try String(data: Data(serialized), encoding: .utf8)
        return string
    }
}
