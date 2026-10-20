# R3 — ai-manus frontend audit (read-only)

Base: `ai-manus/frontend/`. Method: static reading only.

## 0. Stack and language

Vue 3 + TypeScript, Vite 4, Tailwind 3.3, reka-ui, vue-router 4, vue-i18n, TipTap, Monaco, xterm, noVNC, lottie-web, `lucide-vue-next` (`package.json:16-45`).

Design language: warm-gray canvas `#f8f8f7`, text `#34322d`, 1px hairlines at 6–12% black, radii 8/10/12/22 px, signature 110° text-gradient shimmer swept at **2.2 s linear infinite** (`src/assets/theme.css:176-207`, `src/assets/global.css:31-43`).

**Important:** ai-manus has **no computer card, thumbnail, or orb**. The “computer” is a right-side panel / centered dialog. Build X’s card/orb/thumbnail are earlier-round inventions; keep their geometry as instructed, but style them with these tokens.

## 1. Pages and routing

Router `src/router/index.ts`:

| Path | Component | Auth |
|---|---|---|
| `/library` | `MainLayout` → `LibraryPage` | yes |
| `/project/:projectId` | `MainLayout` → `ProjectPage` | yes |
| `/chat`, `/`, `/home` | `MainLayout` → `HomePage` | yes |
| `/chat/:sessionId` | `MainLayout` → `ChatPage` | yes |
| `/share/:sessionId` | `ShareLayout` → `SharePage` | no |
| `/login` | `LoginPage` | no |

Auth guard `:70-103`: `requiresAuth` + auth provider none/null => allow without token; otherwise missing token redirects to `/login?redirect=…`. Shell: `MainLayout` = `SessionSidebar` + router view + `FilePreviewer` + overlays (`TakeOverView`, `CustomDialog`, `SessionFileList`, `SettingsDialog`, `ContextMenu`) (`MainLayout.vue:2-17`).

`ChatPage.vue`: header 56 px, sticky, hairline bottom (`:6-7`); message column max 810 / min 360, 24 px padding (`:154`); list gap 12, bottom 80, top 12 (`:155`); composer sticky footer (`:175`); computer panel sibling (`:188-192`).

`HomePage`: mode switcher, serif greeting 32/40, ChatBox, suggestion chips.

## 2. Components

Chat/session: `ChatPage`, `ChatMessage`, `ChatBox`, `ChatBoxFiles`, `ChatAttachmentList`, `AttachmentsMessage`, `ChatMessageCopyButton`, `ChatWaitingContinue`, `ChatTaskCompleted`, `TakeControlBanner`, `TakeOverView`, `VNCViewer`, `ToolUse`, `PlanPanel`, `PlanStepIcon`, `LiveStatusCanvas`, `ui/LoadingIndicator`, `SimpleBar`.

Computer panel: `ComputerPanel` (shell/width/follow-live), `ComputerPanelContent` (header + content + timeline + planner), `ComputerInactiveEmpty` (160 px inactive monitor), `toolViews/ShellToolView`, `FileToolView`, `BrowserToolView`, `SearchToolView`, `McpToolView`.

Navigation: `SessionSidebar` (300/52 px), `SessionItem` (36 px rows), `UserMenu`, `SearchDialog`.

## 3. Composables

- `useSessionPhase.ts`: phase FSM `pending/running/waiting/completed/error`; `isBusy` only running (`:39-43`); `showWaitingContinue` (`:95-97`); `showTaskCompleted` (`:110-115`); `showThinking` (`:117-151`).
- `useAgentEvents.ts`: event → message list; soft-tool filtering; plan seeding (`:47-237`); error event appends an assistant bubble with the raw error string (`:179-188`).
- `useTool.ts`: tool icon/name/function/arg/view (`:9-49`).
- `useToolShimmer.ts`: `TOOL_SHIMMER_MIN_MS = 2200`; hold shimmer after fast calling→called; persists while active (`:10`, `:27-57`).
- `useLiveToolContent`, `useResizeObserver`, `useSessionSidebar`, `useFilePreviewer`, `useTheme`, `useTime`, `useDialog`, `useContextMenu`.

## 4. Numeric visual specs

### 4.1 Thinking / shimmer

