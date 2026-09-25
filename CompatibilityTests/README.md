# Compatibility tests

Compile-only fixtures that protect apps depending on this package from source-breaking changes.

| Target | Language mode | Written like |
|---|---|---|
| `Swift5Consumer` | Swift 5 | An existing app with no concurrency annotations: completion handlers that mutate captured state, a stateful mutator class, the full configuration API |
| `Swift6Consumer` | Swift 6 | An app adopting Swift concurrency: a shared session in a `static let`, `@MainActor` view models, actors, detached tasks and task groups that pass service-layer values across isolation boundaries |

Both targets are built with `-warnings-as-errors`, so a change that adds a warning to existing app code fails too. Calls to deprecated APIs are left out, because their deprecation warnings are intentional.

Run from the repository root, with the same environment variables as the tests:

```bash
swift build --package-path CompatibilityTests
```

When a change makes a fixture fail, treat it as a breaking change for apps: find a compatible way to make it, or ship it in a major release. Don't adjust the fixture to fit. The public API is also checked for breaking changes against the latest release in CI (`swift package diagnose-api-breaking-changes`). Breakages that were reviewed and are known to be source compatible are listed in `.github/api-breakage/allowlist.txt`.
