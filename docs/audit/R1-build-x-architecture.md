# R1 — Build X app architecture audit (read-only)

Scope: `E:\build x` (Flutter app “Kelivo”, runtime name “Build X”), branch `work-mode-real-backend`, HEAD `5c005b8d`.
Method: static reading of `lib/`, `test/`, `supabase/`, `android/`, `pubspec.yaml`, and existing audit notes. No files changed. No secret values reproduced.

## 0. Bottom line

| Area | Finding |
|---|---|
| Startup | Boot is mostly synchronous setup, then `runApp`; Supabase initialization failures are swallowed; chat loading is deferred until the home page mounts (`lib/main.dart:93-138`, `174-237`). |
| Auth | Email sign-in/up, GitHub OAuth, and guest/anonymous quick access only. No forgot-password, no normal sign-out UI. Work’s “Sign in” button signs the anonymous user out instead of opening a dedicated screen (`auth_page.dart:46-59`, `103-125`; `work_session_provider.dart:150-165`). |
| Drawer/history | Mode filtering is implemented, but **every normal new conversation is temporary**, and temporary conversations are explicitly excluded from the drawer. New Chat and Work conversations never appear in drawer history (`side_drawer.dart:1470-1487`; `chat_service.dart:333-346`). |
| Storage | **No working local chat database.** Chat data is Supabase-only, but new conversations are never inserted, `mode` is never persisted/restored, `conversations.extras` does not exist, and live ACLs deny DML (`chat_service.dart:111-172`, `305-325`, `442-469`; `R4:12-40`). |
| Work | Fully wired UI → agent loop → Daytona edge function, but live execution is blocked before the first model turn by eager `ensure_sandbox`, which needs `workspaces` DML (`manus_agent_loop_service.dart:620-633`; `R4:14-32`). |
| Settings/l10n/theme | Settings are local `SharedPreferences`; theme/l10n wired; auth/Work/account strings bypass ARB; About still says “Kelivo” (`about_page.dart:425`). |
| Tests | Good Work unit/widget coverage; **no auth tests**, **no drawer Chat/Work filter tests**, **no persistence round-trip tests**. Baseline has 15 failures across three suites. |
| ChatBox invariant | `chat_input_bar.dart` and `chat_input_section.dart` must not be modified. They own focus, text, media, send/stop, expansion; the tray slot above them avoids re-parenting (`home_page.dart:1656-1677`). |

## 1. Startup and provider graph

Boot order (`lib/main.dart`): `ensureInitialized` (`:96-97`) → `loadSavedGuestMode` (`:99`) → `Supabase.initialize` inside `try/catch` (`:100-107`) → notifications/logger (`:109-114`) → desktop window (`:116-120`) → `SandboxPathResolver.init` (`:122`) → `AppPreferences` (`:124-125`) → edge-to-edge (`:127`) → `runApp` (`:129`). Desktop title is `Build X` (`:153-155`).

Provider tree (`main.dart:174-237`): `AppPreferences`, `UserProvider`, `ChatService`, `ToolApprovalService`, `AskUserInteractionService`, `AssistantProvider`, `SettingsProvider`, `WorkspaceProvider`, `WorkspaceRuntimeProvider`, `ToolRunRegistry`, `HotkeyProvider`, `UpdateProvider`, `ContextUsageService`, `WorkSessionProvider`. `SettingsProvider` is watched by the root builder (`:238-241`, `382-393`).

Deferred init: `ChatService.init()` is called from `HomePageController.initChat` (`home_page_controller.dart:1080-1089`), not `main()`. `AuthGate` is `MaterialApp.home` (`main.dart:393`; `auth_gate.dart:57-67`). `WorkSessionProvider.initFromPreferences` restores Work if saved (`work_session_provider.dart:211-218`, `50-54`).

Risks:
1. Supabase can fail and the app still starts; `client` falls back to a standalone client with `autoRefreshToken: false` (`supabase_config.dart:93-103`).
2. `loadSavedGuestMode()` runs before `Supabase.initialize` and may create a sticky `_mockClient` (`supabase_config.dart:50`, `93-103`).
3. Chat loading waits for the home page; failed load leaves the drawer skeleton (`side_drawer.dart:3194-3205`).
4. Settings load async → first-frame theme/locale flash.
5. No local chat database bootstrap despite `AGENTS.md` claiming Drift.

## 2. Authentication and session model

