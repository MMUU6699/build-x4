import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../models/work_tool_event.dart';

class SearchToolView extends StatelessWidget {
  const SearchToolView({super.key, required this.event});

  final WorkToolEvent event;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = event.arguments['query']?.toString() ?? '';

    List<Map<String, dynamic>> results = [];
    try {
      final decoded = jsonDecode(event.result);
      if (decoded is List) {
        results = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}

    return Column(
      children: [
        // Search bar header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              Icon(
                Lucide.Search,
                size: 16,
                color: isDark ? Colors.white70 : const Color(0xFF141413),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  query,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Search Results list
        Expanded(
          child: results.isNotEmpty
              ? ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = results[index];
                    final title = item['title']?.toString() ?? 'Result';
                    final url = item['url']?.toString() ?? '';
                    final snippet = item['snippet']?.toString() ?? '';

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF161615)
                            : const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Lucide.Globe,
                                size: 13,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF141413),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            snippet,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: isDark
                                  ? const Color(0xFFCCCCCC)
                                  : const Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      event.result.isNotEmpty
                          ? event.result
                          : 'No structured search results available.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
