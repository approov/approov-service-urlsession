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

// Provides an implementation of URLSession with Approov protection, including dynamic pinning. Methods delegate to an underlying
// URLSession after adding Approov protection. Note that the "Performing Asynchronous Transfers" methods defined from iOS 15 do not
// currently add Approov protection.
// URLSession is Sendable; this subclass restates it as @unchecked because its stored state is immutable after init.
public class ApproovURLSession: URLSession, @unchecked Sendable {
    // configuration for this session
    let urlSessionConfiguration: URLSessionConfiguration
    
    // delegate used to apply pinning to connections
    let pinningURLSessionDelegate: PinningURLSessionDelegate
    
    // URLSession with a delegate that applies pinning
    let pinnedURLSession: URLSession
    
    // task observer used across all sessions
    static let taskObserver: ApproovSessionTaskObserver = ApproovSessionTaskObserver()
    
    /**
     *  URLSession initializer
     *  https://developer.apple.com/documentation/foundation/urlsession/1411597-init
     */
    public init(configuration: URLSessionConfiguration, delegate: URLSessionDelegate?, delegateQueue: OperationQueue?) {
        self.urlSessionConfiguration = configuration
        self.pinningURLSessionDelegate = PinningURLSessionDelegate(with: delegate)
        self.pinnedURLSession = URLSession(configuration: configuration, delegate: pinningURLSessionDelegate, delegateQueue: delegateQueue)
        
        // note we are unable to initialize the URLSession base class as discussed here:
        // https://stackoverflow.com/questions/48158484/subclassing-factory-methods-of-urlsession-in-swift
        // this means that some methods called on URLSession extensions are not operable
        super.init()
    }
    
    /**
     *  URLSession initializer
     *   https://developer.apple.com/documentation/foundation/urlsession/1411474-init
     */
    public convenience init(configuration: URLSessionConfiguration) {
        self.init(configuration: configuration, delegate: nil, delegateQueue: nil)
    }

    /**
     *  A copy of the configuration object for this session. The URLSession base class is never initialized (see
     *  init(configuration:delegate:delegateQueue:)), so its own value is not the configuration supplied by the caller.
     *  https://developer.apple.com/documentation/foundation/urlsession/1411477-configuration
     */
    public override var configuration: URLSessionConfiguration {
        return self.pinnedURLSession.configuration
    }

    /**
     *  The operation queue provided when this session was created, or the one created for it. The URLSession base
     *  class is never initialized, so its own value is not the queue supplied by the caller.
     *  https://developer.apple.com/documentation/foundation/urlsession/1411571-delegatequeue
     */
    public override var delegateQueue: OperationQueue {
        return self.pinnedURLSession.delegateQueue
    }

    /// Registers all task-specific Approov state as one record. The observer
    /// keys this by task object identity because taskIdentifier is only unique
    /// within a single URLSession.
    private func observe(
        _ task: URLSessionTask,
        completionHandler: ApproovTaskCompletionHandling? = nil
    ) {
        ApproovURLSession.taskObserver.observe(
            task: task,
            pinningSession: pinnedURLSession,
            sessionConfig: urlSessionConfiguration,
            completionHandler: completionHandler
        )
    }
    
    // MARK: URLSession dataTask
    /*  Creates a task that retrieves the contents of the specified URL
     *  https://developer.apple.com/documentation/foundation/urlsession/1411554-datatask
     */
    public override func dataTask(with url: URL) -> URLSessionDataTask {
        return dataTask(with: URLRequest(url: url))
    }
    
    /**
     *  Creates a task that retrieves the contents of a URL based on the specified URL request object
     *  https://developer.apple.com/documentation/foundation/urlsession/1410592-datatask
     */
    public override func dataTask(with request: URLRequest) -> URLSessionDataTask {
        let task = self.pinnedURLSession.dataTask(with: request)
        observe(task)
        return task
    }
    
