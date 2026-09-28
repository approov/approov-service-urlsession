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
    private static let sessionChallengeSelector =
        #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))
    private static let taskChallengeSelector =
        #selector(URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:))

    // the delegate supplied by the caller for this task
    private let taskDelegate: URLSessionTaskDelegate

    // applies pinning to challenges before any reach the caller's delegate
    private let pinningDelegate: PinningURLSessionDelegate

    // The task this delegate is attached to. URLSession's session-level challenge callback carries no
    // task, so without this a challenge arriving there cannot be handed to a caller that implements
    // only the task-level callback. Weak: the task owns its delegate.
    private weak var task: URLSessionTask?

    init(wrapping delegate: URLSessionTaskDelegate, for task: URLSessionTask? = nil) {
        self.taskDelegate = delegate
        self.pinningDelegate = PinningURLSessionDelegate(with: delegate)
        self.task = task
    }

    // Challenges are claimed only when the caller's delegate implements them; otherwise URLSession delivers
    // them to the session delegate, which applies pinning itself.
    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == PinningTaskDelegate.sessionChallengeSelector {
            // Claimed when the caller implements either challenge callback. URLSession delivers
            // connection-level challenges, server trust and client certificates among them, only to
            // this selector, so declining it when the caller implements just the task-level callback
            // would send those to the session delegate, which cannot forward them on: its callback
            // carries no task. Claiming it lets pinning run first and the rest reach the caller.
            return taskDelegate.responds(to: aSelector)
                || taskDelegate.responds(to: PinningTaskDelegate.taskChallengeSelector)
        }
        if aSelector == PinningTaskDelegate.taskChallengeSelector {
            return taskDelegate.responds(to: aSelector)
        }
        return super.responds(to: aSelector) || taskDelegate.responds(to: aSelector)
    }

    // Only reached for selectors this class does not implement, so never for the challenge callbacks.
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return taskDelegate.responds(to: aSelector) ? taskDelegate : nil
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // A challenge that is not about pinning, from a caller that implements only the task-level
        // callback, is forwarded there with the task this delegate is attached to. Client-certificate,
        // NTLM and Negotiate challenges arrive on this selector, so without this they would be lost.
        if !challenge.protectionSpace.authenticationMethod.isEqual(NSURLAuthenticationMethodServerTrust),
           !taskDelegate.responds(to: PinningTaskDelegate.sessionChallengeSelector),
           taskDelegate.responds(to: PinningTaskDelegate.taskChallengeSelector),
           let task = task {
            taskDelegate.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
            return
        }
        pinningDelegate.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        pinningDelegate.urlSession(session, task: task, didReceive: challenge, completionHandler: completionHandler)
    }
}
