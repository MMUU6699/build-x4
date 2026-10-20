# R2 — ai-manus backend audit (read-only)

Source root: `ai-manus/`. Scope: `backend/app/**`, `backend/tests/**`, `sandbox/**`, `mockserver/**`.
Method: static reading only; no files changed; no secrets reproduced.

## 0. Layer map

| Layer | Location | Responsibility |
|---|---|---|
| Interfaces | `backend/app/interfaces/` | REST + WebSocket routes, wire schemas, DI |
| Application | `backend/app/application/` | auth, agent, file, token, email services |
| Domain | `backend/app/domain/` | models, flows, agents, tools, prompts, repositories |
| Infrastructure | `backend/app/infrastructure/` | Mongo repos, Docker sandbox, LLM gateways, browsers, search |

Entry points: `backend/app/main.py`, `backend/app/worker.py`, `sandbox/app/main.py`, `mockserver/main.py`.

## 1. Agent loop / planner-executor

- Production runner hard-instantiates `PlanActFlow`: `backend/app/domain/services/agent_task_runner.py:93-104`. `AgentLoopFlow` exists but is only used by tests/harness (`domain/services/flows/agent_loop.py`).
- `AgentTaskRunner.run` loops over input, selects `TaskMode.CHAT` vs agent mode, and for agent mode calls `ensure_sandbox()` per message (`agent_task_runner.py:291-367`, especially `:300-306`).
- Plan-Act states: `IDLE, PLANNING, EXECUTING, SUMMARIZING, COMPLETED, UPDATING` (`flows/plan_act.py:40-46`).
- PLANNING calls `planner.create_plan()`, emits `TitleEvent` + `MessageEvent`; empty plan => COMPLETED (`plan_act.py:200-227`).
- EXECUTING runs exactly one step per iteration, compacts memory, replans only on failure (`plan_act.py:229-275`).
- `WaitEvent` (from `message_ask_user`) is terminal for the turn: no `DoneEvent`, runner returns (`plan_act.py:247-254`; `agent_task_runner.py:335-340`).
- Inner `_tool_loop` (`domain/services/agents/base.py:230-364`): max 100 iterations; nudges the model when an output tool exists and no tool call is made (`:236-244`); unknown tool => error fed back (`:263-271`); emits `ToolEvent(CALLING/CALLED)` (`:274-281`, `:341-349`); terminal live-poll for shell (`:283-336`); max tool result 16,000 chars (`:47-48`).
- `ExecutionAgent` rejects `complete_step(success=true)` with zero work tools (`agents/execution.py:121-138`); work toolkits are `shell,file,browser,search,mcp` (`:51`).
- `can_skip_summarize()` is permanently `False`, so every run pays a summarize LLM call (`prompts/execution.py:127-129`, `plan_act.py:277-287`).

## 2. Prompts

- `CORE_PROMPT` identity/capabilities/language/principles/sandbox (Ubuntu 22.04, Python 3.10, Node 20): `prompts/system.py:21-56`; assembled with per-toolkit instructions and project instructions (`:151`).
- Executor role: one step at a time; every shell/file/browser/search/mcp call must carry a user-facing `brief`; notify with `message_notify_user`; ask only when blocked; do not complete until verified: `prompts/execution.py:11-38`.
- Executor request: step, goal, prior steps, original message, attachments, language: `prompts/execution.py:40-59`.
- Resume prompt after user reply: `prompts/execution.py:61-74`.
- Summarize prompt: deliver via `deliver_result`, explain outcome, attach files, never claim unverified: `prompts/execution.py:76-85`.
- Prior-step truncation to 500 chars: `prompts/execution.py:98-99`.
- Planner role: 3–5 steps for non-trivial work; verify step for software; no meta-only steps; **pure greetings/questions may use an empty step list but must fill `message`**: `prompts/planner.py:31-32`.
- Chat-mode system prompt (no tools/computer/internet): `agent_task_runner.py:377-381`.

## 3. Tools and schemas

Framework: `domain/services/tools/base.py` (`ToolFunction`, `@tool` at `:164-253`, `OutputTool` at `:329-363`, toolkit base at `:365-395`).

