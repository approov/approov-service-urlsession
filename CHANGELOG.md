# Changelog

All notable changes to this package will be documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## [3.5.14] - 2026-09-28

### Fixed
- Pinning can no longer be removed from a request by assigning a task delegate to a task obtained from one of the classic task factory methods (`dataTask`, `downloadTask`, `uploadTask`). `URLSession` prefers a task delegate's implementation of `urlSession(_:didReceive:completionHandler:)` over the session delegate's, and `URLSessionTask.delegate` is settable until the task is resumed, so a delegate answering the server-trust challenge could bypass Approov's pin check entirely. Such a task is now rejected before the TLS handshake. The six async convenience methods, which wrap a supplied delegate in `PinningTaskDelegate`, were already protected.
- WebSocket tasks are now covered by the pinning guard. `webSocketTask(with:)` and its overloads previously returned an unobserved task, so a caller-supplied task delegate could displace the pin check on the upgrade exactly as it could on a data task. Attestation of WebSockets remains unimplemented: no Approov token is added to the upgrade request, and nothing re-attests a connection once it is open, so the guarantee for a WebSocket is TLS pinning of the upgrade and nothing more.
- `downloadTask(withResumeData:)` and its completion-handler overload are deprecated. They were never supported by Approov: resume data embeds the request from the original download, including an Approov token that has since expired, so no valid token can be presented and none is added. Pinning is applied by the session delegate, but these tasks are not observed and so are not covered by the task-delegate guard, which means a task delegate answering the server-trust challenge still removes pinning from a resumed download. The overrides remain, because removing them would let the inherited `URLSession` implementation run against a base class this subclass cannot initialise.
- Host resolution no longer depends on a URL starting with `https`. `hostnameFromURL` matched that prefix and sent every other scheme down its bare-host-name branch, which prepends `https://`, so `http://example.com` and `wss://example.com` resolved to the host `http` and `wss` respectively rather than `example.com`. A non-empty host is now required at each step. This value is used for logging only, so the effect was mis-scoped log lines rather than a protection decision.
- Documented that custom authentication-challenge handling, mutual TLS included, must be done by the session delegate passed to `init(configuration:delegate:delegateQueue:)` implementing `urlSession(_:didReceive:completionHandler:)`. A task delegate cannot handle challenges: implementing the session-level callback on one is rejected, since it would displace Approov pinning, and implementing only the task-level callback never receives a connection-level challenge such as a client certificate. See REFERENCE.md.
- A caller delegate that implements only some of its optional callbacks no longer hangs a task. `PinningURLSessionDelegate` forwarded six completion-handler callbacks with `delegate.urlSession?(...)`, an optional Objective-C call that is a no-op when the delegate does not implement that method, so the completion handler was never invoked and the task never finished. `URLSessionDataDelegate` and `URLSessionTaskDelegate` declare every method optional, so a delegate implementing any subset is legal and was enough to hang an upload indefinitely. Reproduced with a delegate implementing only `urlSession(_:dataTask:didReceive:)`. Each forward now checks `responds(to:)` first and always answers the handler; `needNewBodyStream` and `needNewBodyStreamFrom` had no fallback at all, so they hung even with no delegate set. Present since the delegate was introduced.
- Message signing no longer appends to the `Signature`, `Signature-Input` and `Content-Digest` headers, which produced two dictionary members in one header when a request was processed twice and was rejected by RFC 9421 and RFC 9530 verifiers. Stale signing headers are also stripped on every fail-open path, so a fail-open no longer transmits a signature that does not authenticate the token and body sent with it (#61).

## [3.5.13] - 2026-09-25

### Fixed
- The async convenience methods (`dataWithApproov`, `uploadWithApproov` and `downloadWithApproov`) no longer create a new `URLSession` for each call that supplies a delegate (#63). That session was built from the inherited `configuration` and `delegateQueue`, which belong to the `URLSession` base class that `ApproovURLSession` cannot initialise: `configuration` was `nil` behind a non-optional type, so the caller's headers, timeouts, cookie storage and cache were silently dropped, and the session was never invalidated, leaking it and its delegate for the lifetime of the process (present since 3.2.5). The task is now created on the pinned session and the delegate is attached to it with `URLSessionTask.delegate`, as `URLSession.data(for:delegate:)` does, so the task releases it on completion and the request reuses the session's connections. Server-trust challenges still go through Approov pinning even when the supplied delegate implements `urlSession(_:didReceive:completionHandler:)`, which `URLSession` would otherwise offer that challenge ahead of the session delegate.
- `ApproovURLSession.configuration` and `ApproovURLSession.delegateQueue` now return the configuration and queue the session was created with, rather than the values of the uninitialised base class.
- A completion that reports neither an error nor a result now throws `URLError(.badServerResponse)` from the async convenience methods instead of trapping on a force unwrap.
- `downloadWithApproov` no longer returns the URL of a file that `URLSession` has already deleted. `URLSession` removes a download's temporary file when the task's completion handler returns, and the async methods returned to their caller after that, so reading the returned URL raced with the file's deletion and failed with `NSPOSIXErrorDomain` 2 (present since 3.2.5). The file is now moved to a new location in the temporary directory before the handler returns, so the caller owns it and must move or delete it, as with `URLSession.download(for:)`.

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
