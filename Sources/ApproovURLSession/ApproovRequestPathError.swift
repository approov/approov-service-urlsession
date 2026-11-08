// MIT License
//
// Copyright (c) 2026-present, Approov Ltd.
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

// ApproovRequestPathError creates the errors a request fails with on the request path, other than the
// standard decisions, which keep their ApproovError. Every one is a URLError, the platform's network
// error, so that the app's error handling sees an ordinary network failure.
enum ApproovRequestPathError {

    /**
     * Creates the error for a configuration error of the app's, such as a required body digest that
     * cannot be generated, which is logged. The message must never quote a value that could be a token
     * or a secure string.
     *
     * @param message is the description of the error
     * @return URLError for the error
     */
    static func configuration(_ message: String) -> URLError {
        ApproovService.log(.error, "ApproovService: " + message)
        return URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: "ApproovService: " + message])
    }

    /**
     * Creates the error for a value the Approov SDK issued, such as a token, that a header cannot carry,
     * which is logged. The header is named but never the value.
     *
     * @param what is the description of the value, such as "token"
     * @param header is the header that cannot carry it
     * @return URLError for the error
     */
    static func sdkValue(_ what: String, header: String) -> URLError {
        return configuration("Approov header \(header): invalid character in SDK \(what)")
    }

    /**
     * Creates the error for an error thrown by a service mutator hook that is neither a URL loading
     * error nor a standard decision, which is logged naming the hook.
     *
     * @param hook is the name of the hook
     * @param error is the error the hook threw, which becomes the underlying error
     * @return URLError for the error
     */
    static func hookFailure(_ hook: String, _ error: Error) -> URLError {
        let message = "ApproovServiceMutator.\(hook) failed: \(error.localizedDescription)"
        ApproovService.log(.error, "ApproovService: " + message)
        return URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: "ApproovService: " + message,
                                             NSUnderlyingErrorKey: error as NSError])
    }

    /**
     * Calls a service mutator hook on the request path. A URL loading error is the app's own abort and
     * is thrown unchanged, as is a standard decision made during the call. Any other error, including
     * an ApproovError the app's own code threw, is thrown as a hookFailure.
     *
     * @param hook is the name of the hook
     * @param call is the call to the hook
     * @return the result of the hook
     * @throws Error if the hook threw
     */
    static func callHook<T>(_ hook: String, _ call: () throws -> T) throws -> T {
        return try callHook(hook, call, standardDecision: { throw $0 })
    }

    /**
     * Calls a service mutator hook as callHook does, except that a standard decision thrown during the
     * call is ignored, for a request where the standard decisions do not apply.
     *
     * @param hook is the name of the hook
     * @param call is the call to the hook
     * @return the result of the hook, or nil if it threw a standard decision
     * @throws Error if the hook threw anything else
     */
    static func callHookIgnoringStandardDecisions<T>(_ hook: String, _ call: () throws -> T) throws -> T? {
        return try callHook(hook, { try call() as T? }, standardDecision: { _ in nil })
    }

    // calls a hook, passing a standard decision it throws to standardDecision
    private static func callHook<T>(_ hook: String, _ call: () throws -> T,
                                    standardDecision: (ApproovError) throws -> T) throws -> T {
        let decisions = ApproovStandardDecisions()
        do {
            return try ApproovStandardDecisions.withCurrent(decisions, call)
        } catch let approovError as ApproovError {
            if decisions.contains(approovError) {
                return try standardDecision(approovError)
            }
            throw hookFailure(hook, approovError)
        } catch {
            if (error as NSError).domain == NSURLErrorDomain {
                throw error
            }
            throw hookFailure(hook, error)
        }
    }
}

// ApproovStandardDecisions records the errors the standard decisions throw during one hook call, so
// that they can be told apart from an error the app's own code threw, also when a custom mutator
// inherits or calls them. A hook is called synchronously, so the record is kept per thread.
final class ApproovStandardDecisions {
    // the thread dictionary key of the record of the current hook call
    private static let key = "io.approov.service.urlsession.ApproovStandardDecisions"

    // the decisions made, guarded by lock
    private let lock = NSLock()
    private var made: [String] = []

    /**
     * Runs a hook call with this record as the current one on this thread.
     *
     * @param decisions is the record for the call
     * @param call is the hook call
     * @return the result of the call
     * @throws Error if the call threw
     */
    static func withCurrent<T>(_ decisions: ApproovStandardDecisions, _ call: () throws -> T) rethrows -> T {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[key]
        dictionary[key] = decisions
        defer { dictionary[key] = previous }
        return try call()
    }

    /**
     * Records an error as a standard decision made in the current hook call. Outside a hook call it is
     * only returned.
     *
     * @param error is the standard decision
     * @return the error to be thrown
     */
    static func made(_ error: ApproovError) -> ApproovError {
        (Thread.current.threadDictionary[key] as? ApproovStandardDecisions)?.record(error)
        return error
    }

    // records a standard decision
    private func record(_ error: ApproovError) {
        lock.lock()
        defer { lock.unlock() }
        made.append(String(reflecting: error))
    }

    /**
     * Determines whether an error is one of the standard decisions made in this call, with the same case
     * and values.
     *
     * @param error is the error to be checked
     * @return true if the error is a standard decision, false otherwise
     */
    func contains(_ error: ApproovError) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return made.contains(String(reflecting: error))
    }
}
