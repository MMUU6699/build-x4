# Build X Round 6 — live verification

Captured 2026-10-20 against project `owgpuolvfqfjhezuohyf`.

## Why sign-in is required (and where the check lives)

Chat is usable as a guest. Work is not, because Work creates a Daytona cloud
computer that belongs to one account. The app and the server both enforce that
rule:

| Layer | File | What it does |
| --- | --- | --- |
| App entry | `lib/features/auth/widgets/auth_gate.dart:23` | Shows `AuthPage` until `AuthService` reports a real signed-in session; the guest action only opens Chat. |
| Work UI | `lib/features/home/pages/home_page.dart:1586` | Before sending in Work mode, calls `showAuthPage(requireSignedIn: true)` when `isSignedInForWork` is false. |
| Work state | `lib/features/work/providers/work_session_provider.dart:150` | `isSignedInForWork` is true only for a non-anonymous Supabase user. It is false when Supabase is unconfigured. |
| Chat UI | `lib/features/chat/widgets/chat_empty_state_suggestions.dart:176` | Offers sign-in for Work; Chat remains available to guests. |
| Chat server | `supabase/functions/chat/index.ts:136` | `mode: "work"` + anonymous user returns HTTP 403 `not_signed_in`. |
| Daytona server | `supabase/functions/daytona-workspace/index.ts:592` | Anonymous users are rejected before any sandbox lookup or Daytona call. |

The sign-in question is therefore answered by the same session source used by
the rest of the app: `AuthService` → `AuthGate` → `WorkSessionProvider`. The
server checks are independent, so a modified client cannot bypass them.

> Email confirmation: Supabase's built-in SMTP is not configured on this
> project. New email sign-ups are rate-limited and cannot receive a confirmation
> mail. This is a deployment limitation, not a client auth bypass. Real
> server verification below used temporary confirmed users created through the
> Admin API and then deleted.
>
> Live auth settings read from `/auth/v1/settings` on 2026-10-20:
> `anonymous_users=true`, `email=true`, `disable_signup=false`,
> `mailer_autoconfirm=false`. Guest sessions are therefore allowed by the
> project; Work still rejects them in both edge functions.

## Edge functions deployed

Both functions were deployed with `--no-verify-jwt` so browser CORS preflight
works, but each function still calls `auth.getUser()` itself.

| Function | Local SHA256 | Downloaded server SHA256 |
| --- | --- | --- |
| `chat` | `673BC54B71931043D4E78DE32679F98AB7D8A40C888D6C7464C2A0B728A9D252` | `673BC54B71931043D4E78DE32679F98AB7D8A40C888D6C7464C2A0B728A9D252` |
| `daytona-workspace` | `F01AB255AC05DFE6EE13B4C8BD34619A708B81DBD9AA880AACFA9166B922B3B7` | `F01AB255AC05DFE6EE13B4C8BD34619A708B81DBD9AA880AACFA9166B922B3B7` |

Server source was downloaded with `supabase functions download ... --use-api`
and compared byte-for-byte. The `sha256` values match, so the running functions
are the reviewed sources.

## Real server responses

Temporary confirmed users `round6-primary-*` and `round6-second-*` were created
through the Admin API. Tokens were kept only in browser `sessionStorage`, never
printed. The sandbox was deleted and both users were deleted at the end.

### Sandbox creation

`POST /functions/v1/daytona-workspace` → `ensure_sandbox`:

```json
{
  "success": true,
  "sandboxId": "45cfe028-7fa6-42cb-98a4-3d2418ebfd3b",
  "status": "running",
  "created": true
}
```

HTTP 200, 11.2 s. This is a real Daytona sandbox, not a canned response.

### Real command execution in that sandbox

`POST /functions/v1/daytona-workspace` → `exec_command` with
`echo round6-live-ok && uname -s`:

```json
{
  "stdout": "round6-live-ok\nLinux\n",
  "stderr": "",
  "exitCode": 0
}
```

HTTP 200. The output is the real container output.

### Second user cannot touch the first user's sandbox

The second confirmed user sent `exec_command` with the first sandbox ID:

```json
{
  "error": "Unauthorized access to this sandbox",
  "field": "sandboxId"
}
```

HTTP 403.

### Anonymous Work chat is rejected

An anonymous Supabase user sent a `mode: "work"` request:

```json
{
  "code": "not_signed_in",
  "error": "Sign in with a real account to use Work."
}
```

HTTP 403.

### Cleanup

`delete_sandbox` returned `{"success": true}`. Both temporary users were deleted
with HTTP 200. No permanent test account or running sandbox is left behind.

## Streaming status

The client and both edge functions implement SSE streaming:

- `lib/core/services/api/chat_api_service.dart`: Chat SSE reader and standard
  OpenAI/Mistral `choices[].delta` / `tool_calls` parsing.
- `lib/features/work/services/manus_agent_loop_service.dart`: Work SSE reader,
  streamed thinking text, tool-call accumulation, then the existing agent loop.
