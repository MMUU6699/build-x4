import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/interactive_drawer.dart';
import '../widgets/side_drawer.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../chat/widgets/frosted/chat_frosted_backdrop.dart';
import '../../chat/widgets/chat_assistant_background.dart';

/// Mobile layout scaffold for the home page
/// This widget handles only the structural layout - AppBar, drawer, body structure
/// All message list rendering and input bar logic remain in home_page.dart
class HomeMobileScaffold extends StatelessWidget {
  const HomeMobileScaffold({
    super.key,
    required this.scaffoldKey,
    required this.drawerController,
    required this.assistantPickerCloseTick,
    required this.loadingConversationIds,
    required this.title,
    this.providerName,
    this.modelDisplay,
    required this.onToggleDrawer,
    required this.onDismissKeyboard,
    required this.onSelectConversation,
    required this.onNewConversation,
    required this.onOpenMiniMap,
    required this.onCreateNewConversation,
    required this.onToggleTemporaryConversation,
    this.onSelectModel,
    required this.canToggleTemporaryConversation,
    required this.temporaryConversationEnabled,
    required this.globalSearchMode,
    required this.globalSearchQuery,
    required this.onGlobalSearchQueryChanged,
    required this.onEnterGlobalSearch,
    required this.onExitGlobalSearch,
    required this.onOpenGlobalSearchResult,
    this.appBarOverride,
    required this.body,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final InteractiveDrawerController drawerController;
  final ValueNotifier<int> assistantPickerCloseTick;
  final Set<String> loadingConversationIds;
  final String title;
  final String? providerName;
  final String? modelDisplay;
  final VoidCallback onToggleDrawer;
  final VoidCallback onDismissKeyboard;
  final void Function(String id) onSelectConversation;
  final VoidCallback onNewConversation;
  final VoidCallback onOpenMiniMap;
  final Future<void> Function() onCreateNewConversation;
  final Future<void> Function() onToggleTemporaryConversation;
  final VoidCallback? onSelectModel;
  final bool canToggleTemporaryConversation;
  final bool temporaryConversationEnabled;
  final bool globalSearchMode;
  final String globalSearchQuery;
  final ValueChanged<String> onGlobalSearchQueryChanged;
  final VoidCallback onEnterGlobalSearch;
  final VoidCallback onExitGlobalSearch;
  final Future<void> Function(String conversationId, String messageId)
  onOpenGlobalSearchResult;
  final PreferredSizeWidget? appBarOverride;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InteractiveDrawer(
      controller: drawerController,
      side: DrawerSide.left,
      drawerWidth: MediaQuery.sizeOf(context).width * 0.75,
      scrimColor: cs.onSurface,
      maxScrimOpacity: 0.12,
      barrierDismissible: true,
      drawer: SideDrawer(
        userName: context.watch<UserProvider>().name,
        assistantName: _getAssistantName(context),
        closePickerTicker: assistantPickerCloseTick,
        loadingConversationIds: loadingConversationIds,
        globalSearchMode: globalSearchMode,
        globalSearchQuery: globalSearchQuery,
        onGlobalSearchQueryChanged: onGlobalSearchQueryChanged,
        onEnterGlobalSearch: onEnterGlobalSearch,
        onExitGlobalSearch: onExitGlobalSearch,
        onOpenGlobalSearchResult: (conversationId, messageId) async {
          await onOpenGlobalSearchResult(conversationId, messageId);
          drawerController.close();
        },
        onSelectConversation: (id, {closeDrawer = true}) {
          onSelectConversation(id);
          if (closeDrawer) drawerController.close();
        },
        onNewConversation: ({closeDrawer = true}) async {
          await onCreateNewConversation();
          if (closeDrawer) drawerController.close();
        },
      ),
      child: ChatFrostedBackdrop(
        backdrop: const MobileBackgroundLayer(),
        child: Scaffold(
          key: scaffoldKey,
          resizeToAvoidBottomInset: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: appBarOverride ?? _buildAppBar(context, cs),
          body: body,
        ),
      ),
    );
  }

  String _getAssistantName(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final a = context.watch<AssistantProvider>().currentAssistant;
    final n = a?.name.trim();
    return (n == null || n.isEmpty) ? l10n.homePageDefaultAssistant : n;
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final btnBg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
    final btnBorder = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFEAEAEA);
    final iconColor = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF0D0D0D);

