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

/// A signature that cannot be produced is left out, and the line saying so is written once per process
/// at a higher level, then at debug level.
final class MissingSignatureLogging371Tests: XCTestCase {
    private var base: String!
    private var lines: [(ApproovLogLevel, String)] = []
    private let linesLock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.debug)
        try ApproovService.initialize(config: testAccountID, comment: nil)
        ApproovService.logSink = { [weak self] level, line in
            guard let self else { return }
            self.linesLock.lock(); self.lines.append((level, line)); self.linesLock.unlock()
        }
    }

    override func tearDown() {
        ApproovService.logSink = nil
        ApproovService.setLoggingLevel(.info)
        ApproovService.setServiceMutator(nil)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    private func levels(containing text: String) -> [ApproovLogLevel] {
        linesLock.lock(); defer { linesLock.unlock() }
        return lines.filter { $0.1.contains(text) }.map { $0.0 }
    }

    // sends one request with a signer for both signatures, the given ones being unavailable
    @discardableResult
    private func send(installMissing: Bool, accountMissing: Bool) throws -> URLRequest {
        var signer = ApproovDefaultMessageSigning.combined()
        if installMissing { signer = signer.setInstallMessageSignatureProviderForTesting { _ in "not-base64" } }
        if accountMissing { signer = signer.setAccountMessageSignatureProviderForTesting { _ in "not-base64" } }
        ApproovService.setServiceMutator(signer)
        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: try XCTUnwrap(URL(string: base + "/a"))),
                                                               sessionConfig: nil)
        XCTAssertEqual(response.decision, .ShouldProceed, String(describing: response.error))
        return response.request
    }

    func testAMissingInstallSignatureWarnsOnceThenLogsAtDebug() throws {
        let request = try send(installMissing: true, accountMissing: false)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Signature")?.hasPrefix("account="), true)
        try send(installMissing: true, accountMissing: false)
        XCTAssertEqual(levels(containing: "install message signature unavailable, signed without it"), [.warning, .debug])
        XCTAssertTrue(levels(containing: "account message signature").isEmpty)
    }

    func testAMissingAccountSignatureWarnsOnceThenLogsAtDebug() throws {
        try send(installMissing: false, accountMissing: true)
        try send(installMissing: false, accountMissing: true)
        XCTAssertEqual(levels(containing: "account message signature unavailable, signed without it"), [.warning, .debug])
        XCTAssertTrue(levels(containing: "install message signature").isEmpty)
    }

    func testBothMissingLogsAnErrorOnceThenDebugAndSendsUnsigned() throws {
        let request = try send(installMissing: true, accountMissing: true)
        XCTAssertNil(request.value(forHTTPHeaderField: "Signature"))
        try send(installMissing: true, accountMissing: true)
        let text = "no message signature could be produced, proceeding unsigned: install signature unavailable: account signature unavailable"
        XCTAssertEqual(levels(containing: text), [.error, .debug])
        XCTAssertTrue(levels(containing: "signed without it").isEmpty)
    }

    func testResetRestoresTheFirstTimeBehaviour() throws {
        try send(installMissing: true, accountMissing: false)
        try send(installMissing: true, accountMissing: false)
        ApproovDefaultMessageSigning.resetMissingSignatureLogsForTesting()
        try send(installMissing: true, accountMissing: false)
        XCTAssertEqual(levels(containing: "install message signature unavailable, signed without it"), [.warning, .debug, .warning])
    }
}
