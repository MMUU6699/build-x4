import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../models/work_tool_event.dart';
import '../providers/work_session_provider.dart';
import 'work_computer_modal_sheet.dart';

/// Recessed computer card placed in layout directly above the ChatBox.
/// Strictly follows official Manus mobile design:
/// - 3.1 Placement and structure:
///   - Separate widget directly above the ChatBox, full ChatBox width (16 dp side margins).
///   - Sits BEHIND top edge of ChatBox: lower part covered by ChatBox rounded top.
///   - Visible strip height: 44 dp.
///   - Card shape: top corners radius 27 dp.
///   - Fill: vertical gradient from #F5F5F5 (top) to #F1F1F1 (bottom). No border. No shadow.
/// - 3.2 Thumbnail (the "small screen"):
///   - Size: 59 x 39 dp, radius 8 dp, fill #FEFEFE, soft shadow (blur 8, y offset 2, black 10%).
///   - Pokes out: top edge is 8 dp above the card's top edge. Left edge inset 16 dp from card's left.
///   - Inactive: tiny monitor icon centered + caption "Build X's computer is inactive" (4.5 dp font, #9A9A9A).
///   - Active: live miniature of CURRENT tool view, rendered non-interactive, scaled down with FittedBox.
/// - 3.3 Status label:
///   - To right of thumbnail: 16 dp gap, vertically centered on thumbnail center line.
///   - 16 dp square tile, radius 6 dp, fill #F0EFF7, containing pulsing orb.
///   - Orb: soft blue blob 11 dp, gradient cyan #2CC3E8 to blue #2861F8, pulses 0.85 to 1.10 continuously (1.2s loop).
///   - Gap 8 dp, then text "Working" at 14 dp, color #5F5F5F, regular weight.
/// - 3.4 Behavior:
///   - Visible iff session phase == running.
///   - 200 ms slide-up (12 dp) + fade. Disappears with 150 ms fade only after phase leaves running.
///   - Whole card is one tap target opening computer sheet.
class WorkComputerTray extends StatefulWidget {
  const WorkComputerTray({super.key});

  @override
  State<WorkComputerTray> createState() => _WorkComputerTrayState();
}

