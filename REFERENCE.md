# Reference

The public methods of `ApproovService`, and the classes you use with it. Import the module:

```swift
import ApproovURLSessionPackage
```

The direct methods throw an `ApproovError` on failure:

- `networkingError`: a temporary networking issue; offer a retry.
- `rejectionError`: attestation was rejected; it carries the ARC and rejection reasons when enabled.
- `permanentError`, `configurationError`, `initializationFailure`: not retryable in normal flows.

What a request fails with is in [errors your app can see](ADVANCED.md#errors-your-app-can-see).

## initialize

Initializes the package with your Approov account ID, from your onboarding email or `approov sdk -getConfigString`. Call it once, when your app starts. Each call that is not ignored resets the configuration (header names, the status flag, the service mutator, substitutions, exclusions and the binding header) to its defaults; the logging level is kept.

```swift
try ApproovService.initialize(config: "<your-approov-account-id>")
```

It throws `ApproovError.initializationFailure` if the account ID is not valid, or differs from the one Approov was already initialized with in this app. A call with the same account ID, for example from another Approov package, is accepted.

`""` starts the package in bypass mode, without Approov protection. A later call with your account ID turns protection on. Once protection is on, a call with `""` is ignored.

The optional `comment` is passed to Approov for [initialization options](https://docs.approov.io/direct-sdk-integration/initialization-options/#sdk-initialization-options) and is `nil` otherwise.

## isApproovServiceEnabled

Returns whether the package has been initialized, bypass mode included. `isInitialized()` is the same, under its 3.5.x name.

```swift
let initialized = ApproovService.isApproovServiceEnabled()
```

## isApproovProtectionEnabled

Returns whether Approov protection is on: `false` in bypass mode or before initialization. `isApproovEnabled()` is the same, under its 3.5.x name.

```swift
let protected = ApproovService.isApproovProtectionEnabled()
```

## setTokenHeader

Sets the header the Approov token is added on, and an optional prefix such as `"Bearer "`. A `nil` prefix means none. The default is `Approov-Token` with no prefix.

```swift
ApproovService.setTokenHeader(header: "Authorization", prefix: "Bearer ")
```

## getTokenHeader

Returns the name of the token header.

```swift
let header = ApproovService.getTokenHeader()
```

## getTokenPrefix

Returns the token prefix, or `""` for none.

```swift
let prefix = ApproovService.getTokenPrefix()
```

## setTraceIDHeader

Sets the header that carries the optional Approov TraceID, a debug value. `nil` turns it off. The default is `Approov-TraceID`.

```swift
ApproovService.setTraceIDHeader(header: nil)
```

## getTraceIDHeader

Returns the trace header name, or `nil` if it is off.

```swift
let header = ApproovService.getTraceIDHeader()
```

## setUseApproovStatusIfNoToken

When on, a request that proceeds without a token carries the token fetch status name, such as `NO_NETWORK`, in the token header instead of an empty token. Under `CLOSE_FAILURE` it also lets network failures proceed. Off by default. See [sending the status in the token header](ADVANCED.md#sending-the-status-in-the-token-header).

```swift
ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)
```

## getUseApproovStatusIfNoToken

Returns whether the status is sent in the token header.

```swift
let useStatus = ApproovService.getUseApproovStatusIfNoToken()
```

## Deprecated header names

The 3.5.x names still work and set the same values: `setApproovHeader(header:prefix:)`, `getApproovTokenHeader()`, `setApproovTraceIDHeader(header:)` and `getApproovTraceIDHeader()`.

## setLoggingLevel

Sets the package's logging level: `.off`, `.error`, `.warning`, `.info` (the default) or `.debug`. Every line the package writes follows it. The loggable token is written at `.debug` only.

```swift
ApproovService.setLoggingLevel(.debug)
```

## setServiceMutator

Installs a service mutator, which makes the request decisions. `.CLOSE_FAILURE` is the default and keeps the 3.5.x decisions, `.ALWAYS_PROCEED` never fails a request, and `ApproovDefaultMessageSigning` adds message signing. `nil` reinstates the default. See [service mutators](ADVANCED.md#service-mutators).

```swift
ApproovService.setServiceMutator(.ALWAYS_PROCEED)
```

## getServiceMutator

Returns the service mutator in force.

```swift
let mutator = ApproovService.getServiceMutator()
```

## setDevKey

Sets a [development key](https://approov.io/docs/latest/approov-usage-documentation/#using-a-development-key), so that a development build passes attestation.

```swift
ApproovService.setDevKey(devKey: "<dev-key>")
```

## setBindingHeader

Binds the Approov token to the value of a header your requests carry, such as `Authorization`. Only a hash of the value is sent to Approov. Do not mix it with `setDataHashInToken`.

```swift
ApproovService.setBindingHeader(header: "Authorization")
```

## setDataHashInToken

Binds later tokens to the given data directly, instead of a header value. Only a hash of the data is sent to Approov.

```swift
ApproovService.setDataHashInToken(data: "<data-to-hash>")
```

## setInstallAttributes

Sets an [install attributes token](https://approov.io/docs/latest/approov-usage-documentation/#application-installation-attributes), a signed JWT that is associated with this installation on later token fetches. It throws `ApproovError.permanentError` (`setInstallAttributes: SDK not initialized`) before initialization and in bypass mode.

```swift
try ApproovService.setInstallAttributes("<signed-install-attributes>")
```

## addSubstitutionHeader

Names a header whose value, after the required prefix, is a [secure string](ADVANCED.md#secure-strings) key. The package replaces it with the secure string, or with the fetch status name if there is none.

```swift
ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
ApproovService.addSubstitutionHeader(header: "Authorization", prefix: "Bearer ")
```

## removeSubstitutionHeader

Removes a header added with `addSubstitutionHeader`.

```swift
ApproovService.removeSubstitutionHeader(header: "Api-Key")
```

## getSubstitutionHeaders

Returns the substitution headers mapped to their required prefixes. Empty before initialization.

```swift
let headers = ApproovService.getSubstitutionHeaders()
```

## addSubstitutionQueryParam

Names a query parameter whose value is a secure string key. Every occurrence is substituted.

```swift
ApproovService.addSubstitutionQueryParam(key: "api_key")
```

## removeSubstitutionQueryParam

Removes a query parameter added with `addSubstitutionQueryParam`.

```swift
ApproovService.removeSubstitutionQueryParam(key: "api_key")
```

## getSubstitutionQueryParams

Returns the substitution query parameters. Empty before initialization.

```swift
let params = ApproovService.getSubstitutionQueryParams()
```

## addExclusionURLRegex

Sends requests whose URL matches the pattern without any Approov processing. Their connections are still checked. A pattern that does not compile is logged as an error and not added.

```swift
ApproovService.addExclusionURLRegex(urlRegex: "^https://example\\.com/unprotected/.*$")
```

## removeExclusionURLRegex

Removes a pattern added with `addExclusionURLRegex`.

```swift
ApproovService.removeExclusionURLRegex(urlRegex: "^https://example\\.com/unprotected/.*$")
```

## getExclusionURLRegexs

Returns the exclusion patterns mapped to their compiled forms. Empty before initialization.

```swift
let regexs = ApproovService.getExclusionURLRegexs()
```

## precheck

Checks whether the app passes attestation, for use in development. It needs secure strings to be enabled for the account. It throws `ApproovError.rejectionError` for a rejection, `networkingError` for a problem the user can retry, and `permanentError` otherwise.

```swift
try ApproovService.precheck()
```

## getDeviceID

Returns the Approov device ID of this installation, or `nil` before initialization and in bypass mode. It is different for each app on a device, and may change when the app is reinstalled.

```swift
let deviceID = ApproovService.getDeviceID()
```

## fetchToken

Fetches an Approov token for a URL, for a request the package cannot process. Never cache the token. It throws `ApproovError.networkingError` for a problem the user can retry, and another `ApproovError` otherwise.

```swift
let token = try ApproovService.fetchToken(url: "https://example.com/api")
```

## getServerAdjustedCurrentTimeMS

Returns the current time corrected to the Approov servers' clock, in milliseconds since the epoch, or the device clock if the Approov SDK does not provide it. Message signatures take their `created` and `expires` times from it. It throws `ApproovError.permanentError` before initialization and in bypass mode.

```swift
let now = try ApproovService.getServerAdjustedCurrentTimeMS()
```

## getAccountMessageSignature

Signs a message with the account message signing key, or returns `nil` if it is not available.

```swift
let signature = ApproovService.getAccountMessageSignature(message: message)
```

## getInstallMessageSignature

Signs a message with the install message signing key, which is unique to the installation, or returns `nil` if it is not available.

```swift
let signature = ApproovService.getInstallMessageSignature(message: message)
```

`getMessageSignature(message:)` is deprecated and returns the account signature. It logs a warning the first time it is called.

## fetchSecureString

Fetches the secure string for a key. A non-`nil` `newDef` defines a value for this installation, and `""` removes it. Never cache the value. It throws `ApproovError.rejectionError` for a rejection, `networkingError` for a problem the user can retry, and `permanentError` otherwise. It returns `nil` for a key that does not exist.

```swift
let value = try ApproovService.fetchSecureString(key: "api_key", newDef: nil)
```

## fetchCustomJWT

Fetches a custom JWT with the given JSON payload. It throws `ApproovError.permanentError` for a payload that is not valid JSON, and otherwise as `fetchSecureString` does.

```swift
let jwt = try ApproovService.fetchCustomJWT(payload: "{\"claims\":{}}")
```

## getLastARC

Returns the [Attestation Response Code](https://approov.io/docs/latest/approov-usage-documentation/#attestation-response-code) of the most recent token, secure string or custom JWT fetch the package made, for a request or a direct method. It makes no fetch of its own. It returns `""` if no fetch has been made, the fetch carried no ARC, or ARC is not enabled.

```swift
let arc = ApproovService.getLastARC()
```

## updateRequestWithApproov

Applies Approov protection to a `URLRequest` and returns an `ApproovUpdateResponse` with the `request`, the `decision`, the SDK's `sdkMessage` and any `error`. The `httpAdditionalHeaders` of an optional `URLSessionConfiguration` are read for binding and substitution, and not added to the request.

```swift
let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: session.configuration)
switch response.decision {
case .ShouldProceed:
    break // send response.request
case .ShouldIgnore:
    break // send the original request
case .ShouldRetry:
    break // a problem the user can retry, in response.error
case .ShouldFail:
    break // response.error
}
```

## signRequest

Applies Approov protection to a request and returns the protected copy, for a transport that owns its own `URLSession`. It returns the request unchanged for `.ShouldIgnore` and in bypass mode, and throws `response.error` otherwise: an `ApproovError` for a standard decision, the `URLError` your mutator threw to abort, or a `URLError` for any other mutator or configuration failure. Catch `Error`. It may wait for a token fetch, so do not call it on the main thread.

```swift
let protectedRequest = try ApproovService.signRequest(originalRequest, sessionConfig: session.configuration)
```

`signRequest` does not check the connection. Only an `ApproovURLSession` checks it against your domains' keys.

# ApproovURLSession

A `URLSession` that applies Approov protection to the tasks it creates. It has the initializers and task methods of `URLSession`. The `async` methods of `URLSession` cannot be overridden, so use these instead:

```swift
dataWithApproov(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)
dataWithApproov(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)
uploadWithApproov(for request: URLRequest, fromFile fileURL: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)
uploadWithApproov(for request: URLRequest, from bodyData: Data, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)
downloadWithApproov(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse)
downloadWithApproov(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse)
```

A `delegate` applies to that task only, as with `URLSession`.

`dataTaskPublisherWithApproov(for:)` returns a Combine publisher and the error that stopped protection, if any. It processes the request before it returns, so do not call it on the main thread. If the error is not `nil`, do not subscribe.

# Extension classes

## ApproovServiceMutator

The protocol of a service mutator. Every hook has a default, the `CLOSE_FAILURE` decision, so a mutator implements only the hooks it needs. The standard mutators are `.CLOSE_FAILURE`, `.ALWAYS_PROCEED` and `.DEFAULT`, which is `CLOSE_FAILURE`. `ApproovServiceMutatorDefault` is deprecated. The hooks are listed in [service mutators](ADVANCED.md#service-mutators).

## ApproovRequestMutations

What the package changed on a request, passed to `handleInterceptorProcessedRequest`: `getTokenHeaderKey()`, `getTraceIDHeaderKey()`, `getSubstitutionHeaderKeys()`, `getSubstitutionQueryParamKeys()` and `getOriginalURL()`. A header or query parameter is listed only when it received a secure string.

## ApproovDefaultMessageSigning

The message signing mutator. `setDefaultFactory(_:)` sets the factory for every protected host, and `putHostFactory(hostName:factory:)` one for a single host. `generateDefaultSignatureParametersFactory()` returns the default factory. See [message signing](ADVANCED.md#message-signing).

## SignatureParametersFactory

Builds the signature parameters for each request:

| Method | Does |
|---|---|
| `setUseInstallMessageSigning()` | the install signature only (the default) |
| `setUseAccountMessageSigning()` | the account signature only |
| `setUseInstallAndAccountMessageSigning()` | both signatures |
| `setBodyDigestConfig(_:required:)` | the body digest algorithm, `DIGEST_SHA256` or `DIGEST_SHA512`, and whether it is required |
| `setAddCreated(_:)`, `setExpiresLifetime(_:)` | the `created` and `expires` parameters |
| `setAddApproovTokenHeader(_:)`, `setAddApproovTraceIDHeader(_:)` | whether the token and trace headers are covered |
| `addOptionalHeaders(_:)` | headers covered when present |

## ApproovSessionTaskObserver

`enableLogging` is deprecated. Use `ApproovService.setLoggingLevel(.debug)`.
