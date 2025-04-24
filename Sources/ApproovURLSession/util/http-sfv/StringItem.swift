//
//  StringItem.swift
//  ApproovURLSession
//
//  Created by Johannes Schneiders on 24/04/2025.
//

import RawStructuredFieldValues

// TODO? Replace with String
public struct StringItem {
    // static let structuredFieldType: StructuredFieldType = .item
    var item: Item

    public init(value: String) {
        item = Item(bareItem: RFC9651BareItem.string(value), parameters: [:])
    }

    public init(value: String, parameters: OrderedMap<String, RFC9651BareItem>) {
        item = Item(bareItem: RFC9651BareItem.string(value), parameters: parameters)
    }

    var value: String {
        switch item.bareItem {
        case .string(let string):
            let check: String = string
            return check
        default:
            return ""
        }
    }

    var parameters: OrderedMap<String, String> {
        var paramsAsStrings = OrderedMap<String, String>()
        for (key, value) in item.parameters {
            switch value {
            case .string(let string):
                paramsAsStrings[key] = string
            default:
                continue
            }
        }
        return paramsAsStrings
    }
}
