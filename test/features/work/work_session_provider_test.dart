import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/workspace/work_event_persistence_service.dart';
import 'package:Kelivo/features/work/models/work_task_result.dart';
import 'package:Kelivo/features/work/models/work_tool_event.dart';
import 'package:Kelivo/features/work/models/work_turn.dart';
import 'package:Kelivo/features/work/providers/work_session_provider.dart';
import 'package:Kelivo/features/work/services/manus_agent_loop_service.dart';

class _FakePersistence extends WorkEventPersistenceService {
  const _FakePersistence();

  @override
  Future<List<WorkTurn>> fetchWorkTurns(String conversationId) async =>
      const [];

  @override
  Future<void> saveWorkTurn(WorkTurn turn) async {}

  @override
  Future<void> updateWorkSession({
    required String conversationId,
    String? workspaceId,
    required String phase,
    DateTime? startedAt,
    DateTime? endedAt,
  }) async {}

  @override
  Future<String?> createScreenshotUrl(String path) async =>
      'https://signed.example/$path';
}

class _ScriptedAgent extends ManusAgentLoopService {
  _ScriptedAgent(this.script);

  final Stream<ManusAgentEvent> Function(String request) script;
  final List<String?> pendingToolCallIds = [];

  @override
  Stream<ManusAgentEvent> runAgentLoop({
    required String conversationId,
    required String userRequest,
    int maxIterations = ManusAgentLoopService.defaultMaxIterations,
    CancelToken? cancelToken,
    List<Map<String, dynamic>>? existingMessages,
    String? pendingToolCallId,
  }) {
    pendingToolCallIds.add(pendingToolCallId);
    return script(userRequest);
  }
}

WorkToolEvent _browserEvent({
  String id = 'call_1',
  String? screenshotPath,
  String? screenshotUrl,
}) {
  return WorkToolEvent(
    id: id,
    stepId: 'step_1',
    toolName: 'browser_navigate',
    toolCategory: 'browser',
    brief: 'فتح الصفحة',
    arguments: const {'url': 'https://example.com'},
    browserUrl: 'https://example.com',
    screenshotPath: screenshotPath,
    screenshotUrl: screenshotUrl,
    status: 'completed',
    timestamp: DateTime.now(),
  );
}

