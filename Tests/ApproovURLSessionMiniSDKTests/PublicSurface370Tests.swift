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
// a plain import, not @testable: this file only compiles if every name it uses is public
import ApproovURLSessionPackage
import MiniSDKTestSupport

/// The 3.7.0 common interface as an app sees it: the shared names, their 3.5.x aliases, and the
/// reset that every initialize applies to them.
final class PublicSurface370Tests: XCTestCase {
    private let validInitialConfig = testAccountID

    override func setUpWithError() throws {
        try super.setUpWithError()
        MiniSDKAttesterProxyController.reset()
        resetApproovServiceForTesting()
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-public-surface")
    }

    override func tearDown() {
        ApproovService.setServiceMutator(nil)
        MiniSDKAttesterProxyController.reset()
        resetApproovServiceForTesting()
        super.tearDown()
    }

    func testTokenHeaderSharedNames() {
        XCTAssertEqual(ApproovService.getTokenHeader(), "Approov-Token")
        XCTAssertEqual(ApproovService.getTokenPrefix(), "")
        ApproovService.setTokenHeader(header: "Authorization", prefix: "Bearer ")
        XCTAssertEqual(ApproovService.getTokenHeader(), "Authorization")
        XCTAssertEqual(ApproovService.getTokenPrefix(), "Bearer ")
        // a nil prefix means no prefix, never the text "nil"
        ApproovService.setTokenHeader(header: "Approov-Token", prefix: nil)
        XCTAssertEqual(ApproovService.getTokenPrefix(), "")
    }

    @available(*, deprecated)
    func testDeprecatedHeaderAliasesSetTheSameState() {
        ApproovService.setApproovHeader(header: "X-Token", prefix: "T ")
        XCTAssertEqual(ApproovService.getTokenHeader(), "X-Token")
        XCTAssertEqual(ApproovService.getTokenPrefix(), "T ")
        XCTAssertEqual(ApproovService.getApproovTokenHeader(), "X-Token")
        ApproovService.setApproovTraceIDHeader(header: "X-Trace")
        XCTAssertEqual(ApproovService.getTraceIDHeader(), "X-Trace")
        XCTAssertEqual(ApproovService.getApproovTraceIDHeader(), "X-Trace")
    }

    func testTraceIDHeaderSharedNames() {
        XCTAssertEqual(ApproovService.getTraceIDHeader(), "Approov-TraceID")
        ApproovService.setTraceIDHeader(header: "X-Trace")
        XCTAssertEqual(ApproovService.getTraceIDHeader(), "X-Trace")
        ApproovService.setTraceIDHeader(header: nil)
        XCTAssertNil(ApproovService.getTraceIDHeader())
    }

    func testUseApproovStatusIfNoTokenHasAGetter() {
        XCTAssertFalse(ApproovService.getUseApproovStatusIfNoToken())
        ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)
        XCTAssertTrue(ApproovService.getUseApproovStatusIfNoToken())
    }

    func testInitializeResetsTheSharedSettings() throws {
        ApproovService.setTokenHeader(header: "Authorization", prefix: "Bearer ")
        ApproovService.setTraceIDHeader(header: nil)
        ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-public-surface-2")
        XCTAssertEqual(ApproovService.getTokenHeader(), "Approov-Token")
        XCTAssertEqual(ApproovService.getTokenPrefix(), "")
        XCTAssertEqual(ApproovService.getTraceIDHeader(), "Approov-TraceID")
        XCTAssertFalse(ApproovService.getUseApproovStatusIfNoToken())
    }

    func testEnabledSharedNamesMatchTheirAliases() throws {
        XCTAssertTrue(ApproovService.isApproovServiceEnabled())
        XCTAssertTrue(ApproovService.isApproovProtectionEnabled())
        XCTAssertEqual(ApproovService.isApproovServiceEnabled(), ApproovService.isInitialized())
        XCTAssertEqual(ApproovService.isApproovProtectionEnabled(), ApproovService.isApproovEnabled())
    }

    func testSetInstallAttributesNeedsProtection() throws {
        XCTAssertNoThrow(try ApproovService.setInstallAttributes("signed.install.attributes"))
        MiniSDKAttesterProxyController.resetSdkForTesting()
        resetApproovServiceForTesting()
        try ApproovService.initialize(config: "", comment: nil)
        XCTAssertTrue(ApproovService.isApproovServiceEnabled())
        XCTAssertFalse(ApproovService.isApproovProtectionEnabled())
        XCTAssertThrowsError(try ApproovService.setInstallAttributes("signed.install.attributes")) { error in
            XCTAssertEqual(error.localizedDescription, "setInstallAttributes: SDK not initialized")
        }
    }

    func testACustomMutatorCanReadTheChanges() throws {
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])))
        final class Recorder: ApproovServiceMutator {
            var tokenHeader: String?
            var traceHeader: String?
            var headers: [String] = []
            var queryKeys: [String] = []
            var originalURL: String?
            func handleInterceptorProcessedRequest(_ request: URLRequest,
                                                   changes: ApproovRequestMutations) throws -> URLRequest {
                tokenHeader = changes.getTokenHeaderKey()
                traceHeader = changes.getTraceIDHeaderKey()
                headers = changes.getSubstitutionHeaderKeys()
                queryKeys = changes.getSubstitutionQueryParamKeys()
                originalURL = changes.getOriginalURL()
                return request
            }
        }
        let recorder = Recorder()
        ApproovService.setServiceMutator(recorder)
        _ = ApproovService.updateRequestWithApproov(request: URLRequest(url: url), sessionConfig: nil)
        XCTAssertEqual(recorder.tokenHeader, "Approov-Token")
        XCTAssertEqual(recorder.traceHeader, "Approov-TraceID")
        XCTAssertEqual(recorder.headers, [])
        XCTAssertEqual(recorder.queryKeys, [])
        XCTAssertNil(recorder.originalURL)
    }
}