| Flow | Behavior | Evidence |
|---|---|---|
| Email sign-up | `signUp`; only checks `res.user != null` | `auth_page.dart:46-53` |
| Email sign-in | `signInWithPassword` | `auth_page.dart:54-59` |
| GitHub OAuth | `signInWithOAuth(OAuthProvider.github)` | `auth_page.dart:103-125`, `285-298` |
| Quick access / guest | `SupabaseConfig.enableGuestMode()` | `auth_page.dart:86-101`, `301-316` |

No forgot-password and no normal sign-out button (`signOut` only in `signInForWork`, `work_session_provider.dart:160`).

Guest semantics: persisted under `build_x_guest_bypass_v1` (`supabase_config.dart:8`, `20-25`); tries anonymous sign-in (`:26-31`); even if it fails, `_guestMode` stays true and `authStateNotifier=true` (`:20-34`); `isAuthenticated = _guestMode || currentSession != null` (`:110`). A guest with no real session is treated as authenticated by the gate, while `ChatService` sees `currentUser == null` and uses in-memory shared data (`chat_service.dart:111-145`).

`AuthGate` initializes from `SupabaseConfig.isAuthenticated` (`auth_gate.dart:19`), listens to auth events (`:24-34`) and the notifier (`:36-46`), then shows `AuthPage` or home (`:57-67`).

Work gate:

```dart
bool get isSignedInForWork {
  if (SupabaseConfig.isUnconfigured) return true;
  final user = SupabaseConfig.currentUser;
  return user != null && !user.isAnonymous;
}
```

`work_session_provider.dart:148-154`. UI gate: `chat_empty_state_suggestions.dart:118-177`. The send path is **not** guarded: `home_page.dart:1582-1611` and `startWorkTask` (`work_session_provider.dart:297-334`). Edge functions validate a JWT but do not reject `is_anonymous` (`chat/index.ts:101-116`; `daytona-workspace/index.ts:577-591`).

Email confirmation is required and unverified sign-in is off (`R4:95-105`); sign-up only checks `res.user != null` and does not show “check your email” (`auth_page.dart:46-53`). `AccountProfilePage` saves to local `UserProvider` then Supabase (`account_profile_page.dart:54-80`), has no sign-out, hardcodes `صلاحيات كاملة · Full Access` (`:184-203`), and writes `name`/`bio` to `profiles` although the schema has `display_name` (`user_provider.dart:163-173`; `20261016000000_init_build_x.sql:2-11`).

## 3. Drawer and history

Rows come from `chatService.getAllConversations()` (`side_drawer.dart:1469-1501`). Filters:

| Filter | Rule | Consequence |
|---|---|---|
| Mode | Work keeps only `c.isWork`; Chat keeps only `!c.isWork` (`1470-1474`) | Correct in principle, but no unified list |
| Assistant | If `assistantId != null`, it must resolve to selected assistant (`1475-1483`) | Mismatch hides rows |
| Temporary | Always skips temporary IDs (`1484-1487`) | Hides every normal new conversation |
| Query | Case-insensitive title substring (`1489`) | Search filter |
| Pinned/date | Pinned first, then date grouping (`1496-1503`) | — |

Why it appears empty, in order: (1) temporary conversations, (2) mode mismatch after reload because `_mapToConversation` drops `mode`, (3) assistant mismatch, (4) search query, (5) still initializing, (6) Supabase load failed and cache cleared, (7) Work conversation never saved.

History entry points: desktop `showChatHistoryDesktopDialog` (`side_drawer.dart:1932-1936`, `2013-2017`; `desktop/chat_history_dialog.dart:53-61`) and mobile `ChatHistoryPage` (`side_drawer.dart:2399-2411`; `chat_history_page.dart:40-48`). Both read `getAllConversations()` directly and therefore **can show temporary conversations**; only the drawer hides them. “Delete all” is assistant/pin-scoped, not mode-scoped (`chat_history_dialog.dart:150-158`; `chat_history_page.dart:109-115`).

`switchMode` excludes temporary rows when searching from scratch (`home_page_controller.dart:1609-1664`), but cached temporary IDs can still be restored (`:1620-1660`).

## 4. Storage truth

