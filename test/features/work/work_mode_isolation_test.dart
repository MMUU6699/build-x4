import 'dart:async';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/services/workspace/work_event_persistence_service.dart';
import 'package:Kelivo/features/work/models/work_turn.dart';
import 'package:Kelivo/features/work/providers/work_session_provider.dart';
import 'package:Kelivo/features/work/services/manus_agent_loop_service.dart';

class _IsolatedPersistence extends WorkEventPersistenceService {
  const _IsolatedPersistence();

  @override
  Future<List<WorkTurn>> fetchWorkTurns(String conversationId) async => [];

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
  Future<String?> createScreenshotUrl(String path) async => null;
}

class _FailingAgent extends ManusAgentLoopService {
  @override
  Future<Map<String, dynamic>> checkComputerHealth() async => {
    'status': 'disconnected',
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
    yield const ManusErrorEvent('Could not start the computer: offline');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Work Mode Isolation & Conversation Tests', () {
    test('Conversation correctly determines mode and flags', () {
      final chatConv = Conversation(
        id: 'c1',
        title: 'Chat Convo',
        extras: const {'mode': 'chat'},
      );
      expect(chatConv.mode, equals('chat'));
      expect(chatConv.isChat, isTrue);
      expect(chatConv.isWork, isFalse);

      final workConv = Conversation(
        id: 'w1',
        title: 'Work Convo',
        extras: const {'mode': 'work'},
      );
      expect(workConv.mode, equals('work'));
      expect(workConv.isWork, isTrue);
      expect(workConv.isChat, isFalse);

      final defaultConv = Conversation(id: 'd1', title: 'Default Convo');
      expect(defaultConv.mode, equals('chat'));
      expect(defaultConv.isChat, isTrue);
      expect(defaultConv.isWork, isFalse);
    });

    test('WorkSessionProvider reports a real bootstrap failure', () async {
      final agentService = _FailingAgent();
      final provider = WorkSessionProvider(
        agentService: agentService,
        persistenceService: const _IsolatedPersistence(),
      );

      expect(provider.phase, equals(WorkSessionPhase.idle));
      expect(provider.isWorkMode, isFalse);

      provider.setMode(AppMode.work);
      expect(provider.isWorkMode, isTrue);
      expect(provider.mode, equals(AppMode.work));

      await provider.startWorkTask('w_conv_1', 'افتح المتصفح');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(provider.phase, equals(WorkSessionPhase.error));
      expect(provider.errorMessage, contains('offline'));
    });

    test('Mode switching isolates active state cleanly', () {
      final provider = WorkSessionProvider(
        agentService: _FailingAgent(),
        persistenceService: const _IsolatedPersistence(),
      );
      expect(provider.isWorkMode, isFalse);

      provider.setMode(AppMode.work);
      expect(provider.isWorkMode, isTrue);

      provider.setMode(AppMode.chat);
      expect(provider.isWorkMode, isFalse);
    });
  });
}