| Toolkit | File | Tools |
|---|---|---|
| shell | `tools/shell.py` | `shell_exec` `:35`, `shell_view` `:49`, `shell_wait` `:59`, `shell_write_to_process` `:74`, `shell_kill_process` `:88` |
| file | `tools/file.py` | `file_read` `:30`, `file_write` `:54`, `file_str_replace` `:91`, `file_find_in_content` `:115`, `file_find_by_name` `:136` |
| browser | `tools/browser.py` | `browser_view` `:30`, `browser_navigate` `:36`, `browser_restart` `:45`, `browser_click` `:54`, `browser_input` `:70`, `browser_move_mouse` `:90`, `browser_press_key` `:104`, `browser_select_option` `:116`, `browser_scroll_up` `:130`, `browser_scroll_down` `:142`, `browser_console_exec` `:154`, `browser_console_view` `:166` |
| search | `tools/search.py` | `info_search_web` `:28` |
| message | `tools/message.py` | `message_notify_user` `:25`, `message_ask_user` `:39` |
| plan | `tools/plan.py` | `plan_report` `:30`, `replan` `:50` |
| skill | `tools/skill.py` | `load_skill` `:97` (+ dynamic schema injection `:88`) |
| mcp | `tools/mcp.py` | one dynamic `Tool` per MCP tool (`:315-359`) |

Sandbox requirement: shell/file need `DockerSandbox` (`tools/shell.py:18-25`, `tools/file.py:20-27`); browser connects over CDP (`tools/browser.py:20-27`); search/message/plan/skill/mcp do not.

## 4. Events and streaming

- **No SSE in ai-manus.** Streaming is WebSocket only: `ws /ws/chat` (`interfaces/api/ws_routes.py:165-523`), `ws /ws/sessions` (`:85-162`), VNC proxy (`:526-594`).
- Protocol v2, client frames `join_session`, `leave_session`, `chat`, `stop_session`; server frames `event`, `status_update`, `stream_end`, `ping`, `ack` (`ws_routes.py:34-39`, `:165-523`).
- Catch-up replay via Mongo `last_event_id` (`ws_routes.py:73-82`); keepalive 20 s (`:30-31`).
- Final status precedence: waiting > error > session status (`ws_routes.py:54-70`).
- Event types: `MessageEvent, ToolEvent, StepEvent, PlanEvent, TitleEvent, WaitEvent, DoneEvent, ErrorEvent, StructuredOutputEvent, TerminalUpdateEvent, FileUpdateEvent` (`domain/models/event.py`, `interfaces/schemas/event.py:166-267`).
- `TerminalUpdateEvent` and `FileUpdateEvent` are **stream-only, never persisted** (`agent_task_runner.py:117-123`).

## 5. Sandbox lifecycle (important: ai-manus is eager, not lazy)

- On the first message of an agent session, `AgentDomainService` calls `sandbox_cls.create()` and saves `session.sandbox_id` **before** the model decides anything (`domain/services/agent_domain_service.py:54-75`). This is eager at first message.
- `create()` -> container create/start -> `ensure_sandbox()` (`infrastructure/external/sandbox/docker_sandbox.py:78-133`).
- `ensure_sandbox()` polls supervisor status up to 60 s and requires every service `RUNNING` (`docker_sandbox.py:135-181`), **but the final raise is commented out** (`:182-186`): it fails open after 60 s.
- Runner calls `ensure_sandbox()` per message for agent mode (`agent_task_runner.py:300-306`); chat mode never touches it (`:298`, `:369-419`).
- Wait/resume: `message_ask_user` => `WaitEvent` (`agents/execution.py:174-181`); next user message resumes the same step (`plan_act.py:241-245`, `prompts/execution.py:61-74`).
- Teardown: `AgentDomainService.shutdown()` -> `Task.destroy()` (`agent_domain_service.py:48-52`).

## 6. Persistence

- One Mongo document per session with an unbounded `events: List[AgentEvent]` array: `infrastructure/models/documents.py`; append via `$push` (`infrastructure/repositories/mongo_session_repository.py:143-151`).
- Every `TitleEvent`/`MessageEvent` also writes latest message/unread (`agent_task_runner.py:342-346`): write amplification.
- Chat-mode history replays all persisted `MessageEvent`s with no window (`agent_task_runner.py:398-407`).
- No separate message/turn/event tables; everything is inside the session document.

## 7. Greetings / zero-tool path