| Data | Actual mechanism | Evidence |
|---|---|---|
| Conversations/messages | Supabase via `ChatService` | `chat_service.dart:111-172`, `275-325`, `653-674`, `1126-1143` |
| Local chat DB | No-op stub; no Drift dependency in `pubspec.yaml` | `chat_database_repository.dart:18-42`; `chat_service.dart:403` |
| Settings/theme/locale/guest flag | `SharedPreferences` via `AppPreferences` | `app_preferences.dart:21-37`; `settings_provider.dart:797-829`; `supabase_config.dart:20-25` |
| Work turns | Supabase `work_turns` with JSON events | `work_event_persistence_service.dart:60-95`; `work_turn.dart:80-97` |
| Work agent history | Supabase `work_agent_messages` | `work_event_persistence_service.dart:97-142` |
| Work phase | Supabase `work_sessions` | `work_event_persistence_service.dart:156-190` |
| Screenshots | Supabase Storage signed URLs | `work_event_persistence_service.dart:144-154` |

`ChatService.chatRepositoryOrNull` is always `null` (`chat_service.dart:403`); `MessageBuilderService` gets no local repository (`message_builder_service.dart:191-195`).

`createConversation` (`chat_service.dart:275-325`): in-memory object; if temporary, **no insert**; otherwise inserts only `id/user_id/title/assistant_id/workspace_id/created_at/updated_at`. It never writes `mode`, `plan_state`, `attachments`, or extras. `createDraftConversation` defaults `temporary: true` (`:333-346`); the normal new-chat/new-Work path does not override (`home_view_model.dart:1072-1077`; `chat_controller.dart:275-279`; `ensure_conversation.dart:30-33`). `toggleTemporaryConversation` also creates a temporary draft (`home_view_model.dart:1146-1150`). **No call site of `setTemporaryConversation(..., false)` exists.**

`appendMessageVersion` only writes when non-temporary (`chat_service.dart:1118-1148`); updates/deletes follow the same guard (`:1182-1205`, `:1217-1229`). Normal conversations therefore live only in memory.

`init()` selects conversations (`:116-127`); `_mapToConversation` restores only `id/title/created_at/updated_at/is_pinned/assistant_id` and `mistral_conversation_id` (`:152-172`). It drops `mode`, `plan_state`, `attachments`, `workspace_id`, model overrides.

Schema/code mismatches:

| Client behavior | Schema reality | Effect |
|---|---|---|
| `updateConversationExtras` updates `conversations.extras` (`chat_service.dart:461-464`) | No `extras`; columns are `mode`, `plan_state`, `attachments` (`add_work_mode_tables.sql:4-8`) | PostgREST update fails silently |
| `createConversation` accepts extras but inserts none | No `extras` column | Extras memory-only |
| Mode in `extras` (`conversation.dart:46-49`) | `mode` column exists but unused | Work becomes Chat after reload |
| `UserProvider` upserts `name`/`bio` (`user_provider.dart:167-173`) | `profiles` has `display_name`, no `email`/`bio` (`init_build_x.sql:2-11`) | Profile sync fails silently |
| `Profile` read expects `name`/`email`/`bio` (`user_provider.dart:54-60`) | No such columns | Fields never load |
| `updateWorkSession` uses `conversation_id` FK (`work_event_persistence_service.dart:169-187`) | `work_sessions.conversation_id` has FK to `conversations` (`add_work_mode_tables.sql:11-13`) | Temporary Work draft violates FK |
| `work_turns.conversation_id` text | No FK (`work_mode_security.sql:62-65`) | Turns can save without a conversation row |
| `work_agent_messages.conversation_id` text | No FK (`work_mode_security.sql:96-101`) | Same |
| `work_tool_events` exists and has grants | No client references | Events live in `work_turns.events` |

All Supabase writes are wrapped in `try/catch` + `debugPrint` (`chat_service.dart:322-324`, `371-373`, `397-399`, `466-468`, `1145-1147`, `1202-1204`, `1227-1229`; `work_event_persistence_service.dart:26-28`, `77-80`, `92-94`, `188-190`). The UI looks successful while writes fail.

## 5. Work end to end

Mode: `AppMode.chat|work` (`work_session_provider.dart:14-20`), persisted `app_active_mode_v1` (`:50`, `220-228`). Segmented pill (`segmented_mode_pill.dart:62-101`); `HomePage` observes (`home_page.dart:642-650`); `switchMode` (`home_page_controller.dart:1609-1664`); Work send routed first (`home_page.dart:1582-1612`); Chat send from a Work conversation creates a new Chat conversation (`:1613-1618`).

