# Approov Package for URLSession

![Swift](https://img.shields.io/badge/Swift-5.8%2B-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/iOS-12%2B%20%7C%20watchOS%209%2B-000000?logo=apple&logoColor=white)
![SwiftPM](https://img.shields.io/github/v/tag/approov/approov-service-urlsession?label=SwiftPM&logo=swift&logoColor=white)
![CocoaPods](https://img.shields.io/cocoapods/v/ApproovURLSession?logo=cocoapods&logoColor=white)
![Message Signing](https://img.shields.io/badge/Message%20Signing-RFC%209421-1f6feb)
![Build](https://github.com/approov/approov-service-urlsession/actions/workflows/build_and_test.yml/badge.svg)

This package adds [Approov](https://www.approov.io) to an iOS or watchOS app that uses `URLSession`. After you initialize it, the package adds an Approov token to each request that your app sends to your API domains through an `ApproovURLSession`. The token, a signed JWT, provides proof of attestation. Your backend checks it to decide whether to accept or reject the request. A valid token shows that the request came from a genuine, unmodified copy of your app on a device that passed Approov's checks.

The package also checks the TLS connection to each of your API domains. A request goes ahead only if both the operating system and the [Managed Trust Roots](https://docs.approov.io/security-configuration/dynamic-pinning/#managed-trust-roots) configuration in your Approov account trust the connection. [Connection validation](ADVANCED.md#connection-validation) has the details.

## BEFORE YOU START

You need:

* an Approov account, trial or paid, and its [account ID](#your-account-id)
* your API domains [added to Approov](https://docs.approov.io/getting-started/add-api-domains/). The package adds a token only to requests to these domains.

Then follow the steps below. Each step makes the next one possible:

1. [Add the dependency](#adding-the-dependency). This gives your app `ApproovService` and `ApproovURLSession`.
2. [Initialize](#initializing) `ApproovService` with your account ID. This turns on Approov protection.
3. [Make your requests](#making-requests) through an `ApproovURLSession`. Your requests to your API domains then carry a token.
4. [Look in the debug log](ADVANCED.md#diagnostics) to see that each request gets a token.
5. [Register your app and check tokens on your backend](#next-steps). Until your backend checks the token, your API is not protected.

Optional features are in [ADVANCED.md](ADVANCED.md). Every method is in [REFERENCE.md](REFERENCE.md).

## ADDING THE DEPENDENCY

### Swift Package Manager

In Xcode, choose `File > Add Package Dependencies...`, enter `https://github.com/approov/approov-service-urlsession.git`, choose the dependency rule `Up to Next Major Version` from `3.7.1`, and add the `ApproovURLSessionPackage` product to your app target.

In a `Package.swift`, add the package and the product:

```swift
dependencies: [
    .package(url: "https://github.com/approov/approov-service-urlsession.git", from: "3.7.1")
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

The pods come from GitHub, not from the CocoaPods trunk. Add both to your `Podfile` and run `pod install`:

```ruby
pod 'ApproovURLSession', :git => 'https://github.com/approov/approov-service-urlsession.git', :tag => '3.7.1'
pod 'approov-ios-sdk', :git => 'https://github.com/approov/approov-ios-sdk.git', :tag => '3.7.0'
```

The package supports iOS 12 or later and watchOS 9 or later.

Next, [initialize the package](#initializing).

## INITIALIZING

Initialize `ApproovService` once, when your app starts, with your Approov account ID. Do this before your app sends its first request, for example in `application(_:didFinishLaunchingWithOptions:)`. If your app sends a request through an `ApproovURLSession` before `initialize`, the request goes out without Approov protection.

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
// then configure, after initialize (which resets the configuration) and before the
// app issues protected requests; only the settings your app uses, for example:
// ApproovService.setTokenHeader(header: "Authorization", prefix: "Bearer ")
// ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
```

About this example:

* `initialize` throws if the account ID is incomplete or changed. The `catch` block then starts the package in **bypass mode**, by initializing with `""`. In bypass mode the package sends requests without Approov protection. You can also use bypass mode as a feature flag: initialize with `""` to start your app without Approov.
* Logging the installation device ID is optional. Approov identifies an installation only by its device ID. Log it next to your own user or session ID for correlation.
* Make your configuration calls after `initialize`, before the app sends protected requests. Each `initialize` resets the configuration to its defaults, so the package loses a setting made before it. A setting applies only to requests sent after you make it. See [initialize, then configure](ADVANCED.md#initialize-then-configure).

### Your account ID

Your account ID is in your onboarding email. You can also get it at any time from the Approov CLI, which calls it the SDK config string:

```sh
approov sdk -getConfigString
```

The account ID is the same for every app in your account, and it is not a secret. You can keep it in your source code or deliver it with your app's configuration. The whole value must reach the app unchanged, including its punctuation. See [about the Approov account ID](ADVANCED.md#about-the-approov-account-id).

If the account ID is not available when the app starts, initialize with `""` first. Call `initialize` again when you have the account ID. See [bypass initialization](ADVANCED.md#bypass-initialization).

When the package is initialized, [make your requests](#making-requests) through an `ApproovURLSession`.

## MAKING REQUESTS

Use an `ApproovURLSession` wherever you would create a `URLSession`. It has the same initializers and task methods:

```swift
let session = ApproovURLSession(configuration: .default)
let task = session.dataTask(with: URL(string: "https://api.example.com/shapes")!) { data, response, error in
    // ...
}
task.resume()
```

The `async` methods of `URLSession` cannot be overridden, so use their `WithApproov` versions, such as `try await session.dataWithApproov(for: request)`. For a transport that owns its own `URLSession`, call `ApproovService.signRequest(_:)` to get a protected copy of a request. Both are in [REFERENCE.md](REFERENCE.md).

## CUSTOMIZING THE BEHAVIOUR

[ADVANCED.md](ADVANCED.md) explains how the package behaves and how to customize it:

* [What each request carries](ADVANCED.md#what-each-request-carries), and [what happens when a token fetch fails](ADVANCED.md#what-happens-by-default). By default, a request fails if the device has a network problem. It goes ahead with an empty token header if the app cannot reach the Approov service.
* [Service mutators](ADVANCED.md#service-mutators), which change those decisions. For example, a mutator can send requests without a valid token. It can also fail a request on chosen errors. Your app then receives the `URLError` that the mutator throws and decides what to do, for example retry or show a message.
* [Message signing](ADVANCED.md#message-signing), which you install with one call
* [Header names](ADVANCED.md#header-names), [secure strings](ADVANCED.md#secure-strings), [token binding](ADVANCED.md#token-binding), [excluding URLs](ADVANCED.md#excluding-urls) and [redirects](ADVANCED.md#redirects)
* [Diagnostics](ADVANCED.md#diagnostics), which show the result of each token fetch in the log

Then continue with the [next steps](#next-steps).

## NEXT STEPS

1. [Register your app](https://docs.approov.io/getting-started/add-app-signing-certificates/), so that your release builds pass attestation.
2. [Check tokens on your backend](https://docs.approov.io/getting-started/integrate-backend/), and signatures if you installed message signing. This is the step that protects your API.
3. [Go live](https://docs.approov.io/getting-started/go-live/). Monitor first, then let your backend reject requests without a valid token.

## UPGRADING FROM 3.5.x

Read the [changelog](CHANGELOG.md) for the full list of changes. Test your app and backend together.

### Code changes

* `setApproovInterceptorExtensions`, `prefetch`, `setProceedOnNetworkFailure` and `setFailureCacheTTL` are removed. Use `setServiceMutator`, and `.ALWAYS_PROCEED` to go ahead on network failures.
* A mutator hook that throws something other than a `URLError`, and a message signing configuration error, now fail the request with a `URLError`. Catch `Error` rather than `ApproovError` around `signRequest`.
* A `task.delegate` that you assign directly to a task and that implements the redirect callback now cancels the task. Pass that delegate to the session initializer or to a `WithApproov` method instead.