- Thinking row: height **28 px**, gap **8 px** (`ui/LoadingIndicator.vue:3`).
- Loader: **16×16**, Lottie 60 frames @30 fps played at **2× ≈ 1 s/loop** (`LiveStatusCanvas.vue:37-48`, `live-status-loading.json`).
- Text: **14 px**, gradient `linear-gradient(110deg, text-primary 0%, text-primary 35%, text-shining 50%, text-primary 75%, text-primary 100%)`, `background-size: 200% 100%`, clipped, animation `manus-text-shimmer 2.2s linear infinite` (`LoadingIndicator.vue:6`, `global.css:31-43`).
- Light `--text-shining #e5e5e5`; dark `#474747` (`theme.css:9`, `:89`).
- Tool-label shimmer: same 110°/200%/2.2 s but base `--text-secondary` (`theme.css:190-207`).
- Step header live glyph: same Lottie 16 px; completed swaps to 17 px filled circle with 9 px check (`ChatMessage.vue:93-97`).

### 4.2 Tool rows

- Row gap **8 px**; icon column **20 px**, icon **20 px** (`ToolUse.vue:18-24`).
- Text line-height **20 px**, inner gap **4 px**; brief **14 px** truncate; fallback function 14 px, argument mono **12 px** with 6 px start margin (`:21-43`).
- Timestamp **12/16 px**, tertiary, visible on hover (`:46-47`).
- Step group header **28 px**, 14 px text, 20 px icon well; rail **20 px** gutter with 1 px line; body start padding 20 px; rows 4 px vertical/start padding (`ChatMessage.vue:83-151`).

### 4.3 Computer card/thumbnail/orb

Not present in ai-manus. Nearest references:

- `ComputerInactiveEmpty.vue`: inline SVG **160×160**, monitor 104×72 r8 stroke 3, inner 80×48 r4 at 50%, stand/base 56×6 r3, green dot r3, caption 14 px medium tertiary (`:4-17`).
- Compact summary uses `ToolUse` rows.
- Busy placeholder: `LoadingIndicator` or invisible `h-5` spacer (`ChatPage.vue:170-172`).
- Open affordance: 32 px icon button in panel header (`ComputerPanelContent.vue:42-51`).

### 4.4 Computer sheet

Shell (`ComputerPanel.vue`):

- Sidebar: mobile full-screen fixed; ≥sm sticky 100vh, min width **520 px** (`:7`).
- Width animation `width: ${sideWidth}px`, opacity, `0.2s ease-in-out` (`:10`).
- Width math `min(max(parent/2, min(520,parent)), parent)` (`:82-85`).
- Dialog: fixed inset 0, z 1100, `py-12`, mask `#000000a6`, backdrop blur **12 px** (`:35`); panel `w-900 max-w-95% max-h-1200 h-full` (`:38`); **12 px radius**, 1 px border, 8-layer shadow stack (`ComputerPanelContent.vue:256`).

Header (`ComputerPanelContent.vue:8-126`):

- **56 px** high, gap 8, padding 16/12, 1 px bottom border.
- Title 14 px / 500; subtitle 12 px tertiary gap 8; divider 12×1 px.
- Action label truncates; while calling gets shimmer; function arg 4 px start margin mono.
- Buttons **32×32**, radius 8, icon **18 px**; divider 16×1.
- Presentation pill / “Use computer” popover: top `calc(100%+10px)`, width `min(480px, 100vw-32px)`, radius 20, padding 16, shadow `0 8 32`; heading serif 18 px; body 13/18; buttons h-9 px-4 radius 10.

Content: `flex-1 min-h-0`; tool view or `ComputerInactiveEmpty` (`:129-137`).

Timeline (`:141-210`):

- Bar **45 px**, gap 8, padding 12/16/12/8, 1 px top/bottom border.
- Prev/next 24×24, icon 16, disabled 50%.
- Track **4 px** full radius; fill 4 px blue.
- Thumb **14 px**, 2 px white border, blue fill, drop shadow.
- Hover tooltip 28 px, radius 4, px 10, 12 px text, blue/white.
- Live cluster: 6 px dot + 12 px/500 label; green `#25ba3b` when live/realTime.
- Jump to live: h-10, px-3, 1 px border, gap 4, full radius, 80 px above, shadow.

Planner: button padding 16, gap 8; progress 12 px; expanded max-height 260, gap 4, rows min 20 px, 14 px; step icon 12 px; unknown state is 9 px rotated 30° 3 px-radius brand square with 3 px glow.

