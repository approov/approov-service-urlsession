# Advanced Options

A standard integration needs nothing on this page. It covers the options and details behind the [README](README.md), for when you need them.

## What each request carries

The package fetches an Approov token for every request it processes, and the result decides what the request carries:

| Request to | Token header | Trace header | Secure strings | Signature | Connection |
|---|---|---|---|---|---|
| A token-protected API, token obtained | the token | when the SDK gives one | substituted | when signing is installed | checked |
| A token-protected API, no token, request proceeds | empty, or the status name | when the SDK gives one | placeholders left as written | when signing is installed | checked |
| A secrets-only API (`-noApproovToken`) | none | none | substituted | none | checked |
| Any other host | none | none | placeholders left as written | none | OS trust |

Secure strings are only substituted into an https request. A cleartext request never receives one, and the package logs a warning naming each header or query parameter it left as written.

### Secrets-only APIs

An API you added with `approov api -add <domain> -noApproovToken` needs no Approov token. Its connections are still checked against its keys, and its requests get their secure strings.

## What happens by default

The service mutator decides what happens when the token fetch does not succeed. `ApproovServiceMutator.DEFAULT` is `CLOSE_FAILURE`, which keeps the 3.5.x decisions:

| Token fetch status | `CLOSE_FAILURE` | `ALWAYS_PROCEED` |
|---|---|---|
| `SUCCESS` | sends the token | sends the token |
| `NO_APPROOV_SERVICE` | sends an empty token header | sends an empty token header |
| `NO_NETWORK`, `POOR_NETWORK`, `MITM_DETECTED` | fails with `ApproovError.networkingError`, the user can retry | sends an empty token header |
| `REJECTED` and any other failure | fails with `ApproovError.rejectionError` or `permanentError` | sends an empty token header |
| `UNKNOWN_URL`, `UNPROTECTED_URL` | adds no Approov header | adds no Approov header |

A failure only affects your Approov API domains, the hosts in your pin set. A request to any other host whose token fetch fails is sent unchanged under either mutator. While the app has no configuration yet, for example on a first launch without a network, no host is in the pin set, so nothing is blocked.

### Secure string results

A secure string is fetched for each placeholder on a request to a token-protected or secrets-only API. Neither standard mutator fails a request because of a secure string:

* `SUCCESS` replaces the placeholder with the value.
* Any other status replaces the placeholder with the status name, after any required prefix, such as `Bearer REJECTED` or `UNKNOWN_KEY` in a query parameter. Your backend sees why the secret is missing.

### Values a header or URL cannot carry

A header carries only tab and printable ASCII. A query value must come back unchanged from the URL. A secure string that cannot be carried leaves the placeholder as written, and the package logs a warning naming the header or query parameter, never the value.

### Errors your app can see

* A decision of `CLOSE_FAILURE` fails the request with an `ApproovError`, as in 3.5.x.
* A `URLError` your own mutator throws reaches your app unchanged.
* Anything else a mutator hook throws, an `ApproovError` your code throws included, fails the request with a `URLError` (`.unknown`) naming the hook, with your error as its underlying error.
* A message signing configuration error, a required body digest that cannot be generated or an unsupported algorithm, fails the request with a `URLError`.
* A connection that fails the check fails with `NSURLErrorServerCertificateUntrusted`.

A failed request fails alone. The session and its other tasks are not affected.

## Sending the status in the token header

With `ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)`, a request that proceeds without a token carries the token fetch status name, such as `NO_NETWORK` or `NO_APPROOV_SERVICE`, in place of the empty token, after any prefix. Under `CLOSE_FAILURE` this also lets `NO_NETWORK`, `POOR_NETWORK` and `MITM_DETECTED` go ahead with the status instead of failing. `REJECTED` still fails. The status is never sent to a host that is not one of your Approov API domains.

## Message signing

Message signing is **off unless you install it**. The signer, `ApproovDefaultMessageSigning`, is a service mutator. Give it a default factory and install it after `initialize`:

```swift
ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(
    ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
```

From then on, every request that carries the token header is signed with the install signature, `ecdsa-p256-sha256`. It uses a key unique to the app installation, held in the device's secure hardware. Its dictionary member is `install`.

