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
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
// FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation
import os.log

/// Type-erased access to a completion gate, used when Approov rejects a request
/// before URLSession can produce a response.
protocol ApproovTaskCompletionHandling: AnyObject {
    func complete(with error: Error)
}

/// Ensures that a URLSession completion handler is invoked at most once. A
/// rejected request is completed by the observer and then its underlying task is
/// cancelled; URLSession's later cancellation callback is discarded by this gate.
final class ApproovTaskCompletionGate<Value>: ApproovTaskCompletionHandling, @unchecked Sendable {
    typealias Handler = (Value?, URLResponse?, Error?) -> Void

    private let lock = NSLock()
    private var handler: Handler?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func complete(value: Value?, response: URLResponse?, error: Error?) {
        lock.lock()
        let handler = self.handler
        self.handler = nil
        lock.unlock()
        handler?(value, response, error)
    }

    func complete(with error: Error) {
        complete(value: nil, response: nil, error: error)
    }
}

// ApproovSessionTaskObserver manages the observation of tasks created that need Approov protection. New tasks are initially
// created in a suspended state. When the resume method is called to initiate the network operation this is detected by using the
// Key-Value-Observer mechanism. This provides an opportunity to immediately suspend the task again, while the request is updated with
// Approov protection in an asynchronous thread. The actual networking task can then be resumed with the Approov protection. This
// mechanism avoids any networking operations being executed in the context of the original calling thread, since this might
// legitimately be from the main UI thread.
public class ApproovSessionTaskObserver: NSObject {
    private struct TaskRegistration {
        let pinningSession: URLSession
        let sessionConfig: URLSessionConfiguration
        let completionHandler: ApproovTaskCompletionHandling?
    }

    private static let loggingQueue = DispatchQueue(label: "io.approov.ApproovService.loggingQueue", qos: .userInitiated)
    private static var _enableLogging: Bool = false
    public static var enableLogging: Bool {
        get {
            return loggingQueue.sync { _enableLogging }
        }
        set {
            loggingQueue.sync { _enableLogging = newValue }
        }
    }

    private let TAG = "ApproovSession: "
    static let stateString = "state"

    // A taskIdentifier is unique only within its URLSession. ObjectIdentifier
    // isolates registrations belonging to different sessions that both use task 1.
    private var registrations: [ObjectIdentifier: TaskRegistration] = [:]
    private let registrationsQueue = DispatchQueue(label: "ApproovSessionTaskObserver.registrations")

    /// Atomically registers everything needed to process a task before observing
    /// its initial transition from suspended to running.
    func observe(
        task: URLSessionTask,
        pinningSession: URLSession,
        sessionConfig: URLSessionConfiguration,
        completionHandler: ApproovTaskCompletionHandling? = nil
    ) {
        registrationsQueue.sync {
            registrations[ObjectIdentifier(task)] = TaskRegistration(
                pinningSession: pinningSession,
                sessionConfig: sessionConfig,
                completionHandler: completionHandler
            )
        }
        task.addObserver(
            self,
            forKeyPath: ApproovSessionTaskObserver.stateString,
            options: .new,
            context: nil
        )
        if ApproovSessionTaskObserver.enableLogging {
            logMessage(
                line: String(#line),
                taskId: task.taskIdentifier,
                property: "registration",
                value: String(describing: ObjectIdentifier(task))
            )
        }
    }

    private func removeRegistration(for task: URLSessionTask) -> TaskRegistration? {
        registrationsQueue.sync {
            registrations.removeValue(forKey: ObjectIdentifier(task))
        }
    }

    func getURLSessionState(state: UInt32) -> URLSessionTask.State {
        switch state {
        case 0:
            return .running
        case 1:
            return .suspended
        case 2:
            return .canceling
        default:
            return .completed
        }
    }

    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == ApproovSessionTaskObserver.stateString,
              let task = object as? URLSessionTask else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        task.removeObserver(self, forKeyPath: ApproovSessionTaskObserver.stateString)
        if ApproovSessionTaskObserver.enableLogging {
            logMessage(
                line: String(#line),
                taskId: task.taskIdentifier,
                property: "task.state",
                value: String(describing: task.state)
            )
        }

        guard let registration = removeRegistration(for: task) else {
            // Never allow a task that has lost its Approov state to continue as an
            // unprotected request.
            if task.state == .running {
                task.cancel()
            }
            if ApproovService.loggingLevel >= .error {
                os_log("ApproovService: Missing registration for URLSession task %d", type: .error, task.taskIdentifier)
            }
            return
        }

        guard let newStateNumber = change?[.newKey] as? NSNumber,
              getURLSessionState(state: newStateNumber.uint32Value) == .running else {
            // Cancellation before the first resume needs no Approov processing;
            // URLSession delivers its normal cancellation callback.
            return
        }

        task.suspend()
        DispatchQueue.global(qos: .userInitiated).async {
            guard let currentRequest = task.currentRequest else {
                task.cancel()
                return
            }

            let updateResponse = ApproovService.updateRequestWithApproov(
                request: currentRequest,
                sessionConfig: registration.sessionConfig
            )

            switch updateResponse.decision {
            case .ShouldProceed:
                let selector = NSSelectorFromString("updateCurrentRequest:")
                if task.responds(to: selector) {
                    task.perform(selector, with: updateResponse.request)
                } else if ApproovService.loggingLevel >= .error {
                    os_log(
                        "ApproovService: Unable to modify NSURLRequest headers; object instance is of type %@",
                        type: .error,
                        type(of: task).description()
                    )
                }
                self.resumeIfSuspended(task)

            case .ShouldIgnore:
                self.resumeIfSuspended(task)

            default:
                guard task.state == .suspended else {
                    return
                }
                let error = updateResponse.error ?? URLError(.unknown)
                registration.pinningSession.delegate?.urlSession?(
                    registration.pinningSession,
                    didBecomeInvalidWithError: error
                )
                registration.completionHandler?.complete(with: error)
                // Always terminate the underlying task. Completion-based tasks
                // are protected from the subsequent cancellation callback by the
                // one-shot gate above.
                task.cancel()
            }
        }
    }

    private func resumeIfSuspended(_ task: URLSessionTask) {
        if task.state == .suspended {
            task.resume()
        } else if task.state != .canceling && task.state != .completed && ApproovService.loggingLevel >= .error {
            os_log("ApproovService: Task was not in suspended state after Approov processing", type: .error)
        }
    }

    private func logMessage(line: String, taskId: Int, property: String, value: String) {
        os_log(
            "%{public}@ - Line: %{public}@, TaskID: %{public}d, Property: %{public}@, Value: %{public}@",
            TAG,
            line,
            taskId,
            property,
            value
        )
    }

}
