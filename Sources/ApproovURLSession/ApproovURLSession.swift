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

fileprivate enum ApproovFetchDecision {
    case ShouldProceed
    case ShouldRetry
    case ShouldFail
}
fileprivate struct ApproovUpdateResponse {
    var request:URLRequest
    var decision:ApproovFetchDecision
    var sdkMessage:String
    var error:Error?
}

public class ApproovURLSession: NSObject {
    
    // URLSession
    var urlSession:URLSession
    // URLSessionConfiguration
    var urlSessionConfiguration:URLSessionConfiguration
    // URLSessionDelegate
    var urlSessionDelegate:URLSessionDelegate?
    // The delegate queue
    var delegateQueue:OperationQueue?
    
    /*
     *  URLSession initializer
     *  https://developer.apple.com/documentation/foundation/urlsession/1411597-init
     */
    public init(configuration: URLSessionConfiguration, delegate: URLSessionDelegate?, delegateQueue: OperationQueue?) {
        self.urlSessionConfiguration = configuration
        self.urlSessionDelegate = ApproovURLSessionDataDelegate(with: delegate)
        self.delegateQueue = delegateQueue
        // Set as URLSession delegate our implementation
        self.urlSession = URLSession(configuration: configuration, delegate: urlSessionDelegate, delegateQueue: delegateQueue)
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
    func dataTask(with url: URL) -> URLSessionDataTask {
        return dataTask(with: URLRequest(url: url))
    }
    
    /*  Creates a task that retrieves the contents of a URL based on the specified URL request object
     *  https://developer.apple.com/documentation/foundation/urlsession/1410592-datatask
     */
    func dataTask(with request: URLRequest) -> URLSessionDataTask {
        let userRequest = addUserHeadersToRequest(request: request)
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        var sessionDataTask:URLSessionDataTask?
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                sessionDataTask = self.urlSession.dataTask(with: approovUpdateResponse.request)
            case .ShouldRetry:
                 // We create a task and cancel it immediately
                 sessionDataTask = self.urlSession.dataTask(with: approovUpdateResponse.request)
                 sessionDataTask!.cancel()
                // We should retry doing a fetch after a user driven event
                // Tell the delagate we are marking the session as invalid
                 self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
            default:
                // We create a task and cancel it immediately
                 sessionDataTask = self.urlSession.dataTask(with: approovUpdateResponse.request)
                 sessionDataTask!.cancel()
                // Tell the delagate we are marking the session as invalid
                 self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
        }// switch
        return sessionDataTask!
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
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        // The returned task
        var task:URLSessionDataTask?
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                task = self.urlSession.dataTask(with: approovUpdateResponse.request) { (data, response, error) -> Void in
                    // Invoke completition handler
                    completionHandler(data,response,error)
                }
            case .ShouldRetry:
                // We should retry doing a fetch after a user driven event
                completionHandler(nil,nil,approovUpdateResponse.error)
                // Initialize a URLSessionDataTask object
                task = self.urlSession.dataTask(with: approovUpdateResponse.request) { (data, response, error) -> Void in
                }
                // We cancel the connection and return the task object at end of function
                task?.cancel()
            default:
                completionHandler(nil,nil,approovUpdateResponse.error)
                // Initialize a URLSessionDataTask object
                task = self.urlSession.dataTask(with: approovUpdateResponse.request) { (data, response, error) -> Void in
                }
                // We cancel the connection and return the task object at end of function
                task?.cancel()
        }// switch
    return task!
    }// func
    
    // MARK: URLSession downloadTask
    /*  Creates a download task that retrieves the contents of the specified URL and saves the results to a file
     *  https://developer.apple.com/documentation/foundation/urlsession/1411482-downloadtask
     */
    func downloadTask(with url: URL) -> URLSessionDownloadTask {
        return downloadTask(with: URLRequest(url: url))
    }
    
    /*  Creates a download task that retrieves the contents of a URL based on the specified URL request object
     *  and saves the results to a file
     *  https://developer.apple.com/documentation/foundation/urlsession/1411481-downloadtask
     */
    func downloadTask(with request: URLRequest) -> URLSessionDownloadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        var sessionDownloadTask:URLSessionDownloadTask?
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                sessionDownloadTask = self.urlSession.downloadTask(with: approovUpdateResponse.request)
            case .ShouldRetry:
                 // We create a task and cancel it immediately
                 sessionDownloadTask = self.urlSession.downloadTask(with: approovUpdateResponse.request)
                 sessionDownloadTask!.cancel()
                // We should retry doing a fetch after a user driven event
                // Tell the delagate we are marking the session as invalid
                self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
            default:
                // We create a task and cancel it immediately
                 sessionDownloadTask = self.urlSession.downloadTask(with: approovUpdateResponse.request)
                 sessionDownloadTask!.cancel()
                // Tell the delagate we are marking the session as invalid
                self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
        }// switch
        return sessionDownloadTask!
    }
    
    /*  Creates a download task that retrieves the contents of the specified URL, saves the results to a file,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411608-downloadtask
     */
    func downloadTask(with: URL, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return downloadTask(with: URLRequest(url: with), completionHandler: completionHandler)
    }
    
    /*  Creates a download task that retrieves the contents of a URL based on the specified URL request object,
     *  saves the results to a file, and calls a handler upon completion
     *
     */
    func downloadTask(with request: URLRequest, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        // The returned task
        var task:URLSessionDownloadTask?
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                task = self.urlSession.downloadTask(with: approovUpdateResponse.request) { (data, response, error) -> Void in
                    // Invoke completition handler
                    completionHandler(data,response,error)
                }
            case .ShouldRetry:
                // We should retry doing a fetch after a user driven event
                // Create the early response and invoke callback with custom error
                completionHandler(nil,nil,approovUpdateResponse.error)
                // Initialize a URLSessionDataTask object
                task = self.urlSession.downloadTask(with: approovUpdateResponse.request) { (data, response, error) -> Void in
                }
                // We cancel the connection and return the task object at end of function
                task?.cancel()
            default:
                completionHandler(nil,nil,approovUpdateResponse.error)
                // Initialize a URLSessionDataTask object
                task = self.urlSession.downloadTask(with: approovUpdateResponse.request) { (data, response, error) -> Void in
                }
                // We cancel the connection and return the task object at end of function
                task?.cancel()
        }// switch
    return task!
    }
    
    /*  Creates a download task to resume a previously canceled or failed download
     *  https://developer.apple.com/documentation/foundation/urlsession/1409226-downloadtask
     *  NOTE: this call is not protected by Approov
     */
    func downloadTask(withResumeData: Data) -> URLSessionDownloadTask {
        return self.urlSession.downloadTask(withResumeData: withResumeData)
    }
    
    /*  Creates a download task to resume a previously canceled or failed download and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411598-downloadtask
     *  NOTE: this call is not protected by Approov
     */
    func downloadTask(withResumeData: Data, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return self.urlSession.downloadTask(withResumeData: withResumeData, completionHandler: completionHandler)
    }
    
    // MARK: Upload Tasks
    /*  Creates a task that performs an HTTP request for the specified URL request object and uploads the provided data
     *  https://developer.apple.com/documentation/foundation/urlsession/1409763-uploadtask
     */
    func uploadTask(with request: URLRequest, from: Data) -> URLSessionUploadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        var sessionUploadTask:URLSessionUploadTask?
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                sessionUploadTask = self.urlSession.uploadTask(with: approovUpdateResponse.request, from: from)
            case .ShouldRetry:
                 // We create a task and cancel it immediately
                 sessionUploadTask = self.urlSession.uploadTask(with: approovUpdateResponse.request, from: from)
                 sessionUploadTask!.cancel()
                // We should retry doing a fetch after a user driven event
                // Tell the delagate we are marking the session as invalid
                self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
            default:
                // We create a task and cancel it immediately
                 sessionUploadTask = self.urlSession.uploadTask(with: approovUpdateResponse.request, from: from)
                 sessionUploadTask!.cancel()
                // Tell the delagate we are marking the session as invalid
                self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
        }// switch
        return sessionUploadTask!
    }
    
    /*  Creates a task that performs an HTTP request for the specified URL request object, uploads the provided data,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411518-uploadtask
     */
    func uploadTask(with request: URLRequest, from: Data?, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        // The returned task
        var task:URLSessionUploadTask?
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                task = self.urlSession.uploadTask(with: approovUpdateResponse.request, from: from) { (data, response, error) -> Void in
                    // Invoke completition handler
                    completionHandler(data,response,error)
                }
            case .ShouldRetry:
                // We should retry doing a fetch after a user driven event
                // Create the early response and invoke callback with custom error
                completionHandler(nil,nil,approovUpdateResponse.error)
                // Initialize a URLSessionDataTask object
                task = self.urlSession.uploadTask(with: approovUpdateResponse.request, from: from) { (data, response, error) -> Void in
                }
                // We cancel the connection and return the task object at end of function
                task?.cancel()
            default:
                completionHandler(nil,nil,approovUpdateResponse.error)
                // Initialize a URLSessionDataTask object
                task = self.urlSession.uploadTask(with: approovUpdateResponse.request, from: from) { (data, response, error) -> Void in
                }
                // We cancel the connection and return the task object at end of function
                task?.cancel()
        }// switch
        return task!
    }
    
    /*  Creates a task that performs an HTTP request for uploading the specified file
     *  https://developer.apple.com/documentation/foundation/urlsession/1411550-uploadtask
     */
    func uploadTask(with request: URLRequest, fromFile: URL) -> URLSessionUploadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        var sessionUploadTask:URLSessionUploadTask?
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                sessionUploadTask = self.urlSession.uploadTask(with: approovUpdateResponse.request, fromFile: fromFile)
            case .ShouldRetry:
                 // We create a task and cancel it immediately
                 sessionUploadTask = self.urlSession.uploadTask(with: approovUpdateResponse.request, fromFile: fromFile)
                 sessionUploadTask!.cancel()
                // We should retry doing a fetch after a user driven event
                // Tell the delagate we are marking the session as invalid
                self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
            default:
                // We create a task and cancel it immediately
                 sessionUploadTask = self.urlSession.uploadTask(with: approovUpdateResponse.request, fromFile: fromFile)
                 sessionUploadTask!.cancel()
                // Tell the delagate we are marking the session as invalid
                self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
        }// switch
        return sessionUploadTask!
    }
    
    /*  Creates a task that performs an HTTP request for the specified URL request object, uploads the provided data,
     *  and calls a handler upon completion
     *  https://developer.apple.com/documentation/foundation/urlsession/1411518-uploadtask
     */
    func uploadTask(with request: URLRequest, fromFile: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let userRequest = addUserHeadersToRequest(request: request)
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        // The returned task
        var task:URLSessionUploadTask?
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                task = self.urlSession.uploadTask(with: approovUpdateResponse.request, fromFile: fromFile) { (data, response, error) -> Void in
                    // Invoke completition handler
                    completionHandler(data,response,error)
                }
            case .ShouldRetry:
                // We should retry doing a fetch after a user driven event
                // Create the early response and invoke callback with custom error
                completionHandler(nil,nil,approovUpdateResponse.error)
                // Initialize a URLSessionDataTask object
                task = self.urlSession.uploadTask(with: approovUpdateResponse.request, fromFile: fromFile) { (data, response, error) -> Void in
                }
                // We cancel the connection and return the task object at end of function
                task?.cancel()
            default:
                completionHandler(nil,nil,approovUpdateResponse.error)
                // Initialize a URLSessionDataTask object
                task = self.urlSession.uploadTask(with: approovUpdateResponse.request, fromFile: fromFile) { (data, response, error) -> Void in
                }
                // We cancel the connection and return the task object at end of function
                task?.cancel()
        }// switch
        return task!
    }
    
    /*  Creates a task that performs an HTTP request for uploading data based on the specified URL request
     *  https://developer.apple.com/documentation/foundation/urlsession/1410934-uploadtask
     */
    func uploadTask(withStreamedRequest: URLRequest) -> URLSessionUploadTask {
        let userRequest = addUserHeadersToRequest(request: withStreamedRequest)
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        var sessionUploadTask:URLSessionUploadTask?
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                sessionUploadTask = self.urlSession.uploadTask(withStreamedRequest: approovUpdateResponse.request)
            case .ShouldRetry:
                 // We create a task and cancel it immediately
                 sessionUploadTask = self.urlSession.uploadTask(withStreamedRequest: approovUpdateResponse.request)
                 sessionUploadTask!.cancel()
                // We should retry doing a fetch after a user driven event
                // Tell the delagate we are marking the session as invalid
                self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
            default:
                // We create a task and cancel it immediately
                 sessionUploadTask = self.urlSession.uploadTask(withStreamedRequest: approovUpdateResponse.request)
                 sessionUploadTask!.cancel()
                // Tell the delagate we are marking the session as invalid
                self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
        }// switch
        return sessionUploadTask!
    }
    
    // MARK: Combine Publisher Tasks
    
    /*  Returns a publisher that wraps a URL session data task for a given URL request.
     *  https://developer.apple.com/documentation/foundation/urlsession
     */
    @available(iOS 13.0, *)
    func dataTaskPublisher(for request: URLRequest) -> URLSession.DataTaskPublisher {
        let userRequest = addUserHeadersToRequest(request: request)
        let approovUpdateResponse = ApproovService.updateRequestWithApproov(request: userRequest)
        var sessionTaskPublisher:URLSession.DataTaskPublisher?
        switch approovUpdateResponse.decision {
            case .ShouldProceed:
                // Go ahead and make the API call with the provided request object
                sessionTaskPublisher = self.urlSession.dataTaskPublisher(for: approovUpdateResponse.request)
            case .ShouldRetry:
                 // We create a task and cancel it immediately
                sessionTaskPublisher = self.urlSession.dataTaskPublisher(for: approovUpdateResponse.request)
                // We should retry doing a fetch after a user driven event
                // Tell the delagate we are marking the session as invalid
                self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
            default:
                // We create a task and cancel it immediately
                sessionTaskPublisher = self.urlSession.dataTaskPublisher(for: approovUpdateResponse.request)
                sessionTaskPublisher?.session.invalidateAndCancel()
                // Tell the delagate we are marking the session as invalid
                self.urlSessionDelegate?.urlSession?(self.urlSession, didBecomeInvalidWithError: approovUpdateResponse.error)
        }// switch
        return sessionTaskPublisher!
    }
    
    /*  Returns a publisher that wraps a URL session data task for a given URL request.
     *  https://developer.apple.com/documentation/foundation/urlsession
     */
    @available(iOS 13.0, *)
    func dataTaskPublisher(for url: URL) -> URLSession.DataTaskPublisher {
        return dataTaskPublisher(for: URLRequest(url: url))
    }
    
    
    // MARK: Managing the Session
    /*  Invalidates the session, allowing any outstanding tasks to finish
     *  https://developer.apple.com/documentation/foundation/urlsession/1407428-finishtasksandinvalidate
     */
    func finishTasksAndInvalidate(){
        self.urlSession.finishTasksAndInvalidate()
    }
    
    /*  Flushes cookies and credentials to disk, clears transient caches, and ensures that future requests
     *  occur on a new TCP connection
     *  https://developer.apple.com/documentation/foundation/urlsession/1411622-flush
     */
    func flush(completionHandler: @escaping () -> Void){
        self.urlSession.flush(completionHandler: completionHandler)
    }
    
    /*  Asynchronously calls a completion callback with all data, upload, and download tasks in a session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411578-gettaskswithcompletionhandler
     */
    func getTasksWithCompletionHandler(_ completionHandler: @escaping ([URLSessionDataTask], [URLSessionUploadTask], [URLSessionDownloadTask]) -> Void) {
        self.urlSession.getTasksWithCompletionHandler(completionHandler)
    }
    
    /*  Asynchronously calls a completion callback with all tasks in a session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411618-getalltasks
     */
    func getAllTasks(completionHandler: @escaping ([URLSessionTask]) -> Void) {
        self.urlSession.getAllTasks(completionHandler: completionHandler)
    }
    
    /*  Cancels all outstanding tasks and then invalidates the session
     *  https://developer.apple.com/documentation/foundation/urlsession/1411538-invalidateandcancel
     */
    func invalidateAndCancel() {
        self.urlSession.invalidateAndCancel()
    }
    
    /*  Empties all cookies, caches and credential stores, removes disk files, flushes in-progress downloads to disk,
     *  and ensures that future requests occur on a new socket
     *  https://developer.apple.com/documentation/foundation/urlsession/1411479-reset
     */
    func reset(completionHandler: @escaping () -> Void) {
        self.urlSession.reset(completionHandler: completionHandler)
    }
    
    // MARK: Instance methods
    
    /*  Creates a WebSocket task for the provided URL
     *  https://developer.apple.com/documentation/foundation/urlsession/3181171-websockettask
     */
    @available(iOS 13.0, *)
    func webSocketTask(with: URL) -> URLSessionWebSocketTask {
        self.urlSession.webSocketTask(with: with)
    }
    
    /*  Creates a WebSocket task for the provided URL request
     *  https://developer.apple.com/documentation/foundation/urlsession/3235750-websockettask
     */
    @available(iOS 13.0, *)
    func webSocketTask(with: URLRequest) -> URLSessionWebSocketTask {
        self.urlSession.webSocketTask(with: with)
    }
    
    /*  Creates a WebSocket task given a URL and an array of protocols
     *  https://developer.apple.com/documentation/foundation/urlsession/3181172-websockettask
     */
    @available(iOS 13.0, *)
    func webSocketTask(with: URL, protocols: [String]) -> URLSessionWebSocketTask {
        self.urlSession.webSocketTask(with: with, protocols: protocols)
    }
    
    /*  Add any user defined headers to a URLRequest object
     *  @param  request URLRequest
     *  @return URLRequest the input request including any user defined configuration headers
     */
    func addUserHeadersToRequest( request: URLRequest) -> URLRequest{
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
class ApproovURLSessionDataDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate {
    
    var approovURLDelegate:URLSessionDelegate?
    
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
        ApproovURLSessionDataDelegate.initializePKI()
        self.approovURLDelegate = delegate
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
        approovURLDelegate?.urlSession?(session, didBecomeInvalidWithError: error)
    }
    
    /*  Tells the delegate that all messages enqueued for a session have been delivered
     *  https://developer.apple.com/documentation/foundation/urlsessiondelegate/1617185-urlsessiondidfinishevents
     */
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        approovURLDelegate?.urlSessionDidFinishEvents?(forBackgroundURLSession: session)
    }
    
    /*  Requests credentials from the delegate in response to a session-level authentication request from the remote server
     *  https://developer.apple.com/documentation/foundation/urlsessiondelegate/1409308-urlsession
     */
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // We are only interested in server trust requests
        if !challenge.protectionSpace.authenticationMethod.isEqual(NSURLAuthenticationMethodServerTrust) {
            approovURLDelegate?.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
            return
        }
        do {
            if let serverTrust = try shouldAcceptAuthenticationChallenge(challenge: challenge){
                completionHandler(.useCredential,
                                  URLCredential.init(trust: serverTrust));
                approovURLDelegate?.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
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
        if let delegate =  approovURLDelegate as? URLSessionTaskDelegate {
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
        if let delegate =  approovURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, didCompleteWithError: error)
        }
    }
    
    /*  Tells the delegate that the remote server requested an HTTP redirect
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1411626-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let delegate =  approovURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, willPerformHTTPRedirection: response, newRequest: request, completionHandler: completionHandler)
        }
    }
    
    /*  Tells the delegate when a task requires a new request body stream to send to the remote server
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1410001-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        if let delegate =  approovURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, needNewBodyStream: completionHandler)
        }
    }
    
    /*  Periodically informs the delegate of the progress of sending body content to the server
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1408299-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if let delegate =  approovURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, didSendBodyData: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
        }
    }
    
    /*  Tells the delegate that a delayed URL session task will now begin loading
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2873415-urlsession
     */
    @available(iOS 11.0, *)
    func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest, completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void) {
        if let delegate =  approovURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task:task, willBeginDelayedRequest: request, completionHandler: completionHandler)
        }
    }
    
    /*  Tells the delegate that the session finished collecting metrics for the task
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1643148-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        if let delegate =  approovURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, didFinishCollecting: metrics)
        }
    }
    
    /*  Tells the delegate that the task is waiting until suitable connectivity is available before beginning the network load
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2908819-urlsession
     */
    @available(iOS 11.0, *)
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        if let delegate =  approovURLDelegate as? URLSessionTaskDelegate {
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
        if let delegate =  approovURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
        }
    }
    
    /*  Tells the delegate that the data task was changed to a download task
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1409936-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        if let delegate =  approovURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, didBecome: downloadTask)
        }
    }
    
    /*  Tells the delegate that the data task was changed to a stream task
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411648-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        if let delegate =  approovURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, didBecome: streamTask)
        }
    }
    
    /*  Tells the delegate that the data task has received some of the expected data
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411528-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let delegate =  approovURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session,dataTask: dataTask, didReceive: data)
        }
    }
    
    /*  Asks the delegate whether the data (or upload) task should store the response in the cache
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411612-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {
        if let delegate =  approovURLDelegate as? URLSessionDataDelegate {
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
        if let delegate =  approovURLDelegate as? URLSessionDownloadDelegate {
            delegate.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
        }
    }
    
    /*  Tells the delegate that the download task has resumed downloading
     *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1408142-urlsession
     */
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset: Int64, expectedTotalBytes: Int64) {
        if let delegate =  approovURLDelegate as? URLSessionDownloadDelegate {
            delegate.urlSession?(session, downloadTask: downloadTask, didResumeAtOffset: didResumeAtOffset, expectedTotalBytes: expectedTotalBytes)
        }
    }
    
    /*  Periodically informs the delegate about the download’s progress
     *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1409408-urlsession
     */
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let delegate =  approovURLDelegate as? URLSessionDownloadDelegate {
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
                /* Throw to indicate we could not parse SPKI header */
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
                if let spkiHeader:Data = ApproovURLSessionDataDelegate.pkiHeaders[keyType as! String]?[keyLength as! Int] {
                    return spkiHeader
                }
            }
        }
        return nil
    }
    
    /*  SHA256 of given input bytes
     *
     */
    func sha256(data : Data) -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

}// class


