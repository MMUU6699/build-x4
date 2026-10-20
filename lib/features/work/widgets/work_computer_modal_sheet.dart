import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../models/work_tool_event.dart';
import '../providers/work_session_provider.dart';
import 'tool_views/browser_tool_view.dart';
import 'tool_views/file_tool_view.dart';
import 'tool_views/generic_tool_view.dart';
import 'tool_views/search_tool_view.dart';
import 'tool_views/shell_tool_view.dart';

/// The live computer panel. Shows the tool call the user tapped, or the last
/// call of the current turn.
class WorkComputerModalSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final workSession = context.watch<WorkSessionProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bgColor = isDark ? const Color(0xFF161618) : const Color(0xFFF5F5F5);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);
    final currentEvent = workSession.computerEvent;

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
          _buildHeader(context, isDark, borderColor, workSession),
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
                  : _buildViewportContent(currentEvent),
            ),
          ),
          _buildStatusRow(context, isDark, borderColor, workSession),
        ],
      ),
    );
  }

  Widget _buildStatusRow(
    BuildContext context,
    bool isDark,
    Color borderColor,
    WorkSessionProvider workSession,
  ) {
    final currentEvent = workSession.computerEvent;
    var categoryLabel = 'tools';
    var categoryIcon = Lucide.Wrench;
    if (currentEvent != null) {
      if (currentEvent.isBrowser) {
        categoryLabel = 'the browser';
        categoryIcon = Lucide.Compass;
      } else if (currentEvent.isShell) {
        categoryLabel = 'the terminal';
        categoryIcon = Lucide.Terminal;
      } else if (currentEvent.isFile) {
        categoryLabel = 'the file editor';
        categoryIcon = Lucide.FileCode;
      } else if (currentEvent.isSearch) {
        categoryLabel = 'web search';
        categoryIcon = Lucide.Search;
      }
    }

    var actionSubtitle = currentEvent?.brief ?? '';
    if (currentEvent != null && currentEvent.isBrowser) {
      final url = currentEvent.browserUrl ?? currentEvent.arguments['url'];
      if (url != null && url.toString().isNotEmpty) {
        actionSubtitle = url.toString();
      }
    } else if (currentEvent != null && currentEvent.isShell) {
      final command = currentEvent.arguments['command'];
      if (command != null && command.toString().isNotEmpty) {
        actionSubtitle = command.toString();
      }
    }

    final running = workSession.phase == WorkSessionPhase.running;
    final title = currentEvent == null
        ? 'No computer action yet'
        : running
        ? 'Build X is using $categoryLabel'
        : 'Build X used $categoryLabel';
    final subtitle = currentEvent == null
        ? (running
              ? 'Waiting for the first tool call…'
              : 'The computer has not run a tool.')
        : actionSubtitle;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        14 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161618) : const Color(0xFFF5F5F5),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEDEDED),
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
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF33332B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isDark,
    Color borderColor,
    WorkSessionProvider workSession,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
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
              const SizedBox(width: 28),
            ],
          ),
        ],
      ),
    );
  }

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
            'No computer action yet.',
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

  Widget _buildViewportContent(WorkToolEvent event) {
    if (event.isBrowser) return BrowserToolView(event: event);
    if (event.isShell) return ShellToolView(event: event);
    if (event.isFile) return FileToolView(event: event);
    if (event.isSearch) return SearchToolView(event: event);
    return GenericToolView(event: event);
  }
}
