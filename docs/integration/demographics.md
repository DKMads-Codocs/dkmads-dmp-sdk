# Publisher Guide: Demographics (Age Range & Gender)

This document is **required reading** for all DKMads DMP publisher integrations.

The DMP accepts **only canonical demographic values**. Custom age brackets (for example `19-26`, `30`, or `mid-30s`) are **rejected at ingest** and will not appear in audiences or activations.

---

## Summary

| Rule                 | Requirement                                                 |
| -------------------- | ----------------------------------------------------------- |
| **Trait key**        | `demographic.age_range` and `demographic.gender`            |
| **Who computes age** | **Publisher app** (from date of birth in your own database) |
| **What DMP stores**  | Canonical bucket string only — **never send date of birth** |
| **When to send**     | **Every app open** after login and consent                  |
| **Invalid values**   | Rejected; counted in `rejectedTraits` ingest metric         |

---

## Allowed age range values (exact strings)

Use **one of these values only**. Copy-paste exactly — case and format matter.

| Value     | Meaning                                        |
| --------- | ---------------------------------------------- |
| `18-24`   | Age 18 through 24                              |
| `25-34`   | Age 25 through 34                              |
| `35-44`   | Age 35 through 44                              |
| `45-54`   | Age 45 through 54                              |
| `55-64`   | Age 55 through 64                              |
| `65+`     | Age 65 and older                               |
| `unknown` | Under 18, or age not available / not consented |

### Rejected examples (do not send)

| Value     | Why rejected                   |
| --------- | ------------------------------ |
| `19-26`   | Custom bracket — not canonical |
| `30`      | Raw age — use a bucket         |
| `25 - 34` | Spaces not allowed             |
| `25–34`   | Wrong dash character (en-dash) |
| `mid-30s` | Free text                      |
| `35`      | Raw age                        |

---

## Allowed gender values

| Value     | Notes                                     |
| --------- | ----------------------------------------- |
| `male`    | Lowercase preferred; `Male` is normalized |
| `female`  |                                           |
| `other`   |                                           |
| `unknown` | Not provided or not consented             |

---

## Integration pattern (required)

### 1. Consent first (GDPR)

When the user is in the EU/EEA/UK, call `setConsent()` **before** sending demographics.

```javascript
await DMP.setConsent({
  gdprApplies: true,
  tcfString: 'CP...', // from your CMP
});
// Requires TCF purpose 1 (storage) and purpose 4 (personalized ads profile)
```

### 2. On every app open (after login)

Compute the bucket **in your app** from the user profile you already have. Send only the bucket.

```javascript
import DMP, { ageRangeFromDateOfBirth } from '@dkmads/dmp-sdk';

async function onAppOpen(user) {
  await DMP.setConsent(/* from CMP */);

  const ageRange = user.dateOfBirth ? ageRangeFromDateOfBirth(user.dateOfBirth) : 'unknown';

  DMP.identify(user.id, {
    'demographic.age_range': ageRange,
    'demographic.gender': user.gender ?? 'unknown',
  });

  DMP.track('app_open');
}
```

**Important:**

- Compute age from **your** user record — do not send `dateOfBirth` to the DMP.
- Call `identify()` on **every session** so buckets stay correct when users age into a new bracket.
- Use the shared helper `ageRangeFromDateOfBirth()` from the SDK (see below) so all publishers use the same buckets.

---

## SDK helpers (use these — do not invent your own buckets)

Web / TypeScript (`@dkmads/dmp-sdk` / `@dkmads/sdk-core`):

```typescript
import { ageRangeFromDateOfBirth, ageRangeFromAge, STANDARD_AGE_RANGES } from '@dkmads/dmp-sdk';

// From ISO date string or Date (recommended)
const bucket = ageRangeFromDateOfBirth('1990-06-15'); // → "35-44"

// From integer age
const bucket2 = ageRangeFromAge(28); // → "25-34"

// Reference list for validation in your app
console.log(STANDARD_AGE_RANGES);
// ["18-24","25-34","35-44","45-54","55-64","65+","unknown"]
```

### Kotlin (Android) — reference implementation