    /**
     *  Creates a task that retrieves the contents of the specified URL, then calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1410330-datatask
     */
    @preconcurrency public override func dataTask(with url: URL, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return dataTask(with: URLRequest(url: url), completionHandler: completionHandler)
    }
    
    /**
     *  Creates a task that retrieves the contents of a URL based on the specified URL request object, and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1407613-datatask
     */
    @preconcurrency public override func dataTask(with request: URLRequest, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        let completionGate = ApproovTaskCompletionGate<Data>(handler: completionHandler)
        let task = self.pinnedURLSession.dataTask(with: request) { data, response, error in
            completionGate.complete(value: data, response: response, error: error)
        }
        observe(task, completionHandler: completionGate)
        return task
    }
    
    
    // MARK: URLSession downloadTask
    /**
     *  Creates a download task that retrieves the contents of the specified URL and saves the results to a file
     *  https://developer.apple.com/documentation/foundation/urlsession/1411482-downloadtask
     */
    public override func downloadTask(with url: URL) -> URLSessionDownloadTask {
        return downloadTask(with: URLRequest(url: url))
    }
    
    /**
     *  Creates a download task that retrieves the contents of a URL based on the specified URL request object
     *  and saves the results to a file
     *  https://developer.apple.com/documentation/foundation/urlsession/1411481-downloadtask
     */
    public override func downloadTask(with request: URLRequest) -> URLSessionDownloadTask {
        let task = self.pinnedURLSession.downloadTask(with: request)
        observe(task)
        return task
    }
    
    /**
     *  Creates a download task that retrieves the contents of the specified URL, saves the results to a file,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411608-downloadtask
     */
    @preconcurrency public override func downloadTask(with: URL, completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return downloadTask(with: URLRequest(url: with), completionHandler: completionHandler)
    }
    
    /**
     *  Creates a download task that retrieves the contents of a URL based on the specified URL request object,
     *  saves the results to a file, and calls a handler upon completion.
     *  https://developer.apple.com/documentation/foundation/nsurlsession/1411511-downloadtaskwithrequest?language=objc
     */
    @preconcurrency public override func downloadTask(with request: URLRequest, completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        let completionGate = ApproovTaskCompletionGate<URL>(handler: completionHandler)
        let task = self.pinnedURLSession.downloadTask(with: request) { url, response, error in
            completionGate.complete(value: url, response: response, error: error)
        }
        observe(task, completionHandler: completionGate)
        return task
    }
    
    /**
     *  Creates a download task to resume a previously canceled or failed download
     *  https://developer.apple.com/documentation/foundation/urlsession/1409226-downloadtask
     *  NOTE: this call is not protected by Approov
     */
    public override func downloadTask(withResumeData: Data) -> URLSessionDownloadTask {
        return self.pinnedURLSession.downloadTask(withResumeData: withResumeData)
    }
    
    /**
     *  Creates a download task to resume a previously canceled or failed download and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411598-downloadtask
     *  NOTE: this call is not protected by Approov
     */
    @preconcurrency public override func downloadTask(withResumeData: Data, completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return self.pinnedURLSession.downloadTask(withResumeData: withResumeData, completionHandler: completionHandler)
    }
    
    // MARK: Upload Tasks
    /**
     *  Creates a task that performs an HTTP request for the specified URL request object and uploads the provided data
     *  https://developer.apple.com/documentation/foundation/urlsession/1409763-uploadtask
     */
    public override func uploadTask(with request: URLRequest, from: Data) -> URLSessionUploadTask {
        let task = pinnedURLSession.uploadTask(with: request, from: from)
        observe(task)
        return task
    }
    
    /**
     *  Creates a task that performs an HTTP request for the specified URL request object, uploads the provided data,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411518-uploadtask
     */
    @preconcurrency public override func uploadTask(with request: URLRequest, from: Data?, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let completionGate = ApproovTaskCompletionGate<Data>(handler: completionHandler)
        let task = self.pinnedURLSession.uploadTask(with: request, from: from) { data, response, error in
            completionGate.complete(value: data, response: response, error: error)
        }
        observe(task, completionHandler: completionGate)
        return task
    }
    