`startWorkTask` (`work_session_provider.dart:297-334`): cancel running, phase running, turn ID, save turn, upsert `work_sessions`, start agent loop.

Events: `ManusStartingEvent` → `_startingComputer` (`:407-412`); `Thinking` (`:416-420`); tool started/finished (`:422-440`); notify (`:442-448`); ask (`:450-469`); completed (`:471-494`); error (`:496-498`). Resume sends a `tool` message for the pending call ID (`:359-401`; agent `:596-614`). Loaded running turns become “The app closed before this task finished” (`:279-285`).

Agent loop (`manus_agent_loop_service.dart`): loads persisted history (`:586-594`), system prompt (`:90-134`, `:594`), **eager `health` + `ensureSandbox` before the first model call** (`:618-634`), max 60 iterations (`:77-83`), history 120k chars (`:79-83`, `:652-655`), tool result 8k (`:77`), `tool_choice: notified ? 'auto' : 'any'` (`:657`), plain text nudged with “You must use the computer tools and finish with deliver_result” (`:681-691`), missing tool IDs rejected (`:694-706`), invalid args three strikes (`:743-787`).

Tools: messages (`message_notify_user`, `message_ask_user`, `deliver_result`), shell, file (`read/write/str_replace/find_by_name/find_in_content`), search, browser (`navigate/view/get_text/click/input/scroll/press_key/restart`) (`:136-353`); required args `:356-375`; `brief` optional with generic fallback (`:383-385`, `:791-798`). `deliver_result` is the only completion path and builds attachment previews (`:841-878`).

Daytona runtime: `invokeDaytona` (`daytona_workspace_runtime.dart:69-106`), `checkHealth` → `{'status':'error'}` on exception (`:402-409`), `ensureSandbox` requires non-empty `sandboxId` (`:411-422`). Edge function: auth (`:577-591`), service-role client (`:593-596`), owned sandbox for all actions except health/ensure (`:606-633`), health lists sandboxes and upserts integrations (`:641-665`), ensure reuses/creates workspace, charges 30-minute block, inserts `workspaces` (`:667-762`), ownership `workspaces.user_id = auth.uid()` (`:629-633`), real exec/file/browser actions (`:790-889+`).

Why Work fails live today: eager ensure → edge insert into `workspaces` → no DML (R4) → “Workspace creation failed: permission denied for table workspaces” (`daytona-workspace/index.ts:727-729`) → runtime wraps → “Could not start the computer: …” (`manus_agent_loop_service.dart:630-632`) → provider error turn (`work_session_provider.dart:496-529`). This happens **before the first model call**. Even after ACL repair, Work session rows fail their `conversations` FK because the Work conversation is temporary; `work_turns`/`work_agent_messages` can save because they use text IDs, but there is no conversation row/mode for reload. Tier 1 Daytona internet is restricted (R5), and the agent still eagerly creates a sandbox for greetings/non-computer prompts.

Work UI: turns appended after normal messages (`home_page.dart:1370-1375`); tray visible exactly when Work mode && phase running (`work_computer_tray.dart:70-72`); tap opens panel (`:136-139`); panel is dialog on desktop, bottom sheet on mobile (`work_computer_modal_sheet.dart:18-46`); errors plain red text + “Run again” (`work_turn_widget.dart:468-524`).

## 6. Settings, localization, theme

Settings are local `SharedPreferences`, not Supabase: `SettingsProvider` constructor reads locale and starts `_load()` (`settings_provider.dart:797-800`); theme mode defaults system (`:657-658`, `816-825`); locale key `app_locale_v1` (`:533`), accepted tags (`:2270-2275`); setters persist locally (`:2708-2732`, `:2282-2297`). Unused Supabase profile columns `theme_mode`, `theme_palette`, `locale` (`init_build_x.sql:4-9`).

Theme palette IDs (`palettes.dart:22-31`); `MaterialApp` selects palette (`main.dart:313-319`), dynamic color Android-only (`:313`, `:321-332`), app font (`:334-380`), locale/themes (`:382-393`).

L10n: ARB `app_en.arb`, `app_zh.arb`, `app_zh_Hans.arb`, `app_zh_Hant.arb`; template English (`l10n.yaml:1-4`); generated locales (`app_localizations.dart:96-101`); CI regenerates (`pr-check.yml:53-56`). Hardcoded strings remain in auth page (`auth_page.dart:256-259`, `311-315`), Work empty state (`chat_empty_state_suggestions.dart:139-176`), account page (`account_profile_page.dart:110-117`, `184-203`), Work errors (`work_turn_widget.dart:468-524`).

