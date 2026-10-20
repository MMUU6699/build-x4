import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/work/services/manus_agent_loop_service.dart';
import 'package:Kelivo/core/services/workspace/daytona_workspace_runtime.dart';
import 'package:Kelivo/core/services/workspace/work_event_persistence_service.dart';

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

  group('Browser Agent Execution Tests (No Simulation / Honest Error Verification)', () {
    late DaytonaWorkspaceRuntime runtime;
    late ManusAgentLoopService agentService;

    setUp(() {
      runtime = DaytonaWorkspaceRuntime();
      agentService = ManusAgentLoopService(runtime: runtime);
    });

    test(
      'User command "افتح المتصفح" fails honestly without canned fake simulation',
      () async {
        final events = <ManusAgentEvent>[];
        final stream = agentService.runAgentLoop(
          conversationId: 'test_conv_browser_1',
          userRequest: 'افتح المتصفح',
        );

        await for (final event in stream) {
          events.add(event);
        }

        // In offline unit test environment, agent loop MUST fail honestly with ManusErrorEvent
        expect(events.any((e) => e is ManusErrorEvent), isTrue);
        // Verify NO canned fake completion summary exists
        expect(
          events.any(
            (e) =>
                e is ManusTaskCompletedEvent &&
                e.result.summary.contains('تم فتح المتصفح بنجاح'),
          ),
          isFalse,
        );
      },
    );

    test(
      'User question "هل يمكنك فتح المتصفح؟" fails honestly without canned fake simulation',
      () async {
        final events = <ManusAgentEvent>[];
        final stream = agentService.runAgentLoop(
          conversationId: 'test_conv_browser_2',
          userRequest: 'هل يمكنك فتح المتصفح؟',
        );

        await for (final event in stream) {
          events.add(event);
        }

        expect(events.any((e) => e is ManusErrorEvent), isTrue);
        expect(
          events.any(
            (e) =>
                e is ManusTaskCompletedEvent &&
                e.result.summary.contains('تم فتح المتصفح بنجاح'),
          ),
          isFalse,
        );
      },
    );

    test(
      'User command with URL "افتح المتصفح على https://flutter.dev" fails honestly without canned fake simulation',
      () async {
        final events = <ManusAgentEvent>[];
        final stream = agentService.runAgentLoop(
          conversationId: 'test_conv_browser_3',
          userRequest: 'افتح المتصفح على https://flutter.dev',
        );

        await for (final event in stream) {
          events.add(event);
        }

        expect(events.any((e) => e is ManusErrorEvent), isTrue);
        expect(
          events.any(
            (e) =>
                e is ManusTaskCompletedEvent &&
                e.result.summary.contains('تم فتح المتصفح بنجاح'),
          ),
          isFalse,
        );
      },
    );

    test(
      'DaytonaWorkspaceRuntime navigateBrowser throws honest exception when network is unreachable',
      () async {
        expect(
          () => runtime.navigateBrowser('https://www.google.com'),
          throwsA(anything),
        );
      },
    );

    test(
      'Real browser tools return real CDP page title, elements, and screenshot without simulation',
      () async {
        final mockRuntime = _MockDaytonaRuntime();
        int turn = 0;
        final agent = ManusAgentLoopService(
          runtime: mockRuntime,
          persistenceService: const _NoopPersistence(),
          chatInvoker: (body) async {
            turn++;
            if (turn == 1) {
              return {
                'choices': [
                  {
                    'message': {
                      'role': 'assistant',
                      'content': null,
                      'tool_calls': [
                        {
                          'id': 'call_nav_1',
                          'type': 'function',
                          'function': {
                            'name': 'browser_navigate',
                            'arguments':
                                '{"url": "https://claude.ai", "brief": "فتح موقع Claude"}',
                          },
                        },
                      ],
                    },
                  },
                ],
              };
            } else if (turn == 2) {
              return {
                'choices': [
                  {
                    'message': {
                      'role': 'assistant',
                      'content': null,
                      'tool_calls': [
                        {
                          'id': 'call_click_1',
                          'type': 'function',
                          'function': {
                            'name': 'browser_click',
                            'arguments':
                                '{"index": 0, "brief": "نقر زر تسجيل الدخول"}',
                          },
                        },
                        {
                          'id': 'call_input_1',
                          'type': 'function',
                          'function': {
                            'name': 'browser_input',
                            'arguments':
                                '{"index": 0, "text": "user@example.com", "brief": "كتابة البريد"}',
                          },
                        },
                      ],
                    },
                  },
                ],
              };
            } else {
              return {
                'choices': [
                  {
                    'message': {
                      'role': 'assistant',
                      'content': null,
                      'tool_calls': [
                        {
                          'id': 'call_deliver_1',
                          'type': 'function',
                          'function': {
                            'name': 'deliver_result',
                            'arguments':
                                '{"message": "تم إدخال البيانات في الموقع", "attachments": []}',
                          },
                        },
                      ],
                    },
                  },
                ],
              };
            }
          },
        );

        final events = <ManusAgentEvent>[];
        await for (final ev in agent.runAgentLoop(
          conversationId: 'test_cdp_conv',
          userRequest: 'افتح Claude وسجل الدخول',
        )) {
          events.add(ev);
        }

        // Verify started events
        final startedTools = events
            .whereType<ManusToolStartedEvent>()
            .map((e) => e.toolEvent.toolName)
            .toList();
        expect(startedTools, contains('browser_navigate'));
        expect(startedTools, contains('browser_click'));
        expect(startedTools, contains('browser_input'));
        // Meta tool deliver_result must NOT emit tool started
        expect(startedTools.contains('deliver_result'), isFalse);

        // Verify finished events
        final finishedTools = events
            .whereType<ManusToolFinishedEvent>()
            .toList();
        final navFinished = finishedTools.firstWhere(
          (e) => e.toolEvent.toolName == 'browser_navigate',
        );
        expect(
          navFinished.toolEvent.screenshotUrl,
          equals('https://storage.example.com/screenshot1.png'),
        );
        expect(navFinished.toolEvent.browserUrl, equals('https://claude.ai'));
        expect(navFinished.toolEvent.result, contains('Claude'));
        expect(navFinished.toolEvent.result, contains('[0] <button> "Login"'));

        final clickFinished = finishedTools.firstWhere(
          (e) => e.toolEvent.toolName == 'browser_click',
        );
        expect(
          clickFinished.toolEvent.result,
          isNot(equals('Element clicked')),
        );
        expect(clickFinished.toolEvent.result, contains('Claude Login'));

        final inputFinished = finishedTools.firstWhere(
          (e) => e.toolEvent.toolName == 'browser_input',
        );
        expect(inputFinished.toolEvent.result, isNot(equals('Text entered')));
        expect(inputFinished.toolEvent.result, contains('user@example.com'));

        // Verify task completion
        expect(events.any((e) => e is ManusTaskCompletedEvent), isTrue);
      },
    );

    test(
      'Meta tools and message_ask_user are cleanly handled and pause the loop',
      () async {
        final mockRuntime = _MockDaytonaRuntime();
        final agent = ManusAgentLoopService(
          runtime: mockRuntime,
          persistenceService: const _NoopPersistence(),
          chatInvoker: (body) async {
            return {
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'call_notify_1',
                        'type': 'function',
                        'function': {
                          'name': 'message_notify_user',
                          'arguments': '{"message": "جاري فحص الحساب"}',
                        },
                      },
                      {
                        'id': 'call_ask_1',
                        'type': 'function',
                        'function': {
                          'name': 'message_ask_user',
                          'arguments': '{"question": "ما هو رمز التحقق؟"}',
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
        await for (final ev in agent.runAgentLoop(
          conversationId: 'test_ask_conv',
          userRequest: 'سجل دخولي',
        )) {
          events.add(ev);
        }

        // Neither message_notify_user nor message_ask_user emits ManusToolStartedEvent or ManusToolFinishedEvent
        expect(events.whereType<ManusToolStartedEvent>(), isEmpty);
        expect(events.whereType<ManusToolFinishedEvent>(), isEmpty);

        // Verify notification event
        expect(
          events.any(
            (e) =>
                e is ManusMessageNotifyEvent && e.message == 'جاري فحص الحساب',
          ),
          isTrue,
        );

        // Verify message ask event
        final askEvents = events.whereType<ManusMessageAskEvent>().toList();
        expect(askEvents, hasLength(1));
        expect(askEvents.first.question, equals('ما هو رمز التحقق؟'));
        expect(askEvents.first.toolCallId, equals('call_ask_1'));
      },
    );
  });
}

class _MockDaytonaRuntime extends DaytonaWorkspaceRuntime {
  @override
  Future<Map<String, dynamic>> navigateBrowser(
    String url, {
    String? sandboxId,
  }) async {
    return {
      'url': url,
      'title': 'Claude',
      'interactive_elements': ['[0] <button> "Login"', '[1] <input>'],
      'screenshot_url': 'https://storage.example.com/screenshot1.png',
    };
  }

  @override
  Future<Map<String, dynamic>> browserClick({
    int? index,
    int? x,
    int? y,
    String? sandboxId,
  }) async {
    return {
      'url': 'https://claude.ai/login',
      'title': 'Claude Login',
      'interactive_elements': [
        '[0] <input type="email">',
        '[1] <button> "Next"',
      ],
      'screenshot_url': 'https://storage.example.com/screenshot2.png',
    };
  }

  @override
  Future<Map<String, dynamic>> browserInput({
    int? index,
    required String text,
    bool pressEnter = false,
    String? sandboxId,
  }) async {
    return {
      'url': 'https://claude.ai/login',
      'title': 'Claude Login',
      'interactive_elements': [
        '[0] <input type="email"> "$text"',
        '[1] <button> "Next"',
      ],
      'screenshot_url': 'https://storage.example.com/screenshot3.png',
    };
  }

  @override
  Future<Map<String, dynamic>> browserView({String? sandboxId}) async {
    return {
      'url': 'https://claude.ai',
      'title': 'Claude',
      'interactive_elements': ['[0] <button> "Login"'],
      'screenshot_url': 'https://storage.example.com/screenshot1.png',
    };
  }
}
