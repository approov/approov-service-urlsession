// Written the way existing apps integrate the service layer, in the Swift 5 language mode and without any concurrency
// annotations. It must keep compiling with no errors or warnings. Compiled only, never run.

import Foundation
import ApproovURLSessionPackage

final class LegacyNetworkClient: NSObject, URLSessionDataDelegate {
    var lastResponse: URLResponse?
    var receivedData = Data()

    lazy var session: ApproovURLSession = ApproovURLSession(
        configuration: .default, delegate: self, delegateQueue: OperationQueue.main)

    func configure() throws {
        try ApproovService.initialize(config: "<config>", comment: nil)
        ApproovService.setApproovHeader(header: "Approov-Token", prefix: "Bearer ")
        ApproovService.setApproovTraceIDHeader(header: nil)
        ApproovService.setBindingHeader(header: "Authorization")
        ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)
        ApproovService.setLoggingLevel(.debug)
        ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        ApproovService.addSubstitutionQueryParam(key: "api_key")
        ApproovService.addExclusionURLRegex(urlRegex: "^https://public\\.example\\.com/.*")
        ApproovService.setFailureCacheTTL(ttl: 1)
        ApproovService.setServiceMutator(StatefulMutator())
        ApproovSessionTaskObserver.enableLogging = false
    }

    // Completion handlers that mutate captured and instance state, as pre-concurrency code does.
    func load(_ url: URL) {
        var attempts = 0
        session.dataTask(with: url) { data, response, error in
            attempts += 1
            self.lastResponse = response
            self.receivedData = data ?? Data()
            if error != nil && attempts < 3 {
                self.load(url)
            }
        }.resume()
    }

    func transfer(_ request: URLRequest, file: URL) {
        var count = 0
        session.uploadTask(with: request, from: Data()) { _, _, _ in count += 1 }.resume()
        session.uploadTask(with: request, fromFile: file) { _, _, _ in count += 1 }.resume()
        session.downloadTask(with: request) { _, _, _ in count += 1 }.resume()
        session.downloadTask(with: request.url!) { _, _, _ in count += 1 }.resume()
        session.downloadTask(withResumeData: Data()) { _, _, _ in count += 1 }.resume()
        session.getAllTasks { tasks in count += tasks.count }
        session.getTasksWithCompletionHandler { data, upload, download in count += data.count + upload.count + download.count }
        session.flush { count += 1 }
        session.reset { count += 1 }
    }

    func tasksWithoutHandlers(_ request: URLRequest) -> [URLSessionTask] {
        return [
            session.dataTask(with: request),
            session.uploadTask(with: request, from: Data()),
            session.downloadTask(with: request),
            session.webSocketTask(with: request.url!),
        ]
    }

    @available(iOS 15.0, macOS 12.0, *)
    func loadAsync(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.dataWithApproov(for: request, delegate: nil)
        lastResponse = response
        return data
    }

    func protect(_ request: URLRequest) throws -> URLRequest {
        let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: session.configuration)
        switch response.decision {
        case .ShouldProceed, .ShouldIgnore:
            return try ApproovService.signRequest(response.request)
        case .ShouldRetry, .ShouldFail:
            throw response.error ?? ApproovError.permanentError(message: response.sdkMessage)
        }
    }

    func direct() throws -> [String?] {
        try ApproovService.precheck()
        return [
            try ApproovService.fetchToken(url: "https://api.example.com"),
            try ApproovService.fetchSecureString(key: "key", newDef: nil),
            try ApproovService.fetchCustomJWT(payload: "{}"),
            ApproovService.getDeviceID(),
            ApproovService.getLastARC(),
        ]
    }

    func enableMessageSigning() throws {
        let factory = try ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setBodyDigestConfig(ApproovDefaultMessageSigning.DIGEST_SHA256, required: false)
            .setUseInstallMessageSigning()
            .addOptionalHeaders(["Authorization"])
        ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(factory))
    }

    func describe(_ error: Error) -> String {
        guard let approovError = error as? ApproovError else {
            return error.localizedDescription
        }
        switch approovError {
        case let .rejectionError(message, ARC, reasons):
            return "\(message) \(ARC) \(reasons)"
        case let .initializationFailure(message), let .configurationError(message), let .pinningError(message),
             let .networkingError(message), let .permanentError(message):
            return message
        }
    }
}

// A mutator class with mutable state and no Sendable conformance.
final class StatefulMutator: ApproovServiceMutator {
    var processed = 0

    func handleInterceptorShouldProcessRequest(_ request: URLRequest) throws -> Bool {
        processed += 1
        return request.url?.host != "public.example.com"
    }

    func handlePinningShouldProcessRequest(_ request: URLRequest) -> Bool {
        return true
    }
}
