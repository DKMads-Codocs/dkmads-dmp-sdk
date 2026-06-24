# SSP FPD → DMP Ingest Bridge (Option B)

Server-to-server path for publishers using the **SSP SDK only** (no DMP SDK). SSP forwards mobile first-party profile (FPD) signals to DMP ingest after workspace/property linking is active.

**Recommended path remains Option A:** publisher sends data directly via DMP SDK `identify()` / `setTraits()`. Use this bridge only when the DMP SDK is not installed on the client.

---

## Endpoint

```
POST https://ingest.dmp.dkmads.com/v1/ingest/fpd/mobile
Authorization: Bearer {ssp_server_token}
Content-Type: application/json
```

Local dev: `http://127.0.0.1:4001/v1/ingest/fpd/mobile`

### Authentication

Same tokens as bid-time eval:

| Token                       | Notes                    |
| --------------------------- | ------------------------ |
| Global `SSP_SERVER_TOKEN`   | Dev / platform ops       |
| Workspace `dmp_sst_*` token | Production per publisher |

### Prerequisites

1. Active `workspace_ssp_links` row for `dmpWorkspaceId`
2. Linked DMP property (`property_ssp_links`) — provide `dmpPropertyId` or `sspPropertyId`
3. SSP workspace ID in payload must match link (if provided)

---

## Request body

```json
{
  "dmpWorkspaceId": "61fb4f29-dc38-47e0-bbc4-da74f2852a66",
  "sspWorkspaceId": "a0000000-0000-4000-8000-000000000001",
  "sspPropertyId": "ssp-property-uuid",
  "devicePid": "device-abc-123",
  "userPid": "user-456",
  "signals": {
    "ageRange": "25-34",
    "gender": "female",
    "country": "US",
    "language": "en",
    "interests": { "sports": true, "gaming": false },
    "loyaltyTier": "gold"
  },
  "consent": {
    "gdprApplies": true,
    "tcfString": "CP...",
    "purposes": { "1": true, "4": true }
  }
}
```

| Field                              | Required     | Description                           |
| ---------------------------------- | ------------ | ------------------------------------- |
| `dmpWorkspaceId`                   | Yes          | DMP workspace UUID                    |
| `sspPropertyId` or `dmpPropertyId` | One required | Resolves linked property              |
| `devicePid`                        | Yes          | Must match SSP bid-time lookup key    |
| `userPid`                          | No           | Logged-in user ID                     |
| `signals`                          | No           | SSP FPD fields (mapped below)         |
| `consent`                          | No           | Forwarded to stitcher consent handler |

---

## Signal mapping

Implemented in `@dkmads/shared` → `mapSspFpdSignalsToDmpTraits()`.

| SSP signal                     | DMP trait                                        |
| ------------------------------ | ------------------------------------------------ |
| `ageRange` / `age_range`       | `demographic.age_range` (canonical buckets only) |
| `age` (number)                 | `demographic.age_range` via `ageRangeFromAge()`  |
| `gender`                       | `demographic.gender`                             |
| `incomeRange` / `income_range` | `demographic.income_range`                       |
| `language` / `locale`          | `demographic.language` (ISO-639-1)               |
| `country`                      | `geo.country`                                    |
| `region`                       | `geo.region`                                     |
| `city`                         | `geo.city`                                       |
| `loyaltyTier` / `loyalty_tier` | `custom.loyalty_tier`                            |
| `interests.{name}`             | `interest.{name}` (boolean)                      |

**Non-canonical values are rejected** at the bridge boundary (same rules as SDK ingest). Example: `ageRange: "19-26"` → rejected, not stored.

---

## Response

```json
{
  "accepted": true,
  "traitsAccepted": 4,
  "traitsRejected": 1,
  "rejected": [
    { "field": "ageRange", "value": "19-26", "reason": "non-canonical age_range bucket" }
  ]
}
```

HTTP `202` on success. Profile update is async via Kafka → stitcher → Redis demographics.

---

## SSP implementation sketch

When `syncFirstPartyProfile()` is called on the SSP SDK:

1. Store FPD in SSP database (existing behavior)
2. If `dmp_workspace_id` link is active, POST to DMP ingest bridge
3. Use same `devicePid` / `userPid` as bid middleware

```typescript
await fetch(`${DMP_INGEST_URL}/v1/ingest/fpd/mobile`, {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${SSP_TO_DMP_TOKEN}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    dmpWorkspaceId: workspace.dmpWorkspaceId,
    sspPropertyId: property.id,
    devicePid: profile.devicePid,
    userPid: profile.userId,
    signals: profile.signals,
    consent: profile.consent,
  }),
});
```

---

## Related docs

- [PUBLISHER_INTEGRATION.md](./PUBLISHER_INTEGRATION.md) — Option A dual-SDK (recommended)
- [SSP_DMP_IDENTITY.md](./SSP_DMP_IDENTITY.md) — lookup key alignment
- [PUBLISHER_DEMOGRAPHICS.md](./PUBLISHER_DEMOGRAPHICS.md) — canonical demographic values
