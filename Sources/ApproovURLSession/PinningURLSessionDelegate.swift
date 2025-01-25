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

// Delegate class implementing all available URLSessionDelegate types and implementing Approov dynamic pinning
class PinningURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate {
    
    // any optional further delegate provided
    var optionalURLDelegate: URLSessionDelegate?
    
    // constants to provide the SPKI headers for the public key hashes
    struct Constants {
        static let rsa2048SPKIHeader:[UInt8] = [
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05,
            0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
        ]
        static let rsa3072SPKIHeader:[UInt8] = [
            0x30, 0x82, 0x01, 0xa2, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05,
            0x00, 0x03, 0x82, 0x01, 0x8f, 0x00
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
    
    // the PKI queue to manage serial access to the PKI initialization
    private static let pkiQueue = DispatchQueue(label: "ApproovService.pki", qos: .userInitiated)
    
    // SPKI headers for both RSA and ECC
    private static var spkiHeaders = [String:[Int:Data]]()
    
    // Indicates if the SPKI headers have been initialized
    private static var isInitialized = false
    
    /**
     * Initialize the SPKI dictionary.
     */
    private static func initializeSPKI() {
        pkiQueue.sync {
            if !isInitialized {
                var rsaDict = [Int:Data]()
                rsaDict[2048] = Data(Constants.rsa2048SPKIHeader)
                rsaDict[3072] = Data(Constants.rsa3072SPKIHeader)
                rsaDict[4096] = Data(Constants.rsa4096SPKIHeader)
                var eccDict = [Int:Data]()
                eccDict[256] = Data(Constants.ecdsaSecp256r1SPKIHeader)
                eccDict[384] = Data(Constants.ecdsaSecp384r1SPKIHeader)
                spkiHeaders[kSecAttrKeyTypeRSA as String] = rsaDict
                spkiHeaders[kSecAttrKeyTypeECSECPrimeRandom as String] = eccDict
                isInitialized = true
            }
        }
    }
    
    /**
     * Initialize the delegate, providing it another optional user provided delegate.
     *
     * @param delegate is the optional user delegate
     */
    init(with delegate: URLSessionDelegate?) {
        PinningURLSessionDelegate.initializeSPKI()
        self.optionalURLDelegate = delegate
    }
    
    // MARK: URLSessionDelegate
    
    /**
     *  URLSessionDelegate
     *  A protocol that defines methods that URL session instances call on their delegates to handle session-level events,
     *  like session life cycle changes
     *  https://developer.apple.com/documentation/foundation/urlsessiondelegate
     */
    
    /**
     *  Tells the URL session that the session has been invalidated
     *  https://developer.apple.com/documentation/foundation/urlsessiondelegate/1407776-urlsession
     */
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        optionalURLDelegate?.urlSession?(session, didBecomeInvalidWithError: error)
    }
    
    /**
     *  Tells the delegate that all messages enqueued for a session have been delivered
     *  https://developer.apple.com/documentation/foundation/urlsessiondelegate/1617185-urlsessiondidfinishevents
     */
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        optionalURLDelegate?.urlSessionDidFinishEvents?(forBackgroundURLSession: session)
    }
    
