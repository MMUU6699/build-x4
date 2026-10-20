import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/workspace/daytona_workspace_runtime.dart';
import 'package:Kelivo/core/services/workspace/work_event_persistence_service.dart';
import 'package:Kelivo/features/work/services/manus_agent_loop_service.dart';

class _NoopPersistence extends WorkEventPersistenceService {
  const _NoopPersistence();

  @override
  Future<List<Map<String, dynamic>>> loadAgentHistory(
    String conversationId,
  ) async => [];

  @override
  Future<void> saveAgentHistory(
    String conversationId,
    List<Map<String, dynamic>> messages,
  ) async {}
}

class _RecordingRuntime extends DaytonaWorkspaceRuntime {
  int invocations = 0;

  @override
  Future<Map<String, dynamic>> invokeDaytona({
    required String action,
    Map<String, dynamic>? params,
    String? sandboxId,
  }) async {
    invocations++;
    return const {};
  }
}

Map<String, dynamic> _invalidToolCall(String id) {
  return {
    'choices': [
      {
        'message': {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': id,
              'type': 'function',
              'function': {'name': 'shell_exec', 'arguments': '{}'},
            },
          ],
        },
      },
    ],
  };
}

void main() {
  test(
    'invalid arguments never execute a tool and stop after three strikes',
    () async {
      final runtime = _RecordingRuntime();
      var calls = 0;
      final agent = ManusAgentLoopService(
        runtime: runtime,
        persistenceService: const _NoopPersistence(),
        chatInvoker: (_) async {
          calls++;
          return _invalidToolCall('call_$calls');
        },
      );

      final events = <ManusAgentEvent>[];
      await for (final event in agent.runAgentLoop(
        conversationId: 'conv_invalid',
        userRequest: 'run',
      )) {
        events.add(event);
      }

      expect(calls, 3);
      expect(runtime.invocations, 0);

      final failed = events.whereType<ManusToolFinishedEvent>().toList();
      expect(failed, hasLength(3));
      expect(
        failed.every((event) => event.toolEvent.status == 'failed'),
        isTrue,
      );
      expect(
        failed.first.toolEvent.result,
        contains('Missing required argument'),
      );

      final error = events.whereType<ManusErrorEvent>().single;
      expect(error.error, contains('3 times in a row'));
    },
  );

  test('a missing cosmetic brief does not abort a valid tool call', () async {
    final runtime = _RecordingRuntime();
    var calls = 0;
    final agent = ManusAgentLoopService(
      runtime: runtime,
      persistenceService: const _NoopPersistence(),
      chatInvoker: (_) async {
        calls++;
        if (calls == 1) {
          return {
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'call_shell',
                      'type': 'function',
                      'function': {
                        'name': 'shell_exec',
                        'arguments': '{"command": "echo hi"}',
                      },
                    },
                  ],
                },
              },
            ],
          };
        }
        return {
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'call_done',
                    'type': 'function',
                    'function': {
                      'name': 'deliver_result',
                      'arguments': '{"message": "done"}',
                    },
                  },
                ],
              },
            },
          ],
        };
      },
    );

    final events = <ManusAgentEvent>[];
    await for (final event in agent.runAgentLoop(
      conversationId: 'conv_missing_brief',
      userRequest: 'run',
    )) {
      events.add(event);
    }

    expect(runtime.invocations, 1);
    expect(events.whereType<ManusErrorEvent>(), isEmpty);
    final finished = events.whereType<ManusToolFinishedEvent>().first;
    expect(finished.toolEvent.toolName, 'shell_exec');
    expect(finished.toolEvent.status, 'completed');
    expect(finished.toolEvent.brief, isNotEmpty);
  });
}
