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
import Approov
import CommonCrypto
import os.log
import Combine

public class ApproovURLSession: NSObject {
    
    // URLSession
    var pinnedURLSession:URLSession
    // URLSessionConfiguration
    var urlSessionConfiguration:URLSessionConfiguration
    // Pinned URLSessionDelegate; this could be/is of type PinningURLSessionDelegate but this way avoids explicit cast
    var pinnedURLSessionDelegate:URLSessionDelegate?
    // The delegate queue
    var delegateQueue:OperationQueue?
    // The observer object
    var taskObserver:ApproovSessionTaskObserver?
    /* Use log subsystem for info/error */
    let log = OSLog(subsystem: "approov-service-urlsession", category: "network")

    /*
     *  URLSession initializer
     *  https://developer.apple.com/documentation/foundation/urlsession/1411597-init
     */
    public init(configuration: URLSessionConfiguration, delegate: URLSessionDelegate?, delegateQueue: OperationQueue?) {
        self.urlSessionConfiguration = configuration
        self.pinnedURLSessionDelegate = PinningURLSessionDelegate(with: delegate)
        self.delegateQueue = delegateQueue
        // Set as URLSession delegate our implementation
        self.pinnedURLSession = URLSession(configuration: configuration, delegate: pinnedURLSessionDelegate, delegateQueue: delegateQueue)
        taskObserver = ApproovSessionTaskObserver(session: pinnedURLSession, delegate: pinnedURLSessionDelegate!)
        super.init()
    }
    
    /*
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
    public func dataTask(with url: URL) -> URLSessionDataTask {
        return dataTask(with: URLRequest(url: url))
    }
    
    /*  Creates a task that retrieves the contents of a URL based on the specified URL request object
     *  https://developer.apple.com/documentation/foundation/urlsession/1410592-datatask
     */
    public func dataTask(with request: URLRequest) -> URLSessionDataTask {
        let userRequest = addUserHeadersToRequest(request: request)
        // Create the return object
        let task = self.pinnedURLSession.dataTask(with: userRequest)
        // Add observer
        task.addObserver(taskObserver!, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: nil)
        return task
    }
    
