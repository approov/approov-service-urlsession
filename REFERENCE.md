# Reference

This provides a reference for the public methods defined on `ApproovService`. These are available when you import the Swift Package Manager module:

```swift
import ApproovURLSessionPackage
```

Most methods either throw an `ApproovError` or return an `ApproovUpdateResponse`. The error cases to be aware of are:

- `networkingError`: A temporary networking issue; offer a retry.
- `rejectionError`: Attestation rejected; includes ARC and rejection reasons if enabled.
- `permanentError` / `configurationError` / `initializationFailure`: Non-retryable in normal flows.

## initialize
Initializes the SDK with the config obtained using `approov sdk -getConfigString` or
in the original onboarding email. In the vast majority of integrations, `initialize` should be called **once** during app startup — typically in `application(_:didFinishLaunchingWithOptions:)` or the root view controller. Each successful call resets all service-layer configuration (substitution headers, exclusion URL regexes, binding header, service mutator, `useApproovStatusIfNoToken`) to defaults, so any configuration applied after initialization would be lost on a repeated call.

The most common scenario where `initialize` is called more than once is when **multiple service layers** coexist in the same app (e.g. `approov-service-urlsession` alongside `approov-service-alamofire`, or a React Native bridge layer). Since only one instance of the native Approov SDK can be active at any time, the second service layer's `initialize` call with the same config is handled gracefully — the native SDK reports it is already initialized, and the service layer proceeds normally. Each service layer maintains its own independent configuration state (substitution headers, exclusion regexes, etc.).

The native SDK (3.5+) accepts a same-config re-initialization by returning `false`/`NO` without error, which this service layer handles gracefully. However, calling `initialize` again with the same config still resets the service-layer state, so there is no benefit to doing so in normal app flows with a single service layer.

```swift
try ApproovService.initialize(config: "<config-string>")
```