- `supabase/functions/chat/index.ts`: streams real model chunks; non-stream
  callers still receive a JSON completion.

Live chunk capture is **UNVERIFIED**. The configured Mistral model
(`mistral-medium-latest`) returned this real upstream error during the test:

```json
{
  "error": "The configured model (mistral-medium-latest) is rate limited by Mistral. Retry later or set WORK_MODEL to an allowed model. Details: API error occurred: Status 429\nBody: {\"object\":\"error\",\"message\":\"Rate limit exceeded\",\"type\":\"rate_limited\",\"param\":null,\"code\":\"1300\",\"raw_status_code\":429}"
}
```

HTTP 429. Because no real chunk arrived, no SSE chunk fixture is presented here.
The parser is covered by unit tests and the non-stream path is live; the
end-to-end live stream remains unverified until the Mistral quota resets or a
different allowed model is configured.

## Fixtures

Real response shapes are stored in `test/fixtures/round6/`:

- `chat_work_anonymous_403.json`
- `chat_rate_limit_429.json`
- `daytona_ensure_sandbox_200.json`
- `daytona_exec_command_200.json`
- `daytona_second_user_403.json`

Tokens, API keys, passwords, and `.env` values are not stored in any fixture.

## Targeted test evidence

| Suite | Result |
| --- | --- |
| `test/features/work/work_computer_tray_test.dart` | PASS (4/4) |
| `test/features/work` (all Work suites) | PASS (33/33) |
| `test/core/services/workspace/file_link_resolver_test.dart` | PASS (20 passed +1 symlink skip on Windows) |
| `test/chat_api_code_block_image_skip_test.dart` | PASS (7/7) |
| `test/features/work/work_turn_widget_test.dart` | PASS (targeted) |

The Work card is visible for the entire running phase, including the honest
"Waiting for a screen…" state before the first tool call. It disappears when the
turn completes, so a direct answer does not leave a computer card behind.

`docs/round6/TEST_STATUS.md` records the full-suite limitations. The direct
provider encoder suites are not green because the local fallback only implements
plain OpenAI-compatible `/chat/completions`; production uses the edge function.

## Release artifacts

Built on 2026-10-20 with the external release keystore (alias `buildx`).

| Artifact | Size | SHA256 |
| --- | --- | --- |
| `app-release.aab` | 111,620,994 bytes | `75BAEA13E70192424CFF087AF7728026403A22FA4899B8599BDC3A53BEDB43D4` |
| `app-armeabi-v7a-release.apk` | 25,116,979 bytes | `722F4CD666851718D2AB1E8190A9B29BA5579D153E0A36D7C193849D5417BD2E` |
| `app-arm64-v8a-release.apk` | 25,222,483 bytes | `988B6A695AFBEA5993F8403C280A262EC95CD6A7BD97779A336005D543815C06` |
| `app-x86_64-release.apk` | 25,818,189 bytes | `2E800F2E61616AE655E4E49ECA4F7ACDCF32A72C6E01DBD7DD32892A27FF3451` |

The APKs were built by `flutter build apk --release --split-per-abi` (Gradle
`assembleRelease`, 151.5 s). `apksigner` reports `Verifies`, APK Signature Scheme
v2 `true`, one signer, and certificate SHA-256
`a51283a871a34bb4c9e6985ab11e641c5bbe42c3f653663992bb67b59aa04429`.
`aapt dump badging` reports package `com.buildx.app`, versionName `1.1.0`,
versionCode `1006` (armeabi-v7a), `2006` (arm64-v8a), `4006` (x86_64), minSdk 24,
targetSdk 36, label `Build X`. Each has 23 permissions; the removed permissions
are absent.

The AAB was built with `android\gradlew.bat :app:bundleRelease` (BUILD
SUCCESSFUL, 4m 47s). `jarsigner -verify` reports `jar verified.`; the signing
certificate SHA-256 is
`A5:12:83:A8:71:A3:4B:B4:C9:E6:98:5A:B1:1E:64:1C:5B:BE:42:C3:F6:53:66:39:92:BB:67:B5:9A:A0:44:29`.
`bundletool dump manifest` reports package `com.buildx.app`, versionCode `6`,
versionName `1.1.0`, minSdk 24, targetSdk 36. The removed permissions
`MANAGE_EXTERNAL_STORAGE`, `SYSTEM_ALERT_WINDOW`, and
`POST_PROMOTED_NOTIFICATIONS` are absent; 23 permissions remain.

The Flutter wrapper `flutter build appbundle --release` writes this AAB but exits
1 at its post-build strip *check* because this machine lacks Android
`cmdline-tools`/`apkanalyzer`. Gradle's `bundleRelease` is the authoritative
build here; see `docs/RELEASE_CHECKLIST.md`.

## Still unverified

- Live SSE text/tool-call chunks (Mistral 429).
- A physical Android phone install/run of the release artifacts.
- A permanent user-owned email account: no SMTP, so confirmation mail cannot be
  delivered.
