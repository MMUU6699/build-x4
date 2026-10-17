import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:Kelivo/theme/app_semantic_colors.dart';
import '../core/models/assistant.dart';
import '../core/providers/assistant_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/services/linux_window_service.dart';
import '../features/assistant/pages/assistant_settings_edit_page.dart'
    show showAssistantDesktopDialog;
import '../features/home/controllers/chat_actions.dart' show ChatActions;
import '../features/settings/pages/google_fonts_picker_page.dart';
import '../features/settings/pages/message_style_settings_page.dart';
import '../features/settings/pages/settings_search_page.dart';
import '../features/settings/search/settings_search_index.dart';
import '../features/settings/widgets/custom_theme_widgets.dart';
import '../features/settings/widgets/settings_search_entry.dart';
import '../features/settings/widgets/settings_search_target.dart';
import '../icons/lucide_adapter.dart' as lucide;
import '../l10n/app_localizations.dart';
import '../shared/widgets/ios_switch.dart';
import '../shared/widgets/snackbar.dart';
import '../shared/widgets/tip_icon.dart';
import '../theme/app_font_weights.dart';
import '../theme/custom_theme.dart';
import '../theme/palettes.dart';
import '../utils/app_directories.dart';
import '../utils/avatar_cache.dart';
import '../utils/sandbox_path_resolver.dart';
import 'desktop_context_menu.dart';
import 'setting/about_pane.dart';
import 'setting/auto_retry_pane.dart';
import 'setting/hotkeys_pane.dart';
import 'setting/skills_settings_pane.dart';
import 'setting/stats_pane.dart';
import 'setting/workspace_pane.dart';
import 'widgets/desktop_select_dropdown.dart';

part 'setting/assistants_pane.dart';
part 'setting/display_pane.dart';

/// Desktop settings layout: left menu + vertical divider + right content.
class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({super.key, this.initialProviderKey});

  final String? initialProviderKey;

  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

enum _SettingsMenuItem {
  display,
  assistant,
  workspace,
  skills,
  hotkeys,
  stats,
  about,
}

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  _SettingsMenuItem _selected = _SettingsMenuItem.display;
  SettingsSearchItem? _searchTarget;
  int _searchNavigation = 0;

  Future<void> _openSearch() async {
    final item = await showDesktopSettingsSearch(context);
    if (!mounted || item == null) return;
    final menu = switch (item.destination) {
      SettingsSearchDestination.display ||
      SettingsSearchDestination.colorMode ||
      SettingsSearchDestination.theme ||
      SettingsSearchDestination.themeAdvanced ||
      SettingsSearchDestination.chatDisplay ||
      SettingsSearchDestination.rendering ||
      SettingsSearchDestination.behavior ||
      SettingsSearchDestination.image ||
      SettingsSearchDestination.messageStyle ||
      SettingsSearchDestination.autoRetry => _SettingsMenuItem.display,
      SettingsSearchDestination.assistant => _SettingsMenuItem.assistant,
      SettingsSearchDestination.workspace => _SettingsMenuItem.workspace,
      SettingsSearchDestination.skills => _SettingsMenuItem.skills,
      SettingsSearchDestination.hotkeys => _SettingsMenuItem.hotkeys,
      SettingsSearchDestination.stats => _SettingsMenuItem.stats,
      SettingsSearchDestination.about => _SettingsMenuItem.about,
      _ => _SettingsMenuItem.display,
    };
    setState(() {
      _selected = menu;
      _searchTarget = item;
      _searchNavigation++;
    });
    if (item.destination == SettingsSearchDestination.messageStyle) {
      await showMessageStyleSettingsDialog(context);
    } else if (item.destination == SettingsSearchDestination.autoRetry) {
      await showDesktopAutoRetryDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    const double menuWidth = 250;
    final topBar = SizedBox(
      height: 36,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, top: 8),
          child: Text(
            l10n.settingsPageTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          topBar,
          Expanded(
            child: Row(
              children: [
                _SettingsMenu(
                  width: menuWidth,
                  selected: _selected,
                  onSelect: (item) => setState(() => _selected = item),
                  onSearch: _openSearch,
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
                Expanded(
                  child: FocusTraversalGroup(
                    policy: ReadingOrderTraversalPolicy(),
                    child: () {
                      switch (_selected) {
                        case _SettingsMenuItem.display:
                          return _DisplaySettingsBody(
                            searchTarget: _searchTarget,
                            searchNavigation: _searchNavigation,
                          );
                        case _SettingsMenuItem.assistant:
                          return const _DesktopAssistantsBody();
                        case _SettingsMenuItem.workspace:
                          return const DesktopWorkspacePane(
                            key: ValueKey('workspace'),
                          );
                        case _SettingsMenuItem.skills:
                          return const DesktopSkillsSettingsPane(
                            key: ValueKey('skills'),
                          );
                        case _SettingsMenuItem.hotkeys:
                          return const DesktopHotkeysPane(
                            key: ValueKey('hotkeys'),
                          );
                        case _SettingsMenuItem.stats:
                          return const DesktopStatsPane(key: ValueKey('stats'));
                        case _SettingsMenuItem.about:
                          return const DesktopAboutPane(key: ValueKey('about'));
                      }
                    }(),
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

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({
    required this.width,
    required this.selected,
    required this.onSelect,
    required this.onSearch,
  });
  final VoidCallback onSearch;
  final double width;
  final _SettingsMenuItem selected;
  final ValueChanged<_SettingsMenuItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = [
      (
        _SettingsMenuItem.display,
        lucide.Lucide.Monitor,
        l10n.settingsPageDisplay,
      ),
      (
        _SettingsMenuItem.assistant,
        lucide.Lucide.Bot,
        l10n.settingsPageAssistant,
      ),
      (
        _SettingsMenuItem.workspace,
        lucide.Lucide.FolderCode,
        l10n.workspaceDeskMenuWorkspace,
      ),
      (
        _SettingsMenuItem.skills,
        lucide.Lucide.WandSparkles,
        l10n.workspaceDeskMenuSkills,
      ),
      (
        _SettingsMenuItem.hotkeys,
        lucide.Lucide.Keyboard,
        l10n.settingsPageHotkeys,
      ),
      (
        _SettingsMenuItem.stats,
        lucide.Lucide.ChartColumnBig,
        l10n.settingsPageStatistics,
      ),
      (
        _SettingsMenuItem.about,
        lucide.Lucide.BadgeInfo,
        l10n.settingsPageAbout,
      ),
    ];
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          SettingsSearchEntry(onTap: onSearch),
          const SizedBox(height: 16),
          for (int i = 0; i < items.length; i++) ...[
            _MenuItem(
              icon: items[i].$2,
              label: items[i].$3,
              selected: selected == items[i].$1,
              onTap: () => onSelect(items[i].$1),
              color: cs.onSurface.withValues(alpha: 0.9),
              selectedColor: cs.primary,
              hoverBg: cs.onSurface.withValues(alpha: isDark ? 0.06 : 0.04),
            ),
            if (i != items.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
    required this.selectedColor,
    required this.hoverBg,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final Color selectedColor;
  final Color hoverBg;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.selected
        ? cs.primary.withValues(alpha: 0.10)
        : _hover
        ? widget.hoverBg
        : Colors.transparent;
    final fg = widget.selected ? widget.selectedColor : widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: AppFontWeights.regular,
                    color: fg,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
