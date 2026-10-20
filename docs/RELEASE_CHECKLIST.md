# Build X release checklist

Round 6 release target. Commands were run from `E:\build x`.

## Identity

| Item | Value |
| --- | --- |
| App name | `Build X` (`android:label`, iOS display name) |
| Dart package | `Kelivo` (kept for import stability) |
| Android applicationId | `com.buildx.app` |
| Android namespace | `com.psyche.kelivo` (unchanged so native/Kotlin paths stay valid) |
| Version | `1.1.0+6` (`pubspec.yaml:19`) |
| Launcher icon | existing Build X icon set under `android/app/src/main/res/mipmap-*` and `assets/app_icon.png` |
| Min SDK | 24 (Flutter default; verified in AAB) |
| R8 / resource shrink | enabled for release |
| ProGuard rules | `android/app/proguard-rules.pro` |

The applicationId is deliberately different from the namespace. Android allows
this, and it avoids rewriting every existing Kotlin/Java package while shipping
the Build X identity.

## Signing

- Keystore: `C:\Users\musta\.buildx-keys\buildx-release.jks`
- Alias: `buildx`
- Certificate SHA-256:
  `A5:12:83:A8:71:A3:4B:B4:C9:E6:98:5A:B1:1E:64:1C:5B:BE:42:C3:F6:53:66:39:92:BB:67:B5:9A:A0:44:29`
- Password file: `android/key.properties`, ignored by `android/.gitignore`
- The release build fails fast if `key.properties` is missing; it never falls
  back to the debug key.

Never commit the keystore or `key.properties`. Back up the keystore and its
password outside this repository; losing either prevents app updates.

## Permissions

Kept because a shipped feature uses them:

- Internet, notifications, foreground service/data sync, wake lock, exact alarm,
  boot completed, battery optimization exemption (background chat/notifications).
- Camera/microphone/media images and files (attachments, QR scanner, voice).
- Calendar and location (device tools).
- Accessibility/usage/overlay permissions used by the optional phone-control
  and screen-time tools are declared on their service components, not globally.

Removed in Round 6 because no code path used them:

- `MANAGE_EXTERNAL_STORAGE`
- `SYSTEM_ALERT_WINDOW`
- `POST_PROMOTED_NOTIFICATIONS`

`android:usesCleartextTraffic="true"` remains because local/self-hosted
OpenAI-compatible providers and MCP servers may use plain HTTP. The production
chat path is HTTPS (`https://owgpuolvfqfjhezuohyf.supabase.co`).

## Build

```powershell
flutter pub get
dart format lib test
dart analyze --fatal-infos lib test
flutter test  # see docs/round6/TEST_STATUS.md; not green on this machine
# This machine lacks Android cmdline-tools/apkanalyzer, so Flutter's post-build
# AAB strip *check* fails even when Gradle produced a valid AAB. Use Gradle for
# the bundle so the command exits 0, then verify the artifact manually.
android\gradlew.bat :app:bundleRelease
flutter build apk --release --split-per-abi
```

`flutter build appbundle --release` also writes the AAB, but exits 1 after the
build with `Release app bundle failed to strip debug symbols...`. The message is
misleading here: `flutter doctor` reports missing `cmdline-tools`, so Flutter
cannot run `apkanalyzer files list` to perform its check. Gradle's
`bundleRelease` is the authoritative build in this environment. Installing
Android cmdline-tools would make the Flutter wrapper check work without changing
the app.

Artifacts:

