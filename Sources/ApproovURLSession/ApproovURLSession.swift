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
import Combine // Add this import to use the Fail publisher

// Provides an implementation of URLSession with Approov protection, including dynamic pinning. Methods delegate to an underlying
// URLSession after adding Approov protection. Note that the "Performing Asynchronous Transfers" methods defined from iOS 15 do not
// currently add Approov protection.
public class ApproovURLSession: URLSession {
    // configuration for this session
    var urlSessionConfiguration: URLSessionConfiguration
    
    // delegate used to apply pinning to connections
    var pinningURLSessionDelegate: PinningURLSessionDelegate
    
    // URLSession with a delegate that applies pinning
    var pinnedURLSession: URLSession
    
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
        let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
        sessionPointer.initialize(to: pinnedURLSession)
        task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
        ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
        return task
    }
    
    /**
     *  Creates a task that retrieves the contents of the specified URL, then calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1410330-datatask
     */
    public override func dataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return dataTask(with: URLRequest(url: url), completionHandler: completionHandler)
    }
    
    /**
     *  Creates a task that retrieves the contents of a URL based on the specified URL request object, and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1407613-datatask
     */
    public override func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        let task = self.pinnedURLSession.dataTask(with: request, completionHandler: completionHandler)
        let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
        sessionPointer.initialize(to: pinnedURLSession)
        task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
        ApproovURLSession.taskObserver.addCompletionHandler(taskId: task.taskIdentifier, handler: completionHandler)
        ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
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
        let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
        sessionPointer.initialize(to: pinnedURLSession)
        task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
        ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
        return task
    }
    
    /**
     *  Creates a download task that retrieves the contents of the specified URL, saves the results to a file,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411608-downloadtask
     */
    public override func downloadTask(with: URL, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return downloadTask(with: URLRequest(url: with), completionHandler: completionHandler)
    }
    
    /**
     *  Creates a download task that retrieves the contents of a URL based on the specified URL request object,
     *  saves the results to a file, and calls a handler upon completion.
     *  https://developer.apple.com/documentation/foundation/nsurlsession/1411511-downloadtaskwithrequest?language=objc
     */
    public override func downloadTask(with request: URLRequest, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        let task = self.pinnedURLSession.downloadTask(with: request, completionHandler: completionHandler)
        let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
        sessionPointer.initialize(to: pinnedURLSession)
        task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
        ApproovURLSession.taskObserver.addCompletionHandler(taskId: task.taskIdentifier, handler: completionHandler)
        ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
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
    public override func downloadTask(withResumeData: Data, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return self.pinnedURLSession.downloadTask(withResumeData: withResumeData, completionHandler: completionHandler)
    }
    
    // MARK: Upload Tasks
    /**
     *  Creates a task that performs an HTTP request for the specified URL request object and uploads the provided data
     *  https://developer.apple.com/documentation/foundation/urlsession/1409763-uploadtask
     */
    public override func uploadTask(with request: URLRequest, from: Data) -> URLSessionUploadTask {
        let task = pinnedURLSession.uploadTask(with: request, from: from)
        let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
        sessionPointer.initialize(to: pinnedURLSession)
        task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
        ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
        return task
    }
    
    /**
     *  Creates a task that performs an HTTP request for the specified URL request object, uploads the provided data,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411518-uploadtask
     */
    public override func uploadTask(with request: URLRequest, from: Data?, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let task = self.pinnedURLSession.uploadTask(with: request, from: from, completionHandler: completionHandler)
        let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
        sessionPointer.initialize(to: pinnedURLSession)
        task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
        ApproovURLSession.taskObserver.addCompletionHandler(taskId: task.taskIdentifier, handler: completionHandler)
        ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
        return task
    }
    
    /**
     *  Creates a task that performs an HTTP request for uploading the specified file
     *  https://developer.apple.com/documentation/foundation/urlsession/1411550-uploadtask
     */
    public override func uploadTask(with request: URLRequest, fromFile: URL) -> URLSessionUploadTask {
        let task = self.pinnedURLSession.uploadTask(with: request, fromFile: fromFile)
        let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
        sessionPointer.initialize(to: pinnedURLSession)
        task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
        ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
        return task
    }
    
    /**
     *  Creates a task that performs an HTTP request for the specified URL request object, uploads the provided data,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411518-uploadtask
     */
    public override func uploadTask(with request: URLRequest, fromFile: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let task = self.pinnedURLSession.uploadTask(with: request, fromFile: fromFile, completionHandler: completionHandler)
        let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
        sessionPointer.initialize(to: pinnedURLSession)
        task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
        ApproovURLSession.taskObserver.addCompletionHandler(taskId: task.taskIdentifier, handler: completionHandler)
        ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
        return task
    }
    
    /**
     *  Creates a task that performs an HTTP request for uploading data based on the specified URL request
     *  https://developer.apple.com/documentation/foundation/urlsession/1410934-uploadtask
     */
    public override func uploadTask(withStreamedRequest: URLRequest) -> URLSessionUploadTask {
        let task = self.pinnedURLSession.uploadTask(withStreamedRequest: withStreamedRequest)
        let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
        sessionPointer.initialize(to: pinnedURLSession)
        task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
        ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
        return task
    }
    
    // MARK: Combine Publisher Tasks
    /**
     *  Returns a publisher that wraps a URL session data task for a given URL request.
     *  https://developer.apple.com/documentation/foundation/urlsession
     */
    @available(iOS 13.0, *)
    public func dataTaskPublisherWithApproov(for request: URLRequest) -> URLSession.DataTaskPublisher {
        do {
            // Perform the Approov update
            let approovUpdateResponse = try ApproovService.updateRequestWithApproov(request: request, sessionConfig: urlSessionConfiguration)
            switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                return self.pinnedURLSession.dataTaskPublisher(for: approovUpdateResponse.request)
            case .ShouldIgnore:
                // Ignore the ApproovService request response and just perform the original request
                return self.pinnedURLSession.dataTaskPublisher(for: request)
            default:
                // Create a task and cancel it immediately, marking the session as invalid
                let sessionTaskPublisher = self.pinnedURLSession.dataTaskPublisher(for: approovUpdateResponse.request)
                sessionTaskPublisher.session.invalidateAndCancel()
                self.pinningURLSessionDelegate.urlSession(self.pinnedURLSession, didBecomeInvalidWithError: approovUpdateResponse.error)
                return sessionTaskPublisher
            }
        } catch {
            // Handle the error by creating a failed publisher
            fatalError("Error updating request with Approov: \(error)")
        }
    }
    
    /**
     *  Returns a publisher that wraps a URL session data task for a given URL request. Previous naming of the method.
     *  https://developer.apple.com/documentation/foundation/urlsession
     */
    @available(iOS 13.0, *)
    public func dataTaskPublisherApproov(for request: URLRequest) -> URLSession.DataTaskPublisher {
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
    public override func flush(completionHandler: @escaping () -> Void){
        self.pinnedURLSession.flush(completionHandler: completionHandler)
    }
    
    /**
     *  Asynchronously calls a completion callback with all data, upload, and download tasks in a session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411578-gettaskswithcompletionhandler
     */
    public override func getTasksWithCompletionHandler(_ completionHandler: @escaping ([URLSessionDataTask], [URLSessionUploadTask], [URLSessionDownloadTask]) -> Void) {
        self.pinnedURLSession.getTasksWithCompletionHandler(completionHandler)
    }
    
    /**
     *  Asynchronously calls a completion callback with all tasks in a session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411618-getalltasks
     */
    public override func getAllTasks(completionHandler: @escaping ([URLSessionTask]) -> Void) {
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
    public override func reset(completionHandler: @escaping () -> Void) {
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
     * Implementation of "data(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance.  Note that if a delegate is provided then this will override any delegate supplied during the
     * construction of the URLSession.
     */
    @available(iOS 15.0, *)
    public func dataWithApproov(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let completionHandler = { @Sendable (data: Data?, response: URLResponse?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data!, response!))
                }
            }
            var urlSession = self.pinnedURLSession
            if delegate != nil {
                let sessionDelegate = PinningURLSessionDelegate(with: delegate)
                urlSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: delegateQueue)
            }
            let task = urlSession.dataTask(with: request, completionHandler: completionHandler)
            let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
            sessionPointer.initialize(to: urlSession)
            task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
            ApproovURLSession.taskObserver.addCompletionHandler(taskId: task.taskIdentifier, handler: completionHandler)
            ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
            task.resume()
        }
    }
    
    /**
     * Implementation of "data(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance.  Note that if a delegate is provided then this will override any delegate supplied during the
     * construction of the URLSession.
     */
    @available(iOS 15.0, *)
    public func dataWithApproov(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let completionHandler = { @Sendable (data: Data?, response: URLResponse?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data!, response!))
                }
            }
            var urlSession = self.pinnedURLSession
            if delegate != nil {
                let sessionDelegate = PinningURLSessionDelegate(with: delegate)
                urlSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: delegateQueue)
            }
            let task = urlSession.dataTask(with: url, completionHandler: completionHandler)
            let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
            sessionPointer.initialize(to: urlSession)
            task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
            ApproovURLSession.taskObserver.addCompletionHandler(taskId: task.taskIdentifier, handler: completionHandler)
            ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
            task.resume()
        }
    }
    
    /**
     * Implementation of "upload(for request: URLRequest, fromFile fileURL: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance.  Note that if a delegate is provided then this will override any delegate supplied during the
     * construction of the URLSession.
     */
    @available(iOS 15.0, *)
    public func uploadWithApproov(for request: URLRequest, fromFile fileURL: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let completionHandler = { @Sendable (data: Data?, response: URLResponse?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data!, response!))
                }
            }
            var urlSession = self.pinnedURLSession
            if delegate != nil {
                let sessionDelegate = PinningURLSessionDelegate(with: delegate)
                urlSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: delegateQueue)
            }
            let task = urlSession.uploadTask(with: request, fromFile: fileURL, completionHandler: completionHandler)
            let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
            sessionPointer.initialize(to: urlSession)
            task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
            ApproovURLSession.taskObserver.addCompletionHandler(taskId: task.taskIdentifier, handler: completionHandler)
            ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
            task.resume()
        }
    }
    
    /**
     * Implementation of "upload(for request: URLRequest, from bodyData: Data, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance.  Note that if a delegate is provided then this will override any delegate supplied during the
     * construction of the URLSession.
     */
    @available(iOS 15.0, *)
    public func uploadWithApproov(for request: URLRequest, from bodyData: Data, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let completionHandler = { @Sendable (data: Data?, response: URLResponse?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data!, response!))
                }
            }
            var urlSession = self.pinnedURLSession
            if delegate != nil {
                let sessionDelegate = PinningURLSessionDelegate(with: delegate)
                urlSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: delegateQueue)
            }
            let task = urlSession.uploadTask(with: request, from: bodyData, completionHandler: completionHandler)
            let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
            sessionPointer.initialize(to: urlSession)
            task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
            ApproovURLSession.taskObserver.addCompletionHandler(taskId: task.taskIdentifier, handler: completionHandler)
            ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
            task.resume()
        }
    }
    
    /**
     * Implementation of "download(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance.  Note that if a delegate is provided then this will override any delegate supplied during the
     * construction of the URLSession.
     */
    @available(iOS 15.0, *)
    public func downloadWithApproov(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let completionHandler = { @Sendable (url: URL?, response: URLResponse?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (url!, response!))
                }
            }
            var urlSession = self.pinnedURLSession
            if delegate != nil {
                let sessionDelegate = PinningURLSessionDelegate(with: delegate)
                urlSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: delegateQueue)
            }
            let task = urlSession.downloadTask(with: request, completionHandler: completionHandler)
            let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
            sessionPointer.initialize(to: urlSession)
            task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
            ApproovURLSession.taskObserver.addCompletionHandler(taskId: task.taskIdentifier, handler: completionHandler)
            ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
            task.resume()
        }
    }
    
    /**
     * Implementation of "download(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse)" that is defined
     * in an extension of URLSession and therefore cannot be overridden. The URLSession version cannot be used directly because it is not possible to
     * fully initialize the base URLSession class instance. Note that if a delegate is provided then this will override any delegate supplied during the
     * construction of the URLSession.
     */
    @available(iOS 15.0, *)
    public func downloadWithApproov(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let completionHandler = { @Sendable (url: URL?, response: URLResponse?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (url!, response!))
                }
            }
            var urlSession = self.pinnedURLSession
            if delegate != nil {
                let sessionDelegate = PinningURLSessionDelegate(with: delegate)
                urlSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: delegateQueue)
            }
            let task = urlSession.downloadTask(with: url, completionHandler: completionHandler)
            let sessionPointer = UnsafeMutablePointer<URLSession>.allocate(capacity: 1)
            sessionPointer.initialize(to: urlSession)
            task.addObserver(ApproovURLSession.taskObserver, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: sessionPointer)
            ApproovURLSession.taskObserver.addCompletionHandler(taskId: task.taskIdentifier, handler: completionHandler)
            ApproovURLSession.taskObserver.addSessionConfig(taskId: task.taskIdentifier, sessionConfig: urlSessionConfiguration)
            task.resume()
        }
    }
}
