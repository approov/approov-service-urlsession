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
    /// Everything needed to process one task. Held by the task itself as an associated
    /// object, so its lifetime is exactly the task's: it cannot outlive the task, and a
    /// later task allocated at the same address cannot inherit it.
    private final class TaskRegistration {
        let pinningSession: URLSession
        let sessionConfig: URLSessionConfiguration
        let completionHandler: ApproovTaskCompletionHandling?
        /// Owning the observation token means observation stops when this registration is
        /// released, with no manual addObserver/removeObserver pairing to get wrong.
        var observation: NSKeyValueObservation?

        init(pinningSession: URLSession,
             sessionConfig: URLSessionConfiguration,
             completionHandler: ApproovTaskCompletionHandling?) {
            self.pinningSession = pinningSession
            self.sessionConfig = sessionConfig
            self.completionHandler = completionHandler
        }
    }

    /// Key for the associated object holding the registration on a task.
    private static var registrationKey: UInt8 = 0

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

    // Registrations live on the task objects themselves (see TaskRegistration). This queue
    // only serialises the read-and-clear, which must be atomic so that a task is processed
    // exactly once.
    private let registrationsQueue = DispatchQueue(label: "ApproovSessionTaskObserver.registrations")

    /// Atomically registers everything needed to process a task before observing
    /// its initial transition from suspended to running.
    func observe(
        task: URLSessionTask,
        pinningSession: URLSession,
        sessionConfig: URLSessionConfiguration,
        completionHandler: ApproovTaskCompletionHandling? = nil
    ) {
        let registration = TaskRegistration(
            pinningSession: pinningSession,
            sessionConfig: sessionConfig,
            completionHandler: completionHandler
        )
        // Observe with the block-based API: the token is owned by the registration, and the
        // typed change value removes the need to map a raw state number.
        // Read the state from the task rather than from the change: URLSessionTask.state is an
        // NS_ENUM that does not bridge into NSKeyValueObservedChange, so change.newValue is
        // always nil here (verified on this toolchain).
        registration.observation = task.observe(\.state, options: [.new]) { [weak self] observedTask, _ in
            self?.handleStateChange(of: observedTask, newState: observedTask.state)
        }
        registrationsQueue.sync {
            objc_setAssociatedObject(
                task,
                &ApproovSessionTaskObserver.registrationKey,
                registration,
                .OBJC_ASSOCIATION_RETAIN
            )
        }
        if ApproovSessionTaskObserver.enableLogging {
            logMessage(
                line: String(#line),
                taskId: task.taskIdentifier,
                property: "registration",
                value: String(describing: ObjectIdentifier(task))
            )
        }
    }

    /// Testing hook: reports whether a task still carries a registration, and which session
    /// configuration it carries. Used to assert that registrations live and die with their task.
    func registeredSessionConfig(for task: URLSessionTask) -> URLSessionConfiguration? {
        registrationsQueue.sync {
            (objc_getAssociatedObject(
                task, &ApproovSessionTaskObserver.registrationKey) as? TaskRegistration)?.sessionConfig
        }
    }

    /// Atomically takes the registration off the task. Returns nil if another thread got
    /// there first, which is what makes processing one-shot.
    private func takeRegistrationAndStopObserving(for task: URLSessionTask) -> TaskRegistration? {
        registrationsQueue.sync {
            let registration = objc_getAssociatedObject(
                task, &ApproovSessionTaskObserver.registrationKey) as? TaskRegistration
            if registration != nil {
                objc_setAssociatedObject(
                    task, &ApproovSessionTaskObserver.registrationKey, nil, .OBJC_ASSOCIATION_RETAIN)
            }
            registration?.observation?.invalidate()
            registration?.observation = nil
            return registration
        }
    }

    /// Handles a state change reported by the per-task observation installed in observe(task:).
    /// The registration is taken off the task first, so this runs at most once per task.
    private func handleStateChange(of task: URLSessionTask, newState: URLSessionTask.State) {
        if ApproovSessionTaskObserver.enableLogging {
            logMessage(
                line: String(#line),
                taskId: task.taskIdentifier,
                property: "task.state",
                value: String(describing: task.state)
            )
        }

        guard let registration = takeRegistrationAndStopObserving(for: task) else {
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

        guard newState == .running else {
            // Cancellation before the first resume needs no Approov processing;
            // URLSession delivers its normal cancellation callback. The registration has
            // already been taken, so its observation token is released with it and
            // observation stops here.
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
