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

import XCTest
import Foundation
import CryptoKit
import Approov
@testable import ApproovURLSessionPackage
import MiniSDKTestSupport

/// Message signing on the wire: off out of the box, the install signature by default, both members of
/// one dictionary when asked, the other member when one cannot be produced, the derived components from
/// the URL as it is sent, and created and expires from the Approov servers' clock.
final class Signing370Tests: XCTestCase {
    private let validInitialConfig = testAccountID
    private var base: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = try XCTUnwrap(ProcessInfo.processInfo.environment["TESTING_REPLY_URL"])
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        ApproovService.setLoggingLevel(.off)
        try ApproovService.initialize(config: validInitialConfig, comment: "reinit-signing")
    }

    override func tearDown() {
        ApproovService.setServiceMutator(nil)
        MiniSDKAttesterProxyController.reset()
        ApproovService.resetForTesting()
        super.tearDown()
    }

    private func sign(_ url: String, factory: SignatureParametersFactory? = nil,
                      signer: ApproovDefaultMessageSigning? = nil) throws -> URLRequest {
        if let signer {
            ApproovService.setServiceMutator(signer)
        } else if let factory {
            ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(factory))
        }
        let response = ApproovService.updateRequestWithApproov(request: URLRequest(url: try XCTUnwrap(URL(string: url))), sessionConfig: nil)
        XCTAssertEqual(response.decision, .ShouldProceed, String(describing: response.error))
        return response.request
    }

    // the members of a Signature or Signature-Input dictionary, in order, with their values as sent
    private func members(_ header: String?) -> [(String, String)] {
        guard let header else { return [] }
        var result: [(String, String)] = []
        var depth = 0, start = header.startIndex
        for index in header.indices {
            let c = header[index]
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            if c == "," && depth == 0 {
                result.append(split(String(header[start..<index])))
                start = header.index(after: index)
            }
        }
        result.append(split(String(header[start...])))
        return result
    }

    private func split(_ member: String) -> (String, String) {
        let trimmed = member.trimmingCharacters(in: .whitespaces)
        let equals = trimmed.firstIndex(of: "=")!
        return (String(trimmed[..<equals]), String(trimmed[trimmed.index(after: equals)...]))
    }

    func testThreeSigningStates() throws {
        let off = try sign(base + "/a")
        XCTAssertNil(off.value(forHTTPHeaderField: "Signature"), "signing is off out of the box")
        let install = try sign(base + "/a", factory: ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory())
        XCTAssertEqual(members(install.value(forHTTPHeaderField: "Signature")).map { $0.0 }, ["install"])
        let both = try sign(base + "/a", factory: ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setUseInstallAndAccountMessageSigning())
        XCTAssertEqual(members(both.value(forHTTPHeaderField: "Signature")).map { $0.0 }, ["install", "account"])
        let inputs = members(both.value(forHTTPHeaderField: "Signature-Input"))
        XCTAssertEqual(inputs.map { $0.0 }, ["install", "account"])
        guard inputs.count == 2 else { return }
        XCTAssertTrue(inputs[0].1.contains("alg=\"ecdsa-p256-sha256\""), inputs[0].1)
        XCTAssertTrue(inputs[1].1.contains("alg=\"hmac-sha256\""), inputs[1].1)
        // the same components and times, only the algorithm differs
        XCTAssertEqual(inputs[0].1.replacingOccurrences(of: "ecdsa-p256-sha256", with: "hmac-sha256"), inputs[1].1)
    }

    func testTheOtherMemberIsSentWhenOneCannotBeProduced() throws {
        // a device with no install key, which the SDK reads from the first initialization's options
        MiniSDKAttesterProxyController.resetSdkForTesting()
        ApproovService.resetForTesting()
        try ApproovService.initialize(config: validInitialConfig, comment: "options:no-install-key")
        let request = try sign(base + "/a", factory: ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setUseInstallAndAccountMessageSigning())
        XCTAssertEqual(members(request.value(forHTTPHeaderField: "Signature")).map { $0.0 }, ["account"])
        XCTAssertEqual(members(request.value(forHTTPHeaderField: "Signature-Input")).map { $0.0 }, ["account"])
    }

    func testTheInstallSignatureVerifiesOverTheURLAsSent() throws {
        let url = base + "/p%20a%7Ct%C3%A9?q=%25x%7Cy&z=%20#frag"
        let request = try sign(url, factory: ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory())
        let input = try XCTUnwrap(members(request.value(forHTTPHeaderField: "Signature-Input")).first).1
        let sent = try XCTUnwrap(request.url?.absoluteString.components(separatedBy: "#").first)
        let token = try XCTUnwrap(request.value(forHTTPHeaderField: "Approov-Token"))
        let trace = try XCTUnwrap(request.value(forHTTPHeaderField: "Approov-TraceID"))
        let signatureBase = """
            "@method": GET
            "@target-uri": \(sent)
            "approov-token": \(token)
            "approov-traceid": \(trace)
            "@signature-params": \(input)
            """
        let signatureValue = try XCTUnwrap(members(request.value(forHTTPHeaderField: "Signature")).first).1
        let raw = try XCTUnwrap(Data(base64Encoded: String(signatureValue.dropFirst().dropLast())))
        let key = try P256.Signing.PublicKey(derRepresentation: try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(Approov.getInstallPublicKey()))))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: raw)
        XCTAssertTrue(key.isValidSignature(signature, for: Data(signatureBase.utf8)), "the signature does not cover:\n\(signatureBase)")
    }

    func testDerivedComponentsComeFromTheURLAsSent() throws {
        let provider = ApproovURLSessionComponentProvider(request: URLRequest(url: try XCTUnwrap(URL(string: "https://API.Example.com:8443/p%20a?q=%25x%7Cy#frag"))))
        XCTAssertEqual(provider.getTargetUri(), "https://API.Example.com:8443/p%20a?q=%25x%7Cy")
        XCTAssertEqual(provider.getAuthority(), "api.example.com:8443")
        XCTAssertEqual(provider.getPath(), "/p%20a")
        XCTAssertEqual(provider.getQuery(), "q=%25x%7Cy")
        XCTAssertEqual(provider.getRequestTarget(), "/p%20a?q=%25x%7Cy")
        let defaultPort = ApproovURLSessionComponentProvider(request: URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com:443/"))))
        XCTAssertEqual(defaultPort.getAuthority(), "api.example.com")
    }

    func testSignatureTimesFollowTheApproovServersClock() throws {
        MiniSDKAttesterProxyController.setServerTimeOffsetMS(3_600_000)
        let request = try sign(base + "/a", factory: ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory())
        let input = try XCTUnwrap(members(request.value(forHTTPHeaderField: "Signature-Input")).first).1
        let created = try XCTUnwrap(input.components(separatedBy: ";created=").last?.components(separatedBy: ";").first.flatMap { Int64($0) })
        let device = Int64(Date().timeIntervalSince1970)
        XCTAssertLessThan(abs(created - device - 3_600), 5, "created \(created) is not the servers' time")
        let server = try ApproovService.getServerAdjustedCurrentTimeMS()
        XCTAssertLessThan(abs(server / 1000 - device - 3_600), 5)
    }

    func testServerTimeNeedsProtection() throws {
        MiniSDKAttesterProxyController.resetSdkForTesting()
        ApproovService.resetForTesting()
        try ApproovService.initialize(config: "", comment: nil)
        XCTAssertThrowsError(try ApproovService.getServerAdjustedCurrentTimeMS()) { error in
            XCTAssertEqual(error.localizedDescription, "getServerAdjustedCurrentTimeMS: SDK not initialized")
        }
    }
}