### 4.5 Thread

- Header 56 px; column max 810/min 360, 24 px padding; list gap 12, bottom 80, top 12 (`ChatPage.vue:7`, `:154-155`).
- User bubble: margin-top 24, max-width 90%, radius 12, padding 12, 1 px border, line-height 22 (`ChatMessage.vue:8-20`); meta 12/16, gap 2, py 2, hover-revealed (`:25-29`).
- Assistant header 26 px, gap 8, logo 24 px, name 16 px.
- Lite badge: 12 px text, 20 px tall, py 2 px/px 6, radius 6, 1 px border, margin-left 3 (`:43-47`).
- Reply actions gap 12, bottom padding 20 or 8; copy button 28 px (`:59-66`).
- Composer radius 22, py 12, gap 12, shadow `0 12 32 rgba(0,0,0,.02)`, 1 px border black/8 (`ChatBox.vue:4`); editor 15/24, max-height 216, dense min 28 (`:9-10`); send/stop 32 px circle; stop inner 10×10 r2 white square (`:40-50`).
- Follow FAB 36 px, 80 px above composer.
- Sidebar 300/52 px, 200 ms; row 36 px, radius 10, gap 8 (`SessionSidebar.vue:3-4`, `SessionItem.vue:85`).
- Attachment thumbs 54×54 r12; file chips 280 px r10; sent grid 6 columns max 88 px gap 8.

### 4.6 Tokens

| Token | Light | Dark |
|---|---|---|
| text-primary | `#34322d` | `#dadada` |
| text-secondary | `#535350` | `#acacac` |
| text-tertiary | `#858481` | `#7f7f7f` |
| text-disable | `#b9b9b7` | `#5f5f5f` |
| text-shining | `#e5e5e5` | `#474747` |
| text-blue/brand | `#0081f2` | `#1a93fe` |
| background-gray-main | `#f8f8f7` | `#272728` |
| background-menu-white | `#fff` | `#383739` |
| background-nav | `#f0f0f0` | `#212122` |
| border-main | `#0000000f` | `#ffffff14` |
| border-dark | `#0000001f` | `#ffffff29` |
| success | `#25ba3b` | `#5eb92d` |
| warning | `#efa201` | `#ffbf36` |
| error | `#f25a5a` | `#eb4d4d` |
| fill-tsp-white-main | `#37352f0f` | `#ffffff0f` |
| fill-tsp-gray-dark | `#37352f14` | `#00000047` |
| primary-black | `#1a1a19` | `#fff` |

Body font: system sans (`global.css:15`); serif: Libre Baskerville/Georgia (`tailwind.config.js:11`), used only for home greeting and “Use application” title.

## 5. Icon inventory and Flutter equivalents

Custom SVGs (`src/components/icons/`): `UseComputerIcon` (monitor+cursor) → `LucideMonitor` + `LucideMousePointer2`; `TakeOverIcon` → `LucideMousePointerClick`; `ManusTextIcon`/`ManusLogo*` → asset/`LucideBot`; `BrowserIcon` → `LucideGlobe`; `EditIcon` → `LucideSquarePen`; `ShellIcon` → `LucideSquareTerminal`; `SearchIcon` → `LucideSearch`; `CenterViewIcon` → `LucideMaximize`; `SideViewIcon` → `LucidePanelRight`; `FullViewIcon` → `LucideExpand`; `ShareIcon` → `LucideShare`; `StepCheckIcon` → `LucideCheck`; `SendIcon` → `LucideArrowUp`; `SuccessIcon` → `LucideCircleCheck`; `ErrorIcon` → `LucideCircleAlert`; `InfoIcon` → `LucideInfo`; `LoadingSpinnerIcon` → `CircularProgressIndicator`; `FileIcon` → `LucideFileText`; `CodeFileIcon` → `LucideFileCode2`; `ImageFileIcon` → `LucideFileImage`.

