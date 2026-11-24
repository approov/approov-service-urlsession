# Advanced Options

The `approov-service-urlsession` package works through an `ApproovURLSession`. After you call `initialize` with your account ID, the package adds an Approov token to each request to your API domains. The token is a signed JWT that provides proof of attestation, which your backend can check.

A standard integration of the Approov Package for URLSession needs nothing from this document. You add the dependency, initialize, and use an `ApproovURLSession`, as the [README](README.md) shows. The options below change the defaults, suitable for applications with specific needs. You can find every method used in this document in [REFERENCE.md](REFERENCE.md).

| What you need | Read |
| :--- | :--- |
| Understand what reaches your backend | [What each request carries](#what-each-request-carries), then [What happens by default](#what-happens-by-default) |
| Change how network failures are handled | [What happens by default](#what-happens-by-default), then [Service mutators](#service-mutators) |
| Protect request contents with signatures | [Message signing](#message-signing), then [Account Message Signing](https://docs.approov.io/operations/message-signing/account/) |
| Replace an embedded API secret | [Secure strings](#secure-strings) |
| Configure startup or runtime activation | [Initialize, then configure](#initialize-then-configure), then [Bypass initialization](#bypass-initialization) |
| Investigate an unexpected result | [Diagnostics](#diagnostics), then [Errors your app can see](#errors-your-app-can-see) |

## What each request carries

What the package adds to a request depends on two things:

* the kind of host: a token-protected API domain, a secrets-only API domain, or a host not protected by Approov (one you have not added)
* the outcome of the attestation attempt for the request

Based on the attestation outcome and the kind of host, the package and its [service mutator](#service-mutators) decide what to add to the request. They also decide whether the request goes ahead at all.

| Request goes to | Outcome | What the package adds |
| :--- | :--- | :--- |
| a token-protected domain: an API domain you added to Approov | `SUCCESS` | the token header, and the trace header when the SDK gives a trace ID. Your secure strings, or the [status of each one that could not be fetched](#secure-strings). The signatures, once you install [message signing](#message-signing). A checked connection. |
| a secrets-only domain: an API domain you added with `approov api -add <domain> -noApproovToken` | `UNPROTECTED_URL` | your secure strings, or the status of each one that could not be fetched. A checked connection. No token or trace header, and no signatures. |
| a host not protected by Approov | `UNKNOWN_URL` | nothing. The connection relies on OS trust. |
| a token-fetch failure, to a host protected by Approov | a failure status | depends on the service mutator (see below) |
| a token-fetch failure, to a host not protected by Approov | a failure status | nothing (see below) |

A failure status means the app could not complete the attestation. For example, there was no network, or the Approov service could not be reached. The [service mutator](#what-happens-by-default) then decides whether the request fails in the app or is sent. A request that is sent carries the `Approov-Token` header with an empty token after any prefix. If you turned on [setUseApproovStatusIfNoToken](#sending-the-status-in-the-token-header), it carries the status name instead. It has the trace header when the SDK gives a trace ID, and no secure strings.

For a host not protected by Approov, the request goes out unchanged, whatever the outcome. The standard mutators never fail it in the app. Only your own mutator can, by throwing from `handleInterceptorFetchTokenResult` (see [Service mutators](#service-mutators)).

The headers your backend may receive:

* `Approov-Token` carries the Approov token, or is empty (or holds the [status](#sending-the-status-in-the-token-header)) when no token could be fetched. Only your backend can tell from the token whether the app passed. See [Approov tokens](https://docs.approov.io/core-concepts/approov-tokens/architecture-and-security/).
* `Signature` and `Signature-Input` carry the signatures, once you install [message signing](#message-signing). `Content-Digest` carries the body digest that they cover.
* `Approov-TraceID` is an optional debug header. Your backend passes it through unchanged.

Whatever the attestation outcome, an `ApproovURLSession` checks the TLS connection to each domain you added, token-protected or secrets-only (see [Connection validation](#connection-validation)).

## What happens by default

The package processes a task when your app first resumes it. For every request it processes, it fetches an Approov token for the request URL. It does not process a request before `initialize` or in [bypass mode](#bypass-initialization), a [WebSocket](#websockets) upgrade, or a request to an [excluded URL](#excluding-urls). It then applies the decisions of the installed [service mutator](#service-mutators). The package provides three standard ones:

* `.CLOSE_FAILURE` keeps the 3.5.x token decisions for your API domains. A failed token fetch fails the request in the app, with an `ApproovError` as in 3.5.x.
* `.ALWAYS_PROCEED` never fails a request because of its token fetch. Whatever the token fetch outcome, the request is sent, and your backend decides. Your backend is then the enforcement point.
* `.DEFAULT` is the mutator installed out of the box. `setServiceMutator(nil)` puts it back, and so does each `initialize` that succeeds. `.DEFAULT` points to whatever the release considers default behaviour, which is currently `.CLOSE_FAILURE`.

To opt in to always proceeding:

```swift
ApproovService.setServiceMutator(.ALWAYS_PROCEED)
```

In the table below, "an Approov protected host" means one of the API domains you added to Approov, of either kind.

| Approov token fetch status | `CLOSE_FAILURE` (default) | `ALWAYS_PROCEED` |
| :--- | :--- | :--- |
| `SUCCESS` | proceeds with the token, any trace header, the secure strings and, with message signing installed, the signatures | same |
| `UNPROTECTED_URL` (secrets-only API) | proceeds with the secure strings only, no Approov headers | same |
| `UNKNOWN_URL` (host not protected by Approov) | proceeds untouched | same |
| `NO_APPROOV_SERVICE`, Approov protected host | proceeds with an empty token header (or the status), but no secure strings | same |
| `NO_NETWORK`, `POOR_NETWORK`, `MITM_DETECTED`, Approov protected host | fails with `ApproovError.networkingError`, which the user can retry. With `setUseApproovStatusIfNoToken(shouldUse: true)` it proceeds with the status in the token header instead | proceeds with an empty token header (or the status), but no secure strings |
| any other status (`REJECTED`, `INTERNAL_ERROR`, `BAD_URL`, ...), Approov protected host | fails with `ApproovError.permanentError` | proceeds with an empty token header (or the status), but no secure strings |
| any failure status, host not protected by Approov, or any host before the app has its first Approov configuration | proceeds untouched, and no standard mutator fails it | same |

"The status" in this table means the status name in the token header, after any prefix. A request that goes ahead after a failed token fetch also carries the trace header when the SDK gives a trace ID. It is signed too, if you installed [message signing](#message-signing).

`NO_APPROOV_SERVICE` means the app could not reach the Approov service or its failover.

These are the token fetch decisions only. Under either mutator, these still fail the request:

* a TLS connection that fails the check
* an abort that your own hooks ask for
* a message signing configuration error

### Sending the status in the token header

With `ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)`, a request that proceeds without a token carries the status name, such as `NO_NETWORK`, after any prefix. Under `CLOSE_FAILURE` the network statuses then proceed instead of failing, and `REJECTED` still fails. A host not protected by Approov never receives the status.

### Errors your app can see

A request that fails reports its error to the completion handler, the `async` caller or your delegate's `urlSession(_:task:didCompleteWithError:)`:

* A `CLOSE_FAILURE` decision fails the request with an `ApproovError`, as in 3.5.x.
* A `URLError` that your own mutator throws reaches your app unchanged.
* If your mutator throws any other error, `ApproovError` included, the package wraps it in a `URLError` with code `.unknown`. Its message names the hook, for example `ApproovServiceMutator.handleInterceptorProcessedRequest failed: ...`. Your original error is in its `userInfo` under `NSUnderlyingErrorKey`.
* A message signing configuration error fails the request with a `URLError`. This is a required body digest that cannot be generated, or an unsupported algorithm from a custom configuration.
* A connection that fails the check fails with `NSURLErrorServerCertificateUntrusted`.

A failed request fails alone. The session and its other tasks are not affected.

## Message signing

The signer, `ApproovDefaultMessageSigning`, adds RFC 9421 message signatures to every request that carries the Approov token header.

Message signing is **off unless you install it**. If you do not need signatures, keep the default and install nothing.

The signer is implemented as a service mutator, so installing another mutator, passing `nil` to `setServiceMutator` or an `initialize` that succeeds removes it. The signer makes the standard decisions, the same as `CLOSE_FAILURE`. If those suit you, give it a default factory and install it right after `initialize`, as in the example. To sign under other decisions, such as `ALWAYS_PROCEED`, combine them with the signer in a mutator of your own, as shown below.

```swift
ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(
    ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
```

Once the signer is installed, every request that carries the Approov token header is signed with the install signature, `ecdsa-p256-sha256`. It uses a key unique to the app installation. The private key is held in the Secure Enclave and never leaves the device. Its dictionary member is `install`.

You can add the account signature, `hmac-sha256`, with `setUseInstallAndAccountMessageSigning()` on the factory. It uses a shared account key, delivered to the app when it passes attestation. Its member is `account`. Both are members of the same `Signature` and `Signature-Input` headers, over the same covered components. If one signature cannot be produced, the request goes ahead with the other, or unsigned. `setUseAccountMessageSigning()` and `setUseInstallMessageSigning()` select one signature only.

A request to a secrets-only API that the SDK reports as `UNPROTECTED_URL` carries no token header and is not signed. A request to an Approov protected host can go ahead after a failed token fetch. It then still carries the token header, empty or with the status. So the signer signs it too, over that value.

To sign under other decisions, combine them with the signer in a mutator of your own. Your mutator makes its decisions and calls the signer from its `handleInterceptorProcessedRequest`. This mutator makes the `ALWAYS_PROCEED` token decisions and signs:

```swift
import Approov
import ApproovURLSessionPackage

final class ProceedAndSign: ApproovServiceMutator {
    private let signer = ApproovDefaultMessageSigning().setDefaultFactory(
        ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory())

    func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult, url: String) throws -> Bool {
        return try ApproovAlwaysProceedMutator.ALWAYS_PROCEED.handleInterceptorFetchTokenResult(approovResults, url: url)
    }

    func handleInterceptorProcessedRequest(_ request: URLRequest, changes: ApproovRequestMutations) throws -> URLRequest {
        return try signer.handleInterceptorProcessedRequest(request, changes: changes)
    }
}

ApproovService.setServiceMutator(ProceedAndSign())
```

When you write such a mutator:

* Keep your `handleInterceptorProcessedRequest` safe to repeat. The package calls it again for each redirect, so the follow-up is signed again for its target. There is no hook to turn this on or off.
* To change the request before it is signed, make your change first and then call the signer.
* Let an error from the signer propagate unchanged. A required body digest that cannot be generated then fails the request, as it does when the signer is installed on its own.

Your backend receives `Signature` and `Signature-Input` headers whose members include `install`, `account` or both. A signature that cannot be produced is logged as an error, such as `ApproovService: install message signature unavailable, leaving it out`.

Your backend verifies the signatures as [Installation Message Signing](https://docs.approov.io/operations/message-signing/installation/) and [Account Message Signing](https://docs.approov.io/operations/message-signing/account/) describe.

### What the default signature covers

* the request method and target URI, exactly as the request is sent, without any fragment
* the token header, and the trace header when the package added one
* the `Authorization`, `Content-Length` and `Content-Type` headers, when present
* a SHA-256 `Content-Digest` of the body, when the body is in `httpBody`. The package does not digest a streamed body.
* a `created` timestamp and a 15 second `expires`, from [getServerAdjustedCurrentTimeMS](REFERENCE.md#getserveradjustedcurrenttimems). After the app's first attestation this follows the Approov servers' clock, so a wrong device clock does not move them outside your backend's window

The [SignatureParametersFactory](REFERENCE.md#signatureparametersfactory) methods change these choices, and `putHostFactory(hostName:factory:)` sets a factory for one host. A required body digest, set with `setBodyDigestConfig(_:required:)`, fails each request without a body in `httpBody`.

## Header names

You can change the name of the token header and the trace header, and the prefix in front of the token. By default, the token goes in `Approov-Token` with no prefix, and the trace ID in `Approov-TraceID`.

Change them when your backend expects the token in another header, such as `Authorization` with a `Bearer ` prefix, or does not want the trace header. Passing `nil` turns the trace header off.

```swift
ApproovService.setTokenHeader(header: "Authorization", prefix: "Bearer ")   // default "Approov-Token", no prefix
ApproovService.setTraceIDHeader(header: nil)                                // default "Approov-TraceID", nil disables
```

The 3.5.x names `setApproovHeader` and `setApproovTraceIDHeader` still work and are deprecated. Each `initialize` that succeeds puts these back to their defaults, so set them after it.

## Bypass initialization

Initialize with an empty string instead of the account ID to start the package in bypass mode. In bypass mode the package is enabled but protects nothing: `isApproovServiceEnabled()` is `true` and `isApproovProtectionEnabled()` is `false`. In this mode:

* requests through an `ApproovURLSession` go out with no Approov processing. There is no token, signing, secure strings or Approov connection check, only OS trust.
* the methods that call the SDK do not call it. Those that return a result throw `ApproovError.permanentError` or return `nil`.

Before any `initialize`, a request is handled the same way as in bypass mode. It is neither failed nor held.

Bypass mode is a starting or fallback state. Use it, for example, while your app fetches the account ID remotely. The README example also uses it as a guard, in case the account ID does not reach the app intact.

```swift
try ApproovService.initialize(config: "")
```

A later `initialize` with the account ID turns Approov on at runtime, if the SDK accepts it. Like each `initialize` that succeeds, it resets the configuration to its defaults, so make your configuration calls again after it. An `ApproovURLSession` you already created protects its requests from then on.

Once protection is on, the package ignores an `initialize` with an empty string, and resets nothing. It logs `ApproovService already initialized with a valid config; ignoring empty configuration` at `.info`. The SDK rejects a later `initialize` with a different account ID or a different comment. The package then throws `ApproovError.initializationFailure`, and its state is unchanged. See [initialize in the reference](REFERENCE.md#initialize).

## Initialize, then configure

You normally initialize the package once. Call `initialize` and handle any error it throws. It is synchronous and returns without waiting for the network. Then make every configuration call your app needs, such as:

* the token, trace and binding headers, and `setUseApproovStatusIfNoToken`
* substitution headers and query parameters
* exclusion regular expressions
* the service mutator, and so message signing
* the logging level

Until your configuration calls run, requests use the defaults. A setting applies to requests that the package processes after you make it.

```swift
try ApproovService.initialize(config: "<your-approov-account-id>")
ApproovService.setServiceMutator(.ALWAYS_PROCEED)
```

Configure immediately after `initialize`, before the app sends protected requests. The [README](README.md#initializing) shows where to call `initialize`.

Each `initialize` that succeeds resets these settings to their defaults:

* the token, trace and binding headers
* `setUseApproovStatusIfNoToken`
* the substitutions and the exclusions
* the service mutator

It also clears `getLastARC()`. It keeps the logging level. Any other setting made before `initialize` is lost.

Two kinds of `initialize` change nothing: an empty account ID after protection is on, and a call that the SDK rejects (see [Bypass initialization](#bypass-initialization)). A repeat call with the same account ID and comment succeeds, for example from another Approov package in the same app. It resets this package's configuration too.

When the SDK initializes, `initialize` logs `ApproovService: Approov SDK initialized` at `.info`. When the SDK was already initialized with the same account ID and comment, it logs `ApproovService: Approov SDK already initialized` at `.info`.

### About the Approov account ID

The string you pass to `initialize` looks like `#your-account#p6nZ...=`. It names your account and ends with a hash of the account's public key, which the SDK checks. The same value serves every app in the account, and it is not a secret.

## Token binding

[Token binding](https://docs.approov.io/backend-integration/token-binding/) ties the Approov token to the value of a header on the request, typically an OAuth `Authorization` header. A token then cannot be replayed with different credentials.

There is no binding header by default. Set one when your requests carry a credential header, such as an OAuth `Authorization` header, whose value changes rarely, such as a long-lived OAuth token. Each new value makes the SDK fetch a new token from the Approov service.

```swift
ApproovService.setBindingHeader(header: "Authorization")
```

The package reads the value from the request, or else from the session configuration's `httpAdditionalHeaders`. It matches the exact name you set, so spell it as your requests do.

The SDK holds one binding value for the whole app. For every request that carries the binding header, the package sets that value just before it fetches the token. These are two separate steps. So a token can carry the value of another request, when requests with different values are in flight at once.

The package binds each redirect again. Do not mix `setBindingHeader` with direct `setDataHashInToken` calls, because both set the same SDK value.

The call logs `ApproovService: setBindingHeader: <name>` at `.debug`, and the token your backend receives carries the `pay` claim.

## Secure strings

[Secure strings](https://docs.approov.io/backend-integration/secure-strings/) let you remove API keys and other secrets from your app. An app that passes attestation gets them at runtime from the Approov service. You put a placeholder in a request header or query parameter, and the package replaces it with the secret before the request is sent.

By default there are no substitution headers or query parameters, so a secure string placeholder goes out unchanged. Register the headers and query parameters whose values are secure string keys.

```swift
ApproovService.addSubstitutionHeader(header: "X-Api-Key", prefix: nil)         // whole value is the key
ApproovService.addSubstitutionHeader(header: "Authorization", prefix: "Bearer ") // value after the prefix is the key
ApproovService.addSubstitutionQueryParam(key: "api_key")
```

The package substitutes only on an https request to a secrets-only domain, or to a token-protected domain after a successful token fetch. If a value's secure string fetch fails, the value is replaced by the fetch status name and the request goes ahead. `UNKNOWN_KEY` is the exception: no secure string is defined for that value, so it is left as your app wrote it. Neither standard mutator fails a request because of a secure string.

Header names are matched without regard to case. The package substitutes every occurrence of a query parameter on its own, and changes nothing else in the URL.

The package leaves a placeholder as written, and logs a warning that names the header or query parameter, in two cases. The first is a cleartext request. The second is a secret that a header or the URL cannot carry unchanged. A header carries only tab and printable ASCII.

Your backend receives the secret in place of the key. When it does not, the value it receives gives the reason: a status name such as `REJECTED`, or the key itself. The package logs each fetch at `.debug`, such as `ApproovService: header substitution: X-Api-Key, REJECTED, ARC: <arc>` (see [Diagnostics](#diagnostics)).

## Excluding URLs

Requests whose URL contains a match for an exclusion regular expression are sent untouched, without a token fetch. The expression is not anchored, and the package compares it with the full URL, query included. Use `^` and `$` to match the whole URL. The default `handleInterceptorShouldProcessRequest` applies the exclusions. A mutator that overrides it drops them, unless it calls `ApproovCloseFailureMutator.CLOSE_FAILURE.handleInterceptorShouldProcessRequest(request)`.

There are no exclusions by default. Use them for requests to your API domains that should not fetch a token, such as a health check.

```swift
ApproovService.addExclusionURLRegex(urlRegex: "^https://api\\.example\\.com/health.*")
```

Connection checks still apply to excluded requests on domains added to Approov. Each `initialize` that succeeds resets the exclusions.

`addExclusionURLRegex` logs the expression at `.debug`. An invalid regular expression is logged as an error and nothing is added.

## Connection validation

An `ApproovURLSession` checks the TLS connection to each domain you added to Approov, matched without regard to case or a trailing dot. It checks against the certificate public keys configured for the domain. For a domain with none defined, it falls back to the Managed Trust Roots. With neither, the connection relies on OS trust, and the package logs one warning per host.

It is on by default for every domain you added to Approov. The OS first evaluates the certificate chain. The package then compares the public key of each certificate in that chain with the keys for the domain. A request whose connection fails either check fails with `NSURLErrorServerCertificateUntrusted`. The `dataTaskPublisherWithApproov` publisher reports `NSURLErrorCancelled` instead. If the keys cannot be read, the connection is refused. `signRequest` does not check the connection.

A failure logs an error that names the host, such as `ApproovService: pin verification failed for api.example.com with no match for 2 pins`.

`handlePinningShouldProcessRequest` on your mutator can turn the check off. The package checks a connection once, when it is opened. So the hook can get a request that holds only the scheme, host and port. Its answer applies to every request that reuses the connection.

### WebSockets

WebSockets are not supported. No Approov token or secure string is added to a WebSocket upgrade. Do not put a secure string placeholder on one and expect it to be substituted.

### Custom authentication challenges

The package answers server trust challenges. Every other challenge, such as a client certificate or HTTP authentication, goes to your delegate. Give the delegate to the session, or to a `WithApproov` method, and implement `urlSession(_:didReceive:completionHandler:)`.

While Approov protection is on, the package cancels a task before it connects if the task's own `task.delegate` implements `urlSession(_:didReceive:completionHandler:)` or `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)`. That delegate would decide server trust or redirects instead of the package. Pass that delegate to the session initializer or to a `WithApproov` method instead.

## Redirects

A redirect is protected again for its target. First, the package removes what it added to the previous attempt: the token, trace and signature headers, and the secure strings. So none of them reaches another host, and your redirect delegate sees the request without them. Then the package processes the follow-up as a new request, with a token fetch for the target URL.

A request keeps the mutator it started with, across its redirects. If that mutator fails the follow-up, a completion handler or an `async` caller gets your error. It does not get `NSURLErrorCancelled` or the redirect response.

Some things the package cannot do:

* It follows a redirect unchanged when it did not change the first request. So a host not added to Approov that redirects into one of your API domains sends the follow-up without protection. Add every domain your app calls, redirecting aliases included.
* It does not refresh a request held before it is sent, so a long delay can send an expired token.
* It does not sign an HTTP authentication retry again.
* It does not support a download resumed from resume data, which holds the original request and its expired token.

## Service mutators

A service mutator, an `ApproovServiceMutator`, is the object that holds the package's decisions, such as whether a failed token fetch fails the request. It has one method for each decision, and the package asks the installed mutator at each decision point. The standard mutators and their decisions are in [What happens by default](#what-happens-by-default).

Write your own mutator when your app needs a decision that the standard ones do not make. Every method has a default, the `CLOSE_FAILURE` decision, so implement only what you need. A mutator of your own that should never abort a request delegates the token decisions to `ApproovAlwaysProceedMutator.ALWAYS_PROCEED`. A mutator you install applies to requests processed after the call.

The package's signer is also a mutator. To sign under decisions of your own, see [Message signing](#message-signing).

The hooks:

| Hook | Decides |
| :--- | :--- |
| `handleInterceptorShouldProcessRequest` | whether a request gets Approov processing at all (by default, every request that is not excluded) |
| `handleInterceptorFetchTokenResult` | given the token fetch result, whether to send the request with its Approov headers, send it without them, or abort it |
| `handleInterceptorHeaderSubstitutionResult`, `handleInterceptorQueryParamSubstitutionResult` | whether to apply a secure string substitution |
| `handleInterceptorProcessedRequest` | final changes to the processed request. The signer signs here, so a mutator that calls it makes its own changes first |
| `handlePinningShouldProcessRequest` | whether Approov connection checks (Managed Trust Roots or configured public keys) apply to a request |
| `handlePrecheckResult`, `handleFetchTokenResult`, `handleFetchSecureStringResult`, `handleFetchCustomJWTResult` | how the direct methods turn a result into an error |

To fail a request on your own terms, throw a `URLError` from a hook. Your app's error handling then sees an ordinary network failure (see [Errors your app can see](#errors-your-app-can-see)).

## Diagnostics

The package writes a diagnostic line for each token fetch, and for each secure string fetch.

These lines are written at debug level, which is off by default (see [setLoggingLevel](REFERENCE.md#setlogginglevel)).

To write them, set the level in a debug build:

```swift
ApproovService.setLoggingLevel(.debug)
```

The package writes through `os_log`, so the lines appear in the Xcode console. `.off` silences the package completely.

The package never logs a token. For each request it processes, it logs the [loggable form](https://docs.approov.io/core-concepts/approov-tokens/architecture-and-security/#loggable-tokens) of the result. Its `arc` claim, the [Attestation Response Code](https://docs.approov.io/app-integration/frontend/attestation/#attestation-response-code), tells why attestation gave that result. The direct methods, such as `fetchToken`, log only the status. For example:

```
ApproovService: updateRequest api.example.com: {"did":"...","exp":1757400000,"arc":"IXPSB7TRK26LXE3M", ...,"sip":"a1b2c3"}
```

The line names only the host of the request. So no path or query value, such as a substituted secure string or personal data, is logged.

`ApproovService.getLastARC()` returns the ARC of the most recent fetch the package made, without making one of its own. It returns `""` before the first fetch, and when ARC is not enabled for the account.

To find the reasons behind an `arc`, see [decoding an Attestation Response Code](https://docs.approov.io/app-integration/frontend/attestation/#decoding-an-attestation-response-code). Your account's [metrics](https://docs.approov.io/operations/metrics-graphs/grafana-overview/) show the same results in aggregate. A [development signing certificate](https://docs.approov.io/operations/app-signing-certificates/development-and-testing/#development-app-signing-certificates) lets debug builds pass attestation.