public class ApproovService {
    /* Private initializer */
    fileprivate init(){}
    /* Status of Approov SDK initialisation */
    private static var approovServiceInitialised = false
    /* The singleton object */
    fileprivate static let shared = ApproovService()
    /* The initial config string used to initialize */
    private static var configString:String?
    /* The dispatch queue to manage serial access to intializer modified variables */
    private static let initializerQueue = DispatchQueue(label: "ApproovService.initializer")
    /* map of headers that should have their values substituted for secure strings, mapped to their
     * required prefixes
     */
    private static var substitutionHeaders:Dictionary<String,String> = Dictionary<String,String>()
    /* The dispatch queue to manage serial access to the substitution headers dictionary */
    private static let substitutionQueue = DispatchQueue(label: "ApproovService.substitution")
    /* Use log subsystem for info/error */
    let log = OSLog(subsystem: "approov-service-urlsession", category: "network")
    /* Singleton: config is obtained using `approov sdk -getConfigString`
     * Note the initializer function should only ever be called once. Subsequent calls will be ignored
     * since the ApproovSDK can only be intialized once; if however, an attempt is made to initialize
     * with a different configuration (config) we throw an ApproovException.configurationError
     * If the Approov SDk fails to be initialized for some other reason, an .initializationFailure is raised
     */
    public static func initialize(config: String) throws {
        try initializerQueue.sync  {
            // Check if we attempt to use a different configString
            if (approovServiceInitialised) {
                if (config != configString) {
                    // Throw exception indicating we are attempting to use different config
                    os_log("Approov: Attempting to initialize with different configuration", type: .error)
                    throw ApproovError.configurationError(message: "Attempting to initialize with a different configuration")
                }
                return
            }
            /* Initialise Approov SDK */
            do {
                try Approov.initialize(config, updateConfig: "auto", comment: nil)
                approovServiceInitialised = true
                Approov.setUserProperty("approov-service-urlsession")
            } catch let error {
                // Log error and throw exception
                os_log("Approov: Error initializing Approov SDK: %@", type: .error, error.localizedDescription)
                throw ApproovError.initializationFailure(message: "Error initializing Approov SDK: \(error.localizedDescription)")
            }
        }
    }// initialize func
    
