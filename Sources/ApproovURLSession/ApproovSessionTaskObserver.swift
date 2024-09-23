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
import os.log

// ApproovSessionTaskObserver manages the observation of tasks created that need Approov protection. New tasks are initially
// created in a suspended state. When the resume method is called to initiate the network operation this is detected by using the
// Key-Value-Observer mechanism. This provides an opportunity to immediately suspend the task again, while the request is updated with
// Approov protection in an asynchronous thread. The actual networking task can then be resumed with the Approov protection. This
// mechanism avoids any networking operations being executed in the context of the original calling thread, since this might
// legitimately be from the main UI thread.
public class ApproovSessionTaskObserver: NSObject {
    // Additional logging can be used during development to troubleshoot any issues
    // DO NOT ENABLE IN PRODUCTION
    private var enableLogging = false
    // String prefix to use during logging
    private var TAG = "ApproovSessionTaskObserver: "
    
    // the KVO object we are intersted in
    static let stateString = "state"
    
    // handler specific to Data type
    typealias CompletionHandlerData = ((Data?, URLResponse?, Error?) -> Void)?
    
    // handler specific to URL type
    typealias CompletionHandlerURL = ((URL?, URLResponse?, Error?) -> Void)?
    
    // dictionary to hold completion handlers mapped from their UUID task ID
    var completionHandlers: Dictionary<Int, Any> = Dictionary()
    
    // dictionary to hold URLSessionConfigurations mapped from their UUID task ID
    var sessionConfigs: Dictionary<Int, URLSessionConfiguration> = Dictionary()
    
