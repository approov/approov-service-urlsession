# Approov Service for URLSession 

A wrapper for the [Approov SDK](https://github.com/approov/approov-ios-sdk) to enable easy integration when using [`URLSession`](https://developer.apple.com/documentation/foundation/urlsession) for making the API calls that you wish to protect with Approov. In order to use this you will need a trial or paid [Approov](https://www.approov.io) account.

Please see the [Quickstart](https://github.com/approov/quickstart-ios-swift-urlsession) for example integration.

## ADDING APPROOV SERVICE DEPENDENCY
The Approov integration is available via the [`Swift Package Manager`](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app). This allows inclusion into the project by specifying a dependency in the `File -> Add Packages...` Xcode option.

Enter the repository `https://github.com/approov/approov-service-urlsession.git` into the search box and latest available version will be automatically selected for you.

Once you click `Add Package` the last step will confirm the package product and target selection. The `approov-service-urlsession` is actually an open source wrapper layer that allows you to easily use Approov with `URLSession`. This has a further dependency to the closed source [Approov SDK](https://github.com/approov/approov-ios-sdk).

Alternatively, use `cocoapods` and add the package dependencies similar to how they are used in the example [`shapes-app/Podfile`](https://github.com/approov/quickstart-ios-swift-urlsession/blob/master/shapes-app/Podfile) in the [Quickstart](https://github.com/approov/quickstart-ios-swift-urlsession) repository.

## USING APPROOV SERVICE
The `ApproovURLSession` class mimics the interface of the `URLSession` class provided by Apple but includes an additional Approov attestation calls. The simplest way to use the `ApproovURLSession` class is to find and replace all the `URLSession` construction calls with `ApproovURLSession`. 

```swift
import ApproovURLSessionPackage

try! ApproovService.initialize(config: "<enter-your-config-string-here>")
let session = ApproovURLSession(URLSessionConfiguration.default)
```

Additionally, the Approov SDK wrapper class, `ApproovService` needs to be initialized before using the `ApproovURLSession` object. The `<enter-your-config-string-here>` is a custom string that configures your Approov account access. This will have been provided in your Approov onboarding email (it will be something like `#123456#K/XPlLtfcwnWkzv99Wj5VmAxo4CrU267J1KlQyoz8Qo=`).

For API domains that are configured to be protected with an Approov token, this adds the `Approov-Token` header and pins the connection. This may also substitute header values and query parameters when using secrets protection.

## ERROR TYPES
The `ApproovService` functions may throw specific errors to provide additional information:

* `permanentError` might be due to a feature not enabled using the command line
* `rejectionError` an attestation has been rejected, the `ARC` and `rejectionReasons` may contain specific device information that would help troubleshooting
* `networkingError` generally can be retried since it can be temporary network issue
* `pinningError` is a certificate error
* `configurationError` a configuration feature is disabled or wrongly configured (i.e. attempting to initialize with different config from a previous instantiation) 
* `initializationFailure` the ApproovService failed to be initialized (subsequent network requests will not be performed)

Example error handling:

```swift
if let approovError = error as? ApproovError {
    switch approovError {
    case .networkingError(let message):
        // Temporary network issue: can retry
        print("Retryable networking error: \(message)")
        
    case .rejectionError(let message, let ARC, let rejectionReasons):
        // Attestation rejected: device is untrusted (e.g. secure strings unavailable for this device)
        print("Rejected. ARC: \(ARC), Reasons: \(rejectionReasons)")
        
    case .pinningError(let message):
        // TLS Pinning/Certificate verification failed
        print("Pinning error: \(message)")
        
    case .permanentError(let message):
        // Permanent failure (e.g. service not initialized)
        print("Permanent error: \(message)")
        
    default:
        break
    }
}
```


## CHECKING IT WORKS
Initially you won't have set which API domains to protect, so the interceptor will not add anything. It will have called Approov though and made contact with the Approov cloud service. You will see logging from Approov saying `unknown URL`.

Your Approov onboarding email should contain a link allowing you to access [Live Metrics Graphs](https://approov.io/docs/latest/approov-usage-documentation/#metrics-graphs). After you've run your app with Approov integration you should be able to see the results in the live metrics within a minute or so. At this stage you could even release your app to get details of your app population and the attributes of the devices they are running upon.

## NEXT STEPS
To actually protect your APIs and/or secrets there are some further steps. Approov provides two different options for protection:

* **API PROTECTION** You should use this if you control the backend API(s) being protected and are able to modify them to ensure that a valid Approov token is being passed by the app. An [Approov Token](https://approov.io/docs/latest/approov-usage-documentation/#approov-tokens) is short lived cryptographically signed JWT proving the authenticity of the call.

* **SECRETS PROTECTION** This allows app secrets, including API keys for 3rd party services, to be protected so that they no longer need to be included in the released app code. These secrets are only made available to valid apps at runtime.

Note that it is possible to use both approaches side-by-side in the same app.

See [REFERENCE](REFERENCE.md) for a complete list of all of the `ApproovService` methods.

## DATA TASK PUBLISHER
The version of [`dataTaskPublisher(for:)`](https://developer.apple.com/documentation/foundation/urlsession/3329708-datataskpublisher) provided in `URLSession` does not add Approov protection.

If you wish to use an Approov protected version then please call `dataTaskPublisherApproov` instead. Note though that this method may block when it is called when requesting network communication with the Approov cloud. Therefore you shouldn't call this method from the main UI thread.

## AWAIT-ASYNC ASYNCHRONOUS TRANSFERS
Note that the methods related to [Performing Asynchronous Transfers](https://developer.apple.com/documentation/foundation/urlsession#3842971) (introduced in iOS 15, and discussed in [Using URLSession’s async/await-powered APIs](https://wwdcbysundell.com/2021/using-async-await-with-urlsession/)) should not be called directly and do not provide Approov protection. This is because they are defined in an `extension` to `URLSession` and cannot be overridden by the Approov implementation. Instead various of the methods are provided with an identical method signature but have a `WithApproov` suffix in their name. The supported methods are as follows:

`dataWithApproov(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)`

`dataWithApproov(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)`

`uploadWithApproov(for request: URLRequest, fromFile fileURL: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)`

`uploadWithApproov(for request: URLRequest, from bodyData: Data, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)`

`downloadWithApproov(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse)`

`downloadWithApproov(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse)`

# Changelog

Please see the [CHANGELOG.md](CHANGELOG.md) for more information on the changes in each version.

# Reference

Please see the [REFERENCE.md](REFERENCE.md) for more information on the Approov Service for URLSession.

# Usage

Please see the [USAGE.md](USAGE.md) for more information on how to use this wrapper.
