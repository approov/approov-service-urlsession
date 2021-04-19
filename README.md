# Approov Service for URLSession 

A wrapper for the [Approov SDK](https://github.com/approov/approov-ios-sdk) to enable easy integration when using [`URLSession`](https://developer.apple.com/documentation/foundation/urlsession) for making the API calls that you wish to protect with Approov. In order to use this you will need a trial or paid [Approov](https://www.approov.io) account.

## Adding ApproovService Dependency
The Approov integration is available via [`cocoapods`](https://cocoapods.org/). This allows inclusion into the project by simply specifying a dependency in the `Podfile` for the app:

```
target 'YourApplication' do
    use_frameworks!
    platform :ios, '10.0'
    pod 'approov-service-urlsession', '2.6.1', :source => "https://github.com/approov/approov-service-urlsession.git"
    pod 'approov-ios-sdk', '2.6.1', :source => "https://github.com/approov/approov-ios-sdk.git"
end
```

This package is actually an open source wrapper layer that allows you to easily use Approov with `NSURLSession`. This has a further dependency to the closed source [Approov SDK](https://github.com/approov/approov-ios-sdk).

## Using the approov service urlsession
The `ApproovURLSession` class mimics the interface of the `URLSession` class provided by Apple but includes an additional ApproovSDK attestation call. The simplest way to use the `ApproovURLSession` class is to find and replace all the `URLSession` with `ApproovURLSession`. Additionaly, the Approov SDK needs to be initialized before use. As mentioned above, you will need a paid or trial account for [Approov](https://www.approov.io). Using the command line tools:

```
$ approov sdk -getConfig approov-initial.config
```

The `approov-initial.config` file must then be included in you application bundle and automatically loaded by the Approov SDK. It is possible to change the filename and also include the configuration string as a variable by overriding/modifying the `ApproovSDK` class variables in the `ApproovURLSession.swift` file.

## Approov Token Header
The default header name of `Approov-Token` can be changed by modifying the variable `kApproovTokenHeader` in `ApproovURLSession.swift` file:

```swift
private static let kApproovTokenHeader = "Approov-Token"
```

You may like to change the above value to `Authorization` and prefix the actual Approov JWT Token with `Bearer ` and make use of the resulting header in your integration.
## Token Binding
If you are using [Token Binding](https://approov.io/docs/latest/approov-usage-documentation/#token-binding) then set the header holding the value to be used for binding as follows:

```swift
ApproovSDK.bindHeader = "Authorization"]
```

The Approov SDK allows any string value to be bound to a particular token by computing its SHA256 hash and placing its base64 encoded value inside the pay claim of the JWT token. The property `bindHeader` takes the name of the header holding the value to be bound. This only needs to be called once but the header needs to be present on all API requests using Approov. It is also crucial to use `bindHeader` before any token fetch occurs, like token prefetching being enabled, since setting the value to be bound invalidates any (pre)fetched token.

## Token Prefetching
If you wish to reduce the latency associated with fetching the first Approov token, then a call to `ApproovSDK.prefetchApproovToken` can be made immediately after initialization of the Approov SDK. This initiates the process of fetching an Approov token as a background task, so that a cached token is available immediately when subsequently needed, or at least the fetch time is reduced. Note that if this feature is being used with [Token Binding](https://approov.io/docs/latest/approov-usage-documentation/#token-binding) then the binding must be set prior to the prefetch, as changes to the binding invalidate any cached Approov token.

## Configuration Persistence
An Approov app automatically downloads any new configurations of APIs and their pins that are available. These are stored in the [`UserDefaults`](https://developer.apple.com/documentation/foundation/userdefaults) for the app in a preference key `approov-dynamic`. You can store the preferences differently by modifying or overriding the methods `storeDynamicConfig` and `readDynamicApproovConfig` in `ApproovURLSession.swift`.

