// MIT License
//
// Copyright (c) 2026-present, Approov Ltd.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
// (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
// ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
// THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Approov
import Foundation

protocol ApproovSDKClient {
    func getPins(_ pinType: String) -> [String: [String]]?
    func fetchToken(_ callbackHandler: @escaping (ApproovTokenFetchResult) -> Void, _ url: String)
    func fetchTokenAndWait(_ url: String) -> ApproovTokenFetchResult
    func initialize(_ initialConfig: String, updateConfig: String?, comment: String?) throws
    func fetchConfig() -> String?
    func fetchSecureStringAndWait(_ key: String, _ newDef: String?) -> ApproovTokenFetchResult
    func fetchCustomJWTAndWait(_ payload: String) -> ApproovTokenFetchResult
    func setUserProperty(_ property: String?)
    func setDevKey(_ key: String?)
    func setDataHashInToken(_ data: String)
    func getDeviceID() -> String?
    func getMessageSignature(_ message: String) -> String?
    func getInstallMessageSignature(_ message: String) -> String?
    func string(from status: ApproovTokenFetchStatus) -> String
}

final class LiveApproovSDKClient: ApproovSDKClient {
    func getPins(_ pinType: String) -> [String: [String]]? {
        return Approov.getPins(pinType)
    }

    func fetchToken(_ callbackHandler: @escaping (ApproovTokenFetchResult) -> Void, _ url: String) {
        Approov.fetchToken(callbackHandler, url)
    }

    func fetchTokenAndWait(_ url: String) -> ApproovTokenFetchResult {
        return Approov.fetchTokenAndWait(url)
    }

    func initialize(_ initialConfig: String, updateConfig: String?, comment: String?) throws {
        try Approov.initialize(initialConfig, updateConfig: updateConfig, comment: comment)
    }

    func fetchConfig() -> String? {
        return Approov.fetchConfig()
    }

    func fetchSecureStringAndWait(_ key: String, _ newDef: String?) -> ApproovTokenFetchResult {
        return Approov.fetchSecureStringAndWait(key, newDef)
    }

    func fetchCustomJWTAndWait(_ payload: String) -> ApproovTokenFetchResult {
        return Approov.fetchCustomJWTAndWait(payload)
    }

    func setUserProperty(_ property: String?) {
        Approov.setUserProperty(property)
    }

    func setDevKey(_ key: String?) {
        Approov.setDevKey(key)
    }

    func setDataHashInToken(_ data: String) {
        Approov.setDataHashInToken(data)
    }

    func getDeviceID() -> String? {
        return Approov.getDeviceID()
    }

    func getMessageSignature(_ message: String) -> String? {
        return Approov.getMessageSignature(message)
    }

    func getInstallMessageSignature(_ message: String) -> String? {
        return Approov.getInstallMessageSignature(message)
    }

    func string(from status: ApproovTokenFetchStatus) -> String {
        return Approov.string(from: status)
    }
}
