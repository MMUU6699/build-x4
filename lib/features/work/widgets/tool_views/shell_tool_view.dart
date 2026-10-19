import 'package:flutter/material.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../models/work_tool_event.dart';

class ShellToolView extends StatelessWidget {
  const ShellToolView({super.key, required this.event});

  final WorkToolEvent event;

  @override
  Widget build(BuildContext context) {
    final command = event.arguments['command']?.toString() ?? '';
    final cwd = event.arguments['cwd']?.toString() ?? '~';
    final output = event.result.isNotEmpty
        ? event.result
        : (event.isCalling ? 'Running command...' : 'No output produced.');

    return Column(
      children: [
        // Terminal Window Titlebar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF181817),
            border: Border(bottom: BorderSide(color: Color(0xFF262624))),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFF5F56),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFBD2E),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF27C93F),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Lucide.Terminal, size: 13, color: Colors.white54),
              const SizedBox(width: 6),
              Text(
                'bash - $cwd',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        // Terminal Buffer
        Expanded(
          child: Container(
            color: const Color(0xFF0C0C0B),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prompt line
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(
                          text: 'ubuntu@sandbox',
                          style: TextStyle(
                            color: Color(0xFF25BA3B),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const TextSpan(
                          text: ':',
                          style: TextStyle(color: Colors.white60),
                        ),
                        TextSpan(
                          text: '$cwd\$ ',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: command,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Output text
                  SelectableText(
                    output,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.45,
                      color: event.isFailed
                          ? const Color(0xFFFF6B6B)
                          : const Color(0xFFD6D6D6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