    // Dispatch queue to manage concurrent access to bindHeader variable
    private static let bindHeaderQueue = DispatchQueue(label: "ApproovService.bindHeader", qos: .default, attributes: .concurrent, autoreleaseFrequency: .never, target: DispatchQueue.global())
    private static var _bindHeader = ""
    // Bind Header string
    public static var bindHeader: String {
        get {
            var bindHeader = ""
            bindHeaderQueue.sync {
                bindHeader = _bindHeader
            }
            return bindHeader
        }
        set {
            bindHeaderQueue.async(group: nil, qos: .default, flags: .barrier, execute: {self._bindHeader = newValue})
        }
    }
    
    // Dispatch queue to manage concurrent access to approovTokenHeader variable
    private static let approovTokenHeaderAndPrefixQueue = DispatchQueue(label: "ApproovService.approovTokenHeader", qos: .default, attributes: .concurrent, autoreleaseFrequency: .never, target: DispatchQueue.global())
    /* Approov token default header */
    private static var _approovTokenHeader = "Approov-Token"
    /* Approov token custom prefix: any prefix to be added such as "Bearer " */
    private static var _approovTokenPrefix = ""
    // Approov Token Header String
    public static var approovTokenHeaderAndPrefix: (approovTokenHeader: String, approovTokenPrefix: String) {
        get {
            var approovTokenHeader = ""
            var approovTokenPrefix = ""
            approovTokenHeaderAndPrefixQueue.sync {
                approovTokenHeader = _approovTokenHeader
                approovTokenPrefix = _approovTokenPrefix
        }
        return (approovTokenHeader,approovTokenPrefix)
        }
        set {
            approovTokenHeaderAndPrefixQueue.async(group: nil, qos: .default, flags: .barrier, execute: {(_approovTokenHeader,_approovTokenPrefix) = newValue})
        }
    }

