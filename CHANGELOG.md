# Changelog

All notable changes to this package will be documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## [3.5.6] - 2026-01-29

### Added
- ApproovServiceMutator protocol with default behavior to centralize decision points in the service flow.
- Mutator hooks for precheck, token fetch, secure string fetch, custom JWT fetch, interceptor decisions, and pinning.
- SFV helper to serialize signature values

### Changed
- ApproovService now routes decision logic through the service mutator and exposes set/get APIs.
- Signature header values now use base64-encoded strings (per spec) instead of binary data.
- Pinning delegate now checks the mutator before applying pinning logic.
- CocoaPods spec is now maintained only at the repository root (per-version podspec files remain,but will not be updated).

### Deprecated
- ApproovInterceptorExtensions in favor of ApproovServiceMutator.
