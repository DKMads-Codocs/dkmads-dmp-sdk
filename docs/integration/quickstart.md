# Publisher Integration: DMP + SSP

Unified guide for publishers using **DKMads DMP** (audience data) and **DKMads SSP** (monetization) together.

---

## Overview

| System  | Role                                      | SDK init                                  |
| ------- | ----------------------------------------- | ----------------------------------------- |
| **DMP** | Profiles, traits, demographics, audiences | `appKey` (`dmp_live_...`)                 |
| **SSP** | Ad serving, bid-time audience lookup      | `integrationKey` from linked SSP property |

Both SDKs must share the same **`device_pid`** and **`user_pid`** so SSP bid requests resolve DMP audiences correctly. See [SSP_DMP_IDENTITY.md](./SSP_DMP_IDENTITY.md).

---

## Prerequisites

1. DMP workspace with at least one team member (admin)
2. **SSP workspace linked** to your DMP workspace (`workspace_ssp_links`, status `active`)
3. SSP property created in the SSP dashboard (note property UUID + integration key)

Platform admins link workspaces at **Platform → Workspaces → SSP workspace link**.  
Workspace admins complete property mapping in **Onboarding** (`/onboarding`) or **Properties**.

---

## Quick start (onboarding wizard)

1. Sign in and select your DMP workspace
2. Open **Onboarding** (`/onboarding`)
3. Confirm SSP workspace is linked (green / active)
4. Enter property name + SSP property UUID + SSP integration key
5. Copy **both keys** and the generated SDK snippet

API equivalent (workspace admin):

```http
POST /api/workspaces/current/linked-properties
Authorization: Bearer {jwt}
X-Workspace-Id: {dmp_workspace_id}
Content-Type: application/json

{
  "name": "My Website",
  "platform": "web",
  "domain": "example.com",
  "sspPropertyId": "ssp-property-uuid",
  "sspIntegrationKey": "integration_key_from_ssp",
  "sspLinkStatus": "pending"
}
```

Response includes `appKey` (shown once), `property.id`, and `sspLink`.

---

## SDK initialization

### Web / JavaScript

```javascript
import DMP from '@dkmads/dmp-sdk';
import SSP from '@dkmads/ssp-sdk';

// 1. DMP — canonical profile + traits
await DMP.init({ appKey: 'dmp_live_...' });

// 2. Demographics on every app open (required — see PUBLISHER_DEMOGRAPHICS.md)
await DMP.identify(userId, {
  'demographic.age_range': '25-34',
  'demographic.gender': 'female',
});

// 3. SSP — ads
await SSP.init({
  integrationKey: 'your-ssp-integration-key',
  baseUrl: 'https://ssp.dkmads.com',
});

// 4. Shared identity for bid-time eval (recommended)
const { devicePid, userPid } = DMP.getSharedIdentity();
SSP.linkDmpIdentity({ devicePid, userPid });

// Alternate: auto-read DMP storage after DMP.init
// SSP.linkDmpIdentity();
// — or SSP.init({ ..., useDmpIdentity: true });
```

### Manual init (advanced)

If SSP passes explicit DMP IDs, they **must match** the linked property pair in DMP:

```javascript
await DMP.init({
  appKey: 'dmp_live_...',
  workspaceId: 'dmp-workspace-uuid', // must match workspace_ssp_links.dmp_workspace_id
  propertyId: 'dmp-property-uuid', // must match property_ssp_links.dmp_property_id
});
```

Mismatched IDs are rejected at ingest or return empty eval results. See [SDK_API.md](./SDK_API.md#ssp-linked-properties).

---

## Activation checklist

| Step | Owner           | Action                                                               |
| ---- | --------------- | -------------------------------------------------------------------- |
| 1    | Platform admin  | Link DMP ↔ SSP workspace, set status `active`                        |
| 2    | Workspace admin | Create linked property pair (`/onboarding`)                          |
| 3    | Workspace admin | Mark property SSP link `active` on Properties page                   |
| 4    | Publisher       | Install both SDKs, init with keys from step 2                        |
| 5    | Publisher       | Send `demographic.age_range` on every app open                       |
| 6    | Publisher       | Pass `device_pid` / `user_pid` to SSP targeting signals              |
| 7    | SSP ops         | Confirm bid middleware calls DMP eval with linked `dmp_workspace_id` |

---

## Bid-time flow

```
Publisher app
  → DMP SDK ingest (traits, device_pid)
  → Stitcher writes demographics:{ws}:{device_pid} to Redis
  → Audience worker writes membership:{ws}:{device_pid}

SSP bid request
  → GET /v1/targeting/evaluate?workspace_id={dmp_ws}&device_pid={same_id}
  → Returns audience_ids + demographics
  → Campaign targeting applies segments
```

Eval and catalog APIs require an **active** workspace SSP link. Use workspace-scoped `dmp_sst_*` tokens in production.

---

## Troubleshooting

| Issue                            | Fix                                               |
| -------------------------------- | ------------------------------------------------- |
| Onboarding blocked — no SSP link | Share workspace ID with platform admin            |
| Empty audiences at bid time      | Same `device_pid` in DMP + SSP; compute audiences |
| Empty demographics               | Send canonical traits; confirm stitcher running   |
| `403 workspace is not linked`    | Activate workspace link on both sides             |
| Property link pending            | Mark active on Properties after SSP confirms      |

---

## Related docs

- [SDK_API.md](./SDK_API.md) — DMP SDK methods and manual init rules
- [PUBLISHER_DEMOGRAPHICS.md](./PUBLISHER_DEMOGRAPHICS.md) — age range & gender requirements
- [SSP_DMP_IDENTITY.md](./SSP_DMP_IDENTITY.md) — lookup keys and tokens
- [PLATFORM_UPGRADE_PLAN.md](./PLATFORM_UPGRADE_PLAN.md) — integration phases

---

## SSP SDK note (Phase 12.4)

SSP SDKs ship `linkDmpIdentity()` and `useDmpIdentity` init option (web, iOS, Android, Flutter). See SSP repo `docs/integration/dmp-identity.md`. Until you upgrade SSP SDK bundles, use `setTargetingSignals({ devicePid: DMP.getDevicePid() })` explicitly.

---

## Option B — SSP forwards FPD to DMP (no DMP SDK)

When the publisher uses **SSP SDK only**, the SSP server forwards `syncFirstPartyProfile()` / `fpd/*` data to DMP after each local upsert (enable in SSP **Integrations → DKMads DMP → SSP-only FPD forward**).

```
POST /v1/ingest/fpd/mobile  (ingest service, port 4001)
Authorization: Bearer {ssp_server_token}
```

Requires active workspace + property links. Signals are mapped to canonical DMP traits; invalid demographics are rejected at the boundary.

Full contract: [SSP_FPD_BRIDGE.md](./SSP_FPD_BRIDGE.md) · SSP docs: `ssp.dkmads.com` → `docs/integration/dmp-fpd-forward.md`
