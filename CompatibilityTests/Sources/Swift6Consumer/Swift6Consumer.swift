// Written the way an app adopting Swift concurrency integrates the service layer, in the Swift 6 language mode with
// complete data-race checking. It must keep compiling with no errors or warnings. Compiled only, never run.

import Foundation
import ApproovURLSessionPackage

enum API {
    // A shared session in a static let requires ApproovURLSession to be Sendable.
    static let session = ApproovURLSession(configuration: .default)
}

// Configuration from the main actor at launch.
@MainActor
func configureApproov() throws {
    try ApproovService.initialize(config: "<config>")
    ApproovService.setApproovHeader(header: "Authorization", prefix: "Bearer ")
    ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
    ApproovService.setLoggingLevel(.info)
    ApproovService.setServiceMutator(ApproovServiceMutatorDefault.shared)
}

@MainActor
final class ViewModel {
    private(set) var text = ""
    private(set) var level: ApproovLogLevel = .info

    // A completion handler written in a main-actor type is not isolated to the main actor, because the handler is
    // @Sendable, as it is on URLSession. Main-actor state is updated by hopping back explicitly.
    func load(_ url: URL) {
        API.session.dataTask(with: url) { data, _, _ in
            let text = String(decoding: data ?? Data(), as: UTF8.self)
            Task { @MainActor in
                self.text = text
            }
        }.resume()
    }

    func loadAsync(_ request: URLRequest) async throws {
        let (data, _) = try await API.session.dataWithApproov(for: request)
        text = String(decoding: data, as: UTF8.self)
    }

    // Blocking service-layer calls moved off the main actor; their results cross back to it.
    func token() async throws -> String {
        try await Task.detached { try ApproovService.fetchToken(url: "https://api.example.com") }.value
    }

    func update(_ request: URLRequest) async -> ApproovUpdateResponse {
        await Task.detached { ApproovService.updateRequestWithApproov(request: request, sessionConfig: nil) }.value
    }

    func decision(for request: URLRequest) async -> ApproovFetchDecision {
        await update(request).decision
    }

    func handle(_ error: any Error) -> String {
        (error as? ApproovError)?.localizedDescription ?? error.localizedDescription
    }
}

actor Client {
    private let session = API.session

    func get(_ url: URL) async throws -> Data {
        try await session.dataWithApproov(from: url).0
    }

    func upload(_ request: URLRequest, body: Data) async throws -> URLResponse {
        try await session.uploadWithApproov(for: request, from: body).1
    }

    func download(_ request: URLRequest) async throws -> URL {
        try await session.downloadWithApproov(for: request).0
    }

    // For transports that own their URLSession: sign the request, then send it elsewhere.
    func signed(_ request: URLRequest) throws -> URLRequest {
        try ApproovService.signRequest(request)
    }

    func secureString(_ key: String) throws -> String? {
        try ApproovService.fetchSecureString(key: key, newDef: nil)
    }
}

// Results and errors of the service layer cross isolation boundaries.
func concurrentTokens(for urls: [String]) async -> [Result<String, any Error>] {
    await withTaskGroup(of: Result<String, any Error>.self) { group in
        for url in urls {
            group.addTask { Result { try ApproovService.fetchToken(url: url) } }
        }
        var results: [Result<String, any Error>] = []
        for await result in group {
            results.append(result)
        }
        return results
    }
}
