// MIT License
//
// Copyright (c) 2016-present, Critical Blue Ltd.
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

import Foundation

/// Task-specific delegate installed by the async convenience methods of ApproovURLSession when the caller
/// supplies a delegate. It is attached with URLSessionTask.delegate, so the task releases it on completion.
///
/// It is transparent to URLSession: it reports exactly the callbacks the caller's delegate implements and
/// forwards them unchanged, so callbacks the caller does not implement still fall through to the session
/// delegate, as they do for URLSession.data(for:delegate:). The exception is authentication challenges.
/// URLSession offers the server-trust challenge to a task delegate ahead of the session delegate whenever
/// the task delegate implements urlSession(_:didReceive:completionHandler:), so forwarding that callback
/// would let the caller's delegate bypass Approov pinning. Both challenge callbacks therefore go through
/// PinningURLSessionDelegate, which applies pinning and passes only the challenges pinning does not decide
/// on to the caller's delegate.
@available(iOS 15.0, *)
final class PinningTaskDelegate: NSObject, URLSessionTaskDelegate {
    private static let challengeSelectors: Set<Selector> = [
        #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:)),
        #selector(URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:)),
    ]

    // the delegate supplied by the caller for this task
    private let taskDelegate: URLSessionTaskDelegate

    // applies pinning to challenges before any reach the caller's delegate
    private let pinningDelegate: PinningURLSessionDelegate

    init(wrapping delegate: URLSessionTaskDelegate) {
        self.taskDelegate = delegate
        self.pinningDelegate = PinningURLSessionDelegate(with: delegate)
    }

    // Challenges are claimed only when the caller's delegate implements them; otherwise URLSession delivers
    // them to the session delegate, which applies pinning itself.
    override func responds(to aSelector: Selector!) -> Bool {
        if PinningTaskDelegate.challengeSelectors.contains(aSelector) {
            return taskDelegate.responds(to: aSelector)
        }
        return super.responds(to: aSelector) || taskDelegate.responds(to: aSelector)
    }

    // Only reached for selectors this class does not implement, so never for the challenge callbacks.
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return taskDelegate.responds(to: aSelector) ? taskDelegate : nil
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        pinningDelegate.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        pinningDelegate.urlSession(session, task: task, didReceive: challenge, completionHandler: completionHandler)
    }
}
