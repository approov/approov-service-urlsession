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

/// Pinning of the app's API domains against the echo worker. Pins are looked up per host without
/// regard to case or a trailing dot; a listed host with no pins and no Managed Trust Roots connects on
/// OS trust with one warning; pins that cannot be read fail the connection closed; a refused connection
/// reports NSURLErrorServerCertificateUntrusted, not a cancellation.
final class Pinning370Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var targetURL: URL!
    private var host: String!
    private var warnings: [String] = []
    private let lock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        targetURL = try XCTUnwrap(URL(string: try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])))
        host = try XCTUnwrap(targetURL.host)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.warning)
        ApproovService.logSink = { [weak self] level, line in
            guard let self, level == .warning else { return }
            self.lock.lock(); self.warnings.append(line); self.lock.unlock()
        }
    }

    override func tearDown() {
        ApproovService.logSink = nil
        ApproovService.setLoggingLevel(.info)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    private func initialize(pins: String? = nil) throws {
        if let pins {
            MiniSDKAttesterProxyController.loadScenarioJSON(
                "{\"activeCase\": \"pins\", \"cases\": {\"pins\": {\"protectedDomains\": [\"\(host!)\"], " +
                "\"pins\": {\"public-key-sha256\": \(pins)}}}}")
        }
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-pinning-\(UUID().uuidString)")
    }

    // sends a request through a new session and returns the error it completed with
    private func send() -> Error? {
        let session = ApproovURLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let done = expectation(description: "request")
        var result: Error?
        session.dataTask(with: targetURL) { _, _, error in
            result = error
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        return result
    }

    private func warningCount(naming text: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return warnings.filter { $0.contains(text) }.count
    }

    func testARefusedConnectionIsAnUntrustedCertificate() throws {
        try initialize()
        MiniSDKAttesterProxyController.setNextPinningDirectiveJSON("{\"operation\": \"getPins\", \"shouldFail\": true}")
        let error = send() as NSError?
        XCTAssertEqual(error?.domain, NSURLErrorDomain)
        XCTAssertEqual(error?.code, NSURLErrorServerCertificateUntrusted, "\(String(describing: error))")
    }

    func testPinsAreLookedUpWithoutCaseOrTrailingDot() throws {
        // the exact key carries no pins, so only the normalised match brings in the pin that fails
        try initialize(pins: "{\"\(host.uppercased()).\": [\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\"]}")
        let error = send() as NSError?
        XCTAssertEqual(error?.code, NSURLErrorServerCertificateUntrusted, "\(String(describing: error))")
    }

    func testNoPinsAndNoTrustRootsConnectOnOSTrustWithOneWarning() throws {
        // the host is listed with no pins of its own, and the Managed Trust Roots are empty
        try initialize(pins: "{\"*\": [], \"\(host!)\": []}")
        XCTAssertNil(send())
        XCTAssertNil(send())
        XCTAssertEqual(warningCount(naming: host), 1, "\(warnings)")
    }

    func testPinsThatCannotBeReadFailClosed() throws {
        try initialize()
        MiniSDKAttesterProxyController.setPinsUnavailable(true)
        let error = send() as NSError?
        XCTAssertEqual(error?.code, NSURLErrorServerCertificateUntrusted, "\(String(describing: error))")
    }
}
