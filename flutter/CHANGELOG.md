# Changelog — DKMads DMP Flutter SDK

All notable changes to `dkmads_dmp` on pub.dev are documented here.

## [0.1.0] — 2026-06-18

### Added

- Pure-Dart DMP client (`init`, `identify`, `track`, `setTraits`, `setContext`, `flush`, etc.)
- Public `getDevicePid()`, `getSharedIdentity()` for SSP identity handoff
- `demographics.dart` export (age-range helpers)
- Android / iOS plugin stubs for GAID and LAT

### Fixed

- Stable UUID `device_pid` persistence via `shared_preferences`

### Pending (0.2.0)

- pub.dev publish
- CI matrix per `TEST_MATRIX.md`
