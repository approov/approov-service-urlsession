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

/// The two standard decision sets. CLOSE_FAILURE, the default, keeps the 3.5.x token decisions except
/// that NO_APPROOV_SERVICE proceeds with an empty token header, and with the status flag the network
/// failures proceed too. ALWAYS_PROCEED never aborts. Neither aborts a request because of a secure
/// string.
final class StandardMutators370Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var targetURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        targetURL = try XCTUnwrap(URL(string: try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])))
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-standard-mutators")
    }

    override func tearDown() {
        ApproovService.setServiceMutator(nil)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    private func send(tokenStatus: String) -> ApproovUpdateResponse {
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            "{\"operation\": \"fetchApproovToken\", \"response\": {\"status\": \"\(tokenStatus)\", \"token\": \"\"}}")
        return ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
    }

    private func tokenHeader(_ response: ApproovUpdateResponse) -> String? {
        return response.request.value(forHTTPHeaderField: "Approov-Token")
    }

    func testTheDefaultIsCloseFailure() {
        XCTAssertEqual(String(describing: ApproovService.getServiceMutator()), "ApproovServiceMutator.CLOSE_FAILURE")
        ApproovService.setServiceMutator(.ALWAYS_PROCEED)
        XCTAssertEqual(String(describing: ApproovService.getServiceMutator()), "ApproovServiceMutator.ALWAYS_PROCEED")
        ApproovService.setServiceMutator(nil)
        XCTAssertEqual(String(describing: ApproovService.getServiceMutator()), "ApproovServiceMutator.CLOSE_FAILURE")
        XCTAssertEqual(String(describing: ApproovCloseFailureMutator.DEFAULT), "ApproovServiceMutator.CLOSE_FAILURE")
    }

    func testCloseFailureProceedsOnNoApproovServiceWithAnEmptyToken() {
        let response = send(tokenStatus: "NO_APPROOV_SERVICE")
        XCTAssertEqual(response.decision, .ShouldProceed)
        XCTAssertEqual(tokenHeader(response), "")
    }

    func testCloseFailureAbortsANetworkFailureUnlessTheStatusIsSent() {
        let aborted = send(tokenStatus: "NO_NETWORK")
        XCTAssertEqual(aborted.decision, .ShouldRetry)
        ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)
        let proceeding = send(tokenStatus: "NO_NETWORK")
        XCTAssertEqual(proceeding.decision, .ShouldProceed)
        XCTAssertEqual(tokenHeader(proceeding), "NO_NETWORK")
    }

    func testCloseFailureAbortsARejectionEitherWay() {
        XCTAssertEqual(send(tokenStatus: "REJECTED").decision, .ShouldFail)
        ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)
        XCTAssertEqual(send(tokenStatus: "REJECTED").decision, .ShouldFail)
    }

    func testAlwaysProceedNeverAborts() {
        ApproovService.setServiceMutator(.ALWAYS_PROCEED)
        for status in ["REJECTED", "NO_NETWORK", "MITM_DETECTED", "INTERNAL_ERROR"] {
            let response = send(tokenStatus: status)
            XCTAssertEqual(response.decision, .ShouldProceed, status)
            XCTAssertEqual(tokenHeader(response), "", status)
        }
        ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)
        XCTAssertEqual(tokenHeader(send(tokenStatus: "REJECTED")), "REJECTED")
    }

    func testNeitherAddsAHeaderForAnUnknownURL() {
        for mutator in [ApproovCloseFailureMutator.DEFAULT, ApproovAlwaysProceedMutator.ALWAYS_PROCEED] as [ApproovServiceMutator] {
            ApproovService.setServiceMutator(mutator)
            let response = send(tokenStatus: "UNKNOWN_URL")
            XCTAssertEqual(response.decision, .ShouldProceed)
            XCTAssertNil(tokenHeader(response), String(describing: mutator))
        }
    }

    func testNeitherAbortsOnASecureStringFailure() {
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        var request = URLRequest(url: targetURL)
        request.setValue("api-key-placeholder", forHTTPHeaderField: "Api-Key")
        for mutator in [ApproovCloseFailureMutator.DEFAULT, ApproovAlwaysProceedMutator.ALWAYS_PROCEED] as [ApproovServiceMutator] {
            ApproovService.setServiceMutator(mutator)
            for status in ["REJECTED", "NO_NETWORK", "INTERNAL_ERROR"] {
                MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
                    "{\"operation\": \"fetchSecureString\", \"response\": {\"status\": \"\(status)\"}}")
                let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
                XCTAssertEqual(response.decision, .ShouldProceed, "\(mutator) \(status): \(String(describing: response.error))")
            }
        }
    }
}
