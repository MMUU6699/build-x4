import 'package:flutter/material.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'desktop_nav_rail.dart';
import 'desktop_chat_page.dart';
import 'window_title_bar.dart';
import 'desktop_settings_page.dart';
import '../features/workspace/pages/workspaces_page.dart';
import '../l10n/app_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async';
import 'hotkeys/hotkey_event_bus.dart';
import 'hotkeys/chat_action_bus.dart';
import 'desktop_settings_navigation_bus.dart';
import '../core/services/notification_service.dart';

/// Desktop home screen: left compact rail + main content.
class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({
    super.key,
    this.initialTabIndex,
    this.initialProviderKey,
  });

  final int? initialTabIndex; // 0=Chat, 1=Workspaces, 2=Settings
  final String? initialProviderKey;

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage> {
  int _tabIndex = 0; // 0=Chat, 1=Workspaces, 2=Settings
  StreamSubscription<HotkeyAction>? _hotkeySub;
  StreamSubscription<ChatAction>? _chatActionSub;
  StreamSubscription<DesktopSettingsNavigationTarget>? _settingsNavSub;
  StreamSubscription<String>? _conversationOpenSub;

  @override
  void initState() {
    super.initState();
    if (widget.initialTabIndex != null) {
      _tabIndex = widget.initialTabIndex!.clamp(0, 2);
    }
    _conversationOpenSub = NotificationService.conversationTaps.listen((_) {
      if (!mounted) return;
      setState(() {
        _tabIndex = 0;
      });
      ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
    });
    if (_tabIndex == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ChatActionBus.instance.fire(ChatAction.focusInput);
      });
    }
    _hotkeySub = HotkeyEventBus.instance.stream.listen((action) async {
      switch (action) {
        case HotkeyAction.openSettings:
          if (mounted) {
            setState(() {
              _tabIndex = 2;
            });
            ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
          }
          break;
        case HotkeyAction.closeWindow:
          try {
            await windowManager.close();
          } catch (_) {}
          break;
        case HotkeyAction.toggleAppVisibility:
        case HotkeyAction.showOrHideWindow:
          try {
            final isVisible = await windowManager.isVisible();
            if (!isVisible) {
              await windowManager.show();
              await windowManager.focus();
              if (_tabIndex == 0) {
                ChatActionBus.instance.fire(ChatAction.focusInput);
              }
            } else {
              await windowManager.hide();
            }
          } catch (_) {}
          break;
        case HotkeyAction.newTopic:
          if (_tabIndex == 0) {
            ChatActionBus.instance.fire(ChatAction.newTopic);
          }
          break;
        case HotkeyAction.switchModel:
          break;
        case HotkeyAction.toggleLeftPanelAssistants:
          if (_tabIndex == 0) {
            ChatActionBus.instance.fire(ChatAction.toggleLeftPanelAssistants);
          }
          break;
        case HotkeyAction.toggleLeftPanelTopics:
          if (_tabIndex == 0) {
            ChatActionBus.instance.fire(ChatAction.toggleLeftPanelTopics);
          }
          break;
      }
    });

    _chatActionSub = ChatActionBus.instance.stream.listen((action) {
      if (!mounted) return;
      switch (action) {
        case ChatAction.enterGlobalSearch:
          setState(() {
            _tabIndex = 0;
          });
          break;
        default:
          break;
      }
    });
    _settingsNavSub = DesktopSettingsNavigationBus.instance.stream.listen((
      target,
    ) {
      if (!mounted) return;
      setState(() {
        _tabIndex = 2;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    const minWidth = 960.0;
    const minHeight = 640.0;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final needsWidthPad = w < minWidth;
        final needsHeightPad = h < minHeight;

        Widget body = Row(
          children: [
            DesktopNavRail(
              activeIndex: _tabIndex,
              onTapChat: () {
                setState(() {
                  _tabIndex = 0;
                });
                ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
                ChatActionBus.instance.fire(ChatAction.focusInput);
              },
              onTapWorkspaces: () {
                setState(() {
                  _tabIndex = 1;
                });
                ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
              },
              onTapSettings: () {
                setState(() {
                  _tabIndex = 2;
                });
                ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
              },
            ),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  const DesktopChatPage(),
                  const WorkspacesPage(),
                  DesktopSettingsPage(
                    key: const ValueKey('settings_page'),
                    initialProviderKey: widget.initialProviderKey,
                  ),
                ],
              ),
            ),
          ],
        );

        if (isWindows) {
          body = Column(
            children: [
              const WindowTitleBar(
                title: 'Build X',
                leading: _TitleBarLeading(),
              ),
              Expanded(child: body),
            ],
          );
        }

        if (needsWidthPad || needsHeightPad) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SizedBox(
                width: w < minWidth ? minWidth : w,
                height: h < minHeight ? minHeight : h,
                child: body,
              ),
            ),
          );
        }

        return body;
      },
    );
  }

  @override
  void dispose() {
    try {
      _conversationOpenSub?.cancel();
    } catch (_) {}
    try {
      _hotkeySub?.cancel();
    } catch (_) {}
    try {
      _chatActionSub?.cancel();
    } catch (_) {}
    try {
      _settingsNavSub?.cancel();
    } catch (_) {}
    super.dispose();
  }
}

class _TitleBarLeading extends StatelessWidget {
  const _TitleBarLeading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/app_icon.png',
          width: 16,
          height: 16,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(width: 8),
        Text(
          l10n.aboutPageAppName,
          style: TextStyle(
            fontSize: 13,
            fontWeight: AppFontWeights.semibold,
            color: cs.onSurface.withValues(alpha: 0.8),
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
