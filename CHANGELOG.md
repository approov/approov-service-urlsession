# Changelog

All notable changes to this package will be documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## [3.5.6] - 2026-01-29

### Added
- ApproovServiceMutator protocol with default behavior to centralize decision points in the service flow.
- Mutator hooks for precheck, token fetch, secure string fetch, custom JWT fetch, interceptor decisions, and pinning.
- REFERENCE.md & CHANGELOG.md & APPROOV_SERVICE_MUTATOR.md
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