import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../models/work_plan.dart';
import '../models/work_tool_event.dart';
import '../providers/work_session_provider.dart';
import 'tool_views/browser_tool_view.dart';
import 'tool_views/file_tool_view.dart';
import 'tool_views/mcp_tool_view.dart';
import 'tool_views/search_tool_view.dart';
import 'tool_views/shell_tool_view.dart';

/// Interactive cloud computer modal sheet replicating official Manus Computer Panel (Section 4):
/// - Sheet: top corners radius about 23 dp, background #F5F5F5.
/// - Header: close X icon at left (about 28 dp from edge), centered title "Build X's computer"
///   (about 17 dp, semi-bold, #33332B), right outlined pill (62 x 33 dp, fully rounded) with
///   presentation-screen icon and chevron.
/// - Content card: white, radius about 21 dp, 1 px light border, side margins 16 dp.
/// - Status row: 40 dp tile radius 8 dp, fill #EDEDED, with tool icon in a gray circle (browser = compass).
///   Title (about 16 dp, semi-bold) "Build X is using Browser" / "Terminal" / "File" / "Search".
///   Subtitle (about 12 dp, #858481, one line) with real action.
/// - Slider: thick track (about 7 dp) in #858480 with round knob (about 16 dp) in #858480, full width.
/// - Controls row: skip-previous at left, center Live with 8 dp green dot #25BA3C and 16 dp semi-bold text,
///   skip-next at right. When viewing history, center becomes white outlined pill "Jump to live" with play icon.
/// - Collapsible Plan Bar positioned under timeline scrubber.
/// - Zero emojis policy strictly enforced.
class WorkComputerModalSheet extends StatefulWidget {
  const WorkComputerModalSheet({super.key});

  static Future<void> show(BuildContext context) async {
    final isDesktop =
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux;

    if (isDesktop) {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(23)),
            child: WorkComputerModalSheet(),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (_) => const WorkComputerModalSheet(),
      );
    }
  }

  @override
  State<WorkComputerModalSheet> createState() => _WorkComputerModalSheetState();
}

class _WorkComputerModalSheetState extends State<WorkComputerModalSheet> {
  bool _isPlanBarExpanded = false;

