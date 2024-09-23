//
//  Logger.swift
//  ApproovURLSession
//
//  Created by ivo.liondov on 23/09/2024.
//

// Generic logging function to be used for DEBUGGING ONLY
func logMessage<T>(line: Int, object: T, property: String, value: Any?, tag: String = "DEBUG") {
    let objectType = String(describing: type(of: object))
    let valueString = value != nil ? String(describing: value!) : "nil"
    print("[\(tag)] Line \(line) - \(objectType): \(property) = \(valueString)")
}
