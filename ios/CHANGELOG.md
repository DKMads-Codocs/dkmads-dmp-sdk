# Changelog — DKMads DMP iOS SDK

All notable changes to `DKMadsDMP` (SPM / CocoaPods) are documented here.

## [0.1.0] — 2026-06-18

### Added

- `DMP.configure(_:)` — preferred Swift 6 entry point (replaces enum `init`)
- `identify`, `track`, `setTrait`, `setTraits`, `setContext`, `setConsent`, `optOut`, `reset`, `flush`
- `getDevicePid()`, `getUserPid()`, `getSharedIdentity()` for SSP identity handoff
- `DMPDemographics` helpers
- CocoaPods spec `DKMadsDMP.podspec` @ 0.1.0

### Fixed

- **P1** Swift 6 / Xcode 26 — `DMP.init` deprecated; use `DMP.configure(_:)`
- **P1** `@MainActor` isolation — `DMP` enum matches `DMPClient`
- **P1** Invalid double-unwrap in `syncOptOutToServer` URLRequest construction
- `setContext()` merges into stored event context on flush

### Deprecated

- `DMP.init(_:)` — alias for `configure`; will be removed in 0.2.0