    /**
     *  Creates a task that performs an HTTP request for uploading the specified file
     *  https://developer.apple.com/documentation/foundation/urlsession/1411550-uploadtask
     */
    public override func uploadTask(with request: URLRequest, fromFile: URL) -> URLSessionUploadTask {
        let task = self.pinnedURLSession.uploadTask(with: request, fromFile: fromFile)
        observe(task)
        return task
    }
    
    /**
     *  Creates a task that performs an HTTP request for the specified URL request object, uploads the provided data,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411518-uploadtask
     */
    @preconcurrency public override func uploadTask(with request: URLRequest, fromFile: URL, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let completionGate = ApproovTaskCompletionGate<Data>(handler: completionHandler)
        let task = self.pinnedURLSession.uploadTask(with: request, fromFile: fromFile) { data, response, error in
            completionGate.complete(value: data, response: response, error: error)
        }
        observe(task, completionHandler: completionGate)
        return task
    }
    
    /**
     *  Creates a task that performs an HTTP request for uploading data based on the specified URL request
     *  https://developer.apple.com/documentation/foundation/urlsession/1410934-uploadtask
     */
    public override func uploadTask(withStreamedRequest: URLRequest) -> URLSessionUploadTask {
        let task = self.pinnedURLSession.uploadTask(withStreamedRequest: withStreamedRequest)
        observe(task)
        return task
    }
    
