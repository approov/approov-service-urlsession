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

/// The message signing forms that CHANGELOG, ADVANCED and REFERENCE give, as an app writes them.
final class SigningDecisionsSurface371Tests: XCTestCase {
    private let validInitialConfig = testAccountID

    override func setUpWithError() throws {
        try super.setUpWithError()
        MiniSDKAttesterProxyController.reset()
        resetApproovServiceForTesting()
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-signing-decisions-surface")
    }

    override func tearDown() {
        ApproovService.setServiceMutator(nil)
        MiniSDKAttesterProxyController.reset()
        resetApproovServiceForTesting()
        super.tearDown()
    }

    // a mutator of the app's own, as ADVANCED describes
    private final class MyDecisions: ApproovServiceMutator {}

    func testTheDocumentedFormsCompile() {
        // CHANGELOG, ADVANCED and REFERENCE
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning(decisions: .ALWAYS_PROCEED).setDefaultFactory(
            ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
        XCTAssertEqual(String(describing: ApproovService.getServiceMutator()),
                       "ApproovDefaultMessageSigning(ApproovServiceMutator.ALWAYS_PROCEED)")

        // the other standard decisions, and a mutator of the app's own
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning(decisions: .CLOSE_FAILURE).setDefaultFactory(
            ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
        XCTAssertEqual(String(describing: ApproovService.getServiceMutator()),
                       "ApproovDefaultMessageSigning(ApproovServiceMutator.CLOSE_FAILURE)")
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning(decisions: .DEFAULT))
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning(decisions: MyDecisions()).setDefaultFactory(
            ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
        XCTAssertTrue(String(describing: ApproovService.getServiceMutator()).hasPrefix("ApproovDefaultMessageSigning("))

        // the 3.7.0 form is unchanged
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(
            ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
        XCTAssertEqual(String(describing: ApproovService.getServiceMutator()), "ApproovDefaultMessageSigning")
    }
}
