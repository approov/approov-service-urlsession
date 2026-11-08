# Approov Package for URLSession

![Swift](https://img.shields.io/badge/Swift-5.8%2B-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/iOS-11%2B%20%7C%20watchOS%209%2B-000000?logo=apple&logoColor=white)
![SwiftPM](https://img.shields.io/github/v/tag/approov/approov-service-urlsession?label=SwiftPM&logo=swift&logoColor=white)
![CocoaPods](https://img.shields.io/cocoapods/v/ApproovURLSession?logo=cocoapods&logoColor=white)
![Message Signing](https://img.shields.io/badge/Message%20Signing-RFC%209421-1f6feb)
![Build](https://github.com/approov/approov-service-urlsession/actions/workflows/build_and_test.yml/badge.svg)

This package adds [Approov](https://www.approov.io) to an iOS or watchOS app that uses `URLSession`. Once it is initialized, every request your app makes through an `ApproovURLSession` carries an Approov token, and optionally a message signature, that your backend can check. Your backend then knows each request came from a genuine, unmodified copy of your app.

The package also checks the TLS connection to each of your API domains, against the certificate keys you configured for that domain or else the trust roots Approov manages for your account. A connection that does not match is refused.

You need a trial or paid Approov account. The [Approov documentation](https://approov.io/docs/latest/) shows how to set up your account, register your app and check the integration. This page covers the essentials. Optional features are in [ADVANCED.md](ADVANCED.md), and every method is listed in [REFERENCE.md](REFERENCE.md).

## ADDING THE DEPENDENCY

### Swift Package Manager

In Xcode, choose `File > Add Package Dependencies...`, enter `https://github.com/approov/approov-service-urlsession.git`, choose the dependency rule `Up to Next Major Version` from `3.7.0`, and add the `ApproovURLSessionPackage` product to your app target.

In a `Package.swift`, add the package and the product:

```swift
dependencies: [
    .package(url: "https://github.com/approov/approov-service-urlsession.git", from: "3.7.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "ApproovURLSessionPackage", package: "approov-service-urlsession")
        ]
    )
]
```

### CocoaPods

Add the pod to your `Podfile` and run `pod install`:

```ruby
pod 'ApproovURLSession', '~> 3.7.0'
```

The package supports iOS 11 or later and watchOS 9 or later.

## INITIALIZING

Initialize `ApproovService` once, when your app starts, with your Approov account ID. Requests made before initialization are sent without Approov protection.

```swift
import ApproovURLSessionPackage
import os.log

do {
    // your Approov account ID, from your onboarding email or "approov sdk -getConfigString"
    try ApproovService.initialize(config: "<your-approov-account-id>")
    if ApproovService.isApproovServiceEnabled() && ApproovService.isApproovProtectionEnabled() {
        os_log("Approov initialized; deviceID=%@", ApproovService.getDeviceID() ?? "")
    }
} catch {
    // the value passed was not a valid account ID; run without Approov rather than not at all
    os_log("Approov account ID rejected; starting in bypass mode: %@", error.localizedDescription)
    try? ApproovService.initialize(config: "")
}
// then configure, after initialize and before the
// app issues protected requests; only the settings your app uses, for example:
// ApproovService.setTokenHeader(header: "Authorization", prefix: "Bearer ")
// ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
```

A few notes on this example:

* `initialize` throws if the account ID it receives is incomplete or altered. The `catch` block then starts the package in **bypass mode** by initializing with `""`. In bypass mode requests are sent without Approov protection, but your app still starts.
* Logging the device ID is optional. Approov identifies an installation only by its device ID, so logging it next to your own user or session ID lets you match the two later.
* Make your configuration calls (custom headers, message signing, secure strings and so on) after `initialize`, before the app sends protected requests. Each `initialize` resets the configuration to its defaults, so a setting made before it is lost. See [initialize, then configure](ADVANCED.md#initialize-then-configure).

### Your account ID

Your account ID is in your onboarding email. You can also get it at any time from the Approov CLI, which calls it the SDK config string:

```sh
approov sdk -getConfigString
```

The account ID is the same for every app in your account and is not a secret. You can keep it in your source code or deliver it with your app's configuration. Either way, the whole value must reach the app unchanged, including its punctuation. More in [about the Approov account ID](ADVANCED.md#about-the-approov-account-id).

If another part of your app initializes Approov for you, that only sets the account ID. Your app still needs to make its own configuration calls after that `initialize`, because every `initialize` resets them.

## MAKING REQUESTS

Use an `ApproovURLSession` wherever you would create a `URLSession`. It has the same initializers and task methods:

```swift
let session = ApproovURLSession(configuration: .default)
let task = session.dataTask(with: URL(string: "https://api.example.com/shapes")!) { data, response, error in
    // ...
}
task.resume()
```

The `async` methods of `URLSession` cannot be overridden, so use their `WithApproov` versions, such as `try await session.dataWithApproov(for: request)`. For a transport that owns its own `URLSession`, call `ApproovService.signRequest(_:)` to get a protected copy of a request. Both are listed in [REFERENCE.md](REFERENCE.md).

### What gets sent

For a domain you have added to Approov, each request carries:

* the `Approov-Token` header, the proof that the app passed attestation
* the `Approov-TraceID` header, an optional debug value, whenever the SDK gives one

The connection is checked against the certificate keys configured for the domain, or your account's Managed Trust Roots if it has none. If the check fails, the request fails with `NSURLErrorServerCertificateUntrusted`.

A domain you added with `-noApproovToken` gets a checked connection and its secure strings, but no Approov headers. Requests to any other domain are sent unchanged.

If a secure string cannot be fetched, its placeholder is replaced by the fetch status name, so a header becomes, for example, `Api-Key: REJECTED` or `Api-Key: UNKNOWN_KEY`, and a required prefix stays in front of the status. This lets your backend see why the secret is missing.

### When the app cannot get a token

By default the mutator is `CLOSE_FAILURE`:

* If the Approov service cannot be reached (`NO_APPROOV_SERVICE`), the request is sent with an empty `Approov-Token` header.
* For any other failure the request fails in the app with an `ApproovError`: `networkingError` for a problem the user can retry, such as `NO_NETWORK`, and `rejectionError` or `permanentError` otherwise.

To always send the request and let your backend decide, install `ALWAYS_PROCEED`. A request without a token is then sent with an empty `Approov-Token` header.

```swift
ApproovService.setServiceMutator(.ALWAYS_PROCEED)  // optional but recommended
```

To tell your backend why there is no token, turn on `setUseApproovStatusIfNoToken`. The token header then carries the status name, such as `NO_NETWORK`, in place of the empty token. Under `CLOSE_FAILURE` this also lets `NO_NETWORK`, `POOR_NETWORK` and `MITM_DETECTED` go ahead with the status instead of failing. See [sending the status in the token header](ADVANCED.md#sending-the-status-in-the-token-header).

```swift
ApproovService.setUseApproovStatusIfNoToken(shouldUse: true)
```

If the token fetch fails for a host that is not one of your Approov API domains, the request is sent unchanged under either mutator. More in [what happens by default](ADVANCED.md#what-happens-by-default).

### Message signing

Message signing is off unless you install it. The signer, `ApproovDefaultMessageSigning`, is a service mutator. Install it after `initialize`:

```swift
ApproovService.setServiceMutator(ApproovDefaultMessageSigning().setDefaultFactory(
    ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
```

Every request that carries the token header is then signed with the install signature. See [message signing](ADVANCED.md#message-signing) to add the account signature or choose what is covered.

## VERIFYING

Run your app and make a request. To see what happened, turn on debug logging with `ApproovService.setLoggingLevel(.debug)` in a debug build. The package never logs a token. At debug level it logs the [loggable form](https://approov.io/docs/latest/approov-usage-documentation/#loggable-tokens) of each result. Its `arc` claim explains why attestation gave that result; [diagnostics](ADVANCED.md#diagnostics) shows how to decode it.

Your account's [live metrics](https://approov.io/docs/latest/approov-usage-documentation/#metrics-graphs) show the same results in aggregate, usually within a minute.

## UPGRADING FROM 3.5.x

Read the [changelog](CHANGELOG.md) for the full list of changes, and test your app and backend together.

### Code changes

* `setApproovInterceptorExtensions`, `prefetch`, `setProceedOnNetworkFailure` and `setFailureCacheTTL` are removed. Use `setServiceMutator`, and `ALWAYS_PROCEED` to go ahead on network failures.
* A mutator hook that throws something other than a `URLError`, and a message signing configuration error, now fail the request with a `URLError`. Catch `Error` rather than `ApproovError` around `signRequest`.

### What you may notice

* A secure string that cannot be fetched no longer fails the request. The placeholder is replaced by the status name, such as `Api-Key: REJECTED`. If your backend checks the value it receives, it must expect these status values.
* A failed token fetch only affects requests to your Approov API domains. A request to any other host is sent unchanged instead of failing.
* A connection refused by the certificate check fails with `NSURLErrorServerCertificateUntrusted` instead of `NSURLErrorCancelled`.
* A redirect is protected afresh for its target.

## NEXT STEPS

1. [Add your API domains](https://docs.approov.io/getting-started/add-api-domains/) to Approov.
2. [Register your app](https://docs.approov.io/getting-started/add-app-signing-certificates/).
3. Set up token and signature checks on your backend, following the [Approov documentation](https://approov.io/docs/latest/).

Custom header names, secure strings, token binding, excluding URLs and service mutators are in [ADVANCED.md](ADVANCED.md). Every method is in [REFERENCE.md](REFERENCE.md).
