# DKMads DMP SDK

Official **public** SDK repository for [DKMads DMP](https://dmp.dkmads.com) — audience data, demographics, and SSP identity handoff.

> Mirror of `sdks/` in the [DMP platform monorepo](https://github.com/DKMads-Company-Limited/dmp.dkmads.com).  
> Published via `scripts/publish-dmp-sdk-mirror.sh` — do not edit generated paths by hand.

**Version:** 0.1.0  
**Live documentation:** [dmp.dkmads.com/docs](https://dmp.dkmads.com/docs)

## Packages

| Platform | Path | Install |
|----------|------|---------|
| Web | [`web/`](./web/) | `npm install @dkmads/dmp-sdk` |
| iOS | [`ios/`](./ios/) | SPM / CocoaPods `DKMadsDMP` |
| Android | [`android/`](./android/) | Maven `com.dkmads:dmp-sdk:0.1.0` |
| Flutter | [`flutter/`](./flutter/) | pub `dkmads_dmp` |
| Unity | [`unity/`](./unity/) | UPM `com.dkmads.dmp` |

## Quick start (Web)

```javascript
import DMP, { ageRangeFromDateOfBirth } from '@dkmads/dmp-sdk';

await DMP.init({ appKey: 'dmp_live_...' });
DMP.identify('user-42', {
  'demographic.age_range': ageRangeFromDateOfBirth('1992-03-15'),
});
DMP.track('screen_view', { screen: 'home' });

// Share with SSP for bid-time audiences
const { devicePid, userPid } = DMP.getSharedIdentity();
```

## Documentation

- [Publisher guides](./docs/README.md)
- [DMP + SSP integration](./docs/integration/quickstart.md)
- [Identity contract](./docs/integration/dmp-ssp-identity.md)

## Support

- Dashboard: [dmp.dkmads.com](https://dmp.dkmads.com)
- SSP platform: [ssp.dkmads.com](https://ssp.dkmads.com)
