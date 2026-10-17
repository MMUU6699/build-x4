import 'dart:io' show File, Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/widgets/emoji_text.dart';
import '../l10n/app_localizations.dart';
import '../core/providers/user_provider.dart';
import '../core/providers/settings_provider.dart';
import 'user_profile_dialog.dart';
import '../icons/lucide_adapter.dart' as lucide;
import '../utils/sandbox_path_resolver.dart';
import '../theme/app_font_weights.dart';

/// A compact left rail for desktop with avatar, primary actions, and bottom system toggles.
class DesktopNavRail extends StatelessWidget {
  const DesktopNavRail({
    super.key,
    required this.activeIndex,
    required this.onTapChat,
    required this.onTapWorkspaces,
    required this.onTapSettings,
  });

  final int activeIndex; // 0=Chat, 1=Workspaces, 2=Settings
  final VoidCallback onTapChat;
  final VoidCallback onTapWorkspaces;
  final VoidCallback onTapSettings;

  static const double width = 64.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isMac = Platform.isMacOS;
    final double topGap = isMac ? 36.0 : 8.0;
    final isChatActive = activeIndex == 0;
    final isWorkspacesActive = activeIndex == 1;
    final isSettingsActive = activeIndex == 2;

    return Container(
      width: width,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          SizedBox(height: topGap),
          _UserAvatarButton(),
          const SizedBox(height: 16),
          _CircleAction(
            tooltip: l10n.desktopNavChatTooltip,
            icon: lucide.Lucide.MessageCircle,
            onTap: onTapChat,
            size: 40,
            iconSize: 18,
            iconColor: isChatActive ? cs.primary : null,
          ),
          const SizedBox(height: 8),
          _CircleAction(
            tooltip: l10n.workspaceDeskMenuWorkspace,
            icon: lucide.Lucide.FolderCode,
            onTap: onTapWorkspaces,
            size: 40,
            iconSize: 18,
            iconColor: isWorkspacesActive ? cs.primary : null,
          ),
          const Spacer(),
          _ThemeCycleButton(),
          const SizedBox(height: 8),
          _CircleAction(
            tooltip: l10n.settingsPageTitle,
            icon: lucide.Lucide.Settings,
            onTap: onTapSettings,
            size: 40,
            iconSize: 18,
            iconColor: isSettingsActive ? cs.primary : null,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _UserAvatarButton extends StatefulWidget {
  @override
  State<_UserAvatarButton> createState() => _UserAvatarButtonState();
}

class _UserAvatarButtonState extends State<_UserAvatarButton> {
  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final cs = Theme.of(context).colorScheme;
    Widget avatar;
    final type = up.avatarType;
    final value = up.avatarValue;
    if (type == 'emoji' && value != null && value.isNotEmpty) {
      avatar = Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: EmojiText(value, fontSize: 18, optimizeEmojiAlign: true),
      );
    } else if (type == 'url' && value != null && value.isNotEmpty) {
      avatar = ClipOval(
        child: Image.network(
          value,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return _initialAvatar(up.name, cs);
          },
        ),
      );
    } else if (type == 'file' && value != null && value.isNotEmpty) {
      final fixed = SandboxPathResolver.fix(value);
      final f = File(fixed);
      if (f.existsSync()) {
        avatar = ClipOval(
          child: Image.file(
            f,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return _initialAvatar(up.name, cs);
            },
          ),
        );
      } else {
        avatar = _initialAvatar(up.name, cs);
      }
    } else {
      avatar = _initialAvatar(up.name, cs);
    }

    return _CircleAction(
      tooltip: up.name.isNotEmpty ? up.name : 'Profile',
      onTap: () {
        showUserProfileDialog(context);
      },
      size: 40,
      customChild: avatar,
    );
  }

  Widget _initialAvatar(String name, ColorScheme cs) {
    final trimmed = name.trim();
    final letter = trimmed.isNotEmpty ? trimmed.characters.first : 'U';
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: cs.primary,
          fontSize: 16,
          fontWeight: AppFontWeights.semibold,
        ),
      ),
    );
  }
}

class _CircleAction extends StatefulWidget {
  const _CircleAction({
    required this.tooltip,
    this.icon,
    required this.onTap,
    this.size = 36.0,
    this.iconSize = 18.0,
    this.iconColor,
    this.customChild,
  });

  final String tooltip;
  final IconData? icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final Widget? customChild;

  @override
  State<_CircleAction> createState() => _CircleActionState();
}

class _CircleActionState extends State<_CircleAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.06);

    Widget inner;
    if (widget.customChild != null) {
      inner = widget.customChild!;
    } else {
      final color =
          widget.iconColor ??
          cs.onSurface.withValues(alpha: isDark ? 0.8 : 0.7);
      inner = Icon(widget.icon, size: widget.iconSize, color: color);
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _hover ? hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: inner,
          ),
        ),
      ),
    );
  }
}

class _ThemeCycleButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SettingsProvider>();
    final mode = sp.themeMode;

    IconData icon;
    String tip;
    switch (mode) {
      case ThemeMode.system:
        icon = lucide.Lucide.SunMoon;
        tip = 'System Theme';
        break;
      case ThemeMode.light:
        icon = lucide.Lucide.Sun;
        tip = 'Light Theme';
        break;
      case ThemeMode.dark:
        icon = lucide.Lucide.Moon;
        tip = 'Dark Theme';
        break;
    }

    return _CircleAction(
      tooltip: tip,
      icon: icon,
      onTap: () {
        final next = switch (mode) {
          ThemeMode.system => ThemeMode.light,
          ThemeMode.light => ThemeMode.dark,
          ThemeMode.dark => ThemeMode.system,
        };
        sp.setThemeMode(next);
      },
      size: 40,
      iconSize: 18,
    );
  }
}