`lucide-vue-next` imports map 1:1 to `LucideX` names. Key Work mapping: `Bot`, `PanelLeft`, `SquarePen`, `MessageSquareDashed`, `ChevronUp/Down/Right`, `Search`, `LibraryBig`, `Plus`, `FolderPlus`, `Check`, `Pin`, `PinOff`, `Folder`, `ListFilter`, `Ellipsis`, `Eye`, `Trash`, `Pencil`, `Share2`, `ExternalLink`, `LogOut`, `User`, `Settings2`, `Puzzle`, `Paperclip`, `Globe`, `MousePointerClick`, `Maximize`, `PanelRight`, `Expand`, `CircleDashed`, `CircleCheck`, `CircleAlert`, `Info`, `ArrowUp`, `ArrowDown`, `X`, `Play`, `SkipBack`, `SkipForward`, `Clock`, `Loader2`, `FileText`, `FileImage`, `FileCode2`, `Terminal`, `Monitor`.

## 6. UI decision logic

- Computer panel opens only from a tool row click, takeover, or jump-to-live; never auto-opens (`ChatPage.vue:695-710`, `ComputerPanel.vue:110-115`).
- Panel tool allowlist: `shell`, `file`, `search`, `browser`, `mcp`, `skill`; `todo`/`message` excluded (`constants/tool.ts:122-139`).
- `isLiveTool`: calling, or last non-message tool newer than **300 s** (`ChatPage.vue:681-693`).
- Inactive header: “{name}'s computer” + “Waiting for instructions”; content falls back to 160 px inactive monitor (`ComputerPanelContent.vue:11-21`, `:137`).
- Waiting footer: “Manus will continue after your reply” with dashed 16 px circle (`ChatWaitingContinue.vue`).
- Completed footer: green check + “Task completed” (`ChatTaskCompleted.vue`).
- Takeover banner: waiting + not busy + has browser tool (`ChatPage.vue:327-334`).
- Live dot green when live/realTime; Jump to live only when `!realTime` (`ComputerPanelContent.vue:190-209`).
- Task mode: Agent vs Chat · Lite, 16 px check; switching PATCHes session and reverts on failure (`ChatPage.vue:32-47`, `:338-350`).
- Follow-scroll defaults true; ArrowDown FAB when not following (`ChatPage.vue:245`, `:435-440`, `:717-719`).
- File previewer and computer panel are mutually exclusive (`ComputerPanel.vue:101-108`, `:140-147`).

## 7. Errors / retry / stop

- Agent error event appends an assistant bubble with the raw error string; no message-level retry/regenerate UI (`useAgentEvents.ts:179-188`; `ChatPage.vue` does not pass `onStreamError`).
- Attachment upload has a retry control (`ChatBoxFiles.vue:35-39`, `:69-73`).
- Phase collapses a transport `error` to `completed`; not an error screen (`useSessionPhase.ts:60-64`).
- Stop: WS `stop_session` first, fall back to REST `POST /sessions/{id}/stop` (`chatWs.ts:338-344`, `agent.ts:155-162`); stop button 32 px black circle with 10×10 white square.
- Build X requirement goes beyond ai-manus: friendly error + Details + retry, no raw exception dump.

## 8. Tests / fixtures

- Vitest `src/**/__tests__/*.spec.ts`; Playwright `e2e/*.spec.ts`.
- No recorded JSON event fixtures; inline TS shapes only.
- ToolContent shape: `{tool_call_id, name, function, args, status: 'calling'|'called', brief?, timestamp}` (`types/message.ts:22-31`); + `event_id` on wire (`types/event.ts:36-45`).
- File view: `content: {content, old_content?}`; shell view: `content: {console: [{ps1, command, output}]}`.
- PlanEvent: `{event_id, timestamp, steps: [{id, description, status, result?}]}`.
- Mock scenarios: `mockserver/mock_datas/plan_act_e2e.yaml`, `plan_act_wait_e2e.yaml`.

## 9. Porting notes

1. Do not copy a card/thumbnail/orb from ai-manus; it has none. Keep Build X’s earlier geometry and apply the Manus tokens.
2. Two shimmer gradients: Thinking base `text-primary`; tool labels base `text-secondary`; both 110°, 200%, 2.2 s linear.
3. Tool shimmer minimum **2200 ms**, even after a fast completion.
4. `showThinking` hides only for running/pending steps or calling tools; not for completed notify text.
5. Computer never auto-opens.
6. Panel width `clamp(parent/2, 520, parent)`, 200 ms; dialog 900/95%/1200 with 12 px blur.
7. Timeline playhead in Unix seconds, 250 ms tick, selects last tool ≤ t.
8. ai-manus errors are raw and have no retry; Build X must improve this, not copy it.
9. Keep serif usage sparse.