    /*
     *  Allows token prefetch operation to be performed as early as possible. This
     *  permits a token to be available while an application might be loading resources
     *  or is awaiting user input. Since the initial token fetch is the most
     *  expensive the prefetch seems reasonable.
     */
    public static let prefetch: Void = {
        initializerQueue.sync {
            if approovServiceInitialised {
                // We succeeded initializing Approov SDK, fetch a token
                Approov.fetchToken({(approovResult: ApproovTokenFetchResult) in
                    // Prefetch done, no need to process response
                }, "approov.io")
            }
        }
    }()
    
    
    /*
     * Convenience function fetching the Approov token and updating the request with it. This will also
     * perform header substitutions to include protected secrets.
     *
     * @param request is the original request to be made
     * @return ApproovUpdateResponse providing an updated requets, plus an errors and status
     */
    fileprivate static func updateRequestWithApproov(request: URLRequest) -> ApproovUpdateResponse {
        var returnData = ApproovUpdateResponse(request: request, decision: .ShouldFail, sdkMessage: "", error: nil)
        // Check if Bind Header is set to a non empty String
        if ApproovService.bindHeader != "" {
            /*  Query the URLSessionConfiguration for user set headers. They would be set like so:
             *  config.httpAdditionalHeaders = ["Authorization Bearer" : "token"]
             *  Since the URLSessionConfiguration is part of the init call and we store its reference
             *  we check for the presence of a user set header there.
             */
            if let aValue = request.value(forHTTPHeaderField: ApproovService.bindHeader) {
                // Add the Bind Header as a data hash to Approov token
                Approov.setDataHashInToken(aValue)
            }
        }
        // Invoke fetch token sync
        let approovResult = Approov.fetchTokenAndWait(request.url!.absoluteString)
        // Log result of token fetch
        let aHostname = hostnameFromURL(url: request.url!)
        os_log("Approov: updateRequest %@: %@ ", type: .info, aHostname, approovResult.loggableToken())
        // Update the message
        returnData.sdkMessage = Approov.string(from: approovResult.status)
        switch approovResult.status {
            case ApproovTokenFetchStatus.success:
                // Can go ahead and make the API call with the provided request object
                returnData.decision = .ShouldProceed
                // Set Approov-Token header
                returnData.request.setValue(ApproovService.approovTokenHeaderAndPrefix.approovTokenPrefix + approovResult.token, forHTTPHeaderField: ApproovService.approovTokenHeaderAndPrefix.approovTokenHeader)
            case ApproovTokenFetchStatus.noNetwork,
                 ApproovTokenFetchStatus.poorNetwork,
                 ApproovTokenFetchStatus.mitmDetected:
                 // Must not proceed with network request and inform user a retry is needed
                returnData.decision = .ShouldRetry
                let error = ApproovError.networkingError(message: returnData.sdkMessage)
                returnData.error = error
                return returnData
            case ApproovTokenFetchStatus.unprotectedURL,
                 ApproovTokenFetchStatus.unknownURL,
                 ApproovTokenFetchStatus.noApproovService:
                // We do NOT add the Approov-Token header to the request headers
                returnData.decision = .ShouldProceed
            default:
                let error = ApproovError.permanentError(message: returnData.sdkMessage)
                returnData.error = error
                returnData.decision = .ShouldFail
                return returnData
        }// switch
        
        // we now deal with any header substitutions, which may require further fetches but these
        // should be using cached results
        let isIllegalSubstitution = (approovResult.status == ApproovTokenFetchStatus.unknownURL)
        // Check for the presence of headers
        if let requestHeaders = returnData.request.allHTTPHeaderFields {
            // Make a copy of the original request so we can modify it
            var replacementRequest = returnData.request
            for (key, _) in substitutionHeaders {
                let header = key
                if let prefix = substitutionHeaders[key] {
                    if let value = requestHeaders[header]{
                        // Check if the request contains the header we want to replace
                        if ((value.hasPrefix(prefix)) && (value.count > prefix.count)){
                            let index = prefix.index(prefix.startIndex, offsetBy: prefix.count)
                            let approovResults = Approov.fetchSecureStringAndWait(String(value.suffix(from:index)), nil)
                            os_log("Approov: Substituting header: %@, %@ ", type: .info, header, Approov.string(from: approovResults.status))
                            // Process the result of the token fetch operation
                            if approovResults.status == ApproovTokenFetchStatus.success {
                                if isIllegalSubstitution {
                                    // don't allow substitutions on unadded API domains to prevent them accidentally being
                                    // subject to a Man-in-the-Middle (MitM) attack
                                    let error = ApproovError.configurationError(message: "Header substitution: API domain unknown")
                                    returnData.error = error
                                    return returnData
                                }
                                // We add the modified header to the new copy of request
                                if let secureStringResult = approovResults.secureString {
                                    replacementRequest.setValue(prefix + secureStringResult, forHTTPHeaderField: key)
                                } else {
                                    // Secure string is nil
                                    let error = ApproovError.permanentError(message: "Header substitution: Key lookup error")
                                    returnData.error = error
                                    return returnData
                                }
                            } else if approovResults.status == ApproovTokenFetchStatus.rejected {
                                // if the request is rejected then we provide a special exception with additional information
                                let error = ApproovError.rejectionError(message: "Header substitution: rejected", ARC: approovResults.arc, rejectionReasons: approovResults.rejectionReasons)
                                returnData.error = error
                                return returnData
                            } else if approovResults.status == ApproovTokenFetchStatus.noNetwork ||
                                        approovResults.status == ApproovTokenFetchStatus.poorNetwork ||
                                        approovResults.status == ApproovTokenFetchStatus.mitmDetected {
                                // we are unable to get the secure string due to network conditions so the request can
                                // be retried by the user later
                                let error = ApproovError.networkingError(message: "Header substitution: network issue, retry needed")
                                returnData.error = error
                                return returnData
                            } else if approovResults.status != ApproovTokenFetchStatus.unknownKey {
                                // we have failed to get a secure string with a more serious permanent error
                                let error = ApproovError.permanentError(message: "Header substitution: permanent error")
                                returnData.error = error
                                return returnData
                            }
                        }// if (value)
                    } // if let value
                }// if let prefix
            }// for
            // Replace the modified request headers to the request
            returnData.request = replacementRequest
        }// if let
        
        return returnData
    }
    
