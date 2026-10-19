import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../models/work_tool_event.dart';

class McpToolView extends StatelessWidget {
  const McpToolView({super.key, required this.event});

  final WorkToolEvent event;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final jsonEncoder = const JsonEncoder.withIndent('  ');

    String formattedArgs = '';
    try {
      formattedArgs = jsonEncoder.convert(event.arguments);
    } catch (_) {
      formattedArgs = event.arguments.toString();
    }

    String formattedResult = event.result;
    try {
      final decoded = jsonDecode(event.result);
      formattedResult = jsonEncoder.convert(decoded);
    } catch (_) {}

    return Column(
      children: [
        // Header bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1D) : const Color(0xFFEBE8E1),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(Lucide.Plug, size: 15, color: Colors.purpleAccent),
              const SizedBox(width: 8),
              Text(
                event.toolName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'MCP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.purpleAccent,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: event.isCompleted
                      ? const Color(0xFF25BA3B).withValues(alpha: 0.15)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.08)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  event.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: event.isCompleted
                        ? const Color(0xFF25BA3B)
                        : (isDark ? Colors.white70 : const Color(0xFF141413)),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content area: Arguments + Result
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Arguments',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF10100F)
                        : const Color(0xFFF2F0E8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    formattedArgs,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFFDDDDDD)
                          : const Color(0xFF222222),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Result',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF10100F)
                        : const Color(0xFFF2F0E8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    formattedResult.isNotEmpty
                        ? formattedResult
                        : (event.isCalling ? 'Running...' : 'Empty result'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFFDDDDDD)
                          : const Color(0xFF222222),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