```kotlin
fun ageRangeFromAge(age: Int): String = when {
    age < 18 -> "unknown"
    age <= 24 -> "18-24"
    age <= 34 -> "25-34"
    age <= 44 -> "35-44"
    age <= 54 -> "45-54"
    age <= 64 -> "55-64"
    else -> "65+"
}

fun ageFromDateOfBirth(year: Int, month: Int, day: Int): Int {
    val today = java.time.LocalDate.now()
    var age = today.year - year
    val birthday = java.time.LocalDate.of(year, month, day)
    if (today.isBefore(birthday.withYear(today.year))) age--
    return age
}

// On app open after login:
DMP.identify(userId, mapOf(
    "demographic.age_range" to ageRangeFromAge(ageFromDateOfBirth(dobYear, dobMonth, dobDay)),
    "demographic.gender" to (user.gender ?: "unknown"),
))
```

### Swift (iOS) — reference implementation

```swift
func ageRangeFromAge(_ age: Int) -> String {
    switch age {
    case ..<18: return "unknown"
    case 18...24: return "18-24"
    case 25...34: return "25-34"
    case 35...44: return "35-44"
    case 45...54: return "45-54"
    case 55...64: return "55-64"
    default: return "65+"
    }
}

// On app open after login:
DMP.identify(userId, traits: [
    "demographic.age_range": ageRangeFromAge(user.age),
    "demographic.gender": user.gender ?? "unknown",
])
```

---

## Session flow checklist

```
[ ] App launches
[ ] CMP shown (EU users) → DMP.setConsent()
[ ] User logs in → load profile from YOUR backend
[ ] Compute demographic.age_range locally (never send DOB to DMP)
[ ] DMP.identify(userId, { demographic.age_range, demographic.gender })
[ ] DMP.track(...) for behavioral events
```

---

## What happens when you send invalid data

1. **Ingest** runs `filterEventTraits()` on every batch and identify request.
2. Invalid `demographic.age_range` is **dropped** (not stored).
3. `rejectedTraits` count increases in the ingest response / dashboard metrics.
4. **Stitcher** also skips invalid demographics (defense in depth).
5. Audience rules will **not** match users missing a valid bucket.

Example batch response:

```json
{
  "accepted": 1,
  "rejectedTraits": 1,
  "geoEnriched": true
}
```

---

## API reference

| Endpoint                   | Demographics handling                             |
| -------------------------- | ------------------------------------------------- |
| `POST /v1/ingest/batch`    | Traits filtered per event                         |
| `POST /v1/ingest/identify` | Traits filtered on body                           |
| `GET /api/traits/taxonomy` | Returns `demographics` object with allowed values |

Taxonomy response includes:

```json
{
  "demographics": {
    "ageRange": {
      "traitKey": "demographic.age_range",
      "allowedValues": ["18-24", "25-34", "35-44", "45-54", "55-64", "65+", "unknown"],
      "updatePolicy": "Send on every app open after login and consent (recommended).",
      "rejectedExamples": ["19-26", "30", "25 - 34", "mid-30s", "35"]
    }
  }
}
```

---

## GDPR & privacy

| Topic           | Policy                                                   |
| --------------- | -------------------------------------------------------- |
| Date of birth   | **Do not send** to DMP — compute bucket in publisher app |
| What DMP stores | `demographic.age_range` and `demographic.gender` only    |
| Lawful basis    | Publisher CMP consent (TCF purpose 1 + 4 for EU)         |
| Opt-out         | `DMP.optOut()` stops collection; server honors opt-out   |
| Erasure         | Submit DSAR delete via DMP compliance UI                 |

---

## FAQ

**Q: Can we send birth year instead of age range?**  
A: No. Send only canonical `demographic.age_range`. Compute it in your app.

**Q: What loyalty tier values are allowed?**  
A: `bronze`, `silver`, `gold`, `platinum`, `unknown` only.

**Q: What interest / engagement values?**  
A: Boolean `true` or `false` only (string `"true"` / `"false"` accepted at ingest).

**Q: We only collect age once at signup — is that enough?**  
A: No. Buckets must be refreshed on app open so users move brackets when they age.

**Q: User is 17 — what do we send?**  
A: `unknown`. Do not target minors for personalized ads.

**Q: Can we add custom buckets like `19-26` for our own analytics?**  
A: No. Use `custom.*` traits for non-demographic publisher fields. Age must use canonical buckets.

**Q: How do we test our integration?**  
A: Send `identify` with `demographic.age_range: '19-26'` — confirm `rejectedTraits > 0` and profile has no invalid value in the DMP UI.

---

## Support

- Trait taxonomy: **Developer** page in DMP console or `GET /api/traits/taxonomy`
- Full collection guide: [TRAIT_COLLECTION.md](./TRAIT_COLLECTION.md)
- SDK API: [SDK_API.md](./SDK_API.md)
- Compliance: [RUNBOOK.md](./RUNBOOK.md)
