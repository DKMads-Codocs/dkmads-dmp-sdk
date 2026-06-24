# Flutter native plugin test matrix

Run demographics unit tests (pure Dart, no device):

```bash
cd sdks/flutter && flutter test
```

## CI matrix (recommended before pub publish)

| Job               | Platform                | What to verify                                                              |
| ----------------- | ----------------------- | --------------------------------------------------------------------------- |
| `flutter-test`    | Linux                   | `flutter test` — demographics + identity helpers                            |
| `flutter-analyze` | Linux                   | `flutter analyze`                                                           |
| `android-plugin`  | Android API 34 emulator | `DmpFlutterPlugin`: `isLatEnabled`, `getAdvertisingId` return without crash |
| `ios-plugin`      | iOS 17+ simulator       | Plugin channel `requestATT` returns status string                           |

## Manual smoke (device / emulator)

1. `flutter create /tmp/dmp_smoke && cd /tmp/dmp_smoke`
2. Add path dependency: `dkmads_dmp: path: ../../sdks/flutter`
3. Call `DkmadsDmp.init(...)`, `getSharedIdentity()`, `setContext({'screen': 'home'})`
4. Confirm `devicePid` stable across restarts (`shared_preferences`)

## Cross-platform identity contract: `tests/integration/sdk-parity/identity-contract.test.ts`

CI runs these jobs on every SDK change — see [`.github/workflows/sdk-tests.yml`](../../.github/workflows/sdk-tests.yml).
