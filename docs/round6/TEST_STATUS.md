# Round 6 test status

Date: 2026-10-20. Commands run from `E:\build x`.

## Gates

| Gate | Result | Evidence |
| --- | --- | --- |
| `dart format lib test` | PASS | formatted 931 files, 0 changed |
| `dart analyze --fatal-infos lib test` | PASS | `No issues found!` |
| `flutter test` (full) | NOT GREEN | 3232 passed, 30 skipped, 255 failed/timed out |
| `flutter test test/features/work/work_computer_tray_test.dart` | PASS | 4/4 |
| `flutter test test/features/work` | PASS | 33/33 |
| `flutter test test/core/services/workspace/file_link_resolver_test.dart` | PASS | 20 passed, 1 symlink test skipped (Windows privilege) |
| `flutter test test/chat_api_code_block_image_skip_test.dart` | PASS | 7/7 |

The original baseline is recorded in
`docs/audit/baseline-test-failures.txt`. It had 15 failures before Round 6.
The two baseline geometry failures in
`test/features/home/widgets/message_list_view_padding_test.dart` remain (the
streaming-content finder does not see the virtualized row). They are not auth,
history, Work, or release regressions.

## Known provider-compatibility failures

These suites exercise Kelivo's direct provider request encoders. Round 6 routes
the production app through the Supabase `chat` edge function; the local/offline
fallback only implements plain OpenAI-compatible `/chat/completions`. The tests
use loopback servers, so they now hit that fallback:

- `test/chat_api_custom_request_precedence_test.dart`
- `test/chat_api_generate_text_encoding_test.dart`
- `test/chat_api_prompt_cache_key_test.dart`
- `test/chat_api_text_only_image_filter_test.dart` (some cases)
- `test/chat_api_generate_message_test.dart` (one case)

This is a real limitation of the local fallback, not a production edge-path
regression. It is listed as UNVERIFIED rather than reported as green. The local
fallback is deliberately limited to `SupabaseConfig.isUnconfigured` builds and
loopback/private provider URLs.

The complete run's 255 non-passes are dominated by four groups:

- 10-minute timeouts in the frosted/golden widget suites,
  `chat_assistant_background_test.dart`, and `conversation_skills_sheet_test.dart`
  (the run took 47 minutes).
- SSE in-band-error tests that reached the live edge and received the real
  Mistral HTTP 429 instead of a local error frame.
- `sandbox_path_resolver_test.dart` Windows path-separator expectations
  (`/` vs `\`).
- The provider-compatibility suites listed above and the two baseline
  `message_list_view_padding_test.dart` cases.

No failure is counted as a pass, and the release is not claimed as test-green.

## Not run

- Full suite after the final tray/build edits: not rerun. The last complete run
  finished 3232 passed / 30 skipped / 255 failed or timed out. Network tests
  contact the live Supabase project (HTTP 429) and several golden/frosted and
  skills-sheet tests hit their 10-minute timeouts, so that run is not a reliable
  release gate here. Targeted suites were rerun after the final edits.
- Physical Android device: no device is connected, so the 12-step device test in
  `docs/RELEASE_CHECKLIST.md` is UNVERIFIED.
- Live SSE: Mistral returned 429; see `docs/round6/FINAL_VERIFICATION.md`.