  @override
  Widget build(BuildContext context) {
    final workSession = context.watch<WorkSessionProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.sizeOf(context).height;

    // Section 4: top corners radius about 23 dp, background #F5F5F5
    final bgColor = isDark ? const Color(0xFF161618) : const Color(0xFFF5F5F5);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    final currentEvent = workSession.currentEvent;
    final events = workSession.timelineEvents;
    final totalEvents = events.length;
    final currentIndex =
        workSession.scrubbedIndex ?? (totalEvents > 0 ? totalEvents - 1 : 0);
    final isLive = workSession.isLive;
    final plan = workSession.activePlan;

    return Container(
      height: screenHeight * 0.93,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.16),
            blurRadius: 32,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1. Header (Close X at 28 dp from edge, Centered Title, 62x33 Outlined Pill)
          _buildModalHeader(
            context,
            isDark,
            borderColor,
            workSession,
            currentEvent,
          ),

          // 2. Central Content Card: white, radius about 21 dp, 1 px light border, side margins 16 dp
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E20) : Colors.white,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : const Color(0xFFE5E5E5),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: currentEvent == null
                  ? _buildEmptyState(isDark)
                  : _buildViewportContent(context, currentEvent),
            ),
          ),

          // 3. Status row, Slider, and Controls row
          _buildTimelineScrubber(
            context,
            isDark,
            workSession,
            totalEvents,
            currentIndex,
            isLive,
            borderColor,
            currentEvent,
          ),

          // 4. Collapsible Plan Bar positioned UNDER the timeline scrubber
          if (plan != null && plan.steps.isNotEmpty)
            _buildPlanProgressFooter(isDark, plan, borderColor),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Modal Top Bar (Header)
  // Section 4: Close 'X' icon at left (about 28 dp from edge), centered title
  // "Build X's computer" (about 17 dp, semi-bold, #33332B), at right an outlined
  // pill (about 62 x 33 dp, fully rounded) with presentation-screen icon and chevron.
  // ---------------------------------------------------------------------------
  Widget _buildModalHeader(
    BuildContext context,
    bool isDark,
    Color borderColor,
    WorkSessionProvider workSession,
    WorkToolEvent? currentEvent,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Left: Close button '✕' (about 28 dp from edge)
              GestureDetector(
                onTap: () {
                  workSession.closeComputer();
                  Navigator.of(context).maybePop();
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Icon(
                    Lucide.X,
                    size: 19,
                    color: isDark ? Colors.white70 : const Color(0xFF33332B),
                  ),
                ),
              ),

              // Center: 'Build X's computer' (17 dp, semi-bold, #33332B)
              Expanded(
                child: Center(
                  child: Text(
                    "Build X's computer",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF33332B),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),

              // Right: Symmetric spacing matching left close button
              const SizedBox(width: 28),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Viewport Content
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Lucide.Terminal,
            size: 40,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 12),
          Text(
            'Computer ready.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF858481),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewportContent(BuildContext context, WorkToolEvent event) {
    if (event.isBrowser) {
      return BrowserToolView(event: event);
    } else if (event.isShell) {
      return ShellToolView(event: event);
    } else if (event.isFile) {
      return FileToolView(event: event);
    } else if (event.isSearch) {
      return SearchToolView(event: event);
    }
    return McpToolView(event: event);
  }

  // ---------------------------------------------------------------------------
  // 3. Bottom Timeline Scrubber (Status row + Thick Slider + Transport controls)
  // Section 4:
  // - Status row under the card: 40 dp tile radius 8 dp, fill #EDEDED, with the
  //   tool icon in a gray circle (browser = compass). Title (about 16 dp, semi-bold)
  //   "Build X is using Browser" or "Terminal", "File", "Search". Subtitle (about
  //   12 dp, #858481, one line) with the real action.
  // - Slider: a THICK track (about 7 dp) in #858480 with a round knob (about 16 dp)
  //   in the same color, full width. Knob position = index of the shown tool call.
  // - Controls row: skip-previous icon at left, center Live with an 8 dp green dot
  //   #25BA3C and 16 dp semi-bold text, skip-next at right. At the live edge,
  //   skip-next is dimmed gray. When viewing history, center becomes a white
  //   outlined pill "Jump to live" with a play icon.
  // ---------------------------------------------------------------------------
  Widget _buildTimelineScrubber(
    BuildContext context,
    bool isDark,
    WorkSessionProvider workSession,
    int totalEvents,
    int currentIndex,
    bool isLive,
    Color borderColor,
    WorkToolEvent? currentEvent,
  ) {
    String categoryLabel = 'work-tools';
    IconData categoryIcon = Lucide.Wrench;

    if (currentEvent != null) {
      if (currentEvent.isBrowser) {
        categoryLabel = 'Browser';
        categoryIcon = Lucide.Compass;
      } else if (currentEvent.isShell) {
        categoryLabel = 'Terminal';
        categoryIcon = Lucide.Terminal;
      } else if (currentEvent.isFile) {
        categoryLabel = 'File editor';
        categoryIcon = Lucide.FileCode;
      } else if (currentEvent.isSearch) {
        categoryLabel = 'Search';
        categoryIcon = Lucide.Search;
      }
    }

    String actionSubtitle = currentEvent?.brief ?? 'Waiting for commands...';
    if (currentEvent != null && currentEvent.isBrowser) {
      final url = currentEvent.browserUrl ?? currentEvent.arguments['url'];
      if (url != null && url.toString().isNotEmpty) {
        actionSubtitle = 'Browsing: $url';
      }
    } else if (currentEvent != null && currentEvent.isShell) {
      final cmd = currentEvent.arguments['command'];
      if (cmd != null && cmd.toString().isNotEmpty) {
        actionSubtitle = 'Executing command: $cmd';
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161618) : const Color(0xFFF5F5F5),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          // Status row: 40 dp tile radius 8 dp, fill #EDEDED, tool icon in a gray circle
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFEDEDED),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    categoryIcon,
                    size: 16,
                    color: isDark ? Colors.white70 : const Color(0xFF33332B),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Build X is using $categoryLabel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF33332B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      actionSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFFA5A5A0)
                            : const Color(0xFF858481),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Slider: THICK track (about 7 dp) in #858480 with round knob (about 16 dp)
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 7,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: const Color(0xFF858480),
              inactiveTrackColor: isDark
                  ? Colors.white24
                  : const Color(0xFFD6D5D2),
              thumbColor: const Color(0xFF858480),
            ),
            child: Slider(
              value: totalEvents > 1
                  ? currentIndex.toDouble().clamp(
                      0.0,
                      (totalEvents - 1).toDouble(),
                    )
                  : 0.0,
              min: 0,
              max: totalEvents > 1 ? (totalEvents - 1).toDouble() : 1.0,
              divisions: totalEvents > 1 ? totalEvents - 1 : 1,
              onChanged: totalEvents > 1
                  ? (val) {
                      workSession.scrubTo(val.toInt());
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 6),

          // Controls row:
          // skip-previous icon at left, center Live with 8 dp green dot #25BA3C and 16 dp text,
          // skip-next at right. When viewing history, center becomes white outlined pill "Jump to live".
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Lucide.SkipBack, size: 18),
                color: currentIndex > 0
                    ? (isDark ? Colors.white : const Color(0xFF33332B))
                    : (isDark ? Colors.white24 : const Color(0xFFCCCCCC)),
                onPressed: currentIndex > 0
                    ? () => workSession.skipBack()
                    : null,
              ),

              // Center: Live or "Jump to live"
              if (isLive || totalEvents == 0)
                // Live indicator: 8 dp green dot #25BA3C + 16 dp semi-bold text
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF25BA3C),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Live',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF33332B),
                      ),
                    ),
                  ],
                )
              else
                // History mode: white outlined pill "Jump to live" with play icon
                GestureDetector(
                  onTap: () => workSession.jumpToLive(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFD0D0D0),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Lucide.Play, size: 13, color: Color(0xFF33332B)),
                        SizedBox(width: 6),
                        Text(
                          'Jump to live',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF33332B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              IconButton(
                icon: const Icon(Lucide.SkipForward, size: 18),
                color:
                    !isLive && totalEvents > 0 && currentIndex < totalEvents - 1
                    ? (isDark ? Colors.white : const Color(0xFF33332B))
                    : (isDark ? Colors.white24 : const Color(0xFFCCCCCC)),
                onPressed:
                    !isLive && totalEvents > 0 && currentIndex < totalEvents - 1
                    ? () => workSession.skipForward()
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Collapsible Plan Bar positioned UNDER the timeline scrubber
  // ---------------------------------------------------------------------------
  Widget _buildPlanProgressFooter(
    bool isDark,
    WorkPlan plan,
    Color borderColor,
  ) {
    final bool allDone = plan.completedCount == plan.totalCount;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111112) : const Color(0xFFF9F9F8),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _isPlanBarExpanded = !_isPlanBarExpanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    allDone ? Lucide.Check : Lucide.ListChecks,
                    size: 15,
                    color: allDone
                        ? const Color(0xFF16A34A)
                        : (isDark ? Colors.white70 : const Color(0xFF1A1A1A)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      allDone
                          ? '✓ Task Completed  ${plan.totalCount} / ${plan.totalCount}'
                          : '${plan.currentRunningStep?.description ?? "Plan progress"} (${plan.completedCount} / ${plan.totalCount})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                  Icon(
                    _isPlanBarExpanded ? Lucide.ChevronDown : Lucide.ChevronUp,
                    size: 14,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ],
              ),
            ),
          ),
          if (_isPlanBarExpanded)
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                shrinkWrap: true,
                itemCount: plan.steps.length,
                itemBuilder: (context, idx) {
                  final s = plan.steps[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          s.isCompleted
                              ? Lucide.CheckCircle2
                              : (s.isRunning
                                    ? Lucide.CircleDot
                                    : Lucide.Circle),
                          size: 13,
                          color: s.isCompleted
                              ? const Color(0xFF16A34A)
                              : (s.isRunning
                                    ? (isDark
                                          ? Colors.white
                                          : const Color(0xFF1A1A1A))
                                    : Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