- `build/app/outputs/bundle/release/app-release.aab`
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`

The split APKs carry ABI-adjusted version codes: `1006` (armeabi-v7a), `2006`
(arm64-v8a), and `4006` (x86_64). Version name is `1.1.0`; the AAB itself is
version code `6`.

## Artifact verification

For each artifact:

1. `Get-FileHash <file> -Algorithm SHA256`.
2. `apksigner verify --print-certs <apk>` for APKs and
   `jarsigner -verify -verbose -certs <aab>` for the bundle; confirm the
   certificate SHA-256 matches the signing certificate above.
3. `aapt dump badging <apk>` or `bundletool dump manifest --bundle <aab>` and
   `versionName`/`versionCode`; confirm `com.buildx.app`, `1.1.0`, `6`.
4. `aapt dump permissions <apk>`; confirm the removed permissions above are gone.
5. Scan artifacts and the repository for secrets, then confirm no
   `service_role`, `MISTRAL_API_KEY`, `DAYTONA_API_KEY`, password, or bearer token
   is present.

## Verified build evidence (2026-10-20)

| Artifact | Size | SHA256 |
| --- | --- | --- |
| `app-release.aab` | 111,620,994 bytes | `75BAEA13E70192424CFF087AF7728026403A22FA4899B8599BDC3A53BEDB43D4` |
| `app-armeabi-v7a-release.apk` | 25,116,979 bytes | `722F4CD666851718D2AB1E8190A9B29BA5579D153E0A36D7C193849D5417BD2E` |
| `app-arm64-v8a-release.apk` | 25,222,483 bytes | `988B6A695AFBEA5993F8403C280A262EC95CD6A7BD97779A336005D543815C06` |
| `app-x86_64-release.apk` | 25,818,189 bytes | `2E800F2E61616AE655E4E49ECA4F7ACDCF32A72C6E01DBD7DD32892A27FF3451` |

AAB checks:

- `jarsigner -verify`: `jar verified.`
- Certificate SHA-256:
  `A5:12:83:A8:71:A3:4B:B4:C9:E6:98:5A:B1:1E:64:1C:5B:BE:42:C3:F6:53:66:39:92:BB:67:B5:9A:A0:44:29`
- `bundletool dump manifest`: package `com.buildx.app`, versionCode `6`,
  versionName `1.1.0`, minSdk 24, targetSdk 36.
- Removed permissions absent; 23 permissions remain.

APK checks:

- `apksigner verify --verbose --print-certs`: `Verifies`, APK Signature Scheme v2
  `true`, one signer; certificate SHA-256
  `a51283a871a34bb4c9e6985ab11e641c5bbe42c3f653663992bb67b59aa04429`.
- `aapt dump badging`: package `com.buildx.app`, versionName `1.1.0`,
  versionCode `1006`/`2006`/`4006` by ABI, minSdk 24, targetSdk 36, label
  `Build X`.
- 23 permissions each; `MANAGE_EXTERNAL_STORAGE`, `SYSTEM_ALERT_WINDOW`, and
  `POST_PROMOTED_NOTIFICATIONS` absent.

The AAB was produced by `android\gradlew.bat :app:bundleRelease` (BUILD
SUCCESSFUL, 4m 47s). `flutter build appbundle --release` writes the same AAB but
exits 1 at its `apkanalyzer`-based post-build check on this machine.

## Device acceptance (12 steps)

Not yet run: no physical Android device is connected to this machine.

1. Install the `arm64-v8a` APK on a clean device.
2. Open Build X, confirm the Build X icon/name and no crash before first frame.
3. Choose guest Chat; send a message; confirm the real answer streams.
4. Open history/drawer; confirm the conversation persists after restart.
5. Try Work as a guest; confirm the sign-in gate appears and no sandbox starts.
6. Sign in with a real confirmed account; confirm the profile shows the real
   email/display name.
7. Send a Work greeting; confirm a direct answer appears without starting a
   Daytona sandbox; any temporary computer card is gone after the turn completes.
8. Send a Work task that needs a shell; confirm the card is visible during the
   run with the honest "Waiting for a screen…" state before the first tool call,
   then shows real tool activity; one tap opens exactly one sheet.
9. Confirm the sheet shows real command/output and the footer clears the
   gesture bar.
10. Open a second account; confirm it cannot access the first account's
    sandbox (403) and cannot see its history.
11. Cancel a running response; confirm the UI stops and no late text appears.
12. Reboot/relaunch and confirm the latest history, auth session, and Work state
    are consistent.

## Known deployment blockers

- Supabase built-in SMTP is not configured. New email sign-ups cannot receive a
  confirmation message; use an admin-created confirmed account for device tests
  or configure SMTP before public release.
- Live SSE was not captured because Mistral returned HTTP 429 for
  `mistral-medium-latest`. See `docs/round6/FINAL_VERIFICATION.md`.
- The hardcoded Mistral key that was present in earlier source must be rotated in
  the Mistral console. This session removed it from the app but cannot rotate it.