You can add the account signature, `hmac-sha256`, with `setUseInstallAndAccountMessageSigning()` on the factory. It uses a shared account key, delivered to the app when it passes attestation. Its member is `account`. Both are members of the same `Signature` and `Signature-Input` headers, over the same covered components. Sending both means a device without secure hardware still produces a signature your backend can verify. If one signature cannot be produced, the request goes ahead with the other, or unsigned. `setUseAccountMessageSigning()` and `setUseInstallMessageSigning()` select one.

The signer makes the `CLOSE_FAILURE` decisions. Installing another mutator, passing `nil` to `setServiceMutator` or calling `initialize` removes it. To combine signing with your own decisions, call the signer's `handleInterceptorProcessedRequest` from your own mutator.

See [Installation Message Signing](https://approov.io/docs/latest/approov-usage-documentation/#installation-message-signing) and [Account Message Signing](https://approov.io/docs/latest/approov-usage-documentation/#account-message-signing).

### What the default signature covers

* the request method and target URI, exactly as the request is sent, without any fragment
* the `Approov-Token` header, and the `Approov-TraceID` header when present
* the `Authorization`, `Content-Length` and `Content-Type` headers, when present
* a SHA-256 `Content-Digest` of the body, when the body is in `httpBody`. A streamed body is not digested.
* a `created` timestamp and a 15 second `expires`, both from `ApproovService.getServerAdjustedCurrentTimeMS()`, so they follow the Approov servers' clock even when the device clock is wrong. If the Approov SDK does not provide that time, the device clock is used and a warning is logged

### Choosing the signatures and the covered components

```swift
let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
    .setUseInstallAndAccountMessageSigning()
    .setExpiresLifetime(60)
    .addOptionalHeaders(["X-Request-Id"])
let paymentsFactory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
    .setExpiresLifetime(5)

ApproovService.setServiceMutator(ApproovDefaultMessageSigning()
    .setDefaultFactory(factory)
    .putHostFactory(hostName: "payments.example.com", factory: paymentsFactory))
```

A host factory applies to requests to that host, matched without regard to case or port. The default factory applies to every other protected host. `try factory.setBodyDigestConfig(ApproovDefaultMessageSigning.DIGEST_SHA256, required: true)` makes the digest required: a body that cannot be digested then fails the request.

## Header names

`setTokenHeader(header:prefix:)` sets the token header and an optional prefix, such as `"Authorization"` and `"Bearer "`. `setTraceIDHeader(header:)` sets the trace header, and `nil` turns it off. The 3.5.x names `setApproovHeader` and `setApproovTraceIDHeader` still work and are deprecated.

## About the Approov account ID

The string you pass to `initialize` looks like `#your-account#p6nZ...=`. It names your account and carries a fingerprint of the account's public key. It is not a secret, it does not rotate, and the same value serves every app in the account. Knowing it grants nothing.

## Bypass initialization

`ApproovService.initialize(config: "")` starts the package without Approov protection: an `ApproovURLSession` then behaves like a plain `URLSession`. A later `initialize` with your account ID turns protection on. Once protection is on, an `initialize` with `""` is ignored.

## Initialize, then configure

Each `initialize` that is not ignored resets the configuration to its defaults: header names, the status flag, the service mutator, substitutions, exclusions and the binding header. The logging level is kept. Make your configuration calls after `initialize`, before the app sends protected requests. A setting applies to requests processed after it is made.

## Token binding

`setBindingHeader(header:)` binds the token to the value of a header your requests carry, such as `Authorization`. Only a hash of the value is sent to Approov. When the value changes, the next token is bound to the new value. Do not mix `setBindingHeader` with direct `setDataHashInToken` calls.

## Secure strings

`addSubstitutionHeader(header:prefix:)` names a header whose value, after the prefix, is a secure string key. `addSubstitutionQueryParam(key:)` names a query parameter whose value is a key. The package replaces each with the secure string, as described in [secure string results](#secure-string-results).

### Keys and values

A secure string key is at most 64 characters (see [secure strings](https://approov.io/docs/latest/backend-integration/secure-strings/)). For a key used in a query parameter, use only letters, digits, `.`, `_`, `~` and `-`. Every occurrence of a query parameter is substituted on its own, and nothing else in the URL changes. A `+` in a substituted query value reaches a backend that form-decodes the query as a space. A value a request cannot carry is still readable with `fetchSecureString`.

## Excluding URLs

`addExclusionURLRegex(urlRegex:)` sends requests whose URL matches the pattern without any Approov processing. Their connections are still checked. A pattern that does not compile is logged as an error and not added.

## Connection validation

The package checks the TLS connection to each domain you have added to Approov against the certificate public keys configured for the domain. For a domain with none of its own, it falls back to the Managed Trust Roots. This check is known as pinning. Hosts are matched without regard to case or a trailing dot.

A domain with no keys of its own and no Managed Trust Roots connects on OS trust, and the package logs one warning per host. If the keys cannot be read, the connection is refused.

`handlePinningShouldProcessRequest` on your mutator can turn the check off. A connection is checked once, when it is opened, so the hook is asked with a request holding only the scheme, host and port, and its answer applies to every request that reuses the connection.

### WebSockets

WebSockets are not supported. No Approov token or secure string is added to a WebSocket upgrade. Do not put a secure string placeholder on one and expect it to be substituted.

### Custom authentication challenges

The package answers server trust challenges for your API domains. Every other challenge, such as a client certificate or HTTP authentication, goes to your delegate. For shared handling, give the delegate to the session and implement `urlSession(_:didReceive:completionHandler:)`. A delegate passed to a `WithApproov` method gets the same, after the package's check.

While Approov is enabled, a task whose own `task.delegate` implements `urlSession(_:didReceive:completionHandler:)` is cancelled before it connects, since that delegate would decide server trust instead of the package. Pass that delegate to the session initializer or to a `WithApproov` method instead.

## Service mutators

A mutator changes the package's decisions. Implement `ApproovServiceMutator` and override only the hooks you need; every other hook keeps the `CLOSE_FAILURE` decision:

| Hook | Decides |
|---|---|
| `handleInterceptorShouldProcessRequest` | whether a request is processed at all |
| `handleInterceptorFetchTokenResult` | what a request carries for its token fetch status, or whether it fails |
| `handleInterceptorHeaderSubstitutionResult`, `handleInterceptorQueryParamSubstitutionResult` | whether a secure string is substituted |
| `handleInterceptorProcessedRequest` | final changes to the processed request, where signing happens |
| `handlePinningShouldProcessRequest` | whether the connection is checked |
| `handlePrecheckResult`, `handleFetchTokenResult`, `handleFetchSecureStringResult`, `handleFetchCustomJWTResult` | how the direct methods report a result |

To fail a request on your own terms, throw a `URLError` from a hook. Your app's error handling then sees an ordinary network failure. A request keeps the mutator it started with, across its redirects.

```swift
final class OwnHostsOnly: ApproovServiceMutator {
    func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult, url: String) throws -> Bool {
        if approovResults.status == .noApproovService {
            throw URLError(.cannotConnectToHost)
        }
        return try ApproovCloseFailureMutator.CLOSE_FAILURE.handleInterceptorFetchTokenResult(approovResults, url: url)
    }
}
ApproovService.setServiceMutator(OwnHostsOnly())
```

## Redirects

A redirect is protected afresh for its target. The package first removes what it added to the previous attempt, the token, trace and signature headers and the substituted secure strings, so none of them reaches another host. Your redirect delegate sees the request without them. Then the follow-up is processed as a new request: a token is fetched for the target, and secure strings are substituted only from your own placeholders and only on a protected https target. A URL the server sent is never changed.

Some things the package cannot do:

* A request to a host not added to Approov that redirects into one of your API domains arrives without protection. Add every domain your app calls, redirecting aliases included.
* A request held before it is sent is not refreshed, so a long delay can send an expired token.
* An HTTP authentication retry is not signed again.
* A download resumed from resume data is not supported, because the resume data holds the original request and its expired token.

## Multiple service layers

You can use more than one Approov package in the same app. The Approov SDK is initialized once: a later `initialize` with the same account ID is ignored, and one with a different account ID fails.

## Diagnostics

`ApproovService.setLoggingLevel(_:)` takes `.off`, `.error`, `.warning`, `.info` (the default) or `.debug`, and every line the package writes follows it. The loggable token is written at `.debug` only.

`ApproovService.getLastARC()` returns the [Attestation Response Code](https://approov.io/docs/latest/approov-usage-documentation/#attestation-response-code) of the most recent fetch the package made, without making one of its own. The `arc` claim of a loggable token is the same code. To decode one, ask the CLI for the decoding command once. It prints a `curl` command with your account's API key filled in and an `<arc>` placeholder:

```sh
approov token -showArcInfoCurl
```

Run it with the code in place of `<arc>`. The response lists the flags behind the result, for example `app-not-registered`.
