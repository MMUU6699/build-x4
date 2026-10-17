import 'package:flutter/material.dart';

import '../../assistant/pages/assistant_settings_page.dart';
import '../../stats/pages/stats_page.dart';
import '../../workspace/pages/skills_page.dart';
import '../../workspace/pages/workspace_settings_page.dart';
import '../pages/about_page.dart';
import '../pages/auto_retry_page.dart';
import '../pages/display_settings_page.dart';
import '../pages/image_settings_page.dart';
import '../pages/log_viewer_page.dart';
import '../pages/message_style_settings_page.dart';
import '../pages/mobile_background_settings_page.dart';
import '../pages/sponsor_page.dart';
import '../pages/storage_space_page.dart';
import '../pages/theme_advanced_settings_page.dart';
import '../pages/theme_settings_page.dart';
import '../widgets/settings_search_target.dart';
import 'settings_search_index.dart';

Future<void> openMobileSettingsSearchResult(
  BuildContext context,
  SettingsSearchItem item,
) async {
  final Widget? page = switch (item.destination) {
    SettingsSearchDestination.display => const DisplaySettingsPage(),
    SettingsSearchDestination.theme => const ThemeSettingsPage(),
    SettingsSearchDestination.themeAdvanced =>
      const ThemeAdvancedSettingsPage(),
    SettingsSearchDestination.chatDisplay =>
      const ChatItemDisplaySettingsPage(),
    SettingsSearchDestination.rendering => const RenderingSettingsPage(),
    SettingsSearchDestination.behavior => const BehaviorStartupSettingsPage(),
    SettingsSearchDestination.image => const ImageSettingsPage(),
    SettingsSearchDestination.messageStyle => const MessageStyleSettingsPage(),
    SettingsSearchDestination.autoRetry => const AutoRetryPage(),
    SettingsSearchDestination.haptics => const HapticsSettingsPage(),
    SettingsSearchDestination.background =>
      const MobileBackgroundSettingsPage(),
    SettingsSearchDestination.assistant => const AssistantSettingsPage(),
    SettingsSearchDestination.workspace => const WorkspaceSettingsPage(),
    SettingsSearchDestination.skills => const SkillsPage(),
    SettingsSearchDestination.storage => const StorageSpacePage(),
    SettingsSearchDestination.stats => const StatsPage(),
    SettingsSearchDestination.logs => const LogViewerPage(),
    SettingsSearchDestination.about => const AboutPage(),
    SettingsSearchDestination.sponsor => const SponsorPage(),
    _ => null,
  };
  if (page == null) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          SettingsSearchTarget(label: item.targetLabel, child: page),
    ),
  );
}