    /*
     * Adds the name of a header which should be subject to secure strings substitution. This
     * means that if the header is present then the value will be used as a key to look up a
     * secure string value which will be substituted into the header value instead. This allows
     * easy migration to the use of secure strings. A required
     * prefix may be specified to deal with cases such as the use of "Bearer " prefixed before values
     * in an authorization header.
     *
     * @param header is the header to be marked for substitution
     * @param prefix is any required prefix to the value being substituted or nil if not required
     */
    public static func addSubstitutionHeader(header: String, prefix: String?) {
        if prefix == nil {
            ApproovService.substitutionQueue.sync {
                ApproovService.substitutionHeaders[header] = ""
            }
        } else {
            ApproovService.substitutionQueue.sync {
                ApproovService.substitutionHeaders[header] = prefix
            }
        }
    }
    
    /*
     * Removes the name of a header if it exists from the secure strings substitution dictionary.
     */
    public static func removeSubstitutionHeader(header: String) {
        ApproovService.substitutionQueue.sync {
            if ApproovService.substitutionHeaders[header] != nil {
                ApproovService.substitutionHeaders.removeValue(forKey: header)
            }
        }
    }
    
    /*
     * Fetches a secure string with the given key. If newDef is not nil then a secure string for
     * the particular app instance may be defined. In this case the new value is returned as the
     * secure string. Use of an empty string for newDef removes the string entry. Note that this
     * call may require network transaction and thus may block for some time, so should not be called
     * from the UI thread. If the attestation fails for any reason then an exception is raised. Note
     * that the returned string should NEVER be cached by your app, you should call this function when
     * it is needed. If the fetch fails for any reason an exception is thrown with description. Exceptions
     * could be due to the feature not being enabled from the CLI tools (ApproovError.configurationError
     * type raised), a rejection throws an Approov.rejectionError type which might include additional
     * information regarding the failure reason. An ApproovError.networkError exception should allow a
     * retry operation to be performed and finally if some other error occurs an Approov.permanentError
     * is raised.
     *
     * @param key is the secure string key to be looked up
     * @param newDef is any new definition for the secure string, or nil for lookup only
     * @return secure string (should not be cached by your app) or nil if it was not defined or an error ocurred
     * @throws exception with description of cause
     */
    public static func fetchSecureString(key: String, newDef: String?) throws -> String? {
        // determine the type of operation as the values themselves cannot be logged
        var type = "lookup"
        if newDef == nil {
            type = "definition"
        }
        // Invoke fetch secure string
        let approovResult = Approov.fetchSecureStringAndWait(key, newDef)
        // Log result of token fetch
        os_log("Approov: fetchSecureString: %@: %@ ", type: .info, type, Approov.string(from: approovResult.status))
        // Process the returned Approov status
        if approovResult.status == ApproovTokenFetchStatus.disabled {
            throw ApproovError.configurationError(message: "fetchSecureString: secure string feature disabled")
        } else if  approovResult.status == ApproovTokenFetchStatus.badKey {
            throw ApproovError.permanentError(message: "fetchSecureString: secure string unknown key")
        } else if approovResult.status == ApproovTokenFetchStatus.rejected {
            // if the request is rejected then we provide a special exception with additional information
            throw ApproovError.rejectionError(message: "fetchSecureString: rejected", ARC: approovResult.arc, rejectionReasons: approovResult.rejectionReasons)
        } else if approovResult.status == ApproovTokenFetchStatus.noNetwork ||
                    approovResult.status == ApproovTokenFetchStatus.poorNetwork ||
                    approovResult.status == ApproovTokenFetchStatus.mitmDetected {
            // we are unable to get the secure string due to network conditions so the request can
            // be retried by the user later
            throw ApproovError.networkingError(message: "fetchSecureString: network issue, retry needed")
        } else if ((approovResult.status != ApproovTokenFetchStatus.success) && (approovResult.status != ApproovTokenFetchStatus.unknownKey)){
            // we are unable to get the secure string due to a more permanent error
            throw ApproovError.permanentError(message: "fetchSecureString: unknown error")

        }
        return approovResult.secureString
    }// fetchSecureString
    
