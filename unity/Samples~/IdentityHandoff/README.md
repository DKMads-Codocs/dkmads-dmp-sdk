# Identity Handoff Sample

Demonstrates DMP init → `GetSharedIdentity()` → SSP bid-time eval wiring.

## Setup

1. Install `com.dkmads.dmp` via UPM (git URL or local path).
2. Import **Samples → Identity Handoff** from Package Manager.
3. Create an empty scene, add `IdentityHandoffSample` to a GameObject.
4. Set `appKey` in the Inspector to your DMP live key.
5. Play — check Console for `devicePid` / `userPid`.

## SSP integration

Pass `GetSharedIdentity().DevicePid` to your SSP SDK's `linkDmpIdentity()` (or equivalent) so bid-time `/v1/targeting/evaluate` resolves audiences.

See [SSP_DMP_IDENTITY.md](../../../docs/SSP_DMP_IDENTITY.md).
