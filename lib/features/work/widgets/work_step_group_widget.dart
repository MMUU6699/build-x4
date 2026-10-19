import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../models/work_tool_event.dart';
import '../providers/work_session_provider.dart';
import 'work_computer_modal_sheet.dart';

/// Single unified Work assistant turn widget strictly replicating official Manus:
/// - No crossed-out checklist.
/// - No stuck chip above the ChatBox.
/// - No white card wrapper around final answer.
/// - Assistant turn rendered ONCE directly on background (#EAEAEA / scaffoldBackgroundColor).
/// - 1. Header: Build X wordmark (bold serif, 17 dp). While nothing arrived: 'Build X is thinking...' shimmer.
/// - 2. message_notify_user text (secondary gray, 15 dp).
/// - 3. Tool group 'Used tools >' (chevron). Expanded while running, collapsed after completion.
///      One row per REAL tool call (20 dp icon, brief 14 dp gray). Shimmers while running.
/// - 4. Live indicator while running: 8 dp pulsing blue dot + 'Thinking', 'Using browser', etc.
/// - 5. On completion: collapses activity into top line 'Worked for {N}s >' (real elapsed seconds).
/// - 6. Final answer text, action row (copy, regenerate, 5 outline stars), green check 'Task completed' (#25BA3C).
/// - 7. On error: red-toned line with real error text and retry action.
class WorkStepGroupWidget extends StatefulWidget {
  const WorkStepGroupWidget({super.key});

  @override
  State<WorkStepGroupWidget> createState() => _WorkStepGroupWidgetState();
}