Identity mismatch: package `Kelivo` (`pubspec.yaml:1`), Android `namespace/applicationId com.psyche.kelivo` (`android/app/build.gradle.kts:10`, `21`), label `Build X` (`AndroidManifest.xml:41`), `MaterialApp.title Build X` (`main.dart:384`), About still `Kelivo` (`about_page.dart:425`).

## 7. Tests and verification

533 Dart files under `lib/`, 397 under `test/`, 379 `*_test.dart`, 7 `*_bench.dart`. Benchmarks are outside the default glob and contain no assertions (`AGENTS.md:27-35`).

Work tests: `work_mode_isolation_test.dart`, `work_session_provider_test.dart`, `work_turn_test.dart`, `work_turn_widget_test.dart`, `work_computer_tray_test.dart`, `tool_call_id_preservation_test.dart`, `browser_agent_execution_test.dart`, `agent_history_window_test.dart`, `agent_argument_validation_test.dart`. They cover mode isolation (`work_mode_isolation_test.dart:54-112`), turn lifecycle/waiting/resume/error/cancel/screenshot (`work_session_provider_test.dart:77-290`), tray visibility/thumbnail (`work_computer_tray_test.dart:93-250`), recorded tool-call IDs (`tool_call_id_preservation_test.dart:23-80+`), history window (`agent_history_window_test.dart:69-90+`), argument validation (`agent_argument_validation_test.dart:56-85+`), and honest browser failure (`browser_agent_execution_test.dart:24-118`).

Coverage gaps: no auth tests, no drawer mode-filter tests, no persistence integration tests, no schema-contract test, no live ACL test.

Baseline: `docs/audit/baseline-test-failures.txt` ends `+41 -15 ~1` (`:260`): `chat_api_code_block_image_skip_test` request body null (`:111-117`), `file_link_resolver_test` Windows drive-letter casing (`:14-25`, etc.), `message_list_view_padding_test` stream content missing (`:151-166`, `190-205`).

CI: format changed Dart, regenerate l10n and reject drift, `dart analyze --fatal-infos lib test integration_test`, `flutter test` (`pr-check.yml:31-85`). Baseline is not green on this Windows checkout.

## 8. ChatBox invariant

`ChatInputBar` owns text/focus/media/send/stop/model/reasoning/search/tools/OCR/quick phrases/expansion; `ChatInputSection` is the adapter (`chat_input_section.dart:180-256`, `34-38`, `146-278`). Only production mount: `home_page.dart:1512-1520`. Wrapper `_buildChatInputWithTray` keeps the tray slot always present:

```dart
return Column(
  children: [
    AnimatedSize(child: const WorkComputerTray()),
    chatInput,
  ],
);
```

`home_page.dart:1656-1677`. Both layouts use it (`:1107`, `:1309`). Reasons not to touch: state ownership (`home_page.dart:623-625`), global key identity (`:1521`), tray re-parenting, size measurement (`:1097-1103`, `:1299-1305`), Work/Chat routing boundary (`:1582-1624`).

## Appendix — contradictions to carry into remediation

1. `AGENTS.md` says Drift, but there is no Drift dependency and the local chat repository is a no-op (`chat_database_repository.dart:18-42`; `pubspec.yaml:31-55`).
2. App brands “Build X” but About says “Kelivo” (`main.dart:384`; `about_page.dart:425`).
3. New conversations are always temporary; the drawer defines history as non-temporary (`chat_service.dart:333-346`; `side_drawer.dart:1484-1487`).
4. `conversations.mode` exists but is never read/written (`add_work_mode_tables.sql:5-6`; `chat_service.dart:152-172`, `312-320`).
5. `conversations.extras` is written but does not exist (`chat_service.dart:461-464`).
6. `profiles.name`/`bio` are written but schema has `display_name` (`user_provider.dart:167-173`).
7. Work is gated by a prompt the send path does not enforce (`chat_empty_state_suggestions.dart:118-177`; `home_page.dart:1582-1611`).
8. Work eagerly creates a sandbox before the model can decide (`manus_agent_loop_service.dart:618-633`).
9. Live DB denies DML on the tables the app depends on (R4).
10. Baseline tests are not green.
