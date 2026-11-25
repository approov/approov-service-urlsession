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
@testable import ApproovURLSessionPackage
import MiniSDKTestSupport

/// getLastARC reports the ARC of the most recent fetch the layer made, from the request path or a
/// direct method, and makes no fetch of its own. The layer keeps no failure cache: every request asks
/// the SDK.
final class FetchState370Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var targetURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        targetURL = try XCTUnwrap(URL(string: try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])))
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-fetch-state")
        MiniSDKAttesterProxyController.clearCallLog()
    }

    override func tearDown() {
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    private func nextFetch(_ operation: String, status: String, arc: String) {
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            "{\"operation\": \"\(operation)\", \"response\": {\"status\": \"\(status)\", \"arc\": \"\(arc)\"}}")
    }

    private func tokenFetches() -> Int {
        MiniSDKAttesterProxyController.callLog().filter { $0.hasPrefix("fetchApproovTokenAndWait:") }.count
    }

    func testGetLastARCMakesNoFetch() {
        XCTAssertEqual(ApproovService.getLastARC(), "", "no fetch has been made since initialization")
        XCTAssertEqual(MiniSDKAttesterProxyController.callLog(), [])
    }

    func testGetLastARCIsTheRequestPathFetchARC() {
        nextFetch("fetchApproovToken", status: "SUCCESS", arc: "ARCREQUEST")
        _ = ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
        let fetches = MiniSDKAttesterProxyController.callLog()
        XCTAssertEqual(ApproovService.getLastARC(), "ARCREQUEST")
        XCTAssertEqual(MiniSDKAttesterProxyController.callLog(), fetches, "getLastARC made a fetch")
    }

    func testGetLastARCFollowsTheMostRecentFetch() {
        nextFetch("fetchApproovToken", status: "SUCCESS", arc: "ARCFIRST")
        _ = ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
        nextFetch("fetchApproovToken", status: "REJECTED", arc: "ARCREJECTED")
        XCTAssertThrowsError(try ApproovService.fetchToken(url: targetURL.absoluteString))
        XCTAssertEqual(ApproovService.getLastARC(), "ARCREJECTED", "a direct method's fetch is the most recent")
    }

    func testInitializeClearsTheLastARC() throws {
        nextFetch("fetchApproovToken", status: "SUCCESS", arc: "ARCBEFORE")
        _ = ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
        XCTAssertEqual(ApproovService.getLastARC(), "ARCBEFORE")
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-fetch-state-2")
        XCTAssertEqual(ApproovService.getLastARC(), "")
    }

    func testAFailedFetchIsNotCached() {
        nextFetch("fetchApproovToken", status: "NO_NETWORK", arc: "ARCNONETWORK")
        _ = ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
        let second = ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
        XCTAssertEqual(tokenFetches(), 2, "the second request did not reach the SDK")
        XCTAssertEqual(second.decision, .ShouldProceed, "the second request got the first request's failure")
    }
}