    /**
     *  Requests credentials from the delegate in response to a session-level authentication request from the remote server
     *  https://developer.apple.com/documentation/foundation/urlsessiondelegate/1409308-urlsession
     */
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if !challenge.protectionSpace.authenticationMethod.isEqual(NSURLAuthenticationMethodServerTrust) {
            if let userDelegate = optionalURLDelegate {
                // delegate any challenge that is not to do with pinning
                userDelegate.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
            }
            else {
                // the user is not providing a delegate so we need to invoke the completion handler since we only deal with certificate pinning
                completionHandler(.useCredential, nil)
            }
        }
        else {
            // we have a server trust challenge
            do {
                if let serverTrust = try shouldAcceptAuthenticationChallenge(challenge: challenge) {
                    // the pinning check succeeded
                    completionHandler(.useCredential, URLCredential.init(trust: serverTrust));
                    optionalURLDelegate?.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
                    return
                }
            } catch {
                os_log("ApproovService: urlSession error %@", type: .error, error.localizedDescription)
            }
            completionHandler(URLSession.AuthChallengeDisposition.cancelAuthenticationChallenge, nil)
        }
    }
    
    // MARK: URLSessionTaskDelegate
    
    /**
     *  URLSessionTaskDelegate
     *  A protocol that defines methods that URL session instances call on their delegates to handle task-level events
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate
     */
    
    /**
     *  Requests credentials from the delegate in response to an authentication request from the remote server
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1411595-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            if !challenge.protectionSpace.authenticationMethod.isEqual(NSURLAuthenticationMethodServerTrust) {
                if let userDelegate = optionalURLDelegate {
                    // delegate any challenge that is not to do with pinning
                    userDelegate.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
                }
                else {
                    // the user is not providing a delegate so we need to invoke the completion handler since we only deal with certificate pinning
                    completionHandler(.useCredential, nil)
                }
            }
            else {
                // we have a server trust challenge
                do {
                    if let serverTrust = try shouldAcceptAuthenticationChallenge(challenge: challenge) {
                        // the pinning check succeeded
                        completionHandler(.useCredential, URLCredential.init(trust: serverTrust));
                        delegate.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
                        return
                    }
                } catch {
                    os_log("ApproovService: urlSession error %@", type: .error, error.localizedDescription)
                }
                completionHandler(URLSession.AuthChallengeDisposition.cancelAuthenticationChallenge, nil)
            }
        }
    }
    
    /**
     *  Tells the delegate that the task finished transferring data
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1411610-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, didCompleteWithError: error)
        }
    }
    
    /**
     *  Tells the delegate that the remote server requested an HTTP redirect
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1411626-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, willPerformHTTPRedirection: response, newRequest: request, completionHandler: completionHandler)
        } else {
            completionHandler(request)
        }
    }
    
    /**
     *  Tells the delegate when a task requires a new request body stream to send to the remote server
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1410001-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, needNewBodyStream: completionHandler)
        }
    }
    
    /**
     *  Periodically informs the delegate of the progress of sending body content to the server
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1408299-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, didSendBodyData: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
        }
    }
    
    /**
     *  Tells the delegate that a delayed URL session task will now begin loading
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2873415-urlsession
     */
    @available(iOS 11.0, *)
    func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest, completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task:task, willBeginDelayedRequest: request, completionHandler: completionHandler)
        } else {
            completionHandler(URLSession.DelayedRequestDisposition.continueLoading, request)
        }
    }
    
    /**
     *  Tells the delegate that the session finished collecting metrics for the task
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1643148-urlsession
     */
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, didFinishCollecting: metrics)
        }
    }
    
    /**
     *  Tells the delegate that the task is waiting until suitable connectivity is available before beginning the network load
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2908819-urlsession
     */
    @available(iOS 11.0, *)
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, taskIsWaitingForConnectivity: task)
        }
    }

    /**
     *  Tells the delegate that a new task was created
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/3929682-urlsession
     */
    @available(iOS 16.0, watchOS 9.0, *)
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, didCreateTask: task)
        }
    }
    
    /**
     *  Tells the delegate that a task received an informational response
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/4165504-urlsession
     */
    @available(iOS 17.0, watchOS 10.0, *)
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceiveInformationalResponse response: HTTPURLResponse) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, didReceiveInformationalResponse: response)
        }
    }
    
    /**
     *  Tells the delegate that a task received an informational response
     *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/4165504-urlsession
     */
    @available(iOS 17.0, watchOS 10.0, *)
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStreamFrom offset: Int64, completionHandler: @escaping @Sendable (InputStream?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionTaskDelegate {
            delegate.urlSession?(session, task: task, needNewBodyStreamFrom: offset, completionHandler: completionHandler)
        }
    }
    
    // MARK: URLSessionDataDelegate
    
    /**
     *  URLSessionDataDelegate
     *  A protocol that defines methods that URL session instances call on their delegates to handle task-level events
     *  specific to data and upload tasks
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate
     */
    
    /**
     *  Tells the delegate that the data task received the initial reply (headers) from the server
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1410027-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
    {
        if let delegate = optionalURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
        } else {
            completionHandler(URLSession.ResponseDisposition.allow)
        }
    }
    
    /**
     *  Tells the delegate that the data task was changed to a download task
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1409936-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        if let delegate = optionalURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, didBecome: downloadTask)
        }
    }
    
    /**
     *  Tells the delegate that the data task was changed to a stream task
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411648-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        if let delegate = optionalURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, didBecome: streamTask)
        }
    }
    
    /**
     *  Tells the delegate that the data task has received some of the expected data
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411528-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let delegate = optionalURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session,dataTask: dataTask, didReceive: data)
        }
    }
    
    /**
     *  Asks the delegate whether the data (or upload) task should store the response in the cache
     *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411612-urlsession
     */
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {
        if let delegate = optionalURLDelegate as? URLSessionDataDelegate {
            delegate.urlSession?(session, dataTask: dataTask, willCacheResponse: proposedResponse, completionHandler: completionHandler)
        } else {
                completionHandler(proposedResponse)
        }
    }
    
    // MARK: URLSessionDownloadDelegate
    
    /**
     *  A protocol that defines methods that URL session instances call on their delegates to handle
     *  task-level events specific to download tasks
     *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate
     */
    
    /**
     *  Tells the delegate that a download task has finished downloading
     *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1411575-urlsession
     */
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let delegate = optionalURLDelegate as? URLSessionDownloadDelegate {
            delegate.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
        }
    }
    
    /**
     *  Tells the delegate that the download task has resumed downloading
     *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1408142-urlsession
     */
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset: Int64, expectedTotalBytes: Int64) {
        if let delegate = optionalURLDelegate as? URLSessionDownloadDelegate {
            delegate.urlSession?(session, downloadTask: downloadTask, didResumeAtOffset: didResumeAtOffset, expectedTotalBytes: expectedTotalBytes)
        }
    }
    
    /**
     *  Periodically informs the delegate about the download’s progress
     *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1409408-urlsession
     */
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let delegate = optionalURLDelegate as? URLSessionDownloadDelegate {
            delegate.urlSession?(session, downloadTask: downloadTask, didWriteData: didWriteData, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        }
    }
    
    
    
    // MARK: Utilities
    
    /**
     * Gets the Subject Public Key Info (SPKI) header depending on a public key's type and size.
     *
     * @param publlcKey is the public key of the certificate
     * @return the public key SPKI header, or nil if there was a problem
     */
    private func publicKeyInfoHeaderForKey(publicKey: SecKey) -> Data? {
        guard let publicKeyAttributes = SecKeyCopyAttributes(publicKey) else {
            return nil
        }
        if let keyType = (publicKeyAttributes as NSDictionary).value(forKey: kSecAttrKeyType as String) {
            if let keyLength = (publicKeyAttributes as NSDictionary).value(forKey: kSecAttrKeySizeInBits as String) {
                // find the header
                if let spkiHeader:Data = PinningURLSessionDelegate.spkiHeaders[keyType as! String]?[keyLength as! Int] {
                    return spkiHeader
                }
            }
        }
        return nil
    }
    
    /**
     * Gets a certificate's subject public key info (SPKI).
     *
     *@param certificate is the one being analyzed
     *@return certificate data with the appropriate SPKI header, or nil if there was a problem
     */
    private func publicKeyInfoOfCertificate(certificate: SecCertificate) -> Data? {
        var publicKey:SecKey?
        if #available(iOS 12.0, *) {
            publicKey = SecCertificateCopyKey(certificate)
        } else {
            // fallback on earlier versions
            // from TrustKit https://github.com/datatheorem/TrustKit/blob/master/TrustKit/Pinning/TSKSPKIHashCache.m lines
            // 221-234:
            // Create an X509 trust using the certificate
            let secPolicy = SecPolicyCreateBasicX509()
            var secTrust:SecTrust?
            if SecTrustCreateWithCertificates(certificate, secPolicy, &secTrust) != errSecSuccess {
                return nil
            }
            
            // check the validity of the certificate
            var secTrustResultType = SecTrustResultType.invalid
            if SecTrustEvaluate(secTrust!, &secTrustResultType) != errSecSuccess {
                return nil
            }
            
            // get a public key reference for the certificate from the trust
            publicKey = SecTrustCopyPublicKey(secTrust!)
            
        }
        if publicKey == nil {
            return nil
        }
        
        // get the SPKI header depending on the public key's type and size
        guard var spkiData = publicKeyInfoHeaderForKey(publicKey: publicKey!) else {
            return nil
        }
        
        // combine the public key header and the public key data to form the public key info
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey!, nil) else {
            return nil
        }
        spkiData.append(publicKeyData as Data)
        return spkiData
    }
    
    /**
     * SHA256 of given input bytes.
     *
     * @param data is the input data
     * @return the hash data
     */
    private func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    /**
     *  Evaluates a URLAuthenticationChallenge deciding if to proceed further.
     *
     *  @param  challenge is the  URLAuthenticationChallenge
     *  @return SecTrust?: valid SecTrust if authentication should proceed, nil otherwise
     */
    private func shouldAcceptAuthenticationChallenge(challenge: URLAuthenticationChallenge) throws -> SecTrust? {
        // check we have a server trust, ignore any other challenges
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            return nil
        }
        
        // check the validity of the server cert
        if #available(iOS 12.0, *) {
            if (!SecTrustEvaluateWithError(serverTrust, nil)) {
                throw ApproovError.pinningError(message: "Error during Certificate Trust Evaluation for host \(challenge.protectionSpace.host)")
            }
        }
        else {
            var trustType = SecTrustResultType.invalid
            if (SecTrustEvaluate(serverTrust, &trustType) != errSecSuccess) {
                throw ApproovError.pinningError(message: "Error during Certificate Trust Evaluation for host \(challenge.protectionSpace.host)")
            } else if (trustType != SecTrustResultType.proceed) && (trustType != SecTrustResultType.unspecified) {
                throw ApproovError.pinningError(message: "Error: Certificate Trust Evaluation failure for host \(challenge.protectionSpace.host)")
            }
        }
        
        // get the dynamic pins from Approov
        guard let approovPins = Approov.getPins("public-key-sha256") else {
            os_log("ApproovService: pin verification no Approov pins")
            return serverTrust
        }
        
        // get the pins for the host
        var pinsForHost: [String]
        let host = challenge.protectionSpace.host
        if let pins = approovPins[host] {
            // the host pinning is managed by Approov
            pinsForHost = pins
            if pinsForHost.count == 0 {
                // there are no pins set for the host so use managed trust roots if available
                if approovPins["*"] == nil {
                    // there are no managed trust roots so the host is truly unpinned
                    os_log("ApproovService: pin verification %@ no pins", host)
                    return serverTrust
                } else {
                    // use the managed trust roots for pinning
                    pinsForHost = approovPins["*"]!
                }
            }
        } else {
            // host is not pinned
            os_log("ApproovService: pin verification %@ unpinned", host)
            return serverTrust
        }
        
        // iterate over the certificate chain
        let certCountInChain = SecTrustGetCertificateCount(serverTrust);
        var indexCurrentCert = 0;
        while (indexCurrentCert < certCountInChain) {
            // get the current certificate from the chain - not that this function is deprecated at iOS 15 but the
            // replacement is not available until iOS 15 and has a significantly different interface so we cannot
            // update this yet
            guard let serverCert = SecTrustGetCertificateAtIndex(serverTrust, indexCurrentCert) else {
                throw ApproovError.pinningError(message:
                    "Error getting certificate at index \(indexCurrentCert) from chain for host \(challenge.protectionSpace.host)")
            }
            
            // get the subject public key info from the certificate
            if let publicKeyInfo = publicKeyInfoOfCertificate(certificate: serverCert) {
                // compute the SHA-256 hash of the public key info and base64 encode to create the pin value
                let publicKeyHash = sha256(data: publicKeyInfo)
                let publicKeyHashBase64 = String(data:publicKeyHash.base64EncodedData(), encoding: .utf8)
                
                // see if we have a match on a pin for this certificate in the chain
                for pin in pinsForHost {
                    if publicKeyHashBase64 == pin {
                        os_log("ApproovService: matched pin %@ for %@ from %d pins", pin, host, pinsForHost.count)
                        return serverTrust
                    }
                }
            }
            else {
                os_log("ApproovService: skippng unsupported certificate type")
            }
            
            // move to the next certificate in the chain
            indexCurrentCert += 1
        }
        
        // we return nil if no match in current set of pins from Approov SDK and certificate chain seen during the TLS handshake
        os_log("ApproovService: pin verification failed for %@ with no match for %d pins", host, pinsForHost.count)
        return nil
    }
}
