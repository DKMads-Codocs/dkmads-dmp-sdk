# DKMads DMP SDK API

Shared interface across all five SDKs (Web, iOS, Android, Flutter, Unity).

## Methods

| Method                      | Description                                                                    |
| --------------------------- | ------------------------------------------------------------------------------ |
| `init(config)`              | Initialize SDK with app_key (auto-link) or workspace_id + property_id (manual) |
| `identify(userId, traits?)` | Link events to a known user                                                    |
| `track(event, properties?)` | Record a behavioral event                                                      |
| `setTrait(key, value)`      | Set a single profile trait                                                     |
| `setTraits(traits)`         | Set multiple traits                                                            |
| `setContext(context)`       | Set page/screen context                                                        |
| `setConsent(consent)`       | Record GDPR/CCPA/TCF 2.3 consent; gates subsequent collection                  |
| `optOut()`                  | Stop all collection locally, persist, and sync to server                       |
| `reset()`                   | Clear user session                                                             |
| `flush()`                   | Force-send queued events                                                       |
| `getDevicePid()`            | Stable pseudonymous device id (same key SSP reads via `linkDmpIdentity`)       |
| `getUserPid()`              | Current logged-in user id from `identify()`, or `null`                         |
| `getSharedIdentity()`       | `{ devicePid, userPid }` for SSP bid-time eval                                 |

### Platform init notes

| Platform              | Entry point                           | Notes                                                                         |
| --------------------- | ------------------------------------- | ----------------------------------------------------------------------------- |
| Web / Flutter / Unity | `init(config)`                        | Standard                                                                      |
| **iOS**               | `await DMP.configure(config)`         | Use `configure` — Swift 6 reserves `init` on enums                            |
| **Android**           | `DMP.init(context, config) { ok -> }` | Callback receives `false` if bridge resolve fails; check `isBridgeResolved()` |

## Init Config

```typescript
interface InitConfig {
  appKey: string; // Required
  workspaceId?: string; // Manual mode
  propertyId?: string; // Manual mode
  apiHost?: string; // Default: https://ingest.dmp.dkmads.com
  flushIntervalMs?: number; // Default: 10000
  batchSize?: number; // Default: 20
  collectDeviceIds?: boolean; // Default: true; when false, skip advertising IDs
  debug?: boolean;
}
```

## Consent & Opt-Out (Phase 3)

Collection is gated by consent state and opt-out status:

- **GDPR**: requires TCF purpose 1 (storage) when `gdprApplies: true`
- **CCPA**: blocks collection when `usPrivacy` third character is `Y`
- **iOS**: IDFA only collected when ATT status is `authorized` and `collectDeviceIds` is true
- **Android**: GAID skipped when Limit Ad Tracking (LAT) is enabled

```typescript
await DMP.setConsent({
  gdprApplies: true,
  tcfString: 'CP...',
  purposes: { '1': true, '7': true },
  usPrivacy: '1YNN',
});

DMP.optOut(); // persists locally + POST /v1/ingest/opt-out
```

On `init()`, SDKs check `GET /v1/opt-out/status?device_pid=...` and honor server-side opt-out (e.g. from DSAR delete).

## Demographics (age range & gender)

**Full publisher guide:** [PUBLISHER_DEMOGRAPHICS.md](./PUBLISHER_DEMOGRAPHICS.md)

Publishers must send **canonical** `demographic.age_range` on **every app open** (computed locally from date of birth — **never send DOB to the DMP**). Custom values like `19-26` or `30` are **rejected at ingest**.

Allowed `demographic.age_range` values:

`18-24` | `25-34` | `35-44` | `45-54` | `55-64` | `65+` | `unknown`

```typescript
import DMP, { ageRangeFromDateOfBirth } from '@dkmads/dmp-sdk';

await DMP.setConsent({ gdprApplies: true, tcfString: 'CP...' });

DMP.identify('user-123', {
  'demographic.age_range': ageRangeFromDateOfBirth(user.dateOfBirth),
  'demographic.gender': 'female',
});
```

Helpers exported from `@dkmads/sdk-core` / web SDK:

- `ageRangeFromDateOfBirth(dob)` — recommended
- `ageRangeFromAge(age)`
- `STANDARD_AGE_RANGES` — allowed bucket list

## Installation

| Platform | Command                                                                         |
| -------- | ------------------------------------------------------------------------------- |
| Web      | `npm install @dkmads/dmp-sdk`                                                   |
| iOS      | SPM: `https://github.com/DKMads-Company-Limited/dmp.dkmads.com` path `sdks/ios` |
| Android  | `implementation("com.dkmads:dmp-sdk:0.1.0")`                                    |
| Flutter  | `flutter pub add dkmads_dmp`                                                    |
| Unity    | UPM: `com.dkmads.dmp` from git URL                                              |

## Auto-link vs Manual

**Auto-link** (recommended):

```javascript
await DMP.init({ appKey: 'dmp_live_xxxx' });
```

The ingest service resolves `appKey` → `workspace_id` + `property_id` via the `app_keys` table. No extra IDs required.

**Manual** (SSP co-init or server-side):

```javascript
await DMP.init({
  appKey: 'dmp_live_xxxx',
  workspaceId: 'dmp-workspace-uuid',
  propertyId: 'dmp-property-uuid',
});
```

### SSP-linked properties

When SSP (or your app) passes explicit `workspaceId` / `propertyId`, they **must match** the DMP ↔ SSP link tables:

| Field         | Must match                                                       |
| ------------- | ---------------------------------------------------------------- |
| `workspaceId` | `workspace_ssp_links.dmp_workspace_id` for your publisher        |
| `propertyId`  | `property_ssp_links.dmp_property_id` for the linked SSP property |

If IDs do not match a linked pair:

- Ingest may accept events but they attach to the wrong property
- Bid-time eval (`/v1/targeting/evaluate`) returns empty audiences for mismatched lookup keys
- SSP catalog APIs return `403` when the workspace SSP link is not active

**Recommended:** use auto-link (`appKey` only) for DMP init, and `integrationKey` for SSP init. Share `device_pid` between both SDKs. See [PUBLISHER_INTEGRATION.md](./PUBLISHER_INTEGRATION.md).

Platform admins create linked pairs via `POST /api/workspaces/current/linked-properties` or the **Onboarding** wizard (`/onboarding`).
