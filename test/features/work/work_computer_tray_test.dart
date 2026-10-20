import 'dart:async';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/services/workspace/work_event_persistence_service.dart';
import 'package:Kelivo/features/work/models/work_task_result.dart';
import 'package:Kelivo/features/work/models/work_tool_event.dart';
import 'package:Kelivo/features/work/models/work_turn.dart';
import 'package:Kelivo/features/work/providers/work_session_provider.dart';
import 'package:Kelivo/features/work/services/manus_agent_loop_service.dart';
import 'package:Kelivo/features/work/widgets/work_computer_tray.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';

class MockWorkEventPersistenceService extends WorkEventPersistenceService {
  const MockWorkEventPersistenceService();

  @override
  Future<void> updateWorkSession({
    required String conversationId,
    String? workspaceId,
    required String phase,
    DateTime? startedAt,
    DateTime? endedAt,
  }) async {}

  @override
  Future<Map<String, dynamic>?> fetchIntegrationStatus(String provider) async {
    return {'status': 'connected'};
  }

  @override
  Future<List<WorkTurn>> fetchWorkTurns(String conversationId) async => [];

  @override
  Future<void> saveWorkTurn(WorkTurn turn) async {}

  @override
  Future<String?> createScreenshotUrl(String path) async => null;
}

class MockManusAgentLoopService extends ManusAgentLoopService {
  MockManusAgentLoopService({
    this.events = const [],
    this.waitForCompleter = false,
  });

  final List<ManusAgentEvent> events;
  final bool waitForCompleter;
  final Completer<void> completer = Completer<void>();

  @override
  Future<Map<String, dynamic>> checkComputerHealth() async => {
    'status': 'connected',
  };

  @override
  Stream<ManusAgentEvent> runAgentLoop({
    required String conversationId,
    required String userRequest,
    int maxIterations = ManusAgentLoopService.defaultMaxIterations,
    CancelToken? cancelToken,
    List<Map<String, dynamic>>? existingMessages,
    String? pendingToolCallId,
  }) async* {
    for (final event in events) {
      yield event;
    }
    if (waitForCompleter) {
      await completer.future;
    }
  }
}

void main() {
  Widget buildTestWidget(WorkSessionProvider provider) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<WorkSessionProvider>.value(
          value: provider,
          child: const Column(
            children: [
              WorkComputerTray(),
              SizedBox(height: 50, key: Key('mock_chat_box')),
            ],
          ),
        ),
      ),
    );
  }

  group('WorkComputerTray Widget & Manus Design Tests', () {
    testWidgets('Card is hidden when session is idle', (tester) async {
      final mockAgent = MockManusAgentLoopService();
      final provider = WorkSessionProvider(
        agentService: mockAgent,
        persistenceService: const MockWorkEventPersistenceService(),
      );
      provider.setMode(AppMode.work);
      await tester.pumpWidget(buildTestWidget(provider));

      final animatedOpacityFinder = find.byType(AnimatedOpacity);
      expect(animatedOpacityFinder, findsOneWidget);
      final opacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacity.opacity, 0.0);
      expect(find.text('Working'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'Card is visible in running phase with inactive thumbnail before tool calls',
      (tester) async {
        final mockAgent = MockManusAgentLoopService(waitForCompleter: true);
        final provider = WorkSessionProvider(
          agentService: mockAgent,
          persistenceService: const MockWorkEventPersistenceService(),
        );
        provider.setMode(AppMode.work);
        await tester.pumpWidget(buildTestWidget(provider));

        final taskFuture = provider.startWorkTask('conv_1', 'افتح المتصفح');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final animatedOpacityFinder = find.byType(AnimatedOpacity);
        final opacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
        expect(opacity.opacity, 1.0);
        expect(find.text('Working'), findsOneWidget);

        expect(find.byIcon(Lucide.Monitor), findsOneWidget);
        expect(find.text("Waiting for a screen…"), findsOneWidget);

        if (!mockAgent.completer.isCompleted) mockAgent.completer.complete();
        await provider.cancelWorkTask();
        await taskFuture;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('Thumbnail renders terminal text for shell tool events', (
      tester,
    ) async {
      final shellEvent = WorkToolEvent(
        id: 'tool_sh',
        stepId: 'step_1',
        toolName: 'shell_exec',
        toolCategory: 'shell',
        brief: 'تنفيذ أمر الطرفية',
        arguments: const {'command': 'ls -la'},
        result: 'total 0\ndrwxr-xr-x 2 user user 64 Oct 18 12:00 .',
        status: 'completed',
        timestamp: DateTime.now(),
      );

      final mockAgent = MockManusAgentLoopService(
        events: [
          ManusToolStartedEvent(shellEvent),
          ManusToolFinishedEvent(shellEvent),
        ],
        waitForCompleter: true,
      );
      final provider = WorkSessionProvider(
        agentService: mockAgent,
        persistenceService: const MockWorkEventPersistenceService(),
      );
      provider.setMode(AppMode.work);
      await tester.pumpWidget(buildTestWidget(provider));

      final taskFuture = provider.startWorkTask(
        'conv_1',
        'هل يمكنك فتح المتصفح؟',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Active shell view displayed in thumbnail
      expect(find.text("Build X's computer is inactive"), findsNothing);
      expect(find.text('ubuntu@sandbox:~\$'), findsOneWidget);
      expect(find.text('ls -la'), findsOneWidget);

      if (!mockAgent.completer.isCompleted) mockAgent.completer.complete();
      await provider.cancelWorkTask();
      await taskFuture;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'Card remains visible across multiple tool events and hides only on completion',
      (tester) async {
        final event1 = WorkToolEvent(
          id: 'tool_1',
          stepId: 's1',
          toolName: 'shell_exec',
          toolCategory: 'shell',
          brief: 'echo hello',
          arguments: const {'command': 'echo hello'},
          result: 'hello',
          status: 'completed',
          timestamp: DateTime.now(),
        );

        final event2 = WorkToolEvent(
          id: 'tool_2',
          stepId: 's2',
          toolName: 'browser_navigate',
          toolCategory: 'browser',
          brief: 'navigate to url',
          arguments: const {'url': 'https://example.com'},
          browserUrl: 'https://example.com',
          status: 'completed',
          timestamp: DateTime.now(),
        );

        final result = WorkTaskResult(
          summary: 'Task done',
          attachments: const [],
          completedAt: DateTime.now(),
        );

        final mockAgent = MockManusAgentLoopService(
          events: [
            ManusToolStartedEvent(event1),
            ManusToolFinishedEvent(event1),
            ManusToolStartedEvent(event2),
            ManusToolFinishedEvent(event2),
            ManusTaskCompletedEvent(result),
          ],
        );

        final provider = WorkSessionProvider(
          agentService: mockAgent,
          persistenceService: const MockWorkEventPersistenceService(),
        );
        provider.setMode(AppMode.work);
        await tester.pumpWidget(buildTestWidget(provider));

        await provider.startWorkTask('conv_1', 'multistep task');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // When task completes, card opacity goes to 0
        final animatedOpacityFinder = find.byType(AnimatedOpacity);
        final opacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
        expect(opacity.opacity, 0.0);
        expect(find.text('Working'), findsNothing);

        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
