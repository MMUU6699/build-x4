import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tool Call ID Preservation & Message Order Tests', () {
    test(
      'Feeds real recorded Mistral response and asserts follow-up request contains identical tool call IDs',
      () async {
        final capturedRequests = <Map<String, dynamic>>[];
        int turn = 0;

        // Real recorded Mistral response for "هلا" with tool_calls
        final recordedMistralResponseTurn1 = {
          'id': 'fac95b423d6043279584b38afb816388',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': '',
                'toolCalls': [
                  {
                    'id': 'PGsFuPs59',
                    'type': 'function',
                    'function': {
                      'name': 'message_notify_user',
                      'arguments':
                          '{"message": "Hello! How can I assist you today?"}',
                    },
                    'index': 0,
                  },
                ],
              },
            },
          ],
        };

        final recordedMistralResponseTurn2 = {
          'id': 'turn2_final_completion',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': '',
                'toolCalls': [
                  {
                    'id': 'call_deliver_99',
                    'type': 'function',
                    'function': {
                      'name': 'deliver_result',
                      'arguments': '{"message": "Task completed successfully"}',
                    },
                  },
                ],
              },
            },
          ],
        };

        final agent = ManusAgentLoopService(
          persistenceService: const _NoopPersistence(),
          chatInvoker: (payload) async {
            capturedRequests.add(payload);
            turn++;
            if (turn == 1) {
              return recordedMistralResponseTurn1;
            }
            return recordedMistralResponseTurn2;
          },
        );

        final events = <ManusAgentEvent>[];
        await for (final event in agent.runAgentLoop(
          conversationId: 'test_convo_id_preserve',
          userRequest: 'هلا',
        )) {
          events.add(event);
        }

        // Verify turn 1 was sent and turn 2 followed
        expect(capturedRequests.length, greaterThanOrEqualTo(2));

        // Inspect follow-up request (turn 2)
        final turn2Payload = capturedRequests[1];
        final turn2Messages = (turn2Payload['messages'] as List)
            .cast<Map<String, dynamic>>();

        // Find the tool response message in turn 2
        final toolMessages = turn2Messages
            .where((m) => m['role'] == 'tool')
            .toList();
        expect(toolMessages, isNotEmpty);

        final firstToolMsg = toolMessages.first;
        // MUST carry the exact id of the call it answers
        expect(firstToolMsg['tool_call_id'], equals('PGsFuPs59'));
        expect(firstToolMsg['toolCallId'], equals('PGsFuPs59'));
        expect(firstToolMsg['name'], equals('message_notify_user'));

        // Verify assistant message before tool message also carries matching tool call
        final assistantMsg = turn2Messages.firstWhere(
          (m) => m['role'] == 'assistant',
        );
        final rawCalls =
            (assistantMsg['tool_calls'] ?? assistantMsg['toolCalls']) as List;
        final matchingCall = rawCalls.first as Map<String, dynamic>;
        expect(matchingCall['id'], equals('PGsFuPs59'));
      },
    );

    test(
      'Parallel tool calls: asserts follow-up request preserves exact IDs in matching order',
      () async {
        final capturedRequests = <Map<String, dynamic>>[];
        int turn = 0;

        // Recorded parallel tool calls
        final parallelResponseTurn1 = {
          'id': 'parallel_call_resp',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': '',
                'toolCalls': [
                  {
                    'id': 'call_notify_abc',
                    'type': 'function',
                    'function': {
                      'name': 'message_notify_user',
                      'arguments': '{"message": "Navigating to google"}',
                    },
                    'index': 0,
                  },
                  {
                    'id': 'call_browser_xyz',
                    'type': 'function',
                    'function': {
                      'name': 'browser_click',
                      'arguments': '{"index": 2, "brief": "Click search"}',
                    },
                    'index': 1,
                  },
                ],
              },
            },
          ],
        };

        final finalTurn2 = {
          'id': 'final_done',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': '',
                'toolCalls': [
                  {
                    'id': 'call_deliver_end',
                    'type': 'function',
                    'function': {
                      'name': 'deliver_result',
                      'arguments': '{"message": "All done"}',
                    },
                  },
                ],
              },
            },
          ],
        };

        final agent = ManusAgentLoopService(
          persistenceService: const _NoopPersistence(),
          chatInvoker: (payload) async {
            capturedRequests.add(payload);
            turn++;
            if (turn == 1) return parallelResponseTurn1;
            return finalTurn2;
          },
        );

        final events = <ManusAgentEvent>[];
        await for (final event in agent.runAgentLoop(
          conversationId: 'test_parallel_calls',
          userRequest: 'افتح وابحث',
        )) {
          events.add(event);
        }

        expect(capturedRequests.length, greaterThanOrEqualTo(2));
        final turn2Payload = capturedRequests[1];
        final turn2Messages = (turn2Payload['messages'] as List)
            .cast<Map<String, dynamic>>();

        final toolMessages = turn2Messages
            .where((m) => m['role'] == 'tool')
            .toList();
        expect(toolMessages.length, equals(2));

        // Result order MUST match call order, with matching IDs
        expect(toolMessages[0]['tool_call_id'], equals('call_notify_abc'));
        expect(toolMessages[0]['toolCallId'], equals('call_notify_abc'));
        expect(toolMessages[0]['name'], equals('message_notify_user'));

        expect(toolMessages[1]['tool_call_id'], equals('call_browser_xyz'));
        expect(toolMessages[1]['toolCallId'], equals('call_browser_xyz'));
        expect(toolMessages[1]['name'], equals('browser_click'));
      },
    );

    test(
      'Model returns tool call without an ID: fails with clear error and aborts follow-up request',
      () async {
        final capturedRequests = <Map<String, dynamic>>[];

        final missingIdResponse = {
          'id': 'bad_call_resp',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': '',
                'toolCalls': [
                  {
                    'id': null, // Missing ID
                    'type': 'function',
                    'function': {
                      'name': 'message_notify_user',
                      'arguments': '{"message": "Hello"}',
                    },
                  },
                ],
              },
            },
          ],
        };

        final agent = ManusAgentLoopService(
          persistenceService: const _NoopPersistence(),
          chatInvoker: (payload) async {
            capturedRequests.add(payload);
            return missingIdResponse;
          },
        );

        final events = <ManusAgentEvent>[];
        await for (final event in agent.runAgentLoop(
          conversationId: 'test_missing_id',
          userRequest: 'هلا',
        )) {
          events.add(event);
        }

        // Must yield a clear error event
        expect(events.any((e) => e is ManusErrorEvent), isTrue);
        final err =
            events.firstWhere((e) => e is ManusErrorEvent) as ManusErrorEvent;
        expect(err.error, contains('without an ID'));

        // Never sends a follow-up request with missing/null IDs
        expect(capturedRequests.length, equals(1));
      },
    );
  });
}