void main() {
  group('WorkSessionProvider turns', () {
    test('initial state is idle with no turns', () {
      final provider = WorkSessionProvider(
        agentService: _ScriptedAgent((_) => const Stream.empty()),
        persistenceService: const _FakePersistence(),
      );
      expect(provider.phase, WorkSessionPhase.idle);
      expect(provider.turns, isEmpty);
      expect(provider.isAgentRunning, isFalse);
    });

    test(
      'a completed task keeps one turn with real events and answer',
      () async {
        final event = _browserEvent(
          screenshotPath: 'user/conv/call_1.png',
          screenshotUrl: 'data:image/png;base64,AAAA',
        );
        final agent = _ScriptedAgent(
          (_) => Stream.fromIterable([
            const ManusMessageNotifyEvent('سأفتح الصفحة'),
            ManusToolStartedEvent(event),
            ManusToolFinishedEvent(event),
            ManusTaskCompletedEvent(
              WorkTaskResult(
                summary: 'تم فتح الصفحة.',
                completedAt: DateTime.now(),
              ),
            ),
          ]),
        );
        final provider = WorkSessionProvider(
          agentService: agent,
          persistenceService: const _FakePersistence(),
        );

        await provider.startWorkTask('conv_1', 'افتح example.com');
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(provider.phase, WorkSessionPhase.completed);
        expect(provider.turns, hasLength(1));
        final turn = provider.currentTurn!;
        expect(turn.prompt, 'افتح example.com');
        expect(turn.introMessage, 'سأفتح الصفحة');
        expect(turn.events, hasLength(1));
        expect(turn.events.single.browserUrl, 'https://example.com');
        expect(turn.finalAnswer, 'تم فتح الصفحة.');
        expect(turn.durationSeconds, greaterThanOrEqualTo(1));
        expect(turn.status, 'completed');
        expect(
          provider.screenshotUrlFor(turn.events.single),
          'data:image/png;base64,AAAA',
        );
      },
    );

    test(
      'a second prompt appends a turn and never replaces the first',
      () async {
        var call = 0;
        final agent = _ScriptedAgent((_) {
          call++;
          return Stream.fromIterable([
            ManusTaskCompletedEvent(
              WorkTaskResult(
                summary: 'answer $call',
                completedAt: DateTime.now(),
              ),
            ),
          ]);
        });
        final provider = WorkSessionProvider(
          agentService: agent,
          persistenceService: const _FakePersistence(),
        );

        await provider.startWorkTask('conv_1', 'first');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await provider.startWorkTask('conv_1', 'second');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(provider.turns, hasLength(2));
        expect(provider.turns.first.prompt, 'first');
        expect(provider.turns.first.finalAnswer, 'answer 1');
        expect(provider.turns.last.prompt, 'second');
        expect(provider.turns.last.finalAnswer, 'answer 2');
      },
    );

    test(
      'waiting persists the question and resumes with the tool call id',
      () async {
        final agent = _ScriptedAgent((request) {
          if (request == 'yes') {
            return Stream.fromIterable([
              ManusTaskCompletedEvent(
                WorkTaskResult(summary: 'done', completedAt: DateTime.now()),
              ),
            ]);
          }
          return Stream.fromIterable([
            const ManusMessageAskEvent('Which account?', 'ask_1'),
          ]);
        });
        final provider = WorkSessionProvider(
          agentService: agent,
          persistenceService: const _FakePersistence(),
        );

        await provider.startWorkTask('conv_1', 'sign in');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(provider.phase, WorkSessionPhase.waiting);
        expect(provider.currentTurn!.question, 'Which account?');
        expect(provider.pendingToolCallId, 'ask_1');

        await provider.resumeWorkTaskWithUserAnswer('yes');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(agent.pendingToolCallIds.last, 'ask_1');
        expect(provider.turns, hasLength(1));
        expect(provider.turns.single.status, 'completed');
        expect(provider.turns.single.finalAnswer, 'done');
      },
    );

    test(
      'a stream that ends without deliver_result becomes an error',
      () async {
        final agent = _ScriptedAgent(
          (_) => Stream.fromIterable([
            ManusToolStartedEvent(_browserEvent()),
            ManusToolFinishedEvent(_browserEvent()),
          ]),
        );
        final provider = WorkSessionProvider(
          agentService: agent,
          persistenceService: const _FakePersistence(),
        );

        await provider.startWorkTask('conv_1', 'do it');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(provider.phase, WorkSessionPhase.error);
        expect(provider.currentTurn!.status, 'error');
        expect(provider.errorMessage, contains('without a final result'));
      },
    );

    test('cancel marks the turn stopped and leaves idle phase', () async {
      final controller = StreamController<ManusAgentEvent>();
      final agent = _ScriptedAgent((_) => controller.stream);
      final provider = WorkSessionProvider(
        agentService: agent,
        persistenceService: const _FakePersistence(),
      );

      await provider.startWorkTask('conv_1', 'long task');
      await provider.cancelWorkTask();

      expect(provider.phase, WorkSessionPhase.idle);
      expect(provider.currentTurn!.status, 'stopped');
      expect(provider.currentTurn!.error, 'Stopped by you.');
      await controller.close();
    });

    test('signed screenshot URLs are resolved for persisted paths', () async {
      final event = _browserEvent(
        screenshotPath: 'user/conv/call_1.png',
        screenshotUrl: null,
      );
      final agent = _ScriptedAgent(
        (_) => Stream.fromIterable([
          ManusToolStartedEvent(event),
          ManusToolFinishedEvent(event),
        ]),
      );
      final provider = WorkSessionProvider(
        agentService: agent,
        persistenceService: const _FakePersistence(),
      );

      await provider.startWorkTask('conv_1', 'look');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        provider.screenshotUrlFor(provider.currentTurn!.events.single),
        'https://signed.example/user/conv/call_1.png',
      );
    });

    test('computer opens on the selected turn and event', () async {
      final event = _browserEvent();
      final agent = _ScriptedAgent(
        (_) => Stream.fromIterable([
          ManusToolStartedEvent(event),
          ManusToolFinishedEvent(event),
        ]),
      );
      final provider = WorkSessionProvider(
        agentService: agent,
        persistenceService: const _FakePersistence(),
      );
      await provider.startWorkTask('conv_1', 'look');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final turn = provider.currentTurn!;
      provider.openComputer(turnId: turn.id, eventId: event.id);
      expect(provider.isComputerOpen, isTrue);
      expect(provider.computerTurn!.id, turn.id);
      expect(provider.computerEvent!.id, event.id);

      provider.closeComputer();
      expect(provider.isComputerOpen, isFalse);
    });
  });
}
