import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/workspace/workspace_paths.dart';
import 'package:Kelivo/core/services/workspace/workspace_tools_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('kelivo_tool_handler_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  WorkspaceToolContext createContext() {
    final workspace = Directory(p.join(tmp.path, 'ws'))..createSync();
    final session = Directory(p.join(tmp.path, 'session'))..createSync();
    final skills = Directory(p.join(tmp.path, 'skills'))..createSync();
    return WorkspaceToolContext(
      workspace: Workspace(
        id: 'ws-1',
        name: 'Test Workspace',
        kind: WorkspaceKind.managed,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      binding: const WorkspaceBinding(workspaceId: 'ws-1'),
      paths: WorkspacePaths.native(
        workspaceHostRoot: workspace.path,
        sessionHostDir: session.path,
        skillsHostDir: skills.path,
      ),
      sessionDir: session,
      outputsDir: Directory(p.join(session.path, 'outputs'))..createSync(),
    );
  }

  group('ToolHandlerService', () {
    testWidgets(
      'buildToolDefinitions returns empty when workspaceContext is null',
      (tester) async {
        final settings = SettingsProvider(createBusinessTestPreferences());
        addTearDown(settings.dispose);
        await settings.loaded;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ],
            child: const SizedBox.shrink(),
          ),
        );

        final service = ToolHandlerService(
          contextProvider: tester.element(find.byType(SizedBox)),
        );
        const assistant = Assistant(id: 'a1', name: 'Test');

        final defs = service.buildToolDefinitions(
          settings,
          assistant,
          'mistral',
          'mistral-medium-latest',
          false,
        );

        expect(defs, isEmpty);
        expect(
          service.captureMcpToolRoutes(assistant).containsExposedName('any'),
          isFalse,
        );
      },
    );

    testWidgets(
      'buildToolDefinitions returns tools when workspaceContext is present',
      (tester) async {
        final settings = SettingsProvider(createBusinessTestPreferences());
        addTearDown(settings.dispose);
        await settings.loaded;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ],
            child: const SizedBox.shrink(),
          ),
        );

        final service = ToolHandlerService(
          contextProvider: tester.element(find.byType(SizedBox)),
        );
        const assistant = Assistant(id: 'a1', name: 'Test');

        final defs = service.buildToolDefinitions(
          settings,
          assistant,
          'mistral',
          'mistral-medium-latest',
          false,
          workspaceContext: createContext(),
        );

        expect(defs, isNotEmpty);
        final toolNames = defs
            .map((d) => (d['function'] as Map)['name'] as String)
            .toSet();
        expect(toolNames, containsAll(WorkspaceToolsService.toolNames));
      },
    );

    testWidgets(
      'buildToolCallHandler returns null when workspaceContext is null',
      (tester) async {
        final settings = SettingsProvider(createBusinessTestPreferences());
        addTearDown(settings.dispose);
        await settings.loaded;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ],
            child: const SizedBox.shrink(),
          ),
        );

        final service = ToolHandlerService(
          contextProvider: tester.element(find.byType(SizedBox)),
        );
        const assistant = Assistant(id: 'a1', name: 'Test');

        final handler = service.buildToolCallHandler(settings, assistant);

        expect(handler, isNull);
      },
    );

    testWidgets('buildToolCallHandler returns error for unknown tool', (
      tester,
    ) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      await settings.loaded;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: const SizedBox.shrink(),
        ),
      );

      final service = ToolHandlerService(
        contextProvider: tester.element(find.byType(SizedBox)),
      );
      const assistant = Assistant(id: 'a1', name: 'Test');

      final handler = service.buildToolCallHandler(
        settings,
        assistant,
        workspaceContext: createContext(),
      );

      expect(handler, isNotNull);
      final result = await handler!('unknown_tool', <String, dynamic>{});
      expect(result, isA<Map<String, dynamic>>());
      expect((result as Map)['error'], contains('Unknown tool'));
    });
  });
}
