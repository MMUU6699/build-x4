# Work mode tool contract

This file is the single source of truth for the HTTP contract between the Flutter
Work agent (`lib/features/work/services/manus_agent_loop_service.dart`, through
`DaytonaWorkspaceRuntime`) and the `daytona-workspace` edge function
(`supabase/functions/daytona-workspace/index.ts`).

Both sides must be changed together. Any response field added here must be
returned by the function and parsed by the client.

## Envelope

Every request is `POST /functions/v1/daytona-workspace` with

```json
{
  "action": "<action>",
  "sandboxId": "<owned sandbox id, optional>",
  "...action parameters": "see below"
}
```

Every response carries:

| Header        | Value                                                        |
| ------------- | ------------------------------------------------------------ |
| `x-build-id`  | Build identifier of the deployed function                    |
| CORS headers  | Present on success **and** error responses                   |

Errors are `{"error": "<human readable>", "field": "<optional field name>"}`
with a non-2xx status. `400` means a bad request, `403` means the sandbox is
not owned by the caller, `409` means no sandbox exists yet, `429` means a
quota/rate limit was hit, `500` means an upstream failure.

## Sandbox ownership

- `ensure_sandbox` is the **only** way a Work sandbox is created. The server
  creates/reuses a `workspaces` row for the authenticated user, calls Daytona,
  and stores `daytona_sandbox_id` on that row.
- Every other action that touches a sandbox requires a `sandboxId` that belongs
  to the caller (`workspaces.user_id = auth.uid()`). A missing row means deny.
- There is no `daytona.list()` fallback.
- At most one live sandbox per user.
- If the stored sandbox is gone (Daytona 404), `ensure_sandbox` clears the
  stale id and creates a new sandbox, charging the new sandbox's quota block.

## Actions

### `health`

No parameters. Returns `{status, provider, details, timestamp}` and writes the
result to `integrations`.

### `ensure_sandbox`

Parameters: `language?` (default `typescript`), `snapshot?` (falls back to the
`DAYTONA_SNAPSHOT` secret, otherwise the Daytona default).

Returns:

```json
{ "success": true, "sandboxId": "…", "status": "running", "created": true }
```

Creating a new sandbox consumes one 30-minute sandbox block from the daily
quota. Reusing an existing sandbox does not consume another block.

### `exec_command`

Parameters: `command` (required), `cwd?`, `env?`, `timeout?` (seconds).

Returns the real streams, kept separate:

```json
{ "stdout": "…", "stderr": "…", "exitCode": 0, "output": "…" }
```

### `read_file`

Parameters: `path` (required), `offset?` (1-based line), `limit?` (lines).

```json
{ "content": "…", "byteSize": 1234 }
```

### `write_file`

Parameters: `path` (required), `content` (required), `append?`.

```json
{ "success": true, "originalContent": "…", "modifiedContent": "…", "byteSize": 1234 }
```

### `edit_file`

Parameters: `path`, `old_str`, `new_str` (all required). `old_str` must occur
exactly once; otherwise `409` with the reason.

```json
{ "success": true, "originalContent": "…", "modifiedContent": "…", "byteSize": 1234 }
```

### `list_dir`, `glob`, `grep`, `search_web`

- `list_dir`: `path?` → `{ "files": [...] }`
- `glob`: `pattern`, `path?` → `{ "matches": ["…"] }`
- `grep`: `query`, `path?` → `{ "matches": ["…"] }`
- `search_web`: `query`, `limit?` →
  `{ "results": [{ "title", "url", "snippet", "favicon" }] }`

### Browser actions

`browser_navigate` (`url` required), `browser_view`, `browser_get_text`,
`browser_click` (`index` **or** `coordinate_x` + `coordinate_y`),
`browser_input` (`index` required, `text` required, `press_enter?`),
`browser_scroll` (`direction`), `browser_press_key` (`key`),
`browser_restart` (`url?`).

`browser_restart` kills Chromium, waits for the DevTools port to close,
relaunches it through the same bootstrap path and then navigates to `url` (or
captures `about:blank` when `url` is omitted).

Optional metadata used to name the screenshot object:
`conversationId`, `eventId`.

All browser actions return the **same** shape:

```json
{
  "success": true,
  "url": "https://…",
  "title": "…",
  "page_text": "visible text, max 6000 chars",
  "interactive_elements": ["[0] <a href=\"/x\"> \"Label\"", "…"],
  "elements_count": 12,
  "screenshot_url": "https://…signed…",
  "screenshot_path": "<user_id>/<conversation_id>/<event_id>.png",
  "screenshot_error": null,
  "byte_size": 182734
}
```

`interactive_elements` is always a JSON **array of strings**. Anything else is
treated as no elements; the function never emits a newline-delimited string.

If the screenshot cannot be captured, the action fails loudly. If the capture
succeeds but upload/signing fails, `screenshot_error` explains why and
`screenshot_url` is the **same capture** as a `data:image/png;base64,…` URL.
The function never returns a previous file. Screenshot files have unique names.

### `start_sandbox`, `stop_sandbox`, `delete_sandbox`

Require an owned `sandboxId`.

## Agent tool → action mapping

| Agent tool            | Edge action             |
| --------------------- | ----------------------- |
| `shell_exec`          | `exec_command`          |
| `file_read`           | `read_file`             |
| `file_write`          | `write_file`            |
| `file_str_replace`    | `edit_file`             |
| `file_find_by_name`   | `glob`                  |
| `file_find_in_content`| `grep`                  |
| `info_search_web`     | `search_web`            |
| `browser_*`           | `browser_*`             |

`message_notify_user`, `message_ask_user` and `deliver_result` never reach the
edge function.

## Chat function

`supabase/functions/chat/index.ts` chooses the model from the `WORK_MODEL`
secret (default `mistral-medium-latest`; documented upgrade
`mistral-large-latest`). It never silently swaps the model. Every response
carries `x-model-used`. `maxTokens` defaults to `8192` (capped to the model
limit). A length-truncated tool call is retried once with a larger limit.

The Flutter agent keeps each request under `maxRequestHistoryChars` (120000
characters, roughly 30k tokens) by dropping the oldest complete user turns. The
system prompt and the newest turn are always kept, and a tool result is never
detached from the assistant `tool_calls` message that produced it.
