# Changelog

All notable changes to this package will be documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## [3.5.11] - 2026-06-24

### Added
- Manual release via the dedicated **Release Current Main Branch** workflow (`release.yml`, `workflow_dispatch`): it reads the top CHANGELOG version, refuses to proceed if that version is already tagged (a forgotten CHANGELOG bump), verifies `main` already carries that version in lock-step in `Package.swift` (`releaseTAG`), the CocoaPods `ApproovURLSession.podspec` (`s.version`) and the runtime user-property string, then tags `main`'s HEAD and pushes the tag. It never pushes a commit to `main` (no token/ruleset bypass needed) and the tag points at a `main` commit, so the released commit always belongs to a branch. The version is bumped beforehand via a normal PR; `verify-release` enforces that these three locations match the top CHANGELOG entry. `main` now carries a real `x.y.z` rather than a `dev` placeholder.
- The runtime Approov user-property now reports the service-layer version (`approov-service-urlsession/<version>`); previously a bare, version-less string was reported.

### Fixed
- Message signing now conforms to the cross-layer fail-open policy (core-project-approov#564). An ES256 ASN.1/DER decode failure and a `Signature`/`Signature-Input` serialization failure now log at error level and proceed **unsigned** instead of aborting the request, matching the existing install/account/base64 fail-open paths. The ES256 ASN.1/DER decoder is now bounds-checked so a malformed or truncated signature throws (and fails open) rather than risking an out-of-bounds trap. Only a required body digest that cannot be generated and an unsupported signing algorithm still fail closed.

## [3.5.10] - 2026-06-08

### Added
- New `signRequest(_:sessionConfig:)` convenience method on `ApproovService` that applies Approov protection (token, substitutions, and message signing when configured) to a `URLRequest` and returns the protected request directly. Designed for HTTP transports that own their own `URLSession` (e.g. Apollo iOS, gRPC-Swift) where substituting `ApproovURLSession` is not possible.

### Changed
- Made all members of `ApproovUpdateResponse` (`request`, `decision`, `sdkMessage`, `error`) publicly readable (`public internal(set)`). Previously they had `internal` access, preventing external modules from reading the response fields returned by `updateRequestWithApproov`.
- `initialize(config:comment:)` now resets `serviceMutator` and `useApproovStatusIfNoToken` to defaults on each successful call, alongside the existing resets of substitution headers, exclusion regexes, and binding header.

### Fixed
- `PinningURLSessionDelegate`: In empty-config bypass mode, the challenge handler now calls `.performDefaultHandling` rather than accepting the server trust via `.useCredential`. This ensures OS-level certificate validation always runs even when Approov dynamic pinning is skipped.

## [3.5.9] - 2026-06-02

### Changed
- Simplified `initialize`. The ObjC/Swift interop behavior is preserved: the Approov SDK's ObjC `BOOL` return of `NO` without an `NSError` is bridged by Swift as `Foundation._GenericObjCError` code 0 — this is the "already initialized" signal (equivalent to a `false` boolean return on Android) and is logged without being re-thrown. Any other error is a genuine failure and is still surfaced as an `ApproovError.initializationFailure`. State is only reset after the SDK confirms success, so a failure preserves the prior operating mode.

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
