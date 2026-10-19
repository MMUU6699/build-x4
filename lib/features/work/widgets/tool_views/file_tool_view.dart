import 'package:flutter/material.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../models/work_tool_event.dart';

enum FileViewTab { diff, original, modified }

class FileToolView extends StatefulWidget {
  const FileToolView({super.key, required this.event});

  final WorkToolEvent event;

  @override
  State<FileToolView> createState() => _FileToolViewState();
}

class _FileToolViewState extends State<FileToolView> {
  // Default tab order: Diff | Original | Modified, defaulting to Modified
  FileViewTab _activeTab = FileViewTab.modified;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filePath =
        widget.event.arguments['file_path']?.toString() ??
        widget.event.arguments['path']?.toString() ??
        'file.txt';

    final original = widget.event.originalFileContent ?? '';
    final modified =
        widget.event.modifiedFileContent ??
        widget.event.arguments['content']?.toString() ??
        widget.event.result;

    return Column(
      children: [
        // Top Toolbar: Path + Tab selector (Diff | Original | Modified)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                Lucide.FileCode,
                size: 15,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  filePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Tabs: Diff | Original | Modified
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF121211)
                      : const Color(0xFFDFDDD5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTabButton('Diff', FileViewTab.diff, isDark),
                    _buildTabButton('Original', FileViewTab.original, isDark),
                    _buildTabButton('Modified', FileViewTab.modified, isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Code / Diff Content
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF0C0C0B) : const Color(0xFFFAF9F6),
            width: double.infinity,
            child: _buildContent(isDark, original, modified),
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton(String label, FileViewTab tab, bool isDark) {
    final isSelected = _activeTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF2C2C2A) : const Color(0xFFFFFFFF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white54 : Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark, String original, String modified) {
    if (_activeTab == FileViewTab.original) {
      return _buildPlainCodeView(
        isDark,
        original.isNotEmpty ? original : 'No original file content available.',
      );
    } else if (_activeTab == FileViewTab.modified) {
      return _buildPlainCodeView(
        isDark,
        modified.isNotEmpty ? modified : 'No modified content available.',
      );
    } else {
      return _buildDiffView(isDark, original, modified);
    }
  }

  Widget _buildPlainCodeView(bool isDark, String text) {
    final lines = text.split('\n');
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 1.5,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white24 : Colors.black26,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: SelectableText(
                      lines[i],
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? const Color(0xFFE4E4E4)
                            : const Color(0xFF1E1E1E),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiffView(bool isDark, String original, String modified) {
    final origLines = original.split('\n');
    final modLines = modified.split('\n');

    final diffItems = <Map<String, dynamic>>[];
    final maxLen = origLines.length > modLines.length
        ? origLines.length
        : modLines.length;

    for (int i = 0; i < maxLen; i++) {
      final o = i < origLines.length ? origLines[i] : null;
      final m = i < modLines.length ? modLines[i] : null;

      if (o == m) {
        if (m != null) {
          diffItems.add({'type': 'same', 'text': m, 'line': i + 1});
        }
      } else {
        if (o != null) {
          diffItems.add({'type': 'removed', 'text': o, 'line': i + 1});
        }
        if (m != null) {
          diffItems.add({'type': 'added', 'text': m, 'line': i + 1});
        }
      }
    }

    if (diffItems.isEmpty) {
      return Center(
        child: Text(
          'No differences detected between original and modified.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in diffItems)
            Container(
              color: item['type'] == 'added'
                  ? const Color(
                      0xFF25BA3B,
                    ).withValues(alpha: isDark ? 0.16 : 0.12)
                  : (item['type'] == 'removed'
                        ? const Color(
                            0xFFE53935,
                          ).withValues(alpha: isDark ? 0.16 : 0.12)
                        : Colors.transparent),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      item['type'] == 'added'
                          ? '+'
                          : (item['type'] == 'removed' ? '-' : ' '),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: item['type'] == 'added'
                            ? const Color(0xFF25BA3B)
                            : (item['type'] == 'removed'
                                  ? const Color(0xFFE53935)
                                  : Colors.transparent),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      item['text'] as String,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: item['type'] == 'added'
                            ? (isDark
                                  ? const Color(0xFF66FF88)
                                  : const Color(0xFF0F7B28))
                            : (item['type'] == 'removed'
                                  ? (isDark
                                        ? const Color(0xFFFF7777)
                                        : const Color(0xFFB01212))
                                  : (isDark
                                        ? const Color(0xFFE4E4E4)
                                        : const Color(0xFF1E1E1E))),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