class _WorkStepGroupWidgetState extends State<WorkStepGroupWidget>
    with TickerProviderStateMixin {
  late final AnimationController _shimmerController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  bool _isToolsExpandedManual = false;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workSession = context.watch<WorkSessionProvider>();
    if (!workSession.isWorkMode) return const SizedBox.shrink();

    final isRunning = workSession.isAgentRunning;
    final errorMessage = workSession.errorMessage;
    final timeline = workSession.timelineEvents;
    final notifyMsg = workSession.notifyMessage;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isError =
        !isRunning &&
        (workSession.phase == WorkSessionPhase.error || errorMessage != null);

    // Render ONLY while running or on active error.
    // Completed turns are permanently saved to ChatController and rendered in the message thread.
    if (!isRunning && !isError) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Error state top header: 'Worked for {N}s >'
          if (isError)
            _buildCompletedWorkedHeader(context, isDark, workSession),

          // 2. Running state Header: 'Build X' bold serif + thinking shimmer
          if (isRunning) ...[
            _buildRunningHeader(isDark, timeline, notifyMsg),
            const SizedBox(height: 8),
          ],

          // 3. message_notify_user text (secondary gray, 15 dp)
          if (notifyMsg != null && notifyMsg.isNotEmpty) ...[
            Text(
              notifyMsg,
              style: TextStyle(
                fontSize: 15,
                color: isDark
                    ? const Color(0xFFB0B0B5)
                    : const Color(0xFF555555),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 4. Tool group: 'Used tools >'
          if (timeline.isNotEmpty) ...[
            _buildUsedToolsGroup(context, isDark, workSession, isRunning),
            const SizedBox(height: 10),
          ],

          // 5. Running Live Indicator (bottom-of-block)
          if (isRunning) ...[
            _buildRunningLiveIndicator(isDark, workSession),
            const SizedBox(height: 8),
          ],

          // 6. Error State: Real honest error line + Retry
          if (isError) ...[
            const SizedBox(height: 8),
            _buildErrorRow(context, isDark, workSession),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Completed Top Collapsed Header: 'Worked for {N}s >'
  // ---------------------------------------------------------------------------
  Widget _buildCompletedWorkedHeader(
    BuildContext context,
    bool isDark,
    WorkSessionProvider workSession,
  ) {
    final int duration = workSession.workedDurationSeconds > 0
        ? workSession.workedDurationSeconds
        : 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isToolsExpandedManual = !_isToolsExpandedManual;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Worked for ${duration}s',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF555555),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _isToolsExpandedManual ? Lucide.ChevronDown : Lucide.ChevronRight,
              size: 14,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Running Header: Build X wordmark (bold serif, 17 dp)
  // ---------------------------------------------------------------------------
  Widget _buildRunningHeader(
    bool isDark,
    List<WorkToolEvent> timeline,
    String? notifyMsg,
  ) {
    final bool nothingArrivedYet =
        timeline.isEmpty && (notifyMsg == null || notifyMsg.isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Build X',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
        if (nothingArrivedYet) ...[
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              final double progress = _shimmerController.value;
              return ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  final baseColor = isDark
                      ? const Color(0xFF7A7A80)
                      : const Color(0xFF8E8E93);
                  final highlightColor = isDark
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFF141413);

                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [baseColor, highlightColor, baseColor],
                    stops: const [0.0, 0.5, 1.0],
                    transform: _GradientTranslate(progress * 2 - 1),
                  ).createShader(bounds);
                },
                child: const Text(
                  'Build X is thinking...',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Tool Group: 'Used tools >'
  // ---------------------------------------------------------------------------
  Widget _buildUsedToolsGroup(
    BuildContext context,
    bool isDark,
    WorkSessionProvider workSession,
    bool isRunning,
  ) {
    final isExpanded = isRunning
        ? !_isToolsExpandedManual
        : _isToolsExpandedManual;
    final timeline = workSession.timelineEvents;

    // Group browser calls under 'Browsed N page(s)' if multiple
    final browserCount = timeline.where((e) => e.isBrowser).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _isToolsExpandedManual = !_isToolsExpandedManual;
            });
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                browserCount > 1 ? 'Browsed $browserCount pages' : 'Used tools',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF666666),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isExpanded ? Lucide.ChevronDown : Lucide.ChevronRight,
                size: 14,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ],
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(height: 6),
          for (int i = 0; i < timeline.length; i++)
            _buildToolRow(context, isDark, timeline[i], i, workSession),
        ],
      ],
    );
  }

  Widget _buildToolRow(
    BuildContext context,
    bool isDark,
    WorkToolEvent event,
    int index,
    WorkSessionProvider workSession,
  ) {
    final isEventRunning = event.status == 'running';
    IconData iconData = Lucide.Terminal;
    if (event.isBrowser) {
      iconData = Lucide.Globe;
    } else if (event.isShell) {
      iconData = Lucide.Terminal;
    } else if (event.isFile) {
      iconData = Lucide.FileText;
    } else if (event.isSearch) {
      iconData = Lucide.Search;
    }

    final rowContent = Row(
      children: [
        Icon(
          iconData,
          size: 20,
          color: isDark ? Colors.white60 : const Color(0xFF707070),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            event.brief,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : const Color(0xFF666666),
            ),
          ),
        ),
      ],
    );

    return InkWell(
      onTap: () {
        workSession.openComputer(eventIndex: index);
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const WorkComputerModalSheet(),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: isEventRunning
            ? AnimatedBuilder(
                animation: _shimmerController,
                builder: (context, child) {
                  final progress = _shimmerController.value;
                  return ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) {
                      final base = isDark
                          ? const Color(0xFFAEAEB2)
                          : const Color(0xFF555555);
                      final highlight = isDark
                          ? const Color(0xFFFFFFFF)
                          : const Color(0xFF141413);
                      return LinearGradient(
                        colors: [base, highlight, base],
                        stops: const [0.0, 0.5, 1.0],
                        transform: _GradientTranslate(progress * 2 - 1),
                      ).createShader(bounds);
                    },
                    child: rowContent,
                  );
                },
              )
            : rowContent,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Running Live Indicator (bottom-of-block)
  // ---------------------------------------------------------------------------
  Widget _buildRunningLiveIndicator(
    bool isDark,
    WorkSessionProvider workSession,
  ) {
    final runningEvent = workSession.timelineEvents
        .cast<WorkToolEvent?>()
        .firstWhere((e) => e?.status == 'running', orElse: () => null);

    String statusText = 'Thinking';
    if (runningEvent != null) {
      if (runningEvent.isBrowser) {
        statusText = 'Using browser';
      } else if (runningEvent.isShell) {
        statusText = 'Using terminal';
      } else if (runningEvent.isFile) {
        statusText = 'Editing file';
      } else if (runningEvent.isSearch) {
        statusText = 'Searching web';
      }
    }

    return Row(
      children: [
        ScaleTransition(
          scale: _pulseScale,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF0081F2),
              boxShadow: [
                BoxShadow(
                  color: Color(0x660081F2),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          statusText,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFFB0B0B5) : const Color(0xFF555555),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 7. Error State: Red line with real error text and retry
  // ---------------------------------------------------------------------------
  Widget _buildErrorRow(
    BuildContext context,
    bool isDark,
    WorkSessionProvider workSession,
  ) {
    return Row(
      children: [
        const Icon(Lucide.AlertCircle, size: 16, color: Color(0xFFE53935)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            workSession.errorMessage ?? 'Execution failed',
            style: const TextStyle(
              color: Color(0xFFE53935),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            final cid = workSession.activeConversationId;
            final prompt = workSession.lastPrompt;
            if (cid != null && prompt != null) {
              workSession.startWorkTask(cid, prompt);
            }
          },
          child: const Text(
            'Retry',
            style: TextStyle(
              color: Color(0xFFE53935),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _GradientTranslate extends GradientTransform {
  final double dx;
  const _GradientTranslate(this.dx);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * dx, 0, 0);
  }
}