    /*
     * Fetches a custom JWT with the given payload. Note that this call will require network
     * transaction and thus will block for some time, so should not be called from the UI thread.
     * If the fetch fails for any reason an exception will be thrown. Exceptions could be due to
     * malformed JSON string provided (then a ApproovError.permanentError is raised), the feature not
     * being enabled from the CLI tools (ApproovError.configurationError type raised), a rejection throws
     * a ApproovError.rejectionError type which might include additional information regarding the failure
     * reason. An Approov.networkingError exception should allow a retry operation to be performed. Finally
     * if some other error occurs an Approov.permanentError is raised.
     * 
     * @param payload is the marshaled JSON object for the claims to be included
     * @return custom JWT string or nil if an error occurred
     * @throws exception with description of cause
     */
    public static func fetchCustomJWT(payload: String) throws -> String? {
        // fetch the custom JWT
        let approovResult = Approov.fetchCustomJWTAndWait(payload)
        // Log result of token fetch operation but do not log the value
        os_log("Approov: fetchCustomJWT: %@ ", type: .info, Approov.string(from: approovResult.status))
        // process the returned Approov status
        if approovResult.status == ApproovTokenFetchStatus.badPayload {
            throw ApproovError.permanentError(message: "fetchCustomJWT: malformed JSON")
        } else if  approovResult.status == ApproovTokenFetchStatus.disabled {
            throw ApproovError.configurationError(message: "fetchCustomJWT: feature not enabled")
        } else if approovResult.status == ApproovTokenFetchStatus.rejected {
            // if the request is rejected then we provide a special exception with additional information
            throw ApproovError.rejectionError(message: "fetchCustomJWT: rejected", ARC: approovResult.arc, rejectionReasons: approovResult.rejectionReasons)
        } else if approovResult.status == ApproovTokenFetchStatus.noNetwork ||
                    approovResult.status == ApproovTokenFetchStatus.poorNetwork ||
                    approovResult.status == ApproovTokenFetchStatus.mitmDetected {
            // we are unable to get the secure string due to network conditions so the request can
            // be retried by the user later
            throw ApproovError.networkingError(message: "fetchCustomJWT: network issue, retry needed")
        } else if (approovResult.status != ApproovTokenFetchStatus.success){
            // we are unable to get the secure string due to a more permanent error
            throw ApproovError.permanentError(message: "fetchCustomJWT: unknown error")
        }
        return approovResult.token
    }
    
