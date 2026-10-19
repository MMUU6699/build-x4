import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../providers/work_session_provider.dart';

/// Full-screen interactive browser takeover view replicating official Manus TakeOverView.
/// Features:
/// - Top browser bar: Tabs, URL address bar, Back, Forward, Reload.
/// - Floating vertical dock on the left (6 controls: collapse, pan/touch, keyboard, paste, mobile/desktop, close).
/// - "Let Build X know what you changed" exit dialog on close.
/// - Zero emojis policy.
class InteractiveBrowserTakeoverView extends StatefulWidget {
  const InteractiveBrowserTakeoverView({
    super.key,
    required this.initialUrl,
    this.initialTitle,
  });

  final String initialUrl;
  final String? initialTitle;

  static Future<void> show(
    BuildContext context, {
    required String initialUrl,
    String? initialTitle,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (ctx, anim1, anim2) => InteractiveBrowserTakeoverView(
          initialUrl: initialUrl,
          initialTitle: initialTitle,
        ),
        transitionsBuilder: (ctx, anim1, anim2, child) {
          return FadeTransition(opacity: anim1, child: child);
        },
      ),
    );
  }

  @override
  State<InteractiveBrowserTakeoverView> createState() =>
      _InteractiveBrowserTakeoverViewState();
}

class _InteractiveBrowserTakeoverViewState
    extends State<InteractiveBrowserTakeoverView> {
  late String _currentUrl;
  late String _pageTitle;
  late TextEditingController _urlController;

  bool _isDockExpanded = true;
  bool _isTouchMode = false;
  bool _isMobileViewport = false;
  bool _showMockKeyboard = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl.isNotEmpty
        ? widget.initialUrl
        : 'https://www.google.com';
    _pageTitle = widget.initialTitle ?? 'Google';
    _urlController = TextEditingController(text: _currentUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handleExit() async {
    final workSession = context.read<WorkSessionProvider>();

    // Show "Let Build X know what you changed" modal dialog
    final result = await showDialog<_TakeoverFeedbackResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _TakeoverFeedbackDialog(),
    );

    if (!mounted) return;

    if (result != null && result.continueChat) {
      // User submitted feedback to let agent continue
      await workSession.resumeWithTakeoverFeedback(
        result.summary,
        persistLogin: result.persistLogin,
        currentUrl: _currentUrl,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121214)
          : const Color(0xFFF7F7F8),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // 1. Top Browser Chrome Bar
                _buildTopBrowserBar(isDark),

                // 2. Interactive Remote Viewport Canvas
                Expanded(
                  child: Center(
                    child: Container(
                      width: _isMobileViewport ? 420 : double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E20) : Colors.white,
                        boxShadow: _isMobileViewport
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: _buildInteractiveBrowserContent(isDark),
                    ),
                  ),
                ),
              ],
            ),

            // 3. Floating Vertical Control Dock on the Left
            Positioned(
              left: 16,
              top: 80,
              child: _buildFloatingControlDock(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBrowserBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFEBEBEB),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Column(
        children: [
          // Tab row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Lucide.Globe,
                      size: 13,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        _pageTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Lucide.X,
                      size: 11,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Small Exit Pill
              GestureDetector(
                onTap: () => _handleExit(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.X, size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Exit Takeover',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Navigation & Address Bar
          Row(
            children: [
              IconButton(
                icon: const Icon(Lucide.ArrowLeft, size: 15),
                onPressed: () {},
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              IconButton(
                icon: const Icon(Lucide.ArrowRight, size: 15),
                onPressed: () {},
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: isDark ? Colors.white38 : Colors.black26,
              ),
              IconButton(
                icon: const Icon(Lucide.RotateCw, size: 15),
                onPressed: () {},
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Lucide.ShieldCheck,
                        size: 13,
                        color: Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (val) {
                            setState(() {
                              _currentUrl = val;
                              _pageTitle = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveBrowserContent(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Lucide.Compass,
              size: 48,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
            const SizedBox(height: 16),
            Text(
              _currentUrl,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Remote browser session in sandbox',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Floating Vertical Control Dock on the Left (#3A3A3C capsule, 6 controls)
  // ---------------------------------------------------------------------------
  Widget _buildFloatingControlDock(BuildContext context) {
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3C).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Toggle Dock Expand
          _buildDockIcon(
            icon: _isDockExpanded ? Lucide.ChevronUp : Lucide.ChevronDown,
            label: 'Collapse',
            onTap: () => setState(() => _isDockExpanded = !_isDockExpanded),
          ),
          if (_isDockExpanded) ...[
            const SizedBox(height: 6),
            // 2. Pan / Touch Mode
            _buildDockIcon(
              icon: Lucide.MousePointer,
              isActive: _isTouchMode,
              label: 'Touch Mode',
              onTap: () => setState(() => _isTouchMode = !_isTouchMode),
            ),
            const SizedBox(height: 6),
            // 3. Keyboard Input
            _buildDockIcon(
              icon: Lucide.Keyboard,
              isActive: _showMockKeyboard,
              label: 'Keyboard',
              onTap: () =>
                  setState(() => _showMockKeyboard = !_showMockKeyboard),
            ),
            const SizedBox(height: 6),
            // 4. Paste Clipboard
            _buildDockIcon(
              icon: Lucide.ClipboardPaste,
              label: 'Paste',
              onTap: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  _urlController.text = data!.text!;
                }
              },
            ),
            const SizedBox(height: 6),
            // 5. Mobile / Desktop Viewport Toggle
            _buildDockIcon(
              icon: _isMobileViewport ? Lucide.Smartphone : Lucide.Monitor,
              isActive: _isMobileViewport,
              label: 'Viewport',
              onTap: () =>
                  setState(() => _isMobileViewport = !_isMobileViewport),
            ),
            const SizedBox(height: 10),
            Container(height: 1, width: 24, color: Colors.white24),
            const SizedBox(height: 10),
          ],
          // 6. Close / Exit Button
          _buildDockIcon(
            icon: Lucide.X,
            color: Colors.redAccent,
            label: 'Exit',
            onTap: () => _handleExit(),
          ),
        ],
      ),
    );
  }

  Widget _buildDockIcon({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    Color? color,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.08),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 15,
            color:
                color ?? (isActive ? const Color(0xFF141413) : Colors.white70),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// "Let Build X know what you changed" Exit Modal Dialog
// -----------------------------------------------------------------------------
class _TakeoverFeedbackResult {
  final bool continueChat;
  final String summary;
  final bool persistLogin;

  const _TakeoverFeedbackResult({
    required this.continueChat,
    required this.summary,
    required this.persistLogin,
  });
}

class _TakeoverFeedbackDialog extends StatefulWidget {
  const _TakeoverFeedbackDialog();

  @override
  State<_TakeoverFeedbackDialog> createState() =>
      _TakeoverFeedbackDialogState();
}

class _TakeoverFeedbackDialogState extends State<_TakeoverFeedbackDialog> {
  final TextEditingController _summaryController = TextEditingController();
  bool _persistLogin = true;

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              'Let Build X know what you changed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF111111),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              'Summarize your browser actions to help Build X work smoothly.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : const Color(0xFF666666),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            // Multiline input field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _summaryController,
                maxLines: 4,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'Please enter content (optional)',
                  hintStyle: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Persist login state row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFEFEFEF),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Persist login state across tasks',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF333333),
                      ),
                    ),
                  ),
                  Switch(
                    value: _persistLogin,
                    activeThumbColor: isDark
                        ? Colors.white
                        : const Color(0xFF141413),
                    activeTrackColor: isDark ? Colors.white38 : Colors.black26,
                    onChanged: (val) => setState(() => _persistLogin = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons: Cancel (gray) & Continue chat (black/white)
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        const _TakeoverFeedbackResult(
                          continueChat: false,
                          summary: '',
                          persistLogin: false,
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFE5E5EA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF555555),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _TakeoverFeedbackResult(
                          continueChat: true,
                          summary: _summaryController.text.trim(),
                          persistLogin: _persistLogin,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: isDark
                          ? Colors.white
                          : const Color(0xFF111111),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Continue chat',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFF111111) : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