    /*  Creates a task that retrieves the contents of the specified URL, then calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1410330-datatask
     */
    public func dataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return dataTask(with: URLRequest(url: url), completionHandler: completionHandler)
    }
    
    /*  Creates a task that retrieves the contents of a URL based on the specified URL request object, and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1407613-datatask
     */
    public func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        let userRequest = addUserHeadersToRequest(request: request)
        let task = self.pinnedURLSession.dataTask(with: userRequest, completionHandler: completionHandler)
        task.addObserver(taskObserver!, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: nil)
        taskObserver?.addCompletionHandlerTaskToDictionary(taskId: task.taskIdentifier, handler: completionHandler)
        return task
    }
    
    // MARK: URLSession downloadTask
    /*  Creates a download task that retrieves the contents of the specified URL and saves the results to a file
     *  https://developer.apple.com/documentation/foundation/urlsession/1411482-downloadtask
     */
    public func downloadTask(with url: URL) -> URLSessionDownloadTask {
        return downloadTask(with: URLRequest(url: url))
    }
    
    /*  Creates a download task that retrieves the contents of a URL based on the specified URL request object
     *  and saves the results to a file
     *  https://developer.apple.com/documentation/foundation/urlsession/1411481-downloadtask
     */
    public func downloadTask(with request: URLRequest) -> URLSessionDownloadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        // The return object
        let task = self.pinnedURLSession.downloadTask(with: userRequest)
        // Add observer
        task.addObserver(taskObserver!, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: nil)
        return task
    }
    
    /*  Creates a download task that retrieves the contents of the specified URL, saves the results to a file,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411608-downloadtask
     */
    public func downloadTask(with: URL, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return downloadTask(with: URLRequest(url: with), completionHandler: completionHandler)
    }
    
    /*  Creates a download task that retrieves the contents of a URL based on the specified URL request object,
     *  saves the results to a file, and calls a handler upon completion
     *
     */
    public func downloadTask(with request: URLRequest, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        // The return object
        let task = self.pinnedURLSession.downloadTask(with: userRequest, completionHandler: completionHandler)
        // Add observer
        task.addObserver(taskObserver!, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: nil)
        taskObserver?.addCompletionHandlerTaskToDictionary(taskId: task.taskIdentifier, handler: completionHandler)
        return task
    }
    
    /*  Creates a download task to resume a previously canceled or failed download
     *  https://developer.apple.com/documentation/foundation/urlsession/1409226-downloadtask
     *  NOTE: this call is not protected by Approov
     */
    public func downloadTask(withResumeData: Data) -> URLSessionDownloadTask {
        return self.pinnedURLSession.downloadTask(withResumeData: withResumeData)
    }
    
    /*  Creates a download task to resume a previously canceled or failed download and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411598-downloadtask
     *  NOTE: this call is not protected by Approov
     */
    public func downloadTask(withResumeData: Data, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return self.pinnedURLSession.downloadTask(withResumeData: withResumeData, completionHandler: completionHandler)
    }
    
    // MARK: Upload Tasks
    /*  Creates a task that performs an HTTP request for the specified URL request object and uploads the provided data
     *  https://developer.apple.com/documentation/foundation/urlsession/1409763-uploadtask
     */
    public func uploadTask(with request: URLRequest, from: Data) -> URLSessionUploadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        // The return object
        let task = pinnedURLSession.uploadTask(with: userRequest, from: from)
        // Add observer
        task.addObserver(taskObserver!, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: nil)
        return task
    }
    
    /*  Creates a task that performs an HTTP request for the specified URL request object, uploads the provided data,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411518-uploadtask
     */
    public func uploadTask(with request: URLRequest, from: Data?, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        // The return object
        let task = self.pinnedURLSession.uploadTask(with: userRequest, from: from, completionHandler:  completionHandler)
        // Add observer
        task.addObserver(taskObserver!, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: nil)
        taskObserver?.addCompletionHandlerTaskToDictionary(taskId: task.taskIdentifier, handler: completionHandler)
        return task
    }
    
    /*  Creates a task that performs an HTTP request for uploading the specified file
     *  https://developer.apple.com/documentation/foundation/urlsession/1411550-uploadtask
     */
    public func uploadTask(with request: URLRequest, fromFile: URL) -> URLSessionUploadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        // The return object
        let task = self.pinnedURLSession.uploadTask(with: userRequest, fromFile: fromFile)
        // Add observer
        task.addObserver(taskObserver!, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: nil)
        return task
    }
    
    /*  Creates a task that performs an HTTP request for the specified URL request object, uploads the provided data,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411518-uploadtask
     */
    public func uploadTask(with request: URLRequest, fromFile: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        // The return object
        let task = self.pinnedURLSession.uploadTask(with: userRequest, fromFile: fromFile, completionHandler: completionHandler)
        // Add observer
        task.addObserver(taskObserver!, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: nil)
        taskObserver?.addCompletionHandlerTaskToDictionary(taskId: task.taskIdentifier, handler: completionHandler)
        return task
    }
    
    /*  Creates a task that performs an HTTP request for uploading data based on the specified URL request
     *  https://developer.apple.com/documentation/foundation/urlsession/1410934-uploadtask
     */
    public func uploadTask(withStreamedRequest: URLRequest) -> URLSessionUploadTask {
        let userRequest = addUserHeadersToRequest(request: withStreamedRequest)
        // The return object
        let task = self.pinnedURLSession.uploadTask(withStreamedRequest: userRequest)
        // Add observer
        task.addObserver(taskObserver!, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: nil)
        return task
    }
    
    // MARK: Combine Publisher Tasks
    /*  Returns a publisher that wraps a URL session data task for a given URL request.
     *  https://developer.apple.com/documentation/foundation/urlsession
     */
    @available(iOS 13.0, *)
    public func dataTaskPublisher(for request: URLRequest) -> URLSession.DataTaskPublisher {
        let userRequest = addUserHeadersToRequest(request: request)
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                return self.pinnedURLSession.dataTaskPublisher(for: approovUpdateResponse.request)
            case .ShouldRetry:
                 // We create a task and cancel it immediately
                let sessionTaskPublisher = self.pinnedURLSession.dataTaskPublisher(for: approovUpdateResponse.request)
                // We should retry doing a fetch after a user driven event
                // Tell the delagate we are marking the session as invalid
                self.pinnedURLSessionDelegate?.urlSession?(self.pinnedURLSession, didBecomeInvalidWithError: approovUpdateResponse.error)
                return sessionTaskPublisher
            case .ShouldIgnore:
                // We should ignore the ApproovService request response: use the session modified headers
                return self.pinnedURLSession.dataTaskPublisher(for: userRequest)
            default:
                // We create a task and cancel it immediately
                let sessionTaskPublisher = self.pinnedURLSession.dataTaskPublisher(for: approovUpdateResponse.request)
                sessionTaskPublisher.session.invalidateAndCancel()
                // Tell the delagate we are marking the session as invalid
                self.pinnedURLSessionDelegate?.urlSession?(self.pinnedURLSession, didBecomeInvalidWithError: approovUpdateResponse.error)
                return sessionTaskPublisher
        }// switch
    }
    
    
    // MARK: Managing the Session
    /*  Invalidates the session, allowing any outstanding tasks to finish
     *  https://developer.apple.com/documentation/foundation/urlsession/1407428-finishtasksandinvalidate
     */
    public func finishTasksAndInvalidate(){
        self.pinnedURLSession.finishTasksAndInvalidate()
    }
    
    /*  Flushes cookies and credentials to disk, clears transient caches, and ensures that future requests
     *  occur on a new TCP connection
     *  https://developer.apple.com/documentation/foundation/urlsession/1411622-flush
     */
    public func flush(completionHandler: @escaping () -> Void){
        self.pinnedURLSession.flush(completionHandler: completionHandler)
    }
    
    /*  Asynchronously calls a completion callback with all data, upload, and download tasks in a session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411578-gettaskswithcompletionhandler
     */
    public func getTasksWithCompletionHandler(_ completionHandler: @escaping ([URLSessionDataTask], [URLSessionUploadTask], [URLSessionDownloadTask]) -> Void) {
        self.pinnedURLSession.getTasksWithCompletionHandler(completionHandler)
    }
    
    /*  Asynchronously calls a completion callback with all tasks in a session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411618-getalltasks
     */
    public func getAllTasks(completionHandler: @escaping ([URLSessionTask]) -> Void) {
        self.pinnedURLSession.getAllTasks(completionHandler: completionHandler)
    }
    
    /*  Cancels all outstanding tasks and then invalidates the session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411538-invalidateandcancel
     */
    public func invalidateAndCancel() {
        self.pinnedURLSession.invalidateAndCancel()
    }
    
    /*  Empties all cookies, caches and credential stores, removes disk files, flushes in-progress downloads to disk,
     *  and ensures that future requests occur on a new socket
     *  https://developer.apple.com/documentation/foundation/urlsession/1411479-reset
     */
    public func reset(completionHandler: @escaping () -> Void) {
        self.pinnedURLSession.reset(completionHandler: completionHandler)
    }
    
    // MARK: Instance methods
    
    /*  Creates a WebSocket task for the provided URL
     *  https://developer.apple.com/documentation/foundation/urlsession/3181171-websockettask
     */
    @available(iOS 13.0, *)
    public func webSocketTask(with: URL) -> URLSessionWebSocketTask {
        self.pinnedURLSession.webSocketTask(with: with)
    }
    
    /*  Creates a WebSocket task for the provided URL request
     *  https://developer.apple.com/documentation/foundation/urlsession/3235750-websockettask
     */
    @available(iOS 13.0, *)
    public func webSocketTask(with: URLRequest) -> URLSessionWebSocketTask {
        self.pinnedURLSession.webSocketTask(with: with)
    }
    
    /*  Creates a WebSocket task given a URL and an array of protocols
     *  https://developer.apple.com/documentation/foundation/urlsession/3181172-websockettask
     */
    @available(iOS 13.0, *)
    public func webSocketTask(with: URL, protocols: [String]) -> URLSessionWebSocketTask {
        self.pinnedURLSession.webSocketTask(with: with, protocols: protocols)
    }
    
    /*  Add any user defined headers to a URLRequest object
     *  @param request URLRequest
     *  @return URLRequest the input request including any user defined configuration headers
     */
    func addUserHeadersToRequest(request: URLRequest) -> URLRequest{
        var returnRequest = request
        if let allHeaders = urlSessionConfiguration.httpAdditionalHeaders {
            for key in allHeaders.keys {
                returnRequest.addValue(allHeaders[key] as! String, forHTTPHeaderField: key as! String)
            }
        }
        return returnRequest
    }

}// class


