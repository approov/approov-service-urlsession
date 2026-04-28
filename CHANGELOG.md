# Changelog

All notable changes to this package will be documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## [3.5.8] - 2026-04-09

### Added
- Integrated a localized testing framework for comprehensive service layer verification.
- Added extensive test coverage for core service flows, including initialization, token management, and request mutation.
- Added `ApproovService.isInitialized()` to expose the service-layer initialization state.
- Thread-safe failure mode caching for the interceptor path when the platform SDK returns a failure status (`NO_NETWORK`, `POOR_NETWORK`, `MITM_DETECTED`, `NO_APPROOV_SERVICE`).

### Changes
- Updated the build manifest to support flexible dependency resolution for verification suites.
- Added internal service hooks to facilitate automated testing environments.

### Fixed
- Enabled macOS host-side compilation for the package in local testing framework mode by extending the relevant availability annotations in `PinningURLSessionDelegate`.
- Excluded the vendored `util/sig/LICENSE` file from the main package target to avoid SwiftPM unhandled file warnings during tests.
- Initializing with an empty config string now keeps the service layer initialized while forwarding requests without Approov processing.
- Initializing first with an empty config string and later with a valid non-empty config string now enables Approov at runtime instead of being rejected as a different-configuration initialization.
- Tightened the initialization guard so only actual `reinit...` comments bypass same-config enforcement.
- Added explicit cross-service-layer initialization handling and tests so a benign same-config already-initialized native SDK outcome is tolerated, while real different-configuration failures still surface as initialization errors.

## [3.5.7] - 2026-03-06

### Breaking changes
- Renamed the Swift Package Manager package to `ApproovURLSessionPackage`.
- Renamed the CocoaPods `module_name` to `ApproovURLSessionPackage`; CocoaPods integrations must update their `import` statements to use the new module name.
- Renamed the CocoaPods module name to `ApproovURLSessionPackage`. CocoaPods consumers must update imports to `import ApproovURLSessionPackage`.
- `setProceedOnNetworkFailure()` and `getProceedOnNetworkFailure()` are no longer used internally and no longer affect behavior. To customize network failure handling, use `setServiceMutator` with a custom `ApproovServiceMutator`. By default, `.noNetwork`, `.poorNetwork`, and `.mitmDetected` now block the request unless a custom mutator overrides that behavior. See `USAGE.md` for details.

### Changes
- Made `loggingLevel` thread-safe with a dedicated `loggingQueue` to prevent data races on concurrent reads/writes.
- Gated all `os_log` calls in `PinningURLSessionDelegate` and `ApproovSessionTaskObserver` behind `ApproovService.loggingLevel` so that `setLoggingLevel` controls all package logging consistently.
- Fixed logging level guard mismatch in `ApproovDefaultMessageSigning` (`.info` → `.error`).
- Updated the underlying Approov SDK to be consumed as a package dependency rather than a direct binary target, avoiding `fatalError` identity conflicts when integrating alongside other Approov service layers in Swift Package Manager.
- Updated `ApproovService.initialize` to ignore `Foundation._GenericObjCError` exceptions from the underlying SDK when it has already been initialized by another service layer in the application.
- Changed `dataTaskPublisherWithApproov` to return `(URLSession.DataTaskPublisher, Error?)`. When Approov blocks a request, such as during a connectivity failure, only the affected tasks are cancelled instead of invalidating the entire underlying `URLSession`.
- Updated `ApproovDefaultMessageSigning` to read the configured Approov token header through an internal synchronized accessor instead of assuming `Approov-Token`.

## [3.5.6] - 2026-01-29

### Added
- ApproovServiceMutator protocol with default behavior to centralize decision points in the service flow.
- Mutator hooks for precheck, token fetch, secure string fetch, custom JWT fetch, interceptor decisions, and pinning.
- REFERENCE.md & CHANGELOG.md & USAGE.md
- Added `setUseApproovStatusIfNoToken` to allow using status as token value when token is missing.
### Changed
- ApproovService now routes decision logic through the service mutator and exposes set/get APIs.
- Pinning delegate now checks the mutator before applying pinning logic.
- CocoaPods spec is now maintained only at the repository root (per-version podspec files remain,but will not be updated).
### Fixed
- Task‑level URLSession auth challenge handler can return without calling completionHandler, triggering API MISUSE warning
- Prevented exceptions when key-pair generation fails. The service now logs an error and continues without the install message signature, allowing the backend to decide whether to reject the request.
### Deprecated
- ApproovInterceptorExtensions in favor of ApproovServiceMutator.
- setProceedOnNetworkFailure() and getProceedOnNetworkFailure() in favor of ApproovServiceMutator.
- prefetch() is now automatically called when the service is initialized.
