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

/// An instance that wraps a URLSessionTask through a proxy does not report the task's state
/// changes; they are reported only on the wrapped task. The layer must observe the wrapped task,
/// and must never send a task it cannot observe.
final class WrappedTask370Tests: XCTestCase {
    private let url = URL(string: "https://example.invalid/")!

    /// A genuine task is observed directly.
    func testObservableTaskOfAGenuineTaskIsTheTaskItself() {
        let task = URLSession(configuration: .ephemeral).dataTask(with: url)
        XCTAssertTrue(ApproovSessionTaskObserver.observableTask(for: task) === task)
        task.cancel()
    }

    /// A wrapper that exposes the task it wraps is observed through that task.
    func testObservableTaskUnwrapsAWrapperThatExposesItsTask() {
        let inner = URLSession(configuration: .ephemeral).dataTask(with: url)
        let wrapped = unsafeBitCast(ExposingTaskWrapper(inner), to: URLSessionTask.self)
        XCTAssertTrue(ApproovSessionTaskObserver.observableTask(for: wrapped) === inner)
        inner.cancel()
    }

    /// A wrapper that does not expose its task cannot be observed.
    func testObservableTaskIsNilForAWrapperThatHidesItsTask() {
        let wrapped = unsafeBitCast(HidingTaskWrapper(), to: URLSessionTask.self)
        XCTAssertNil(ApproovSessionTaskObserver.observableTask(for: wrapped))
    }

    /// A task that cannot be observed is cancelled and its completion handler gets an error at once,
    /// so it is never sent without Approov.
    func testUnobservableTaskIsCancelledAndFailsWithAnError() {
        let hiding = HidingTaskWrapper()
        let wrapped = unsafeBitCast(hiding, to: URLSessionTask.self)
        var received: Error?
        let gate = ApproovTaskCompletionGate<Data> { _, _, error in received = error }
        ApproovSessionTaskObserver().observe(
            task: wrapped,
            pinningSession: URLSession(configuration: .ephemeral),
            sessionConfig: .ephemeral,
            completionHandler: gate
        )
        XCTAssertTrue(hiding.cancelled, "an unobservable task must be cancelled")
        guard case .permanentError(let message)? = received as? ApproovError else {
            return XCTFail("expected ApproovError.permanentError, got \(String(describing: received))")
        }
        XCTAssertTrue(message.contains("HidingTaskWrapper"))
    }
}

/// Stands in for a proxy that exposes the task it wraps.
private final class ExposingTaskWrapper: NSObject {
    private let inner: URLSessionTask
    init(_ inner: URLSessionTask) { self.inner = inner }
    @objc func wrappedTask() -> URLSessionTask { inner }
}

/// Stands in for a proxy that hides the task it wraps.
private final class HidingTaskWrapper: NSObject {
    private(set) var cancelled = false
    @objc func cancel() { cancelled = true }
}
