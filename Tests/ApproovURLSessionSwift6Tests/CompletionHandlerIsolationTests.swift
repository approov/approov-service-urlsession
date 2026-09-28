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
import XCTest
import ApproovURLSessionPackage

/// In the Swift 6 language mode, a closure written inside a @MainActor context is isolated to the main actor unless the
/// parameter it is passed to is @Sendable. URLSession runs completion handlers on its delegate queue, so if an
/// ApproovURLSession method took a non-Sendable handler, the handler below would be main-actor code called off the main
/// thread: the Swift runtime reports that as a data race, and traps with SWIFT_UNEXPECTED_EXECUTOR_LOG_LEVEL=2. Every
/// handler is therefore written literally inside this @MainActor test, as app code would be.
@MainActor
final class CompletionHandlerIsolationTests: XCTestCase {

    private var replyURL: URL {
        get throws {
            let value = ProcessInfo.processInfo.environment["TESTING_REPLY_URL_UNPROTECTED"]
            return try XCTUnwrap(value.flatMap(URL.init(string:)), "TESTING_REPLY_URL_UNPROTECTED must be set")
        }
    }

    func testTaskCompletionHandlersWrittenOnTheMainActorRunOffIt() async throws {
        let session = ApproovURLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = try replyURL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let bodyFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("{}".utf8).write(to: bodyFile)
        defer { try? FileManager.default.removeItem(at: bodyFile) }

        let completions = (0..<7).map { expectation(description: "completion \($0)") }
        session.dataTask(with: url) { _, _, error in
            XCTAssertNil(error)
            completions[0].fulfill()
        }.resume()
        session.dataTask(with: request) { _, _, error in
            XCTAssertNil(error)
            completions[1].fulfill()
        }.resume()
        session.uploadTask(with: request, from: Data("{}".utf8)) { _, _, error in
            XCTAssertNil(error)
            completions[2].fulfill()
        }.resume()
        session.uploadTask(with: request, fromFile: bodyFile) { _, _, error in
            XCTAssertNil(error)
            completions[3].fulfill()
        }.resume()
        session.downloadTask(with: url) { _, _, error in
            XCTAssertNil(error)
            completions[4].fulfill()
        }.resume()
        session.downloadTask(with: URLRequest(url: url)) { _, _, error in
            XCTAssertNil(error)
            completions[5].fulfill()
        }.resume()
        let resumable = session.downloadTask(withResumeData: Data()) { _, _, _ in
            // invalid resume data fails immediately; only the isolation of the handler matters here
            completions[6].fulfill()
        }
        resumable.resume()
        await fulfillment(of: completions, timeout: 30)
    }

    func testSessionCompletionHandlersWrittenOnTheMainActorRunOffIt() async throws {
        let session = ApproovURLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        let completions = (0..<4).map { expectation(description: "completion \($0)") }
        session.getAllTasks { _ in completions[0].fulfill() }
        session.getTasksWithCompletionHandler { _, _, _ in completions[1].fulfill() }
        session.flush { completions[2].fulfill() }
        session.reset { completions[3].fulfill() }
        await fulfillment(of: completions, timeout: 30)
    }
}
