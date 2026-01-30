# Approov Service Mutator

The `ApproovServiceMutator` allows you to customize the behavior of the Approov URLSession layer at key points in the request lifecycle. You can override specific methods to tailor the handling of attestations and requests while retaining the default behavior for other cases.

## Why use a mutator

- Centralize app-specific policy without forking the service layer.
- Add telemetry on rejections or network failures.
- Skip Approov processing for health checks or local endpoints.
- Customize pinning decisions per request.
- Adjust behavior when token or secure string fetches fail.

## Default Behavior

By default, the `ApproovService` processes requests based on the status of the Approov token fetch. Note that the SDK only knows if an attestation token has been obtained; it cannot determine if the token is valid (validity is checked by your backend).

| Approov Fetch Status | Action | Result |
| :--- | :--- | :--- |
| **Success** | Proceed | The request acts as expected and is sent with the `Approov-Token`. |
| **No Network / Poor Network** | Throw Exception | An `ApproovError.networkingError` is thrown. The request is marked as `.ShouldRetry`. |
| **Rejection** | Throw Exception | An `ApproovError.rejectionError` is thrown. The request is marked as `.ShouldFail`. |
| **No Approov Service / Unknown URL** | Proceed | The request is sent **without** an `Approov-Token`. |

## Customizing Request Handling with Mutators

You may want to modify this behavior to suit specific app requirements. A common use case is handling `NO_APPROOV_SERVICE` statuses.

### Prevent Access Without a Token (e.g. NO_APPROOV_SERVICE)

The standard behavior for statuses like `NO_APPROOV_SERVICE` is to proceed with the request without adding an Approov token. This might occur, for example, if a device cannot connect to the Approov cloud due to a restricted network environment. You may wish to prevent this behavior to ensure that *only* requests with valid proof of attestation reach your backend API, allowing you to explicitly handle this case within your application.

You can use a mutator to enforce this policy by throwing an error or returning `false` for such statuses.

### Example: Enforce Token Presence

Override `handleInterceptorFetchTokenResult` to check for `noApproovService` and prevent the request to your API from continuing; instead log the event. Since `NO_APPROOV_SERVICE` implies the SDK cannot reach the Approov servers, this could be a transient issue (e.g., no DNS server available) or a permanent configuration/network restriction. You might choose to retry the request once to handle transient errors, or if the issue persists, inform the user of a network issue and suggest checking their connection or changing networks.

```swift
import ApproovURLSession
import Approov

final class EnforceTokenMutator: ApproovServiceMutator {
    func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult, url: String) throws -> Bool {
        // If the service is not available (NO_APPROOV_SERVICE), do not proceed.
        // This could be transient (e.g. no DNS) so we throw a networking error to trigger a retry.
        if approovResults.status == .noApproovService {
            throw ApproovError.networkingError(message: "Network issue. Will attempt connection again.")
        }

        // For all other statuses, use the default behavior.
        return try ApproovServiceMutatorDefault.shared.handleInterceptorFetchTokenResult(approovResults, url: url)
    }
```

### Allow Access Without Token (Optional)

Conversely, if the device could not obtain proof of attestation, for example because of a `.poorNetwork` or `.noNetwork` response from the SDK, the default behavior is to cancel the request to your API. However, you might prefer to let the request attempt the connection to your backend without the Approov Token to allow for server-side handling (e.g., returning a custom 401/403).

To implement this, check for `.poorNetwork` and return `true`, which proceeds without the token.

```swift
    if approovResults.status == .noApproovService {
        return true // Proceed without token
    }
}
```

## How to use a custom mutator in your application

Create a mutator, then install it once during app startup (for example in your AppDelegate or app initialization path).

```swift
import ApproovURLSession
import Approov

final class MyMutator: ApproovServiceMutator {
    // Override only the hooks you need.
}
ApproovService.setServiceMutator(MyMutator()) // Install custom implementation or pass nil to revert to default behaviour
```



## Message signing

It is possible to sign HTTP requests using Approov to ensure message integrity and authenticity. There are two types of message signing available:

1.  [Installation Message Signing](https://ext.approov.io/docs/latest/approov-usage-documentation/#installation-message-signing): Uses an installation-specific key (held in the device's Secure Enclave/TEE) to sign requests. This provides strong non-repudiation as the signing key never leaves the device and is unique to that specific installation.
2.  [Account Message Signing](https://ext.approov.io/docs/latest/approov-usage-documentation/#account-message-signing): Uses a shared account-specific secret key (HMAC-SHA256) to sign requests. This key is delivered to the SDK only upon successful attestation.

**Advantages of Message Signing:**
*   **Integrity:** Ensures that the request parameters (headers, body, URL) have not been tampered with during transit.
*   **Authenticity:** Proves that the request originated from a genuine, attested application instance.

Message signing is not enabled unless you opt in. By default, the `ApproovService` uses the class `ApproovServiceMutatorDefault`, which does no message signing. Even if you install `ApproovDefaultMessageSigning`, a signature is only added when:

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

This example implementation demonstrates how to customize the `ApproovServiceMutator` to apply different options to API requests based on the hostname.

```swift
import ApproovURLSession

final class CustomLogic: ApproovServiceMutator {
    private let signer: ApproovServiceMutator
    private let protectedHosts: Set<String> // Hosts that require an Approov token
    private let allowOfflineForHosts: Set<String> // Hosts that allow requests without an Approov token
    private let skipPinningHosts: Set<String> // Hosts that skip pinning

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
```

### Log rejections with ARC + device ID to your telemetry

An important part of your security strategy is to monitor and analyze rejections. This example shows how to log rejections with the ARC and device ID to your telemetry. It assumes you are using a custom `ApproovServiceMutator` that prevents requests from proceeding without an Approov token. If this is not the case, and a request is made in poor network conditions, there is a small chance that `getLastARC()` will be executed just as an attestation completes. This would provide an ARC, even though the original request timed out without one. The following code is a simple example of how to do this.

```swift
        if let httpResponse = response.response {
            let code = httpResponse.statusCode
            if code == 200 {
                // Process request
            } else {
                // Log rejection: ARC + device ID can beadded for correlating a particular request to the failure reason
                let arc = ApproovService.getLastARC() // We are certain we have an ARC code because our custom ApproovServiceMutator prevents requests without an Approov token to proceed
                let deviceID = ApproovService.getDeviceID()
                // Log rejection
                myLogger.log("Request rejected with ARC: \(arc) and device ID: \(deviceID); response code: \(code)")
            }
        }
```

## Tips

- Keep mutator logic fast and side-effect safe. These hooks run on the request path.
- Use `ApproovServiceMutatorDefault.shared` to preserve the existing behavior and layer your changes on top.
- If you override multiple hooks, keep them focused (one concern per hook) for easier testing and maintenance.