class _WorkComputerTrayState extends State<WorkComputerTray>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    // 1.2s continuous pulsing loop (0.85 to 1.10 scale)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseScale = Tween<double>(begin: 0.85, end: 1.10).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workSession = context.watch<WorkSessionProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Visible iff session phase == running in Work mode
    final bool isVisible =
        workSession.isWorkMode && workSession.phase == WorkSessionPhase.running;
    final currentEvent = workSession.currentEvent;

    if (isVisible) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
    }

    return AnimatedSlide(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      offset: isVisible ? Offset.zero : const Offset(0, 0.25),
      child: AnimatedOpacity(
        duration: Duration(milliseconds: isVisible ? 200 : 150),
        curve: Curves.easeInOut,
        opacity: isVisible ? 1.0 : 0.0,
        child: isVisible
            ? _buildCard(context, isDark, workSession, currentEvent)
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    bool isDark,
    WorkSessionProvider workSession,
    WorkToolEvent? currentEvent,
  ) {
    // 3.1 Card measurements:
    // Full width with 16 dp horizontal margins.
    // Visible strip: 44 dp above ChatBox.
    // Bottom overlap: 14 dp behind ChatBox top edge.
    // Top poke out for thumbnail: 8 dp.
    // Total layout height: 8 + 44 = 52 dp.
    const double pokeOutHeight = 8.0;
    const double visibleStripHeight = 44.0;
    const double overlapBehindChatBox = 14.0;
    const double layoutHeight = pokeOutHeight + visibleStripHeight; // 52.0 dp

    final cardGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF202022), Color(0xFF18181A)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F5F5), Color(0xFFF1F1F1)],
          );

    final statusTileBg = isDark
        ? const Color(0xFF282834)
        : const Color(0xFFF0EFF7);
    final workingTextColor = isDark
        ? const Color(0xFFAEAEAE)
        : const Color(0xFF5F5F5F);

    return GestureDetector(
      onTap: () {
        workSession.openComputer();
        WorkComputerModalSheet.show(context);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: layoutHeight,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 3.1 Card background container (sits behind ChatBox top edge)
            Positioned(
              top: pokeOutHeight,
              left: 0,
              right: 0,
              bottom: -overlapBehindChatBox,
              child: Container(
                decoration: BoxDecoration(
                  gradient: cardGradient,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(27),
                  ),
                ),
              ),
            ),

            // 3.2 Thumbnail (the "small screen"): 59 x 39 dp, radius 8 dp, fill #FEFEFE
            // Pokes out 8 dp above card top edge (top: 0), inset 16 dp from left
            Positioned(
              top: 0,
              left: 16,
              width: 59,
              height: 39,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1B1B1E)
                      : const Color(0xFFFEFEFE),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A000000), // black 10%
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildThumbnailContent(isDark, workSession),
              ),
            ),

            // 3.3 Status label: 16 dp gap to right of thumbnail, vertically centered
            Positioned(
              top: 0,
              height: 39,
              left: 16 + 59 + 16, // 91 dp from card's left edge
              right: 16,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 16 dp square tile, radius 6 dp, fill #F0EFF7
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: statusTileBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: ScaleTransition(
                        scale: _pulseScale,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2CC3E8), Color(0xFF2861F8)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // "Working" text at 14 dp, regular weight, #5F5F5F
                    Text(
                      'Working',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                        color: workingTextColor,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3.2 Thumbnail content: Real screenshot or Dark Terminal Preview
  // ---------------------------------------------------------------------------
  Widget _buildThumbnailContent(bool isDark, WorkSessionProvider workSession) {
    // 0. If no events have run yet, show inactive computer thumbnail
    if (workSession.timelineEvents.isEmpty &&
        workSession.currentEvent == null) {
      return _buildInactiveThumbnail(isDark);
    }

    // 1. Look for latest real screenshot in timeline events
    String? latestScreenshot;
    for (final ev in workSession.timelineEvents.reversed) {
      if (ev.screenshotUrl != null && ev.screenshotUrl!.isNotEmpty) {
        latestScreenshot = ev.screenshotUrl;
        break;
      }
    }

    if (latestScreenshot != null && latestScreenshot.isNotEmpty) {
      if (latestScreenshot.startsWith('http')) {
        return Image.network(
          latestScreenshot,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _buildTerminalPreview(workSession),
        );
      } else {
        try {
          final comma = latestScreenshot.indexOf(',');
          final b64 = comma != -1
              ? latestScreenshot.substring(comma + 1)
              : latestScreenshot;
          final Uint8List bytes = base64Decode(b64);
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _buildTerminalPreview(workSession),
          );
        } catch (_) {}
      }
    }

    // 2. Real terminal preview if no screenshot captured yet
    return _buildTerminalPreview(workSession);
  }

  Widget _buildInactiveThumbnail(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF3F3F5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Lucide.Monitor,
              size: 14,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(height: 2),
            Text(
              "Build X's computer is inactive",
              style: TextStyle(
                fontSize: 4.0,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalPreview(WorkSessionProvider workSession) {
    final lastEvent =
        workSession.currentEvent ??
        (workSession.timelineEvents.isNotEmpty
            ? workSession.timelineEvents.last
            : null);
    final cmd =
        lastEvent?.arguments['command']?.toString() ??
        (lastEvent != null
            ? '${lastEvent.toolName} ${lastEvent.brief}'
            : 'daytona sandbox ready');
    final stdout = lastEvent != null && lastEvent.result.isNotEmpty
        ? lastEvent.result.trim()
        : 'Process active';

    return Container(
      color: const Color(0xFF141416),
      padding: const EdgeInsets.all(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'ubuntu@sandbox:~\$',
            style: TextStyle(
              fontSize: 4.5,
              color: Color(0xFF4ADE80),
              fontFamily: 'monospace',
              height: 1.0,
            ),
          ),
          Text(
            cmd,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 4.5,
              color: Colors.white,
              fontFamily: 'monospace',
              height: 1.0,
            ),
          ),
          Text(
            stdout,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 4.0,
              color: Colors.white70,
              fontFamily: 'monospace',
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
