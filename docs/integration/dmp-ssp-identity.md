# SSP ↔ DMP Identity Mapping

Bid-time audience evaluation (`GET /v1/targeting/evaluate`) resolves profiles by **lookup key** — the same identifier values your publisher SDKs send to DMP ingest.

---

## Lookup keys (must match ingest)

| Eval query param | DMP ingest identifier `type` | When to use                                |
| ---------------- | ---------------------------- | ------------------------------------------ |
| `device_pid`     | `device_pid`                 | Anonymous / pre-login sessions (web, app)  |
| `user_pid`       | `user_pid`                   | Logged-in user (stable across devices)     |
| `profile_id`     | DMP internal UUID            | Server-side only — rarely used at bid time |

**Rule:** SSP must pass the **same** `device_pid` and/or `user_pid` that the DMP SDK sends on every event. If SSP generates its own device ID and DMP uses a different one, eval returns empty audiences and demographics.

---

## Recommended publisher pattern

```javascript
// 1. DMP SDK — establishes canonical profile + traits
await DMP.init({ appKey: 'dmp_live_...' });
const { devicePid, userPid } = DMP.getSharedIdentity();

// 2. SSP SDK — monetization (separate init)
await SSP.init({ integrationKey: '...', baseUrl: 'https://ssp.dkmads.com' });

// 3. Share DMP identifiers (preferred)
SSP.linkDmpIdentity({ devicePid, userPid });

// Legacy manual path:
// SSP.setTargetingSignals({ devicePid, userPid: loggedInUserId ?? undefined });
```

On the SSP bid path, resolve `devicePid` / `userPid` from the ad request and call:

```
GET /v1/targeting/evaluate?workspace_id={dmp_workspace_id}&device_pid={devicePid}
Authorization: Bearer {ssp_eval_token}
```

Use the **DMP workspace ID** from the linked workspace pair (Settings → SSP Integration), not the SSP workspace UUID.

### SSP `linkDmpIdentity` (Phase 2)

SSP SDKs can read the DMP `device_pid` from local storage instead of generating a separate SSP id:

| Platform | Storage read by SSP                                                                |
| -------- | ---------------------------------------------------------------------------------- |
| Web      | `localStorage['dkmads_dmp_device_pid']`                                            |
| iOS      | `UserDefaults['dkmads_dmp_device_pid']`                                            |
| Android  | `SharedPreferences('dkmads_dmp')` → `dkmads_dmp_device_pid` or legacy `device_pid` |

Call `SSP.linkDmpIdentity()` after both SDKs initialize, or pass `useDmpIdentity: true` on SSP init. Verify with `SSP.diagnostics().identity_source` (`dmp_storage` / `dmp_explicit`).

---

## Demographics at bid time

The stitcher writes Redis keys after trait upsert:

```
demographics:{dmp_workspace_id}:{lookup_key}
```

Payload example (no PII):

```json
{
  "age_range": "25-34",
  "gender": "female",
  "country": "US",
  "language": "en"
}
```

Lookup key is `device_pid` or `user_pid` — same as eval membership keys (`membership:{workspace}:{lookup_key}`).

Demographic values must use [canonical buckets](PUBLISHER_DEMOGRAPHICS.md). Invalid values are rejected at ingest and never appear in Redis.

---

## Authentication

| Token                       | Scope                 | Use case                                |
| --------------------------- | --------------------- | --------------------------------------- |
| Global `SSP_SERVER_TOKEN`   | All linked workspaces | Platform ops, load tests                |
| Workspace `dmp_sst_*` token | Single DMP workspace  | Production SSP bid engine per publisher |

Workspace tokens are created in **Settings → Developer** (admin) or via `POST /api/workspaces/current/server-tokens`.

Both token types require an **active** `workspace_ssp_links` row for the target `workspace_id`.

---

## Workspace + property linking

Before eval returns data:

1. Platform admin links DMP workspace ↔ SSP workspace (`status: active`)
2. Workspace admin maps each DMP property ↔ SSP property (Properties page)
3. Publisher initializes both SDKs with keys from the linked property pair

See [PLATFORM_UPGRADE_PLAN.md](PLATFORM_UPGRADE_PLAN.md) Phase 10–11 for the full integration checklist.

---

## Failure modes

| Symptom                                  | Likely cause                                                   |
| ---------------------------------------- | -------------------------------------------------------------- |
| Empty `audience_ids`                     | Audience not computed, or lookup key mismatch                  |
| Empty `demographics`                     | Traits not ingested, stitcher not running, or wrong lookup key |
| `403 workspace is not linked to SSP`     | `workspace_ssp_links.status` is not `active`                   |
| `403 token not valid for this workspace` | Workspace-scoped token used with wrong `workspace_id`          |
| Opt-out user                             | `audience_ids` and `demographics` intentionally empty          |

---

## Related endpoints

| Endpoint                              | Purpose                                                          |
| ------------------------------------- | ---------------------------------------------------------------- |
| `GET /v1/targeting/evaluate`          | Bid-time membership + demographics (eval service, port 4002)     |
| `GET /v1/ssp-links/status`            | Mutual link verification (SSP Integrations → Verify mutual link) |
| `GET /v1/audiences?workspace_id=`     | Campaign UI audience catalog (API service)                       |
| `GET /v1/audiences/:id/rules-summary` | Human-readable rules for SSP display (no PII)                    |