    return AppBar(
      systemOverlayStyle: isDark
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      leadingWidth: 58,
      leading: Padding(
        padding: const EdgeInsetsDirectional.only(start: 14),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            button: true,
            label: 'Menu',
            child: InkWell(
              onTap: () {
                onDismissKeyboard();
                onToggleDrawer();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: btnBg,
                  border: Border.all(color: btnBorder, width: 1.0),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  'assets/icons/list.svg',
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                ),
              ),
            ),
          ),
        ),
      ),
      title: const SizedBox.shrink(),
      actions: [
        // Temporary chat circular button (40x40)
        Semantics(
          button: true,
          label: 'Temporary chat',
          child: InkWell(
            onTap: () async {
              await onToggleTemporaryConversation();
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: temporaryConversationEnabled
                    ? (isDark
                          ? const Color(0xFFFFFFFF)
                          : const Color(0xFF0D0D0D))
                    : btnBg,
                border: Border.all(
                  color: temporaryConversationEnabled
                      ? (isDark
                            ? const Color(0xFFFFFFFF)
                            : const Color(0xFF0D0D0D))
                      : btnBorder,
                  width: 1.0,
                ),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              alignment: Alignment.center,
              child: Icon(
                Lucide.MessageCircleDashed,
                size: 19,
                color: temporaryConversationEnabled
                    ? (isDark
                          ? const Color(0xFF0A0A0A)
                          : const Color(0xFFFFFFFF))
                    : iconColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // New conversation circular button (40x40)
        Semantics(
          button: true,
          label: 'New conversation',
          child: InkWell(
            onTap: () async {
              await onCreateNewConversation();
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: btnBg,
                border: Border.all(color: btnBorder, width: 1.0),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              alignment: Alignment.center,
              child: Icon(Lucide.SquarePen, size: 19, color: iconColor),
            ),
          ),
        ),
        const SizedBox(width: 14),
      ],
    );
  }
}

/// Mobile background widget with assistant-specific image and gradient overlay
class MobileBackgroundLayer extends StatelessWidget {
  const MobileBackgroundLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChatAssistantBackground();
  }
}

/// Scroll navigation buttons (scroll to bottom + scroll to previous message)
class ScrollNavigationButtons extends StatelessWidget {
  const ScrollNavigationButtons({
    super.key,
    required this.showJumpToBottom,
    required this.inputBarHeight,
    required this.hasMessages,
    required this.onScrollToBottom,
    required this.onScrollToPreviousQuestion,
  });

  final bool showJumpToBottom;
  final double inputBarHeight;
  final bool hasMessages;
  final VoidCallback onScrollToBottom;
  final VoidCallback onScrollToPreviousQuestion;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

/// Selection mode toolbar overlay
class SelectionToolbarOverlay extends StatelessWidget {
  const SelectionToolbarOverlay({
    super.key,
    required this.visible,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool visible;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 122),
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: IgnorePointer(
                ignoring: !visible,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GlassCircleButton(
                      icon: Lucide.X,
                      color: cs.onSurface,
                      onTap: onCancel,
                      semanticLabel: l10n.homePageCancel,
                    ),
                    const SizedBox(width: 14),
                    _GlassCircleButton(
                      icon: Lucide.Check,
                      color: cs.primary,
                      onTap: onConfirm,
                      semanticLabel: l10n.homePageDone,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatefulWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  State<_GlassCircleButton> createState() => _GlassCircleButtonState();
}

class _GlassCircleButtonState extends State<_GlassCircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassBase = cs.surface.withValues(alpha: 0.06);
    final overlay = cs.onSurface.withValues(alpha: isDark ? 0.06 : 0.05);
    final tileColor = _pressed
        ? Color.alphaBlend(overlay, glassBase)
        : glassBase;
    final borderColor = cs.outlineVariant.withValues(alpha: 0.10);

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tileColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Center(
                  child: Icon(widget.icon, size: 18, color: widget.color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
