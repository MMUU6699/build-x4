import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/work_tool_event.dart';
import '../../providers/work_session_provider.dart';

/// Browser tool view matching Manus reference:
/// - Top row with centered underlined URL (about 11.5 dp, #535350) + hairline divider.
/// - Live screenshot view under it with aspect-fit containment.
class BrowserToolView extends StatefulWidget {
  const BrowserToolView({super.key, required this.event});

  final WorkToolEvent event;

  @override
  State<BrowserToolView> createState() => _BrowserToolViewState();
}

class _BrowserToolViewState extends State<BrowserToolView> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url =
        widget.event.browserUrl ??
        widget.event.arguments['url']?.toString() ??
        '';

    return Column(
      children: [
        // Top row: centered underlined URL (about 11.5 dp, #535350)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isDark ? const Color(0xFF1E1E20) : Colors.white,
          alignment: Alignment.center,
          child: Text(
            url.isEmpty ? 'No page loaded' : url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? const Color(0xFFA5A5A0) : const Color(0xFF535350),
              decoration: TextDecoration.underline,
              decorationColor: isDark
                  ? const Color(0xFFA5A5A0)
                  : const Color(0xFF535350),
            ),
          ),
        ),
        // Hairline divider
        Container(
          height: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFEFEFEF),
        ),
        // Viewport Content / Screenshot / Text fallback
        Expanded(
          child: Container(
            width: double.infinity,
            color: isDark ? const Color(0xFF0F0F0E) : const Color(0xFFFBFBF9),
            child: _buildViewportContent(isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildViewportContent(bool isDark) {
    final workSession = context.watch<WorkSessionProvider>();
    final screenshot = workSession.screenshotUrlFor(widget.event);
    if (screenshot != null && screenshot.isNotEmpty) {
      if (screenshot.startsWith('http')) {
        return Image.network(
          screenshot,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildTextFallback(isDark),
        );
      } else {
        try {
          final comma = screenshot.indexOf(',');
          final b64 = comma != -1
              ? screenshot.substring(comma + 1)
              : screenshot;
          final Uint8List bytes = base64Decode(b64);
          return Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _buildTextFallback(isDark),
          );
        } catch (_) {}
      }
    }
    return _buildTextFallback(isDark);
  }

  Widget _buildTextFallback(bool isDark) {
    final content = widget.event.result.isNotEmpty
        ? widget.event.result
        : 'No page text was captured for this step.';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: SelectableText(
        content,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: isDark ? const Color(0xFFDDDDDD) : const Color(0xFF222222),
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
