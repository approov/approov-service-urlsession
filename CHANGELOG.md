# Changelog

All notable changes to this package will be documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## [3.6.0] - 2026-09-25

### Added
- Swift 6 support. The package compiles in the Swift 6 language mode with complete data-race checking, and apps can use it from either the Swift 5 or the Swift 6 language mode. No existing API is removed or renamed, and apps in the Swift 5 language mode need no source changes and get no new warnings.
- `ApproovUpdateResponse`, `ApproovFetchDecision`, `ApproovLogLevel` and `ApproovServiceMutatorDefault` conform to `Sendable`, and `ApproovURLSession` and `ApproovSessionTaskObserver` restate the `Sendable` conformance of their base classes. Swift 6 apps can pass these values between actors and tasks, for example returning the result of `updateRequestWithApproov` from a detached task, which previously failed to compile.
- CocoaPods: the podspec declares `swift_versions` (5.0 and 6.0). Without it, CocoaPods compiled the pod in the Swift language mode of the app target, so it failed to build in apps set to Swift 6.
- CI gates for Swift 6 support: the tests also run under Thread Sanitizer, app-style fixtures in the Swift 5 and Swift 6 language modes must compile without warnings (`CompatibilityTests`), the public API is checked for breaking changes against the latest release, and the package is built for iOS against the Approov SDK.

### Fixed
- The completion handlers of the `ApproovURLSession` task methods (`dataTask`, `uploadTask`, `downloadTask`, `getAllTasks`, `getTasksWithCompletionHandler`, `flush` and `reset`) are now `@Sendable`, matching `URLSession`. Previously, in a Swift 6 app, a completion handler written inside a `@MainActor` type was treated as main-actor code although `URLSession` runs it on its delegate queue; the Swift runtime reports this as a data race. The methods are marked `@preconcurrency`, like the `URLSession` methods they override, so Swift 5 apps see no change.

### Changed
- Minimum toolchain: Xcode 16 (Swift 6.0), up from Xcode 14.3 (Swift 5.8). The App Store already requires Xcode 16 or later. Deployment targets are unchanged.
- The SPKI header table used by dynamic pinning is now an immutable, lazily initialised constant rather than a dictionary populated on first use under a dedicated queue.

### Note for Swift 6 apps
- A completion handler passed to an `ApproovURLSession` task method is no longer isolated to the enclosing actor, exactly as with `URLSession`. Code that updated main-actor state directly from such a handler, which was already a data race at runtime, now fails to compile and must hop back explicitly, for example with `Task { @MainActor in ... }` or `DispatchQueue.main.async`.

## [3.5.13] - 2026-09-25

### Fixed
- The async convenience methods (`dataWithApproov`, `uploadWithApproov` and `downloadWithApproov`) no longer create a new `URLSession` for each call that supplies a delegate (#63). That session was built from the inherited `configuration` and `delegateQueue`, which belong to the `URLSession` base class that `ApproovURLSession` cannot initialise: `configuration` was `nil` behind a non-optional type, so the caller's headers, timeouts, cookie storage and cache were silently dropped, and the session was never invalidated, leaking it and its delegate for the lifetime of the process (present since 3.2.5). The task is now created on the pinned session and the delegate is attached to it with `URLSessionTask.delegate`, as `URLSession.data(for:delegate:)` does, so the task releases it on completion and the request reuses the session's connections. Server-trust challenges still go through Approov pinning even when the supplied delegate implements `urlSession(_:didReceive:completionHandler:)`, which `URLSession` would otherwise offer that challenge ahead of the session delegate.
- `ApproovURLSession.configuration` and `ApproovURLSession.delegateQueue` now return the configuration and queue the session was created with, rather than the values of the uninitialised base class.
- A completion that reports neither an error nor a result now throws `URLError(.badServerResponse)` from the async convenience methods instead of trapping on a force unwrap.

### Changed
- When a delegate is supplied to an async convenience method, the delegate passed to `init(configuration:delegate:delegateQueue:)` now receives the callbacks for that task that the supplied delegate does not implement, matching `URLSession`. Previously it received none of them.

## [3.5.12] - 2026-08-14

### Fixed
- Isolated URLSession observer state by task object identity. Requests from different sessions can now use equal session-local task identifiers without overwriting their configuration or completion handlers.
- Added one-shot completion handling for rejected requests. The observer now cancels the underlying URLSessionTask without calling the application completion handler twice.
- Removed the manually allocated KVO context that carried the pinning `URLSession` to the observer. The buffer was created with `UnsafeMutablePointer<URLSession>.allocate` and released with `deallocate()` alone, which frees the memory without releasing the strong session reference it held, leaking one retain of the pinned session per task and keeping the session alive for the lifetime of the process (present since 3.1.2). The session now reaches the observer through the per-task registration, so no manual memory management remains.
- Task registrations now live on the task object itself rather than in a dictionary keyed by `ObjectIdentifier(task)`. That key is only the task's address, so a task created and then dropped without being resumed or cancelled left its registration behind, and a later task allocated at the same address inherited it — taking another request's pinning session, session configuration and completion handler. Address recycling is not rare: 198 of 200 create-and-drop cycles reused an address in measurement. The registration is now an associated object, so it is released exactly when its task is, and observation uses the block-based KVO API whose token the registration owns, removing the manual addObserver/removeObserver pairing.

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
