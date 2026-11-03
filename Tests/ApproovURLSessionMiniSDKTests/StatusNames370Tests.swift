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

import XCTest
import Foundation
import Approov
@testable import ApproovURLSessionPackage
import MiniSDKTestSupport

/// A status that leaves the layer, in the token header or in an error, is the SDK's token fetch
/// status name as the Android SDK spells it, never the iOS SDK's prose.
final class StatusNames370Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var targetURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        targetURL = try XCTUnwrap(URL(string: try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])))
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-status-names")
    }

    override func tearDown() {
        ApproovService.setServiceMutator(nil)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    private func nextTokenFetch(_ status: String) {
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            "{\"operation\": \"fetchApproovToken\", \"response\": {\"status\": \"\(status)\"}}")
    }

    func testEveryStatusHasItsName() {
        let expected: [(ApproovTokenFetchStatus, String)] = [
            (.success, "SUCCESS"), (.noNetwork, "NO_NETWORK"), (.mitmDetected, "MITM_DETECTED"),
            (.poorNetwork, "POOR_NETWORK"), (.noApproovService, "NO_APPROOV_SERVICE"), (.badURL, "BAD_URL"),
            (.unknownURL, "UNKNOWN_URL"), (.unprotectedURL, "UNPROTECTED_URL"),
            (.notInitialized, "NOT_INITIALIZED"), (.rejected, "REJECTED"), (.disabled, "DISABLED"),
            (.unknownKey, "UNKNOWN_KEY"), (.badKey, "BAD_KEY"), (.badPayload, "BAD_PAYLOAD"),
            (.internalError, "INTERNAL_ERROR"),
        ]
        for (status, name) in expected {
            XCTAssertEqual(ApproovService.statusName(status), name)
        }
    }

    func testTheTokenHeaderCarriesTheStatusName() throws {
        // a mutator that lets a failure proceed, so that the status reaches the token header
        final class Proceeding: ApproovServiceMutator {
            func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult,
                                                   url: String) throws -> Bool {
                return true
            }
        }
        ApproovService.setServiceMutator(Proceeding())
        ApproovService.setTokenHeader(header: "Authorization", prefix: "Bearer ")
        ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)
        nextTokenFetch("NO_APPROOV_SERVICE")
        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
        XCTAssertEqual(response.request.value(forHTTPHeaderField: "Authorization"), "Bearer NO_APPROOV_SERVICE")
    }

    func testTheDefaultTokenFailureNamesTheStatus() {
        nextTokenFetch("NO_NETWORK")
        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
        XCTAssertEqual(response.error?.localizedDescription, "Approov token fetch for \(targetURL.absoluteString): NO_NETWORK")
    }

    func testADirectMethodFailureNamesTheStatus() {
        nextTokenFetch("POOR_NETWORK")
        XCTAssertThrowsError(try ApproovService.fetchToken(url: targetURL.absoluteString)) { error in
            XCTAssertEqual(error.localizedDescription, "fetchToken network error: POOR_NETWORK")
        }
    }
}