/*
 *  Delegate class implementing all available URLSessionDelegate types
 */
class PinningURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate {
    
    var optionalURLDelegate:URLSessionDelegate?
    
    struct Constants {
        static let rsa2048SPKIHeader:[UInt8] = [
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05,
            0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
        ]
        static let rsa4096SPKIHeader:[UInt8]  = [
            0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05,
            0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
        ]
        static let ecdsaSecp256r1SPKIHeader:[UInt8]  = [
            0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48,
            0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
        ]
        static let ecdsaSecp384r1SPKIHeader:[UInt8]  = [
            0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b, 0x81, 0x04,
            0x00, 0x22, 0x03, 0x62, 0x00
        ]
    }
    
    // PKI headers for both RSA and ECC
    private static var pkiHeaders = [String:[Int:Data]]()
    /*
     *  Initialize PKI dictionary
     */
    private static func initializePKI() {
        var rsaDict = [Int:Data]()
        rsaDict[2048] = Data(Constants.rsa2048SPKIHeader)
        rsaDict[4096] = Data(Constants.rsa4096SPKIHeader)
        var eccDict = [Int:Data]()
        eccDict[256] = Data(Constants.ecdsaSecp256r1SPKIHeader)
        eccDict[384] = Data(Constants.ecdsaSecp384r1SPKIHeader)
        pkiHeaders[kSecAttrKeyTypeRSA as String] = rsaDict
        pkiHeaders[kSecAttrKeyTypeECSECPrimeRandom as String] = eccDict
    }
    init(with delegate: URLSessionDelegate?){
        PinningURLSessionDelegate.initializePKI()
        self.optionalURLDelegate = delegate
    }
    