    // the dispatch queue to manage serial access to the dictionary
    private let handlersQueue = DispatchQueue(label: "ApproovSessionTaskObserver")

    
    /**
     * Adds a task UUID mapped to a function to be invoked as a callback in case of an error.
     *
     * @param taskId is the ID of the task being tracked
     * @param handler is the completion handler to be called
     */
    public func addCompletionHandler(taskId: Int, handler: Any) -> Void {
        handlersQueue.sync {
            logMessage(line: String(#line), 
                    function: "addCompletionHandler",
                    property: "taskId", 
                    value: String(taskId))
            completionHandlers[taskId] = handler;
        }
    }
    
    /**
     * Adds a task UUID mapped to a session configuration.
     *
     * @param taskId is the ID of the task being tracked
     * @param sessionConfig is the session configuration fr the task
     */
    public func addSessionConfig(taskId: Int, sessionConfig: URLSessionConfiguration) -> Void {
        handlersQueue.sync {
            //MARK: LOG_MESSAGE
            if enableLogging {
                // Pass the values as strings
                let taskIdString = String(taskId)
                let sessionConfigDescription = sessionConfig.description
                
                logMessage(
                    line: String(#line),
                    function: "addSessionConfig",
                    property: "sessionConfig",
                    value: sessionConfigDescription
                )
            }
            sessionConfigs[taskId] = sessionConfig;
        }
    }
    
    /**
     * Gets the state of the session given the raw state value.
     *
     * @param state is the raw state value
     * @return the enumerated value
     */
    func getURLSessionState(state: UInt32) -> URLSessionTask.State {
        let sessionState: URLSessionTask.State
            
        switch state {
        case 0:
            sessionState = .running
        case 1:
            sessionState = .suspended
        case 2:
            sessionState = .canceling
        default:
            sessionState = .completed
        }
        
        // Log the raw state and the corresponding session state
        logMessage(line: String(#line), function: "getURLSessionState", property: "URLSessionTask.State", value: String(describing: sessionState))
        
        return sessionState
    }
    
    /**
     * It is necessary to use KVO and observe the task returned to the user in order to modify the original request
     * Since we do not want to block the task in order to contact the Approov servers, we have to perform the Approov
     * network connection asynchronously and depending on the result, modify the header and resume the request or
     * cancel the task after informing the caller of the error.
     *
     * @param keyPath the key path of the value being changed
     * @param object is the source object being changed
     * @param change is a dictionary describing the change
     * @param context is an optional value providing context to the change
     */
    public override func observeValue(forKeyPath keyPath: String?,
                             of object: Any?,
                         change: [NSKeyValueChangeKey : Any]?,
                             context: UnsafeMutableRawPointer?) {
        // Log the key path, object type, change, and context address
        let objectType = String(describing: type(of: object))
        // Prepare the context description
        let contextDescription = context != nil ? String(describing: context!) : "nil"
        logMessage(
            line: String(#line),
            function: "observeValue",
            property: "keyPath",
            value: keyPath ?? "nil",
            objectDescription: "Object Type: \(objectType), Context Address: \(contextDescription)"
        )                        
        // check if we are see a state change
        if keyPath == ApproovSessionTaskObserver.stateString {
            logMessage(line: String(#line), function: "observeValue",property:"", value: "State change detected")
            // we remove ourselves as an observer as we do not need any further state changes
            let task = object as! URLSessionTask
            task.removeObserver(self, forKeyPath: ApproovSessionTaskObserver.stateString)
            logMessage(
                line: String(#line), 
                function: "observeValue",
                property:"task", 
                value: "Stopped observing task with id: \(task.taskIdentifier)"
            )
            // The pinning session
            let customPinningSession: URLSession? = context?.assumingMemoryBound(to: URLSession.self).pointee
            // We can dispose of the URLSession pointer after the execution of this block
            defer {
                logMessage(
                    line: String(#line), 
                    function: "observeValue",
                    property:"context", 
                    value: "Deallocating context"
                )
                context?.deallocate()
            }
            // get any completion handler and session config from the dictionary and then remove it
            var completionHandler: Any?
            var sessionConfig: URLSessionConfiguration?
            handlersQueue.sync {
                if completionHandlers.keys.contains(task.taskIdentifier) {
                    completionHandler = completionHandlers[task.taskIdentifier]
                    completionHandlers.removeValue(forKey: task.taskIdentifier)
                    logMessage(
                        line: String(#line),
                        function: "observeValue",
                        property: "completionHandlers.keys.contains",
                        value: String(task.taskIdentifier),
                        objectDescription: "Removed completion handler from dictionary"
                    )
                }
                if sessionConfigs.keys.contains(task.taskIdentifier) {
                    sessionConfig = sessionConfigs[task.taskIdentifier]
                    sessionConfigs.removeValue(forKey: task.taskIdentifier)
                    logMessage(
                        line: String(#line),
                        function: "observeValue",
                        property: "sessionConfigs.keys.contains",
                        value: String(task.taskIdentifier),
                        objectDescription: "Removed sessionConfig from dictionary"
                    )
                }
            }
            
            // determine the new state from the raw enum value
            let newStateEnum = change![NSKeyValueChangeKey.newKey] as! NSNumber
            let newState = getURLSessionState(state: newStateEnum.uint32Value)
            
            // We detect the initial switch from when the task is created in Suspended state to when the user
            // triggers the Resume state. We immediately pause the task by suspending it again and doing the background
            // Approov network connection before considering if the actual connection should be resumed or terminated.
            // Note that this is meant to only happen during the initial resume call since we remove ourselves as observers
            // at the first ever resume call
            if newState == URLSessionTask.State.running {
                // immediately suspend the task so that it cannot make progress
                logMessage(
                    line: String(#line),
                        function: "observeValue",
                        property: "newState",
                        value: String(describing: newState),
                        objectDescription: "Will suspend task with ID: \(task.taskIdentifier)"
                )
                task.suspend()
                logMessage(
                    line: String(#line),
                        function: "observeValue",
                        property: "task.suspend()",
                        // Get the current state of the task
                        value: String(describing: task.state),
                        objectDescription: "Suspended task state with ID: \(task.taskIdentifier)"
                )
                // execute the Approov processing in a background thread since it may need network access and thus take
                // some time to complete and we cannot do this in the context of the task resume caller (which might be the
                // main UI thread, for instance)
                DispatchQueue.global(qos: .userInitiated).async {
                    // update the request using Approov and handler its response
                    let updateResponse = ApproovService.updateRequestWithApproov(request: task.currentRequest!, sessionConfig: sessionConfig)
                    
                    if updateResponse.decision == .ShouldProceed {
                        // modify original request by calling the "updateCurrentRequest" method in the underlying
                        // Objective-C implementation
                        let sel = NSSelectorFromString("updateCurrentRequest:")
                        if task.responds(to: sel) {
                            task.perform(sel, with: updateResponse.request)
                        } else {
                            // this means that URLRequest has removed the `updateCurrentRequest` method or we are observing an object that
                            // is not an instance of URLRequest. Both are fatal errors.
                            os_log("ApproovService: Unable to modify NSURLRequest headers; object instance is of type %@", type: .error, type(of: task).description())
                        }
                        
                        // the task execution can now be resumed to perform the actual network request (as long as it is
                        // still suspended and thus hasn't been cancelled)
                        if task.state == URLSessionTask.State.suspended {
                            task.resume()
                            self.logMessage(
                                line: String(#line),
                                    function: "observeValue",
                                    property: "task.resume()",
                                    // Get the current state of the task
                                    value: String(describing: task.state),
                                    objectDescription: "Resumed task state with ID: \(task.taskIdentifier)"
                            )
                        } else {
                            os_log("ApproovService: Task was not in suspended state after Approov processing", type: .error)
                        }
                        return
                    } else if updateResponse.decision == .ShouldIgnore {
                        // we should just pass on the request and not modify the headers or URL in any way - unless it is
                        // already cancelled
                        if task.state == URLSessionTask.State.suspended {
                            task.resume()
                            self.logMessage(
                                line: String(#line),
                                    function: "observeValue",
                                    property: "task.resume()",
                                    // Get the current state of the task
                                    value: String(describing: task.state),
                                    objectDescription: "Resumed task state with ID: \(task.taskIdentifier)"
                            )
                        }
                    } else if task.state == URLSessionTask.State.suspended {
                        self.logMessage(
                                line: String(#line),
                                    function: "observeValue",
                                    property: "task.state == URLSessionTask.State.suspended",
                                    // Get the current state of the task
                                    value: String(describing: task.state),
                                    objectDescription: "Will process custom delegate for task with ID: \(task.taskIdentifier)"
                            )
                        if let pinningSession = customPinningSession {
                            if let pinningDelegate = pinningSession.delegate {
                                // the task is still suspended and we have an error condition, first inform the pinning delegate
                                pinningDelegate.urlSession!(pinningSession, didBecomeInvalidWithError: updateResponse.error)
                                // call any completion handler with the error or cancel if there is no completion handler
                                if let handler = completionHandler as! CompletionHandlerData {
                                    handler(nil, nil, updateResponse.error)
                                    self.logMessage(
                                    line: String(#line),
                                    function: "observeValue",
                                    property: "completionHandler as! CompletionHandlerData",
                                    // Get the current state of the task
                                    value: updateResponse.error?.localizedDescription ?? "error with no message",
                                    objectDescription: "Delegate handler with error message for task with ID: \(task.taskIdentifier)"
                                )
                                } else if let handler = completionHandler as! CompletionHandlerURL {
                                    handler(nil, nil, updateResponse.error)
                                    self.logMessage(
                                    line: String(#line),
                                    function: "observeValue",
                                    property: "completionHandler as! CompletionHandlerURL",
                                    // Get the current state of the task
                                    value: updateResponse.error?.localizedDescription ?? "error with no message",
                                    objectDescription: "Delegate handler with error message for task with ID: \(task.taskIdentifier)"
                                )
                                } else {
                                    task.cancel()
                                    self.logMessage(
                                    line: String(#line),
                                    function: "observeValue",
                                    property: "task.cancel()",
                                    // Get the current state of the task
                                    value: String(describing: task.state),
                                    objectDescription: "Invoked cancel for task with ID: \(task.taskIdentifier)"
                                )
                                }
                            } else {
                                os_log("ApproovService: Pinning Delegate from url session pointer is invalid", type: .error)
                            }
                        } else {
                            os_log("ApproovService: Pinning Session pointer is invalid/not of type URLSession %@", type: .error, context.debugDescription)
                        }
                    }
                    self.logMessage(
                        line: String(#line),
                        function: "observeValue",
                        property: "No decision from token fetch and no completion handler invoked",
                        // Get the current state of the task
                        value: String(describing: task.state),
                        objectDescription: "Error for task with ID: \(task.taskIdentifier)"
                    )
                }
            }
        }
    }

    // DEBUG function to log additional messages
    func logMessage(line: String, function: String, property: String, value: String, objectDescription: String? = nil) {
        var message = "\(TAG) - Line: \(line), Function: \(function), Property: \(property), Value: \(value)"
        if let description = objectDescription {
            message += ", Object Description: \(description)"
        }
        print(message)
    }
  

}
