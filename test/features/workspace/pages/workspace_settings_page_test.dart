import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/workspace_provider.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/workspace/pages/workspace_settings_page.dart';
import 'package:Kelivo/features/workspace/pages/workspaces_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/theme/theme_factory.dart';

import '../../../support/business_test_harness.dart';
import '../terminal/fake_workspace_runtime.dart';

class _CountingRuntimeProvider extends WorkspaceRuntimeProvider {
  int refreshCalls = 0;

  @override
  Future<RuntimeStatus> refresh() async {
    refreshCalls += 1;
    return super.refresh();
  }
}

void main() {
  testWidgets(
    'refresh is called once on mount and displays Daytona Cloud Sandbox',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late _CountingRuntimeProvider runtime;
      late WorkspaceProvider workspaces;

      await tester.runAsync(() async {
        runtime = _CountingRuntimeProvider()
          ..register(FakeWorkspaceRuntime(ready: true));
        workspaces = WorkspaceProvider();
        await workspaces.loaded;
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider<WorkspaceProvider>.value(value: workspaces),
            ChangeNotifierProvider<WorkspaceRuntimeProvider>.value(
              value: runtime,
            ),
          ],
          child: MaterialApp(
            theme: buildLightTheme(null),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const WorkspaceSettingsPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(runtime.refreshCalls, 1);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(WorkspaceSettingsPage)),
      )!;
      expect(find.text(l10n.workspaceEnvTitle), findsOneWidget);
      expect(find.text('Daytona Cloud Sandbox'), findsOneWidget);
      expect(find.text('Active & Cloud Connected'), findsOneWidget);
      expect(find.byKey(WorkspacesPane.createKey), findsOneWidget);
    },
  );
}
