import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/workspace/work_event_persistence_service.dart';
import 'package:Kelivo/features/work/services/manus_agent_loop_service.dart';

class _RecordingPersistence extends WorkEventPersistenceService {
  const _RecordingPersistence();

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

Map<String, dynamic> _deliverResult() => {
  'choices': [
    {
      'message': {
        'role': 'assistant',
        'content': '',
        'toolCalls': [
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

Future<List<Map<String, dynamic>>> _captureRequestMessages(
  List<Map<String, dynamic>> existingMessages,
  String prompt,
) async {
  final captured = <Map<String, dynamic>>[];
  final agent = ManusAgentLoopService(
    persistenceService: const _RecordingPersistence(),
    chatInvoker: (payload) async {
      captured.add(payload);
      return _deliverResult();
    },
  );

  await for (final _ in agent.runAgentLoop(
    conversationId: 'history_cap_test',
    userRequest: prompt,
    existingMessages: existingMessages,
  )) {}

  expect(captured, hasLength(1));
  return (captured.single['messages'] as List).cast<Map<String, dynamic>>();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Work agent history window', () {
    test(
      'drops the oldest complete turns instead of sending unbounded history',
      () async {
        final existing = <Map<String, dynamic>>[];
        for (var i = 0; i < 40; i++) {
          existing.add({'role': 'user', 'content': 'u$i ${'x' * 3000}'});
          existing.add({'role': 'assistant', 'content': 'a$i ${'y' * 3000}'});
        }

        final messages = await _captureRequestMessages(
          existing,
          'the newest question',
        );
        final conversation = messages
            .where((m) => m['role'] != 'system')
            .toList();

        expect(conversation.first['role'], 'user');
        expect(conversation.last['content'], 'the newest question');
        final chars = conversation.fold<int>(
          0,
          (sum, message) => sum + jsonEncode(message).length,
        );
        expect(
          chars,
          lessThanOrEqualTo(ManusAgentLoopService.maxRequestHistoryChars),
        );
        expect(
          conversation.any(
            (m) => m['content']?.toString().startsWith('u0 ') ?? false,
          ),
          isFalse,
        );
      },
    );

    test(
      'never sends a tool result without the assistant call it answers',
      () async {
        final existing = <Map<String, dynamic>>[];
        for (var i = 0; i < 30; i++) {
          final callId = 'call_$i';
          existing.add({'role': 'user', 'content': 'task $i'});
          existing.add({
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': callId,
                'type': 'function',
                'function': {
                  'name': 'exec_command',
                  'arguments': '{"command": "echo $i"}',
                },
              },
            ],
          });
          existing.add({
            'role': 'tool',
            'tool_call_id': callId,
            'toolCallId': callId,
            'name': 'exec_command',
            'content': 'r$i ${'z' * 4000}',
          });
        }

        final messages = await _captureRequestMessages(existing, 'next task');
        final conversation = messages
            .where((m) => m['role'] != 'system')
            .toList();

        expect(conversation.first['role'], 'user');
        final toolIds = conversation
            .where((m) => m['role'] == 'tool')
            .map((m) => (m['tool_call_id'] ?? m['toolCallId']).toString())
            .toSet();
        for (final message in conversation.where(
          (m) => m['role'] == 'assistant',
        )) {
          final calls = message['tool_calls'] as List<dynamic>?;
          if (calls == null) continue;
          for (final call in calls.cast<Map<String, dynamic>>()) {
            expect(toolIds, contains(call['id'].toString()));
          }
        }
      },
    );
  });
}
