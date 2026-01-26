# Reference

This provides a reference for the public methods defined on `ApproovService`. These are available when you import:

```swift
import ApproovURLSession
```

Most methods either throw an `ApproovError` or return an `ApproovUpdateResponse`. The error cases to be aware of are:

- `networkingError`: A temporary networking issue; offer a retry.
- `rejectionError`: Attestation rejected; includes ARC and rejection reasons if enabled.
- `permanentError` / `configurationError` / `initializationFailure`: Non-retryable in normal flows.

## initialize
Initializes the Approov SDK. This should be called early in app startup. Subsequent calls with a different config will throw a configuration error.

```swift
try ApproovService.initialize(config: "<config-string>")
```

Optional comment can be provided:

```swift
try ApproovService.initialize(config: "<config-string>", comment: "my-comment")
```

## setProceedOnNetworkFailure
Controls whether network calls should proceed when Approov cannot fetch due to network errors. Use with *CAUTION* because it may allow requests before pins are updated.

```swift
ApproovService.setProceedOnNetworkFailure(proceed: true)
```

## getProceedOnNetworkFailure
Returns the current setting for proceed-on-network-failure.

```swift
let proceed = ApproovService.getProceedOnNetworkFailure()
```

## setDevKey
Sets the Approov development key for development builds.

```swift
ApproovService.setDevKey(devKey: "<dev-key>")
```

## setApproovHeader
Sets the header and optional prefix used to transmit the Approov token.

```swift
ApproovService.setApproovHeader(header: "Approov-Token", prefix: "Bearer ")
```

## setApproovTraceIDHeader
Sets the header name used to carry the optional Approov TraceID. Pass `nil` to disable.

```swift
ApproovService.setApproovTraceIDHeader(header: "Approov-TraceID")
ApproovService.setApproovTraceIDHeader(header: nil)
```

## getApproovTraceIDHeader
Returns the configured TraceID header name, or `nil` if disabled.

```swift
let header = ApproovService.getApproovTraceIDHeader()
```

## setBindingHeader
Sets a header name used for token binding. If present on a request, its value is hashed and bound into the token.

```swift
ApproovService.setBindingHeader(header: "Authorization")
```

## setServiceMutator
Installs a service mutator to customize behavior at key points in the service flow. Pass `nil` to restore defaults.

```swift
ApproovService.setServiceMutator(myMutator)
ApproovService.setServiceMutator(nil)
```

## setApproovInterceptorExtensions (deprecated)
Backwards-compatible API for message signing; use `setServiceMutator` instead.

```swift
ApproovService.setApproovInterceptorExtensions(myExtensions)
```

## addSubstitutionHeader
Marks a header for secure string substitution. Optionally provide a required prefix (e.g. `"Bearer "`).

```swift
ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
ApproovService.addSubstitutionHeader(header: "Authorization", prefix: "Bearer ")
```

## removeSubstitutionHeader
Removes a header previously added for substitution.

```swift
ApproovService.removeSubstitutionHeader(header: "Api-Key")
```

## addSubstitutionQueryParam
Adds a query parameter key for secure string substitution.

```swift
ApproovService.addSubstitutionQueryParam(key: "api_key")
```

## removeSubstitutionQueryParam
Removes a previously-added query parameter substitution key.

```swift
ApproovService.removeSubstitutionQueryParam(key: "api_key")
```

## addExclusionURLRegex
Adds a regex for URLs that should be excluded from Approov protection. Use with *EXTREME CAUTION* due to dynamic pinning behavior.

```swift
ApproovService.addExclusionURLRegex(urlRegex: "^https://example\\.com/unprotected/.*$")
```

## removeExclusionURLRegex
Removes a previously-added exclusion regex.

```swift
ApproovService.removeExclusionURLRegex(urlRegex: "^https://example\\.com/unprotected/.*$")
```

## prefetch
Starts a background token fetch to reduce latency for the next request.

```swift
ApproovService.prefetch()
```

## precheck
Performs an attestation precheck using secure strings. Throws on failure.

```swift
try ApproovService.precheck()
```

## getDeviceID
Returns the Approov device ID (may be `nil` on error).

```swift
let deviceId = ApproovService.getDeviceID()
```

## setDataHashInToken
Sets a data hash to bind into subsequently fetched tokens. Use this instead of `setBindingHeader` (not both).

```swift
ApproovService.setDataHashInToken(data: "<data-to-hash>")
```

## fetchToken
Fetches an Approov token for a URL when you cannot use interception.

```swift
let token = try ApproovService.fetchToken(url: "https://example.com/api")
```

## getMessageSignature (deprecated)
Returns a message signature using the account message signing key. Prefer `getAccountMessageSignature` or `getInstallMessageSignature`.

```swift
let signature = ApproovService.getMessageSignature(message: message)
```

## getAccountMessageSignature
Returns an account message signature for the given message.

```swift
let signature = ApproovService.getAccountMessageSignature(message: message)
```

## getInstallMessageSignature
Returns an install message signature for the given message.

```swift
let signature = ApproovService.getInstallMessageSignature(message: message)
```

## fetchSecureString
Fetches a secure string. If `newDef` is provided, defines or updates the secure string for this installation.

```swift
let value = try ApproovService.fetchSecureString(key: "api_key", newDef: nil)
```

## fetchCustomJWT
Fetches a custom JWT for the given JSON payload.

```swift
let jwt = try ApproovService.fetchCustomJWT(payload: "{\"claims\":{...}}")
```

## getLastARC
Returns the last known Attestation Response Code (ARC), or an empty string if unavailable.

```swift
let arc = ApproovService.getLastARC()
```

## updateRequestWithApproov
Updates a `URLRequest` with Approov protection (token, substitutions, etc.). Returns an `ApproovUpdateResponse` describing the decision and any error.

```swift
let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: session.configuration)
```
