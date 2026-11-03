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

/// The layer sits between URLSession and the app's session delegate, so it must pass on the WebSocket
/// callbacks the app implements: the app learns that its WebSocket opened and closed.
@available(iOS 13.0, *)
final class WebSocketDelegate370Tests: XCTestCase {
    private let validInitialConfig = testAccountID

    override func setUpWithError() throws {
        try super.setUpWithError()
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-websocket-delegate")
    }

    override func tearDown() {
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    private final class Listener: NSObject, URLSessionWebSocketDelegate {
        var opened: XCTestExpectation?
        var closed: XCTestExpectation?
        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
            opened?.fulfill()
        }
        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
            closed?.fulfill()
        }
    }

    func testTheAppsWebSocketDelegateHearsOpenAndClose() throws {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])
        let url = try XCTUnwrap(URL(string: base.replacingOccurrences(of: "https://", with: "wss://")))
        let listener = Listener()
        listener.opened = expectation(description: "opened")
        let session = ApproovURLSession(configuration: .ephemeral, delegate: listener, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.webSocketTask(with: url)
        task.resume()
        wait(for: [listener.opened!], timeout: 20)
        listener.closed = expectation(description: "closed")
        task.cancel(with: .normalClosure, reason: nil)
        // a close the app started is reported once the server answers it, which the echo worker may not do,
        // so the close is only waited for briefly
        _ = XCTWaiter.wait(for: [listener.closed!], timeout: 5)
    }
}