    // MARK: URLSessionDelegate
    
    /*  URLSessionDelegate
     *  A protocol that defines methods that URL session instances call on their delegates to handle session-level events,
     *  like session life cycle changes
     *  https://developer.apple.com/documentation/foundation/urlsessiondelegate
     */
    
    /*  Tells the URL session that the session has been invalidated
     *  https://developer.apple.com/documentation/foundation/urlsessiondelegate/1407776-urlsession
     */
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        optionalURLDelegate?.urlSession?(session, didBecomeInvalidWithError: error)
    }
    
    /*  Tells the delegate that all messages enqueued for a session have been delivered
     *  https://developer.apple.com/documentation/foundation/urlsessiondelegate/1617185-urlsessiondidfinishevents
     */
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        optionalURLDelegate?.urlSessionDidFinishEvents?(forBackgroundURLSession: session)
    }
    
    /*  Requests credentials from the delegate in response to a session-level authentication request from the remote server
     *  https://developer.apple.com/documentation/foundation/urlsessiondelegate/1409308-urlsession
     */
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // We are only interested in server trust requests
        if !challenge.protectionSpace.authenticationMethod.isEqual(NSURLAuthenticationMethodServerTrust) {
            optionalURLDelegate?.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
            return
        }
        do {
            if let serverTrust = try shouldAcceptAuthenticationChallenge(challenge: challenge){
                completionHandler(.useCredential,
                                  URLCredential.init(trust: serverTrust));
                optionalURLDelegate?.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
                return
            }
        } catch {
            os_log("Approov: urlSession error %@", type: .error, error.localizedDescription)
        }
        completionHandler(URLSession.AuthChallengeDisposition.cancelAuthenticationChallenge,nil)
    }
    
    // MARK: URLSessionTaskDelegate
    
    /*  URLSessionTaskDelegate
     *  A protocol that defines methods that URL session instances call on their delegates to handle task-level events
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate
     */
    
    /*  Requests credentials from the delegate in response to an authentication request from the remote server
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1411595-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            // We are only interested in server trust requests
            if !challenge.protectionSpace.authenticationMethod.isEqual(NSURLAuthenticationMethodServerTrust) {
                delegate.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
                return
            }
            do {
                if let serverTrust = try shouldAcceptAuthenticationChallenge(challenge: challenge){
                    completionHandler(.useCredential,
                                      URLCredential.init(trust: serverTrust));
                    delegate.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
                    return
                }
            } catch {
                os_log("Approov: urlSession error %@", type: .error, error.localizedDescription)
            }
            
            completionHandler(URLSession.AuthChallengeDisposition.cancelAuthenticationChallenge,nil)
        }
    }
    
    /*  Tells the delegate that the task finished transferring data
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1411610-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, didCompleteWithError: error)
        }
    }
    
    /*  Tells the delegate that the remote server requested an HTTP redirect
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1411626-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, willPerformHTTPRedirection: response, newRequest: request, completionHandler: completionHandler)
        }
    }
    
    /*  Tells the delegate when a task requires a new request body stream to send to the remote server
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1410001-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, needNewBodyStream: completionHandler)
        }
    }
    
    /*  Periodically informs the delegate of the progress of sending body content to the server
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1408299-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, didSendBodyData: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
        }
    }
    
    /*  Tells the delegate that a delayed URL session task will now begin loading
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2873415-urlsession
     */
    @available(iOS 11.0, *)
    func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest, completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task:task, willBeginDelayedRequest: request, completionHandler: completionHandler)
        }
    }
    
    /*  Tells the delegate that the session finished collecting metrics for the task
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1643148-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, didFinishCollecting: metrics)
        }
    }
    
    /*  Tells the delegate that the task is waiting until suitable connectivity is available before beginning the network load
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2908819-urlsession
     */
    @available(iOS 11.0, *)
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, taskIsWaitingForConnectivity: task)
        }
    }

    
    // MARK: URLSessionDataDelegate
    
    /*  URLSessionDataDelegate
     *  A protocol that defines methods that URL session instances call on their delegates to handle task-level events
     *  specific to data and upload tasks
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate
     */
    
    /*  Tells the delegate that the data task received the initial reply (headers) from the server
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1410027-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
    {
        if let delegate = optionalURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
        }
    }
    
    /*  Tells the delegate that the data task was changed to a download task
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1409936-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        if let delegate = optionalURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, didBecome: downloadTask)
        }
    }
    
    /*  Tells the delegate that the data task was changed to a stream task
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411648-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        if let delegate = optionalURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, didBecome: streamTask)
        }
    }
    
    /*  Tells the delegate that the data task has received some of the expected data
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411528-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let delegate = optionalURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session,dataTask: dataTask, didReceive: data)
        }
    }
    
    /*  Asks the delegate whether the data (or upload) task should store the response in the cache
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411612-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, willCacheResponse: proposedResponse, completionHandler: completionHandler)
        }
    }
    
    // MARK: URLSessionDownloadDelegate
    
    /*  A protocol that defines methods that URL session instances call on their delegates to handle
     *  task-level events specific to download tasks
     *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate
     */
    
    /*  Tells the delegate that a download task has finished downloading
     *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1411575-urlsession
     */
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let delegate = optionalURLDelegate as? URLSessionDownloadDelegate {
            delegate.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
        }
    }
    
    /*  Tells the delegate that the download task has resumed downloading
     *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1408142-urlsession
     */
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset: Int64, expectedTotalBytes: Int64) {
        if let delegate = optionalURLDelegate as? URLSessionDownloadDelegate {
            delegate.urlSession?(session, downloadTask: downloadTask, didResumeAtOffset: didResumeAtOffset, expectedTotalBytes: expectedTotalBytes)
        }
    }
    
    /*  Periodically informs the delegate about the download’s progress
     *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1409408-urlsession
     */
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let delegate = optionalURLDelegate as? URLSessionDownloadDelegate {
            delegate.urlSession?(session, downloadTask: downloadTask, didWriteData: didWriteData, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        }
    }
    
    
    
    // MARK: Utilities
    
    /*  Evaluates a URLAuthenticationChallenge deciding if to proceed further
     *  @param  challenge: URLAuthenticationChallenge
     *  @return SecTrust?: valid SecTrust if authentication should proceed, nil otherwise
     */
    func shouldAcceptAuthenticationChallenge(challenge: URLAuthenticationChallenge) throws -> SecTrust? {
        // Check we have a server trust, ignore any other challenges
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            return nil
        }
        
        // Check the validity of the server cert
        var trustType = SecTrustResultType.invalid
        if (SecTrustEvaluate(serverTrust, &trustType) != errSecSuccess) {
            throw ApproovError.pinningError(message: "Error during Certificate Trust Evaluation for host \(challenge.protectionSpace.host)")
        } else if (trustType != SecTrustResultType.proceed) && (trustType != SecTrustResultType.unspecified) {
            throw ApproovError.pinningError(message: "Error: Certificate Trust Evaluation failure for host \(challenge.protectionSpace.host)")
        }
        // Get the certificate chain count
        let certCountInChain = SecTrustGetCertificateCount(serverTrust);
        var indexCurrentCert = 0;
        while(indexCurrentCert < certCountInChain){
            // get the current certificate from the chain
            guard let serverCert = SecTrustGetCertificateAtIndex(serverTrust, indexCurrentCert) else {
                throw ApproovError.pinningError(message: "Error getting certificate at index \(indexCurrentCert) from chain for host \(challenge.protectionSpace.host)")
            }
            
            // get the subject public key info from the certificate
            guard let publicKeyInfo = publicKeyInfoOfCertificate(certificate: serverCert) else {
                // Throw to indicate we could not parse SPKI header
                throw ApproovError.pinningError(message: "Error parsing SPKI header for host \(challenge.protectionSpace.host) Unsupported certificate type, SPKI header cannot be created")
            }
            
            // compute the SHA-256 hash of the public key info and base64 encode the result
            let publicKeyHash = sha256(data: publicKeyInfo)
            let publicKeyHashBase64 = String(data:publicKeyHash.base64EncodedData(), encoding: .utf8)
            
            // check that the hash is the same as at least one of the pins
            guard let approovCertHashes = Approov.getPins("public-key-sha256") else {
                throw ApproovError.pinningError(message: "Approov SDK getPins() call failed")
            }
            // Get the receivers host
            let host = challenge.protectionSpace.host
            if let certHashList = approovCertHashes[host] {
                // Actual variable to hold certificate hashes
                var actualCertHashList = certHashList
                // We have no pins defined for this host, accept connection (unpinned)
                if actualCertHashList.count == 0 { // the host is in but no pins defined
                    // if there are no pins and no managed trust allow connection
                    if approovCertHashes["*"] == nil {
                        return serverTrust;  // We do not pin connection explicitly setting no pins for the host
                    } else {
                        // there are no pins for current host, then we try and use any managed trust roots since @"*" is available
                        actualCertHashList = approovCertHashes["*"]!
                    }
                }
                // We have on or more cert hashes matching the receivers host, compare them
                for certHash in actualCertHashList {
                    if publicKeyHashBase64 == certHash {
                        return serverTrust
                    }
                }
            } else {
                // Host is not pinned
                return serverTrust
            }
            indexCurrentCert += 1
        }
        // We return nil if no match in current set of pins from Approov SDK and certificate chain seen during TLS handshake
        return nil
    }
    /*
    * gets a certificate's subject public key info (SPKI)
    */
    func publicKeyInfoOfCertificate(certificate: SecCertificate) -> Data? {
        var publicKey:SecKey?
        if #available(iOS 12.0, *) {
            publicKey = SecCertificateCopyKey(certificate)
        } else {
            // Fallback on earlier versions
            // from TrustKit https://github.com/datatheorem/TrustKit/blob/master/TrustKit/Pinning/TSKSPKIHashCache.m lines
            // 221-234:
            // Create an X509 trust using the certificate
            let secPolicy = SecPolicyCreateBasicX509()
            var secTrust:SecTrust?
            if SecTrustCreateWithCertificates(certificate, secPolicy, &secTrust) != errSecSuccess {
                return nil
            }
            // get a public key reference for the certificate from the trust
            var secTrustResultType = SecTrustResultType.invalid
            if SecTrustEvaluate(secTrust!, &secTrustResultType) != errSecSuccess {
                return nil
            }
            publicKey = SecTrustCopyPublicKey(secTrust!)
            
        }
        if publicKey == nil {
            return nil
        }
        // get the SPKI header depending on the public key's type and size
        guard var spkiHeader = publicKeyInfoHeaderForKey(publicKey: publicKey!) else {
            return nil
        }
        // combine the public key header and the public key data to form the public key info
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey!, nil) else {
            return nil
        }
        spkiHeader.append(publicKeyData as Data)
        return spkiHeader
    }

    /*
    * gets the subject public key info (SPKI) header depending on a public key's type and size
    */
    func publicKeyInfoHeaderForKey(publicKey: SecKey) -> Data? {
        guard let publicKeyAttributes = SecKeyCopyAttributes(publicKey) else {
            return nil
        }
        if let keyType = (publicKeyAttributes as NSDictionary).value(forKey: kSecAttrKeyType as String) {
            if let keyLength = (publicKeyAttributes as NSDictionary).value(forKey: kSecAttrKeySizeInBits as String) {
                // Find the header
                if let spkiHeader:Data = PinningURLSessionDelegate.pkiHeaders[keyType as! String]?[keyLength as! Int] {
                    return spkiHeader
                }
            }
        }
        return nil
    }
    
    /*
     * SHA256 of given input bytes
     */
    func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

}// class

