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

/// Token binding. The SDK holds one binding value for the process, so the layer sets the value of the
/// binding header and fetches the token as one step, and each token carries the value of its own
/// request. Requests without the binding header do not wait for that step.
final class Binding370Tests: XCTestCase {
    private var base: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])
        MiniSDKAttesterProxyController.reset()
        MiniSDKAttesterProxyController.resetSdkForTesting()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: testAccountID, comment: nil)
        ApproovService.setBindingHeader(header: "Authorization")
    }

    override func tearDown() {
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    // the claims of a JWT, without checking its signature
    private func claims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return nil
        }
        var padded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded.append(String(repeating: "=", count: (4 - padded.count % 4) % 4))
        guard let data = Data(base64Encoded: padded) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // the pay claim the SDK makes from a binding value: base64(SHA-256(UTF-8 value))
    private func pay(_ value: String) -> String {
        return ApproovDefaultMessageSigning.sha256(data: Data(value.utf8)).base64EncodedString()
    }

    private func bound(_ value: String, header: String = "Authorization") throws -> URLRequest {
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/binding")))
        request.setValue(value, forHTTPHeaderField: header)
        return request
    }

    func testConcurrentRequestsEachGetATokenBoundToTheirOwnValue() throws {
        let count = 10
        let rounds = 20
        var mismatches: [String] = []
        for round in 0..<rounds {
            let requests = try (0..<count).map { try bound("Bearer value-\(round)-\($0)") }
            var tokens = [String?](repeating: nil, count: count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: count) { index in
                let response = ApproovService.updateRequestWithApproov(request: requests[index], sessionConfig: nil)
                let token = response.request.value(forHTTPHeaderField: "Approov-Token")
                lock.lock()
                tokens[index] = token
                lock.unlock()
            }
            for index in 0..<count {
                let value = "Bearer value-\(round)-\(index)"
                let token = try XCTUnwrap(tokens[index], "no token for \(value)")
                let got = claims(token)?["pay"] as? String
                if got != pay(value) {
                    mismatches.append(value)
                }
            }
        }
        XCTAssertEqual(mismatches, [], "\(mismatches.count) of \(count * rounds) tokens were bound to another request's value")
    }

    func testTheBindingHeaderIsFoundWithoutRegardToCase() throws {
        ApproovService.setBindingHeader(header: "authorization")
        let response = ApproovService.updateRequestWithApproov(request: try bound("Bearer mixed-case"), sessionConfig: nil)
        let token = try XCTUnwrap(response.request.value(forHTTPHeaderField: "Approov-Token"))
        XCTAssertEqual(claims(token)?["pay"] as? String, pay("Bearer mixed-case"))
        XCTAssertEqual(MiniSDKAttesterProxyController.callLog().filter { $0.hasPrefix("setDataHashInToken:") },
                       ["setDataHashInToken:Bearer mixed-case"])
    }

    func testABindingHeaderFromTheSessionIsFoundWithoutRegardToCase() throws {
        ApproovService.setBindingHeader(header: "X-Session-Binding")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["x-session-binding": "session-value"]
        let request = URLRequest(url: try XCTUnwrap(URL(string: base + "/binding")))
        let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: configuration)
        let token = try XCTUnwrap(response.request.value(forHTTPHeaderField: "Approov-Token"))
        XCTAssertEqual(claims(token)?["pay"] as? String, pay("session-value"))
    }

    func testOnlyARequestWithTheBindingHeaderWaitsForTheBindingStep() throws {
        // the binding step is held, as a slow token fetch for a bound request would hold it
        ApproovService.bindingLock.lock()
        var held = true
        defer {
            if held {
                ApproovService.bindingLock.unlock()
            }
        }
        let unbound = expectation(description: "unbound request")
        let boundDone = expectation(description: "bound request")
        let unboundRequest = URLRequest(url: try XCTUnwrap(URL(string: base + "/unbound")))
        let boundRequest = try bound("Bearer waiting")
        var boundFinished = false
        let state = NSLock()
        DispatchQueue.global().async {
            _ = ApproovService.updateRequestWithApproov(request: unboundRequest, sessionConfig: nil)
            unbound.fulfill()
        }
        DispatchQueue.global().async {
            _ = ApproovService.updateRequestWithApproov(request: boundRequest, sessionConfig: nil)
            state.lock()
            boundFinished = true
            state.unlock()
            boundDone.fulfill()
        }
        wait(for: [unbound], timeout: 10)
        state.lock()
        let finishedWhileHeld = boundFinished
        state.unlock()
        XCTAssertFalse(finishedWhileHeld, "a bound request did not wait for the binding step")
        ApproovService.bindingLock.unlock()
        held = false
        wait(for: [boundDone], timeout: 10)
    }
}
