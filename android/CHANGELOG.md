# Changelog — DKMads DMP Android SDK

All notable changes to `com.dkmads:dmp-sdk` are documented here.

## [0.1.0] — 2026-06-18

### Added

- `DMP.init`, `identify`, `track`, `setTrait`, `setTraits`, `setContext`, `setConsent`, `optOut`, `reset`, `flush`
- `getDevicePid()`, `getUserPid()`, `getSharedIdentity()` for SSP identity handoff
- `Demographics` helpers (`ageRangeFromDateOfBirth`, `normalizeAgeRange`, etc.)
- Maven publish config (`com.dkmads:dmp-sdk:0.1.0`)

### Fixed

- **P0** Duplicate `context` property — renamed to `appContext` + `eventContext`
- **P0** `JSONObject.clear()` compile error — `reset()` reassigns new `JSONObject()` instances
- **P0** Init callback always `true` — callback now reports bridge/init success; added `isInitialized()` / `isBridgeResolved()`
