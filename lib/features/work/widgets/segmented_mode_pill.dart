import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/work_session_provider.dart';

class SegmentedModePill extends StatelessWidget {
  const SegmentedModePill({super.key, this.onModeChanged});

  final ValueChanged<AppMode>? onModeChanged;

  @override
  Widget build(BuildContext context) {
    final workSession = context.watch<WorkSessionProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWork = workSession.isWorkMode;

    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFEFEFEF);
    final borderColor = isDark
        ? const Color(0xFF2C2C2E)
        : Colors.black.withValues(alpha: 0.05);
    final indicatorColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFFFFFFF);
    final activeTextColor = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF0D0D0D);
    final inactiveTextColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF555555);

    return Container(
      width: 164,
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: isWork ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 78,
              height: 32,
              decoration: BoxDecoration(
                color: indicatorColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.07),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    workSession.setMode(AppMode.chat);
                    onModeChanged?.call(AppMode.chat);
                  },
                  child: Center(
                    child: Text(
                      'Chat',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: !isWork ? FontWeight.w600 : FontWeight.w500,
                        color: !isWork ? activeTextColor : inactiveTextColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    workSession.setMode(AppMode.work);
                    onModeChanged?.call(AppMode.work);
                  },
                  child: Center(
                    child: Text(
                      'Work',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: isWork ? FontWeight.w600 : FontWeight.w500,
                        color: isWork ? activeTextColor : inactiveTextColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