- Chat mode: one LLM call, `TitleEvent` + `MessageEvent` + `DoneEvent`, no sandbox (`agent_task_runner.py:369-419`).
- Agent Plan-Act mode: Planner is allowed an empty step list for greetings, but still creates a **sandbox first** (Q5). Cost: one Planner call + Plan/Title/Message/Done events + one container.
- If a greeting reaches a structured agent with an output tool, a prose answer is nudged up to 100 iterations (`agents/base.py:236-244`, `:361-362`). Build X must avoid this by treating a first-turn plain answer as final.

## 8. Sandbox browser / shell APIs

- Sandbox app routes: `/api/v1/shell/{exec,view,wait,write,kill}`, `/api/v1/file/{read,write,replace,search,find,upload,download}`, `/api/v1/supervisor/status` (`sandbox/app/api/v1/*.py`).
- Backend calls `/api/v1/file/exists`, `/delete`, `/list` which **do not exist** in the sandbox app (`docker_sandbox.py:301-344` vs `sandbox/app/api/v1/file.py:15-147`). Dead methods today, trap for later.
- Shell is tmux-backed with a PS1 sentinel; `wait` soft-waits 5 s then Ctrl-C, default 60 s (`sandbox/app/services/shell.py:36-65`, `:404-440`, `:485-505`).
- File reads have no default cap; backend truncates to 16k (`sandbox/app/services/file.py:22-27`, `backend/.../base.py:47`).
- Browser stack in `sandbox/supervisord.conf`: Xvfb `1280x1029x24` (`:23-32`), Chromium CDP `0.0.0.0:8222` with `--no-sandbox --disable-web-security` (`:35-74`), socat `9222->8222` (`:77-86`), x11vnc `5900` **no password** (`:89-99`), websockify `5901` (`:102-111`), app `8080` (`:114-125`).
- Backend browser CDP URL: sandbox IP port 9222 (`docker_sandbox.py:499-514`); VNC proxied over the chat WS (`ws_routes.py:526-594`).

## 9. Real fixtures / tests

- `backend/tests/harness.py`: `ScriptedLLM` records requests (`:31-64`), `FakeSandbox` (`:84-121`), `FakeSessionRepository` (`:138-150`), flow builders (`:162-197`), `create_plan_call` (`:200-221`).
- Behaviour tests: `test_plan_act_flow.py`, `test_single_loop_manus.py`, `test_plan_act_prompts.py`, `test_context_engineering.py`, `test_domain_tools.py`, `test_execution_context.py`, `test_plan_progress.py`, `test_todo_projection.py`, `test_llm_*`, `test_ws_final_agent_status.py`, `test_e2e_plan_act.py`.
- Mockserver scenarios: `mockserver/mock_datas/plan_act_e2e.yaml`, `plan_act_wait_e2e.yaml`.
- No sandbox tests for the missing `/exists`, `/delete`, `/list` routes.

## 10. Risk register relevant to Build X

| # | Risk | Evidence | Build X implication |
|---|---|---|---|
| R1 | `ensure_sandbox` fails open | `docker_sandbox.py:182-186` | Build X must fail closed with a structured `sandbox_unavailable` error |
| R2 | Backend calls nonexistent file routes | `docker_sandbox.py:301-344` | Do not copy; verify Build X runtime routes |
| R3 | Eager sandbox on first message | `agent_domain_service.py:54-75` | **Do not copy**: Round 6 requires lazy ensure on first computer tool |
| R4 | Terminal/File updates not persisted | `agent_task_runner.py:117-123` | Persist enough for history restore |
| R5 | Unbounded events document | `mongo_session_repository.py:143-151` | Build X uses per-row tables; keep pagination |
| R8 | VNC no password, Chromium `--disable-web-security` | `supervisord.conf:61`, `:90` | Keep VNC behind auth/proxy; never expose directly |
| R9 | Summarize always runs | `prompts/execution.py:127-129` | Build X can skip for no-tool answers |
| R10 | 100-iteration nudge loop | `agents/base.py:236-244` | Treat first-turn plain answer as final |

## Mapping notes for the summary

- ai-manus Plan-Act (Planner + Executor) -> Build X single agent loop with `tool_choice=auto`; gap: Build X currently forces tools and eagerly ensures a sandbox.
- ai-manus `message_notify_user` / `deliver_result` -> Build X should port the notify-first/final-result contract.
- ai-manus tool `brief` field -> Build X tool rows need a real user-facing subtitle.
- ai-manus WS event stream -> Build X has SSE in `supabase/functions/chat`; Work must consume it, not fake status text.
- ai-manus eager sandbox -> Build X must be **lazier than the reference** (first computer tool only).