/*
 * Approov error conditions
 */
public enum ApproovError: Error {
    case initializationFailure(message: String)
    case configurationError(message: String)
    case pinningError(message: String)
    case networkingError(message: String)
    case permanentError(message: String)
    case rejectionError(message: String, ARC: String?, rejectionReasons: String?)
}

/*
 * Convenience function that converts Approov status code to its String representation
 */
func stringFromApproovTokenFetchStatus(status: ApproovTokenFetchStatus) -> String {
    return Approov.string(from: status)
}

/*
 * Host component only gets resolved if the string includes the protocol used
 * This is not always the case when making requests so a convenience method is needed
 */
func hostnameFromURL(url: URL) -> String {
    if url.absoluteString.starts(with: "https") {
        return url.host!
    } else {
        let fullHost = "https://" + url.absoluteString
        let newURL = URL(string: fullHost)
        if let host = newURL?.host {
            return host
        } else {
            return ""
        }
    }
}

/* The ApproovSessionTask observer */
public class ApproovSessionTaskObserver : NSObject {
    // The KVO object we are intersted in
    static let stateString = "state"
    // Handler specific to Data type
    typealias CompletionHandlerData = ((Data?,URLResponse?,Error?)->Void)?
    // Handler specific to URL type
    typealias CompletionHandlerURL = ((URL?,URLResponse?,Error?)->Void)?
    // Dictionary to hold completion handlers to their mapped UUID task id
    var completionHandlers: Dictionary<Int,Any> = Dictionary()
    /* The dispatch queue to manage serial access to the dictionary */
    private let handlersQueue = DispatchQueue(label: "ApproovSessionTaskObserver")
    /* Reference to the pinning session and pinning delegate objects */
    private var pinningSessionReference: URLSession?
    private var pinningDelegatereference: PinningURLSessionDelegate
    
