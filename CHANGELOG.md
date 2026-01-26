# Changelog

All notable changes to this package will be documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## [Unreleased] - 2026-01-26

### Added
- ApproovServiceMutator protocol with default behavior to centralize decision points in the service flow.
- Mutator hooks for precheck, token fetch, secure string fetch, custom JWT fetch, interceptor decisions, and pinning.
- SFV helper to serialize signature values as string items.

### Changed
- ApproovService now routes decision logic through the service mutator and exposes set/get APIs.
- ApproovDefaultMessageSigning updated to emit signature values as strings per spec.
- Pinning delegate now checks the mutator before applying pinning logic.

### Deprecated
- ApproovInterceptorExtensions in favor of ApproovServiceMutator.

