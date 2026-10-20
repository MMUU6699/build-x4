import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../models/work_tool_event.dart';
import '../models/work_turn.dart';
import '../providers/work_session_provider.dart';

/// One agent turn in the conversation thread.
///
/// The turn is persisted and never replaces earlier turns. Tool rows only ask
/// the provider to open the computer; [HomePage] owns the single sheet.
class WorkTurnWidget extends StatefulWidget {
  const WorkTurnWidget({super.key, required this.turn});

  final WorkTurn turn;

  @override
  State<WorkTurnWidget> createState() => _WorkTurnWidgetState();
}

class _WorkTurnWidgetState extends State<WorkTurnWidget>
    with TickerProviderStateMixin {
  late final AnimationController _shimmerController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  bool? _toolsExpandedOverride;

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

  bool get _toolsExpanded {
    if (_toolsExpandedOverride != null) return _toolsExpandedOverride!;
    return widget.turn.isRunning;
  }

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final workSession = context.watch<WorkSessionProvider>();
    final hasActivity = turn.events.isNotEmpty;
    final startingComputer = workSession.isStartingComputer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (turn.isRunning || turn.isWaiting)
            _buildRunningHeader(
              context,
              isDark,
              turn,
              hasActivity,
              startingComputer,
            )
          else
            _buildFinishedHeader(isDark, turn),
          if (turn.introMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              turn.introMessage,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: isDark
                    ? const Color(0xFFB0B0B5)
                    : const Color(0xFF555555),
              ),
            ),
          ],
          if (hasActivity) ...[
            const SizedBox(height: 8),
            _buildToolGroup(context, isDark, workSession, turn),
          ],
          if (turn.isRunning) ...[
            const SizedBox(height: 8),
            _buildLiveIndicator(isDark, turn),
          ],
          if (turn.isWaiting) ...[
            const SizedBox(height: 8),
            _buildWaiting(turn, isDark),
          ],
          if (turn.isCompleted) ...[
            const SizedBox(height: 10),
            _buildFinalAnswer(context, isDark, turn),
          ],
          if (turn.isError) ...[
            const SizedBox(height: 8),
            _buildError(context, isDark, workSession, turn),
          ],
          if (turn.isStopped) ...[
            const SizedBox(height: 8),
            Text(
              turn.error ?? 'Stopped by you.',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? const Color(0xFFAEAEB2)
                    : const Color(0xFF707070),
              ),
            ),
          ],
          if (turn.isCompleted || turn.isError) ...[
            const SizedBox(height: 8),
            _buildActionRow(context, isDark, workSession, turn),
          ],
        ],
      ),
    );
  }

  Widget _buildRunningHeader(
    BuildContext context,
    bool isDark,
    WorkTurn turn,
    bool hasActivity,
    bool startingComputer,
  ) {
    final nothingArrivedYet =
        !hasActivity && turn.introMessage.isEmpty && turn.question == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          turn.isWaiting ? 'Build X is waiting' : 'Build X',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            color: isDark ? Colors.white : const Color(0xFF141413),
          ),
        ),
        if (nothingArrivedYet) ...[
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              final progress = _shimmerController.value;
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
                child: Text(
                  turn.isWaiting
                      ? 'Waiting for your answer...'
                      : startingComputer
                      ? 'Starting computer...'
                      : 'Build X is thinking...',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildFinishedHeader(bool isDark, WorkTurn turn) {
    final expanded = _toolsExpanded;
    final label = turn.isCompleted
        ? 'Worked for ${turn.durationSeconds}s'
        : turn.isError
        ? 'Stopped after ${turn.durationSeconds}s'
        : 'Worked for ${turn.durationSeconds}s';
    return GestureDetector(
      onTap: () => setState(() => _toolsExpandedOverride = !_toolsExpanded),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF555555),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            expanded ? Lucide.ChevronDown : Lucide.ChevronRight,
            size: 14,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ],
      ),
    );
  }

  Widget _buildToolGroup(
    BuildContext context,
    bool isDark,
    WorkSessionProvider workSession,
    WorkTurn turn,
  ) {
    final expanded = _toolsExpanded;
    final browserCount = turn.events.where((event) => event.isBrowser).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _toolsExpandedOverride = !_toolsExpanded),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                browserCount > 1
                    ? 'Browsed $browserCount pages'
                    : 'Used ${turn.events.length} tools',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF666666),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded ? Lucide.ChevronDown : Lucide.ChevronRight,
                size: 14,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ],
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 6),
          for (final event in turn.events)
            _buildToolRow(context, isDark, workSession, turn, event),
        ],
      ],
    );
  }

  Widget _buildToolRow(
    BuildContext context,
    bool isDark,
    WorkSessionProvider workSession,
    WorkTurn turn,
    WorkToolEvent event,
  ) {
    IconData icon = Lucide.Wrench;
    if (event.isBrowser) {
      icon = Lucide.Globe;
    } else if (event.isShell) {
      icon = Lucide.Terminal;
    } else if (event.isFile) {
      icon = Lucide.FileText;
    } else if (event.isSearch) {
      icon = Lucide.Search;
    }

    final isRunning = event.status == 'running';
    final row = Row(
      children: [
        Icon(
          icon,
          size: 18,
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
      onTap: () => workSession.openComputer(turnId: turn.id, eventId: event.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: isRunning
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
                    child: row,
                  );
                },
              )
            : row,
      ),
    );
  }

  Widget _buildLiveIndicator(bool isDark, WorkTurn turn) {
    final runningEvent = turn.events.cast<WorkToolEvent?>().firstWhere(
      (event) => event?.status == 'running',
      orElse: () => null,
    );
    var statusText = 'Thinking';
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
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          statusText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFFB0B0B5) : const Color(0xFF555555),
          ),
        ),
      ],
    );
  }

  Widget _buildWaiting(WorkTurn turn, bool isDark) {
    return Text(
      turn.question ?? 'The agent needs more information to continue.',
      style: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: isDark ? const Color(0xFFD5D5D8) : const Color(0xFF333333),
      ),
    );
  }

  Widget _buildFinalAnswer(BuildContext context, bool isDark, WorkTurn turn) {
    final answer = turn.finalAnswer ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          answer,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: isDark ? const Color(0xFFE8E8EA) : const Color(0xFF1A1A1A),
          ),
        ),
        if (turn.result != null && turn.result!.attachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final attachment in turn.result!.attachments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Lucide.Paperclip,
                    size: 14,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      attachment.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFFA5A5A0)
                            : const Color(0xFF6B6B6B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Lucide.CheckCircle2, size: 14, color: Color(0xFF25BA3C)),
            SizedBox(width: 5),
            Text(
              'Task completed',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF25BA3C),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildError(
    BuildContext context,
    bool isDark,
    WorkSessionProvider workSession,
    WorkTurn turn,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Lucide.AlertCircle, size: 16, color: Color(0xFFE53935)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            turn.error ?? 'The task failed.',
            style: const TextStyle(
              color: Color(0xFFE53935),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    bool isDark,
    WorkSessionProvider workSession,
    WorkTurn turn,
  ) {
    final color = isDark ? Colors.white54 : Colors.black45;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (turn.isCompleted)
          _iconButton(
            icon: Lucide.Copy,
            color: color,
            tooltip: 'Copy answer',
            onTap: () {
              final answer = turn.finalAnswer ?? '';
              if (answer.isEmpty) return;
              Clipboard.setData(ClipboardData(text: answer));
            },
          ),
        _iconButton(
          icon: Lucide.RotateCcw,
          color: color,
          tooltip: 'Run again',
          onTap: () =>
              workSession.startWorkTask(turn.conversationId, turn.prompt),
        ),
      ],
    );
  }

  Widget _iconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
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