    init(session: URLSession, delegate: URLSessionDelegate) {
        pinningSessionReference = session
        pinningDelegatereference = delegate as! PinningURLSessionDelegate
        super.init()
    }
    
    /*  Adds a task UUID mapped to a function to be invoked as a callback in case of error
     *  after cancelling the task
     */
    func addCompletionHandlerTaskToDictionary(taskId: Int, handler: Any) -> Void {
        handlersQueue.sync {
            completionHandlers[taskId] = handler;
        }
    }
    
    /*
     * It is necessary to use KVO and observe the task returned to the user in order to modify the original request
     * Since we do not want to block the task in order to contact the Approov servers, we have to perform the Approov
     * network connection asynchronously and depending on the result, modify the header and resume the request or
     * cancel the task after informing the caller of the error
     */
    public override func observeValue(forKeyPath keyPath: String?,
                             of object: Any?,
                         change: [NSKeyValueChangeKey : Any]?,
                             context: UnsafeMutableRawPointer?) {
        /*
            NSURLSessionTaskStateRunning = 0,
            NSURLSessionTaskStateSuspended = 1,
            NSURLSessionTaskStateCanceling = 2,
            NSURLSessionTaskStateCompleted = 3,
         */
        if keyPath == ApproovSessionTaskObserver.stateString {
            let newC = change![NSKeyValueChangeKey.newKey] as! NSNumber
            let newState = getURLSessionState(state: newC.uint32Value)
            
            // The task at hand; we simply cast to superclass from which specific Data/Download ... etc classes inherit
            let task = object as! URLSessionTask
            /*  If the new state is Cancelling or Completed we must remove ourselves as observers and return
             *  because the user is either cancelling or the connection has simply terminated
             */
            if ((newState == URLSessionTask.State.completed) || (newState == URLSessionTask.State.canceling)) {
                os_log("task id %lu is cancelling or has completed; removing observer", task.taskIdentifier)
                task.removeObserver(self, forKeyPath: ApproovSessionTaskObserver.stateString)
                // If the completionHandler is in dictionary, remove it since it will not be needed
                handlersQueue.sync {
                    if completionHandlers.keys.contains(task.taskIdentifier) {
                        completionHandlers.removeValue(forKey: task.taskIdentifier)
                    }
                }
                return
            }
            
            /*  We detect the initial switch from when the task is created in Suspended state to when the user
             *  triggers the Resume state. We immediately pause the task by suspending it again and doing the background
             *  Approov network connection before considering if the actual connection should be resumed or terminated.
             *  Note that this is meant to only happen during the initial resume call since we remove ourselves as observers
             *  at the first ever resume call
             */
            if newState == URLSessionTask.State.running {
                // Suspend immediately the task: Note this is optional since the current callback is executed before another one being invoked
                task.suspend()
                // We do not need any information about further changes; we are done since we only need the furst ever resume call
                // Remove observer
                task.removeObserver(self, forKeyPath: ApproovSessionTaskObserver.stateString)
                // If the completion handler is in dictionary, remove it since it will not be needed (no error condition)
                handlersQueue.sync {
                    if completionHandlers.keys.contains(task.taskIdentifier) {
                        completionHandlers.removeValue(forKey: task.taskIdentifier)
                    }
                }
                // Contact Approov service
                let resultData = ApproovService.updateRequestWithApproov(request: task.currentRequest!)
                if resultData.decision == .ShouldProceed {
                    // Modify original request
                    let sel = NSSelectorFromString("updateCurrentRequest:")
                    if task.responds(to: sel) {
                        task.perform(sel, with: resultData.request)
                    } else {
                        // This means that URLRequest has removed the `updateCurrentRequest` method or we are observing an object that
                        // is not an instance of URLRequest. Both are fatal errors.
                        os_log("Fatal ApproovSession error: Unable to modify NSURLRequest headers; object instance is of type %@", type: .error, type(of: task).description())
                    }
                    task.resume()
                    return
                } else if resultData.decision == .ShouldIgnore {
                    // We should ignore the request and not modify the headers in any way
                    task.resume()
                    return
                } else {
                    // Error handling
                    handlersQueue.sync {
                        // Call the delegate
                        pinningDelegatereference.urlSession(pinningSessionReference!, didBecomeInvalidWithError: resultData.error)
                        if completionHandlers.keys.contains(task.taskIdentifier) {
                            // Completion handler invocation
                            if let handler = completionHandlers[task.taskIdentifier] as! CompletionHandlerData {
                                handler(nil,nil, resultData.error)
                            } else if let handler = completionHandlers[task.taskIdentifier] as! CompletionHandlerURL {
                                handler(nil,nil, resultData.error)
                            }
                            // We have invoked the original handler with error message; remove it from dictionary
                            completionHandlers.removeValue(forKey: task.taskIdentifier)
                        }
                    }
                    task.cancel()
                }
            }
        }
    } // func
    
    
    func getURLSessionState(state: UInt32) -> URLSessionTask.State {
        /*
            NSURLSessionTaskStateRunning = 0,
            NSURLSessionTaskStateSuspended = 1,
            NSURLSessionTaskStateCanceling = 2,
            NSURLSessionTaskStateCompleted = 3,
         */
        switch state {
        case 0:
            return URLSessionTask.State.running
        case 1:
            return URLSessionTask.State.suspended
        case 2:
            return URLSessionTask.State.canceling
        default:
            return URLSessionTask.State.completed
        }
    }
    
}

