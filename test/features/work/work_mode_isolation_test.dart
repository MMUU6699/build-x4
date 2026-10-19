import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/features/work/providers/work_session_provider.dart';
import 'package:Kelivo/features/work/services/manus_agent_loop_service.dart';
import 'package:Kelivo/core/services/workspace/daytona_workspace_runtime.dart';

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

    test(
      'WorkSessionProvider transitions through phases on startWorkTask',
      () async {
        final runtime = DaytonaWorkspaceRuntime();
        final agentService = ManusAgentLoopService(runtime: runtime);
        final provider = WorkSessionProvider(agentService: agentService);

        expect(provider.phase, equals(WorkSessionPhase.idle));
        expect(provider.isWorkMode, isFalse);

        provider.setMode(AppMode.work);
        expect(provider.isWorkMode, isTrue);
        expect(provider.mode, equals(AppMode.work));

        final completer = Completer<void>();
        void listener() {
          if (provider.phase == WorkSessionPhase.completed ||
              provider.phase == WorkSessionPhase.error) {
            if (!completer.isCompleted) completer.complete();
          }
        }

        provider.addListener(listener);

        await provider.startWorkTask('w_conv_1', 'افتح المتصفح');
        expect(provider.phase, equals(WorkSessionPhase.running));
        expect(provider.isAgentRunning, isTrue);

        await completer.future.timeout(const Duration(seconds: 5));
        provider.removeListener(listener);

        // In unit test environment without mock, agent loop fails honestly with real error
        expect(provider.phase, equals(WorkSessionPhase.error));
        expect(provider.errorMessage, isNotNull);
      },
    );

    test('Mode switching isolates active state cleanly', () {
      final provider = WorkSessionProvider();
      expect(provider.isWorkMode, isFalse);

      provider.setMode(AppMode.work);
      expect(provider.isWorkMode, isTrue);

      provider.setMode(AppMode.chat);
      expect(provider.isWorkMode, isFalse);
    });
  });
}
