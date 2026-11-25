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

/// Every line the layer writes goes through its logging level: OFF writes nothing, the loggable
/// token and per-request substitution lines are DEBUG only, an invalid exclusion pattern is an
/// ERROR, and the deprecated getMessageSignature warns once per process.
final class Logging370Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var targetURL: URL!
    private var lines: [(ApproovLogLevel, String)] = []
    private let linesLock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        targetURL = try XCTUnwrap(URL(string: try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])))
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-logging")
        ApproovService.logSink = { [weak self] level, line in
            guard let self else { return }
            self.linesLock.lock(); self.lines.append((level, line)); self.linesLock.unlock()
        }
    }

    override func tearDown() {
        ApproovService.logSink = nil
        ApproovService.setLoggingLevel(.info)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    private func written() -> [(ApproovLogLevel, String)] {
        linesLock.lock(); defer { linesLock.unlock() }
        return lines
    }

    private func written(containing text: String) -> [ApproovLogLevel] {
        written().filter { $0.1.contains(text) }.map { $0.0 }
    }

    func testOffWritesNothing() {
        ApproovService.addExclusionURLRegex(urlRegex: "[unclosed")
        _ = ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
        XCTAssertTrue(written().isEmpty, "OFF wrote: \(written().map { $0.1 })")
    }

    func testLoggableTokenOnlyAtDebug() {
        ApproovService.setLoggingLevel(.info)
        _ = ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
        XCTAssertEqual(written(containing: "updateRequest").count, 0, "a per-request token line at INFO")
        ApproovService.setLoggingLevel(.debug)
        _ = ApproovService.updateRequestWithApproov(request: URLRequest(url: targetURL), sessionConfig: nil)
        XCTAssertEqual(written(containing: "updateRequest"), [.debug])
    }

    func testSubstitutionLinesOnlyAtDebugWithTheARC() {
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        var request = URLRequest(url: targetURL)
        request.setValue("missing-key", forHTTPHeaderField: "Api-Key")
        ApproovService.setLoggingLevel(.info)
        _ = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        XCTAssertEqual(written(containing: "Api-Key").count, 0, "a substitution line at INFO")
        ApproovService.setLoggingLevel(.debug)
        _ = ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil)
        let substitution = written().filter { $0.1.contains("Api-Key") }
        XCTAssertEqual(substitution.map { $0.0 }, [.debug])
        XCTAssertTrue(substitution.first?.1.contains("ARC: \(ApproovService.getLastARC())") ?? false, "no ARC: \(substitution)")
    }

    func testInvalidExclusionPatternIsAnError() {
        ApproovService.setLoggingLevel(.error)
        ApproovService.addExclusionURLRegex(urlRegex: "[unclosed")
        XCTAssertEqual(written(containing: "addExclusionURLRegex"), [.error])
        XCTAssertTrue(ApproovService.getExclusionURLRegexs().isEmpty, "the invalid pattern was added")
    }

    @available(*, deprecated)
    func testGetMessageSignatureWarnsOncePerProcess() {
        ApproovService.setLoggingLevel(.warning)
        let first = ApproovService.getMessageSignature(message: "message")
        _ = ApproovService.getMessageSignature(message: "message")
        XCTAssertEqual(first, ApproovService.getAccountMessageSignature(message: "message"))
        XCTAssertEqual(written(containing: "getMessageSignature"), [.warning])
    }
}
