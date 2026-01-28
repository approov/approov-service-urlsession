# Approov Service Mutator

The Approov service mutator lets you customize how the Approov URLSession layer behaves at key points in the attestation and request flow. You override only the hooks you care about and keep the default behavior for everything else.

## Why use a mutator

- Centralize app-specific policy without forking the service layer.
- Add telemetry on rejections or network failures.
- Skip Approov processing for health checks or local endpoints.
- Customize pinning decisions per request.
- Adjust behavior when token or secure string fetches fail.

## How to install in your app

Create a mutator, then install it once during app startup (for example in your AppDelegate or app initialization path).

```swift
import ApproovURLSession

final class MyMutator: ApproovServiceMutator {
    // Override only the hooks you need.
}

// Install (or pass nil to restore defaults)
ApproovService.setServiceMutator(MyMutator())
```

## Message signing (default: off)

Message signing is not enabled unless you opt in. By default, `ApproovService` uses
`ApproovServiceMutatorDefault`, which does no signing. Even if you install
`ApproovDefaultMessageSigning`, a signature is only added when:

- The request already has an `Approov-Token` header (i.e., Approov processing ran).
- A `SignatureParametersFactory` is configured (default or host-specific).

### Enable with default settings

```swift
let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)
ApproovService.setServiceMutator(signer)
```

### Customize behavior

```swift
let factory = SignatureParametersFactory()
    .setUseAccountMessageSigning() // or setUseInstallMessageSigning()
    .setAddCreated(true)
    .setExpiresLifetime(60)

let signer = ApproovDefaultMessageSigning()
    .setDefaultFactory(factory)
    .putHostFactory(hostName: "api.example.com", factory: factory)

ApproovService.setServiceMutator(signer)
```

To disable signing, remove the signer (`setServiceMutator(nil)`) or return `nil`
from your factory for hosts you want to skip. If you have custom mutator logic,
call the signer from `handleInterceptorProcessedRequest` (see example below).

## Real-world examples

### Policy-driven mutator (host scoping, offline fallback, message signing, pinning)

```swift
import ApproovURLSession

final class CustomLogic: ApproovServiceMutator {
    private let signer: ApproovServiceMutator
    private let protectedHosts: Set<String>
    private let allowOfflineForHosts: Set<String>
    private let skipPinningHosts: Set<String>

    init(
        signer: ApproovServiceMutator = ApproovDefaultMessageSigning(),
        protectedHosts: Set<String> = ["api.example.com"],
        allowOfflineForHosts: Set<String> = ["status.example.com"],
        skipPinningHosts: Set<String> = ["metrics.example.com"]
    ) {
        self.signer = signer
        self.protectedHosts = protectedHosts
        self.allowOfflineForHosts = allowOfflineForHosts
        self.skipPinningHosts = skipPinningHosts
    }

    func handleInterceptorShouldProcessRequest(_ request: URLRequest) throws -> Bool {
        guard let host = request.url?.host, protectedHosts.contains(host) else { return false }
        return try ApproovServiceMutatorDefault.shared.handleInterceptorShouldProcessRequest(request)
    }

    func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult,
                                           url: String) throws -> Bool {
        if approovResults.status == .noNetwork || approovResults.status == .poorNetwork,
           let host = URL(string: url)?.host, allowOfflineForHosts.contains(host) {
            return false
        }
        return try ApproovServiceMutatorDefault.shared
            .handleInterceptorFetchTokenResult(approovResults, url: url)
    }

    func handleInterceptorProcessedRequest(_ request: URLRequest,
                                           changes: ApproovRequestMutations) throws -> URLRequest {
        var req = try signer.handleInterceptorProcessedRequest(request, changes: changes)
        req.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        return req
    }

    func handlePinningShouldProcessRequest(_ request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return true }
        return !skipPinningHosts.contains(host)
    }
}
```

### Log rejections with ARC + device ID to your telemetry

```swift
final class LoggingMutator: ApproovServiceMutator {
    func handlePrecheckResult(_ approovResults: ApproovTokenFetchResult) throws {
        if approovResults.status == .rejected {
            let arc = approovResults.arc ?? ""
            let deviceID = ApproovService.getDeviceID() ?? ""
            let reasons = approovResults.rejectionReasons.joined(separator: ",")
            MyTelemetry.log(event: "approov_rejected", fields: [
                "arc": arc, "device_id": deviceID, "reasons": reasons
            ])
        }
        try ApproovServiceMutatorDefault.shared.handlePrecheckResult(approovResults)
    }
}
```

## Tips

- Keep mutator logic fast and side-effect safe. These hooks run on the request path.
- Use `ApproovServiceMutatorDefault.shared` to preserve the existing behavior and layer your changes on top.
- If you override multiple hooks, keep them focused (one concern per hook) for easier testing and maintenance.

## Reference

- [Approov SDK fetch status handling](https://ext.approov.io/docs/latest/approov-direct-sdk-integration/#fetch-status-handling)