An optional `comment` parameter is forwarded directly to the native SDK. The `comment` should be `nil` unless you are using [SDK initialization options](https://approov.io/docs/latest/approov-direct-sdk-integration/#sdk-initialization-with-options) or performing an explicit [SDK reinitialization](https://approov.io/docs/latest/approov-direct-sdk-integration/#reinitializing-the-sdk). These are advanced use cases — for example, passing `"options:no-install-key"` to disable install keys, or `"reinit"` to reset internal SDK state. Some of these flows require calling `initialize` a second time with the same config, which is fully supported by the service layer. Note that each call still resets the service-layer configuration to defaults, so any substitution headers, exclusion regexes, etc. must be re-applied after the second call.

```swift
try ApproovService.initialize(config: "<config-string>", comment: "options:no-install-key")
```

If an attempt is made to initialize with a **different** non-empty config, an `ApproovError.initializationFailure` is raised — the existing operating mode is preserved. To switch to a different config at runtime you must use the `reinit` comment flow as described in the [Approov SDK documentation](https://approov.io/docs/latest/approov-direct-sdk-integration/#reinitializing-the-sdk).

Passing an empty config string bypasses Approov SDK initialization. In that mode the service layer still reports itself as initialized, but requests are forwarded as plain `URLSession` traffic without Approov token injection, message signing, secure strings, or pinning. A later call to `initialize()` with a valid non-empty config string will then enable the native Approov SDK at runtime. By contrast, once initialized with a valid config, a subsequent empty-config call is silently ignored — the service layer cannot be downgraded from protected to bypass mode.


## isInitialized
Returns whether the service layer has been initialized.

```swift
let initialized = ApproovService.isInitialized()
```

This reports the service-layer state, not whether Approov protection is active. If initialization used an empty config string then this still returns `true`, while the layer operates without Approov support.

## isApproovEnabled
Returns whether Approov protection is currently enabled.

```swift
let enabled = ApproovService.isApproovEnabled()
```

This returns `true` only if the service layer has been initialized with a valid, non-empty configuration string. If initialized with an empty string, or not initialized at all, it returns `false`.

## setProceedOnNetworkFailure
*OBSOLETE* Use `setServiceMutator` instead to customize the behavior of the service.
Controls whether network calls should proceed when Approov cannot fetch due to network errors. Use with *CAUTION* because it may allow requests before pins are updated.

```swift
ApproovService.setProceedOnNetworkFailure(proceed: true)
```

## getProceedOnNetworkFailure
*OBSOLETE* Use `setServiceMutator` instead to customize the behavior of the service.
Returns the current setting for proceed-on-network-failure.

```swift
let proceed = ApproovService.getProceedOnNetworkFailure()
```

## setDevKey
Sets a development key indicating that the app is a development version and it should
pass attestation even if the app is not registered or it is running on an emulator. The
development key value can be rotated at any point in the account if a version of the app
containing the development key is accidentally released. This is primarily
used for situations where the app package must be modified or resigned in
some way as part of the testing process or when using Approov in a development
environment.

```swift
ApproovService.setDevKey(devKey: "<dev-key>")
```

## setApproovHeader
Sets the header that the Approov token is added on, as well as an optional
prefix String (such as "Bearer "). By default the token is provided on
"Approov-Token" with no prefix.

```swift
ApproovService.setApproovHeader(header: "Approov-Token", prefix: "Bearer ")
```

## getApproovTokenHeader
Returns the name of the header used to carry the Approov token.

```swift
let header = ApproovService.getApproovTokenHeader()
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
Sets a binding header that must be present on all requests using the Approov service. A
header should be chosen whose value is unchanging for most requests (such as an
Authorization header). A hash of the header value is supplied to Approov so the issued token can
carry the corresponding `pay` claim and be bound to the value. This may then be verified by the backend API integration. This
method should typically only be called once.

```swift
ApproovService.setBindingHeader(header: "Authorization")
```

## setUseApproovStatusIfNoToken
Sets a flag indicating if the Approov fetch status (e.g. `NO_NETWORK`, `MITM_DETECTED`) should be
used as the token header value if the actual token fetch fails or returns an empty token. This allows
passing error condition information to the backend via the Approov-Token header, which might
otherwise be empty or missing.

```swift
ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)
```

## setLoggingLevel
Sets the service-layer logging level. This controls the verbosity of unified logging (`os_log`) output generated internally by the package. All log statements are gated by this level.

Available levels (in order of increasing verbosity):
- `.off`: Disables all logging from the `ApproovService` package.
- `.error`: Only logs critical errors (e.g., initialization failures, missing pins).
- `.warning`: Logs warnings and errors (e.g., duplicated initializations with identical configurations).
- `.info` (Default): Logs informative events, configuration receipts, and the token states being set.
- `.debug`: Logs highly verbose tracing information for every request, initialization step, and token fetch.

```swift
ApproovService.setLoggingLevel(.debug)
```

## setServiceMutator
Installs a service mutator to customize behavior at key points in the service flow. Pass `nil` to restore defaults. See the `USAGE.md` for more information and a custom mutator example implementation.

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
Adds the name of a header which should be subject to secure strings substitution. This
means that if the header is present then the value will be used as a key to look up a
secure string value which will be substituted into the header value instead. This allows
easy migration to the use of secure strings. A required prefix may be specified to deal
with cases such as the use of `Bearer ` prefixed before values in an authorization header.

```swift
ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
ApproovService.addSubstitutionHeader(header: "Authorization", prefix: "Bearer ")
```

## removeSubstitutionHeader
Removes a header previously added for substitution.

```swift
ApproovService.removeSubstitutionHeader(header: "Api-Key")
```

## getSubstitutionHeaders
Returns the map of headers currently subject to secure string substitution, mapped to their required prefixes.

```swift
let headers = ApproovService.getSubstitutionHeaders()
```

## addSubstitutionQueryParam
Adds a key name for a query parameter that should be subject to secure strings substitution.
This means that if the query parameter is present in a URL then the value will be used as a
key to look up a secure string value which will be substituted as the query parameter value
instead. This allows easy migration to the use of secure strings. 

```swift
ApproovService.addSubstitutionQueryParam(key: "api_key")
```

## removeSubstitutionQueryParam
Removes a query parameter key name previously added using addSubstitutionQueryParam.

```swift
ApproovService.removeSubstitutionQueryParam(key: "api_key")
```

## getSubstitutionQueryParams
Returns the set of query parameter keys currently subject to secure string substitution.

```swift
let params = ApproovService.getSubstitutionQueryParams()
```

## addExclusionURLRegex
Adds an exclusion URL regular expression. If a URL for a request matches this regular expression
then it will not be subject to any Approov protection. Note that this facility must be used with
EXTREME CAUTION due to the impact of dynamic pinning. Pinning may be applied to all domains added
using Approov, and updates to the pins are received when an Approov fetch is performed. If you
exclude some URLs on domains that are protected with Approov, then these will be protected with
Approov pins but without a path to update the pins until a URL is used that is not excluded. Thus
you are responsible for ensuring that there is always a possibility of calling a non-excluded
URL, or you should make an explicit call to fetchToken if there are persistent pinning failures.
Conversely, use of those option may allow a connection to be established before any dynamic pins
have been received via Approov, thus potentially opening the channel to a MitM.

```swift
ApproovService.addExclusionURLRegex(urlRegex: "^https://example\\.com/unprotected/.*$")
```

## removeExclusionURLRegex
Removes an exclusion URL regular expression previously added using addExclusionURLRegex.

```swift
ApproovService.removeExclusionURLRegex(urlRegex: "^https://example\\.com/unprotected/.*$")
```

## getExclusionURLRegexs
Returns the current map of exclusion URL regular expressions and their compiled `NSRegularExpression` patterns.

```swift
let regexs = ApproovService.getExclusionURLRegexs()
```

## prefetch
*OBSOLETE* This method is obsolete and is now a no-op. The underlying Approov SDK manages prefetching automatically.


```swift
ApproovService.prefetch()
```

## precheck
Performs a precheck to determine if the app will pass attestation. This requires secure
strings to be enabled for the account, although no strings need to be set up. This will
likely require network access so may take some time to complete. It may throw an exception
if the precheck fails or if there is some other problem. Exceptions could be due to
a rejection (throws an `ApproovError.rejectionError`) type which might include additional
information regarding the rejection reason. An `ApproovError.networkingError` exception should
allow a retry operation to be performed and finally if some other error occurs an
`ApproovError.permanentError` is raised. Useful during development to check if the app will pass attestation.

```swift
try ApproovService.precheck()
```

## getDeviceID
Gets the device ID used by Approov to identify the particular device that the SDK is running on. Note
that different Approov apps on the same device will return a different ID. Moreover, the ID may be
changed by an uninstall and reinstall of the app.

```swift
let deviceId = ApproovService.getDeviceID()
```

## setDataHashInToken
Directly sets the data hash for subsequently fetched Approov tokens. If the hash is
different from any previously set value then this will cause the next token fetch operation to
fetch a new token with the correct payload data hash. The resulting token is expected to carry the
`pay` claim as a base64 encoded string of the SHA256 hash of the
data. Note that the data is hashed locally and never sent to the Approov cloud service. This method is an alternative to `setBindingHeader`. While both methods bind a header value to a token, this function sets the bound value directly, whereas `setBindingHeader` uses the value from a specified header. You should use one or the other, but not both.

```swift
ApproovService.setDataHashInToken(data: "<data-to-hash>")
```

## fetchToken
Performs an Approov token fetch for the given URL. This should be used in situations where it
is not possible to use the networking interception to add the token. This will
likely require network access so may take some time to complete. If the attestation fails
for any reason then an `ApproovError` is thrown. This will be `ApproovNetworkException` for
networking issues wher a user initiated retry of the operation should be allowed. Note that
the returned token should *NEVER* be cached by your app, you should call this function when
it is needed.

```swift
let token = try ApproovService.fetchToken(url: "https://example.com/api")
```

## getMessageSignature
*OBSOLETE* Returns a message signature using the account message signing key. Use `getAccountMessageSignature` or `getInstallMessageSignature` instead.

```swift
let signature = ApproovService.getMessageSignature(message: message)
```

## getAccountMessageSignature
Gets the signature for the given message using the account-specific signing key.
This key is transmitted to the SDK after a successful fetch if the feature is enabled.

```swift
let signature = ApproovService.getAccountMessageSignature(message: message)
```

## getInstallMessageSignature
Gets the signature for the given message using the install-specific signing key.
This key is tied to the specific app installation and is transmitted after a successful fetch.

```swift
let signature = ApproovService.getInstallMessageSignature(message: message)
```

## fetchSecureString
Fetches a secure string with the given key. If newDef is not nil then a secure string for
the particular app instance may be defined. In this case the new value is returned as the
secure string. Use of an empty string for newDef removes the string entry. Note that this
call may require network transaction and thus may block for some time, so should not be called
from the UI thread. If the attestation fails for any reason then an exception is raised. Note
that the returned string should *NEVER* be cached by your app, you should call this function when
it is needed. If the fetch fails for any reason an exception is thrown with description.
A rejection throws an `ApproovError.rejectionError` type which might include additional information
regarding the failure reason. An `ApproovError.networkingError` exception should allow a retry operation to be performed and finally, if some other error occurs, an `ApproovError.permanentError` is raised.

```swift
let value = try ApproovService.fetchSecureString(key: "api_key", newDef: nil)
```

## fetchCustomJWT
Fetches a custom JWT with the given payload. Note that this call will require network
transaction and thus will block for some time, so should not be called from the UI thread.
If the fetch fails for any reason an exception will be thrown. Exceptions could be due to
malformed JSON string provided (then an `ApproovError.permanentError` is raised), a rejection throws
an ApproovError.rejectionError type which might include additional information regarding the failure
reason. An `ApproovError.networkingError` exception should allow a retry operation to be performed. If
some other error occurs an `ApproovError.permanentError` is raised.

```swift
let jwt = try ApproovService.fetchCustomJWT(payload: "{\"claims\":{...}}")
```

## getLastARC
Gets the last [Attestation Response Code](https://ext.approov.io/docs/latest/approov-usage-documentation/#attestation-response-code) code. *WARNING* The ARC code should ideally be returned from your server as part of a rejected API call (such as for an invalid JWT token or missing token). However, if you are unable to customize your server response to include the ARC code (for example, when using a WAF service), you can use this method to obtain the ARC code. Be aware that if the device has recently experienced a network transition or temporary connectivity loss and a request has been made without an Approov Token, you might receive an incorrect or outdated ARC code from this method if connectivity is available at the time the call is made. 

```swift
let arc = ApproovService.getLastARC()
```

## updateRequestWithApproov
Updates a `URLRequest` with Approov protection (token, substitutions, etc.). Returns an `ApproovUpdateResponse` describing the decision and any error. All members of `ApproovUpdateResponse` (`request`, `decision`, `sdkMessage`, `error`) are public.

```swift
let response = ApproovService.updateRequestWithApproov(request: request, sessionConfig: session.configuration)
switch response.decision {
case .ShouldProceed:
    // use response.request
case .ShouldIgnore:
    // use original request unchanged
case .ShouldRetry:
    // retry after a delay
case .ShouldFail:
    // handle response.error
}
```

## signRequest
Convenience method that applies Approov protection to a `URLRequest` and returns the protected request directly. This is intended for use with HTTP transports that own their own `URLSession` (e.g. Apollo iOS, gRPC-Swift) where substituting `ApproovURLSession` is not possible. The returned request includes the Approov token and any header/query substitutions. Message signing headers are also applied if a signing mutator is configured (see `USAGE.md`).

The method calls `updateRequestWithApproov` internally and interprets the decision:
- `.ShouldProceed`: returns the updated (protected) request.
- `.ShouldIgnore`: returns the original request unchanged.
- `.ShouldRetry`: throws `ApproovError.networkingError` so the caller can retry.
- `.ShouldFail`: throws the underlying error (or `ApproovError.permanentError`).

Note: This method performs a synchronous Approov token fetch and may block briefly while the SDK contacts the Approov cloud. Call it from a background thread or async context to avoid blocking the main thread.

```swift
let protectedRequest = try ApproovService.signRequest(originalRequest)
```

An optional `URLSessionConfiguration` can be provided so `signRequest` can consider any session-level `httpAdditionalHeaders` for token binding and header substitution lookups (these headers are not added to the returned request):

```swift
let protectedRequest = try ApproovService.signRequest(originalRequest, sessionConfig: session.configuration)
```

> **Important — Dynamic Pinning:** `signRequest` does **not** apply dynamic TLS pinning. When you use `ApproovURLSession`, its delegate automatically validates the server's TLS certificate against Approov's dynamic pin set (`Approov.getPins("public-key-sha256")`). A plain `URLSession` bypasses this entirely. If your transport owns its own `URLSession` and delegate, you are responsible for implementing certificate pinning separately — for example by calling `Approov.getPins("public-key-sha256")` in your `URLSessionDelegate`'s `urlSession(_:didReceive:completionHandler:)` method and verifying the server certificate's SPKI hash against the returned set.

