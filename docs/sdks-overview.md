# DKMads DMP SDKs

Native and cross-platform publisher SDKs. Shared API surface: [docs/SDK_API.md](../docs/SDK_API.md).

**Public mirror (publishers):** [github.com/DKMads-Codocs/dkmads-mmp-sdk](https://github.com/DKMads-Codocs/dkmads-mmp-sdk)  
**Live docs:** [dmp.dkmads.com/docs](https://dmp.dkmads.com/docs)  
**Sync:** `./scripts/publish-dmp-sdk-mirror.sh 0.1.0 --push` — see [MIRROR.md](./MIRROR.md)

| SDK     | Path           | Version | Artifact                                    |
| ------- | -------------- | ------- | ------------------------------------------- |
| Web     | `sdks/web`     | 0.1.0   | `npm install @dkmads/dmp-sdk`               |
| iOS     | `sdks/ios`     | 0.1.0   | SPM / CocoaPods `DKMadsDMP`                 |
| Android | `sdks/android` | 0.1.0   | Maven `com.dkmads:dmp-sdk:0.1.0`            |
| Flutter | `sdks/flutter` | 0.1.0   | pub `dkmads_dmp` (local path until publish) |
| Unity   | `sdks/unity`   | 0.1.0   | UPM `com.dkmads.dmp`                        |

Each SDK has its own [CHANGELOG](./android/CHANGELOG.md) — see per-platform folder.

## Running native unit tests

Run from **repo root** (`dmp.dkmads.com/`) — paths are relative to root, not `tests/integration/` or other packages.

```bash
# Vitest identity contract (works from any cwd)
pnpm test:sdk
# or explicitly:
pnpm test:sdk:parity

# Native demographics (repo-root scripts — safe if cwd is elsewhere)
pnpm test:sdk:ios
pnpm test:sdk:flutter
pnpm test:sdk:android
pnpm test:sdk:all

# Manual (must cd from repo root first)
cd "$(git rev-parse --show-toplevel)"
cd sdks/ios && swift test
cd sdks/flutter && flutter test
cd sdks/android && gradle test --no-daemon
```

**Note:** Do not put shell comments on the same line as `pnpm test:sdk` in copy-paste blocks — some terminals pass trailing tokens to vitest as filters.

Unity: open a project with the package, **Window → General → Test Runner → EditMode → DemographicsTests**.

## Publishing (0.1.0 — manual until CI wired)

### npm (`@dkmads/dmp-sdk`)

```bash
cd sdks/web && pnpm build && npm publish --access public
```

### CocoaPods

```bash
cd sdks/ios
pod spec lint DKMadsDMP.podspec
pod trunk push DKMadsDMP.podspec
```

Tag release: `git tag sdks/ios/0.1.0 && git push origin sdks/ios/0.1.0`

### Maven Central (`com.dkmads:dmp-sdk`)

```bash
cd sdks/android && ./gradlew publishReleasePublicationToMavenLocal
# Configure signing + Sonatype in gradle.properties before Central upload
```

### pub.dev (`dkmads_dmp`)

```bash
cd sdks/flutter
flutter pub publish --dry-run
flutter pub publish
```

### Unity UPM

- Git URL: `https://github.com/DKMads-Company-Limited/dmp.dkmads.com.git?path=sdks/unity`
- Or OpenUPM scoped registry after `npm publish` on openupm.com

## Platform entry points

| Platform              | Init                                  |
| --------------------- | ------------------------------------- |
| Web / Flutter / Unity | `init(config)`                        |
| iOS                   | `await DMP.configure(config)`         |
| Android               | `DMP.init(context, config) { ok -> }` |

## Integration tests

```bash
pnpm test:sdk
```

CI: [`.github/workflows/sdk-tests.yml`](../.github/workflows/sdk-tests.yml) — iOS, Android, Flutter, vitest parity on SDK path changes.