    // MARK: Combine Publisher Tasks
    /**
     *  Returns a publisher that wraps a URL session data task for a given URL request.
     *  https://developer.apple.com/documentation/foundation/urlsession
     */
    @available(iOS 13.0, *)
    public func dataTaskPublisherWithApproov(for request: URLRequest) -> (URLSession.DataTaskPublisher , Error?) {
        // in this case we must perform the Approov update in the context of the caller - which may mean that the calling
        // thread experience some delay to the potential network request to Approov
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: request, sessionConfig: urlSessionConfiguration)
        switch approovUpdateResponse.decision {
        case .ShouldProceed:
            // go ahead and make the API call with the provided request object
            return (self.pinnedURLSession.dataTaskPublisher(for: approovUpdateResponse.request), nil)
        case .ShouldIgnore:
            // we should ignore the ApproovService request response and just perform the original request
            return (self.pinnedURLSession.dataTaskPublisher(for: request), nil)
        // .ShouldFail .ShouldRetry are treated the same here
        default:
            // we create a task and cancel it immediately, telling the delegate we are marking the task as invalid
            let sessionTaskPublisher = self.pinnedURLSession.dataTaskPublisher(for: approovUpdateResponse.request)
            // We cancel all the tasks for the current pinned session as it is now invalid but we do not cancel the session itself
            self.pinnedURLSession.getAllTasks { tasks in
                tasks.forEach { $0.cancel() }
            }
            self.pinningURLSessionDelegate.urlSession(self.pinnedURLSession, didBecomeInvalidWithError: approovUpdateResponse.error)
            return (sessionTaskPublisher, approovUpdateResponse.error)
        }
    }
    
    /**
     *  Returns a publisher that wraps a URL session data task for a given URL request. Previous naming of the method.
     *  https://developer.apple.com/documentation/foundation/urlsession
     */
    @available(iOS 13.0, *)
    public func dataTaskPublisherApproov(for request: URLRequest) -> (URLSession.DataTaskPublisher, Error?) {
        return dataTaskPublisherWithApproov(for: request)
    }
    
    
    // MARK: Managing the Session
    /**
     *  Invalidates the session, allowing any outstanding tasks to finish
     *  https://developer.apple.com/documentation/foundation/urlsession/1407428-finishtasksandinvalidate
     */
    public override func finishTasksAndInvalidate() {
        self.pinnedURLSession.finishTasksAndInvalidate()
    }
    
    /**
     *  Flushes cookies and credentials to disk, clears transient caches, and ensures that future requests
     *  occur on a new TCP connection
     *  https://developer.apple.com/documentation/foundation/urlsession/1411622-flush
     */
    @preconcurrency public override func flush(completionHandler: @escaping @Sendable () -> Void){
        self.pinnedURLSession.flush(completionHandler: completionHandler)
    }
    
    /**
     *  Asynchronously calls a completion callback with all data, upload, and download tasks in a session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411578-gettaskswithcompletionhandler
     */
    @preconcurrency public override func getTasksWithCompletionHandler(_ completionHandler: @escaping @Sendable ([URLSessionDataTask], [URLSessionUploadTask], [URLSessionDownloadTask]) -> Void) {
        self.pinnedURLSession.getTasksWithCompletionHandler(completionHandler)
    }
    
    /**
     *  Asynchronously calls a completion callback with all tasks in a session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411618-getalltasks
     */
    @preconcurrency public override func getAllTasks(completionHandler: @escaping @Sendable ([URLSessionTask]) -> Void) {
        self.pinnedURLSession.getAllTasks(completionHandler: completionHandler)
    }
    
    /**
     *  Cancels all outstanding tasks and then invalidates the session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411538-invalidateandcancel
     */
    public override func invalidateAndCancel() {
        self.pinnedURLSession.invalidateAndCancel()
    }
    
    /**
     *  Empties all cookies, caches and credential stores, removes disk files, flushes in-progress downloads to disk,
     *  and ensures that future requests occur on a new socket
     *  https://developer.apple.com/documentation/foundation/urlsession/1411479-reset
     */
    @preconcurrency public override func reset(completionHandler: @escaping @Sendable () -> Void) {
        self.pinnedURLSession.reset(completionHandler: completionHandler)
    }
    
    // MARK: Instance methods
    
    /**
     *  Creates a WebSocket task for the provided URL
     *  https://developer.apple.com/documentation/foundation/urlsession/3181171-websockettask
     */
    @available(iOS 13.0, *)
    public override func webSocketTask(with: URL) -> URLSessionWebSocketTask {
        self.pinnedURLSession.webSocketTask(with: with)
    }
    
    /**
     *  Creates a WebSocket task for the provided URL request
     *  https://developer.apple.com/documentation/foundation/urlsession/3235750-websockettask
     */
    @available(iOS 13.0, *)
    public override func webSocketTask(with: URLRequest) -> URLSessionWebSocketTask {
        self.pinnedURLSession.webSocketTask(with: with)
    }
    
    /**
     *  Creates a WebSocket task given a URL and an array of protocols
     *  https://developer.apple.com/documentation/foundation/urlsession/3181172-websockettask
     */
    @available(iOS 13.0, *)
    public override func webSocketTask(with: URL, protocols: [String]) -> URLSessionWebSocketTask {
        self.pinnedURLSession.webSocketTask(with: with, protocols: protocols)
    }
    
    /**
     * Runs a task created on the pinned session and returns its result, for the async convenience methods below.
     * A delegate supplied by the caller is attached to the task alone, as URLSession does for its own async methods:
     * the request still uses this session's configuration and connections, callbacks the delegate does not
     * implement are delivered to the session delegate, and the task releases the delegate when it completes.
     * Authentication challenges are still subject to Approov pinning, see PinningTaskDelegate.
     */
    @available(iOS 15.0, *)
    private func performWithApproov<Value: Sendable>(
        delegate: URLSessionTaskDelegate?,
        makeTask: (URLSession, @escaping @Sendable (Value?, URLResponse?, Error?) -> Void) -> URLSessionTask
    ) async throws -> (Value, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let completionGate = ApproovTaskCompletionGate<Value> { value, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let value = value, let response = response {
                    continuation.resume(returning: (value, response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            let task = makeTask(self.pinnedURLSession) { value, response, error in
                completionGate.complete(value: value, response: response, error: error)
            }
            // the task delegate must be set before the task is first resumed
            if let delegate = delegate {
                task.delegate = PinningTaskDelegate(wrapping: delegate)
            }
            observe(task, completionHandler: completionGate)
            task.resume()
        }
    }

    /**
     * Implementation of "data(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance. If a delegate is provided then it receives the callbacks for this task that it implements,
     * and the delegate supplied during the construction of the URLSession receives the rest.
     */
    @available(iOS 15.0, *)
    public func dataWithApproov(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        return try await performWithApproov(delegate: delegate) { session, completionHandler in
            session.dataTask(with: request, completionHandler: completionHandler)
        }
    }

    /**
     * Implementation of "data(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance. If a delegate is provided then it receives the callbacks for this task that it implements,
     * and the delegate supplied during the construction of the URLSession receives the rest.
     */
    @available(iOS 15.0, *)
    public func dataWithApproov(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        return try await performWithApproov(delegate: delegate) { session, completionHandler in
            session.dataTask(with: url, completionHandler: completionHandler)
        }
    }

    /**
     * Implementation of "upload(for request: URLRequest, fromFile fileURL: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance. If a delegate is provided then it receives the callbacks for this task that it implements,
     * and the delegate supplied during the construction of the URLSession receives the rest.
     */
    @available(iOS 15.0, *)
    public func uploadWithApproov(for request: URLRequest, fromFile fileURL: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        return try await performWithApproov(delegate: delegate) { session, completionHandler in
            session.uploadTask(with: request, fromFile: fileURL, completionHandler: completionHandler)
        }
    }

    /**
     * Implementation of "upload(for request: URLRequest, from bodyData: Data, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance. If a delegate is provided then it receives the callbacks for this task that it implements,
     * and the delegate supplied during the construction of the URLSession receives the rest.
     */
    @available(iOS 15.0, *)
    public func uploadWithApproov(for request: URLRequest, from bodyData: Data, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        return try await performWithApproov(delegate: delegate) { session, completionHandler in
            session.uploadTask(with: request, from: bodyData, completionHandler: completionHandler)
        }
    }

    /**
     * Implementation of "download(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance. If a delegate is provided then it receives the callbacks for this task that it implements,
     * and the delegate supplied during the construction of the URLSession receives the rest.
     */
    @available(iOS 15.0, *)
    public func downloadWithApproov(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse) {
        return try await performWithApproov(delegate: delegate) { session, completionHandler in
            session.downloadTask(with: request, completionHandler: ApproovURLSession.keepingDownloadedFile(completionHandler))
        }
    }

    /**
     * Implementation of "download(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance. If a delegate is provided then it receives the callbacks for this task that it implements,
     * and the delegate supplied during the construction of the URLSession receives the rest.
     */
    @available(iOS 15.0, *)
    public func downloadWithApproov(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse) {
        return try await performWithApproov(delegate: delegate) { session, completionHandler in
            session.downloadTask(with: url, completionHandler: ApproovURLSession.keepingDownloadedFile(completionHandler))
        }
    }

    /**
     * URLSession deletes the file it passes to a download task's completion handler as soon as the handler returns, but
     * the async download methods return to their caller after that. Like URLSession.download(for:), they must hand the file
     * to the caller, so the file is first moved to a new location in the temporary directory. The caller owns the file and
     * must move or delete it.
     */
    private static func keepingDownloadedFile(
        _ completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void
    ) -> @Sendable (URL?, URLResponse?, Error?) -> Void {
        return { location, response, error in
            guard let location = location, error == nil else {
                completionHandler(location, response, error)
                return
            }
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("ApproovDownload_\(UUID().uuidString).tmp")
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                completionHandler(destination, response, nil)
            } catch {
                completionHandler(nil, response, error)
            }
        }
    }
}