    /*
     * Performs a precheck to determine if the app will pass attestation. This requires secure
     * strings to be enabled for the account, although no strings need to be set up. This will
     * likely require network access so may take some time to complete. It may throw an exception
     * if the precheck fails or if there is some other problem. Exceptions could be due to
     * a rejection (throws a ApproovError.rejectionError) type which might include additional
     * information regarding the rejection reason. A ApproovError.networkingError exception should
     * allow a retry operation to be performed and finally if some other error occurs an
     * ApproovError.permanentError is raised.
     */
    public static func precheck() throws {
        // try to fetch a non-existent secure string in order to check for a rejection
        let approovResults = Approov.fetchSecureStringAndWait("precheck-dummy-key", nil)
        // process the returned Approov status
        if approovResults.status == ApproovTokenFetchStatus.rejected {
            // if the request is rejected then we provide a special exception with additional information
            throw ApproovError.rejectionError(message: "precheck: rejected", ARC: approovResults.arc, rejectionReasons: approovResults.rejectionReasons)
        } else if approovResults.status == ApproovTokenFetchStatus.noNetwork ||
                    approovResults.status == ApproovTokenFetchStatus.poorNetwork ||
                    approovResults.status == ApproovTokenFetchStatus.mitmDetected {
            // we are unable to get the secure string due to network conditions so the request can
            // be retried by the user later
            throw ApproovError.networkingError(message: "precheck: network issue, retry needed")
        } else if (approovResults.status != ApproovTokenFetchStatus.success) && (approovResults.status != ApproovTokenFetchStatus.unknownKey){
            // we are unable to get the secure string due to a more permanent error
            throw ApproovError.permanentError(message: "precheck unknown error")
        }
    }
} // ApproovService class




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
