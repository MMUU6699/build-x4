import 'dart:async';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/work/models/work_plan.dart';
import 'package:Kelivo/features/work/models/work_task_result.dart';
import 'package:Kelivo/features/work/models/work_tool_event.dart';
import 'package:Kelivo/features/work/providers/work_session_provider.dart';
import 'package:Kelivo/features/work/services/manus_agent_loop_service.dart';

class MockManusAgentLoopService extends ManusAgentLoopService {
  MockManusAgentLoopService({this.eventsToEmit = const []});

  final List<ManusAgentEvent> eventsToEmit;

  @override
  Stream<ManusAgentEvent> runAgentLoop({
    required String conversationId,
    required String userRequest,
    WorkPlan? initialPlan,
    int maxIterations = 25,
    CancelToken? cancelToken,
    List<Map<String, dynamic>>? existingMessages,
    String? pendingToolCallId,
  }) async* {
    for (final event in eventsToEmit) {
      yield event;
    }
  }
}

void main() {
  group('WorkSessionPhase State Machine & Card Visibility Tests', () {
    late WorkSessionProvider provider;

    setUp(() {
      provider = WorkSessionProvider();
    });

    test('Initial phase is idle and card should not be visible', () {
      expect(provider.phase, WorkSessionPhase.idle);
      expect(provider.isBusy, isFalse);
      expect(provider.isAgentRunning, isFalse);
      expect(provider.showThinking, isFalse);
    });

    test(
      'Phase transitions to running when task starts (Card Visible)',
      () async {
        final taskFuture = provider.startWorkTask(
          'conv_123',
          'افتح المتصفح الخاص بك على Google Chrome',
        );
        expect(provider.phase, WorkSessionPhase.running);
        expect(provider.isBusy, isTrue);
        expect(provider.isAgentRunning, isTrue);
        await provider.cancelWorkTask();
        await taskFuture;
      },
    );

    test(
      'showThinking rule: true when running and no tool is calling',
      () async {
        final taskFuture = provider.startWorkTask('conv_123', 'test task');
        expect(provider.phase, WorkSessionPhase.running);
        expect(provider.showThinking, isTrue);
        await provider.cancelWorkTask();
        await taskFuture;
      },
    );

    test(
      'Phase transitions to idle when task is cancelled (Card Disappears)',
      () async {
        final taskFuture = provider.startWorkTask('conv_123', 'test task');
        expect(provider.phase, WorkSessionPhase.running);

        await provider.cancelWorkTask();
        expect(provider.phase, WorkSessionPhase.idle);
        expect(provider.isBusy, isFalse);
        await taskFuture;
      },
    );
  });

  group('Timeline Scrubber & Computer Sheet Navigation Tests', () {
    test(
      'Timeline events update live, scrubbing and jump to live behave correctly',
      () async {
        final event1 = WorkToolEvent(
          id: 'tool_1',
          stepId: 'step_1',
          toolName: 'browser_navigate',
          toolCategory: 'browser',
          brief: 'فتح صفحة Google في المتصفح',
          arguments: const {'url': 'https://www.google.com'},
          screenshotUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==',
          status: 'completed',
          timestamp: DateTime.now(),
        );

        final event2 = WorkToolEvent(
          id: 'tool_2',
          stepId: 'step_2',
          toolName: 'browser_view',
          toolCategory: 'browser',
          brief: 'التقاط لقطة شاشة للصفحة',
          screenshotUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA',
          status: 'completed',
          timestamp: DateTime.now(),
        );

        final mockAgent = MockManusAgentLoopService(
          eventsToEmit: [
            ManusToolStartedEvent(event1),
            ManusToolFinishedEvent(event1),
            ManusToolStartedEvent(event2),
            ManusToolFinishedEvent(event2),
          ],
        );

        final provider = WorkSessionProvider(agentService: mockAgent);

        // Initially empty
        expect(provider.timelineEvents.isEmpty, isTrue);
        expect(provider.isLive, isTrue);

        await provider.startWorkTask('conv_test', 'test task');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(provider.timelineEvents.length, 2);
        expect(provider.currentEvent?.id, 'tool_2');

        // Scrub to first event
        provider.scrubTo(0);
        expect(provider.scrubbedIndex, 0);
        expect(provider.isLive, isFalse);
        expect(provider.currentEvent?.id, 'tool_1');

        // Jump to live
        provider.jumpToLive();
        expect(provider.isLive, isTrue);
        expect(provider.currentEvent?.id, 'tool_2');

        // Computer open / close
        provider.openComputer(eventIndex: 0);
        expect(provider.isComputerOpen, isTrue);
        expect(provider.scrubbedIndex, 0);

        provider.closeComputer();
        expect(provider.isComputerOpen, isFalse);
      },
    );
  });

  group('End-to-End Acceptance Test: Arabic Browser Navigation Task', () {
    test(
      'Executes Arabic task: notification, browser tool with screenshot, and completion',
      () async {
        final toolEvent = WorkToolEvent(
          id: 'call_google_nav',
          stepId: 'step_1',
          toolName: 'browser_navigate',
          toolCategory: 'browser',
          brief: 'فتح صفحة Google في المتصفح',
          arguments: const {'url': 'https://www.google.com'},
          browserUrl: 'https://www.google.com',
          screenshotUrl:
              'https://image.thum.io/get/width/1280/crop/800/https://www.google.com',
          status: 'completed',
          timestamp: DateTime.now(),
        );

        final deliverable = WorkTaskResult(
          summary: 'تم فتح متصفح Google Chrome بنجاح وعرض الصفحة الرئيسية.',
          attachments: const [],
          completedAt: DateTime.now(),
        );

        final mockAgent = MockManusAgentLoopService(
          eventsToEmit: [
            const ManusMessageNotifyEvent(
              'سأقوم الآن بفتح متصفح Google Chrome والانتقال إلى الصفحة الرئيسية.',
            ),
            ManusToolStartedEvent(toolEvent),
            ManusToolFinishedEvent(toolEvent),
            ManusTaskCompletedEvent(deliverable),
          ],
        );

        final provider = WorkSessionProvider(agentService: mockAgent);

        expect(provider.phase, WorkSessionPhase.idle);
        expect(provider.isBusy, isFalse);

        // 1. User sends Arabic task
        await provider.startWorkTask(
          'conv_arabic',
          'افتح المتصفح الخاص بك على Google Chrome',
        );
        await Future.delayed(const Duration(milliseconds: 50));

        // 2. Task finishes via ManusTaskCompletedEvent
        expect(provider.phase, WorkSessionPhase.completed);
        expect(provider.isBusy, isFalse);
        expect(provider.taskResult, isNotNull);
        expect(
          provider.taskResult!.summary,
          contains('تم فتح متصفح Google Chrome بنجاح'),
        );

        // 3. Timeline recorded tool event with Arabic brief and real screenshot URL
        expect(provider.timelineEvents.length, 1);
        final recordedTool = provider.timelineEvents.first;
        expect(recordedTool.toolName, 'browser_navigate');
        expect(recordedTool.brief, 'فتح صفحة Google في المتصفح');
        expect(recordedTool.screenshotUrl, isNotNull);
        expect(recordedTool.browserUrl, 'https://www.google.com');

        // 4. Elapsed worked duration is calculated
        expect(provider.workedDurationSeconds >= 0, isTrue);

        // 5. Card visibility rule: Phase is completed, so isBusy/isAgentRunning is false
        expect(provider.isAgentRunning, isFalse);
      },
    );

    test(
      'Executes question phrasing: "هل يمكنك فتح المتصفح؟" with tools and not plain chatbot answer',
      () async {
        final toolEvent = WorkToolEvent(
          id: 'call_browser_question',
          stepId: 'step_1',
          toolName: 'browser_navigate',
          toolCategory: 'browser',
          brief: 'فتح صفحة Google في متصفح Chrome',
          arguments: const {'url': 'https://www.google.com'},
          browserUrl: 'https://www.google.com',
          screenshotUrl:
              'https://image.thum.io/get/width/1280/crop/800/https://www.google.com',
          status: 'completed',
          timestamp: DateTime.now(),
        );

        final deliverable = WorkTaskResult(
          summary: 'نعم، تم فتح المتصفح بنجاح والانتقال إلى الصفحة المطلوبة.',
          attachments: const [],
          completedAt: DateTime.now(),
        );

        final mockAgent = MockManusAgentLoopService(
          eventsToEmit: [
            const ManusMessageNotifyEvent(
              'سأقوم بفتح المتصفح وتنفيذ طلبك على الفور.',
            ),
            ManusToolStartedEvent(toolEvent),
            ManusToolFinishedEvent(toolEvent),
            ManusTaskCompletedEvent(deliverable),
          ],
        );

        final provider = WorkSessionProvider(agentService: mockAgent);

        // User asks if assistant can open the browser
        await provider.startWorkTask('conv_q', 'هل يمكنك فتح المتصفح؟');
        await Future.delayed(const Duration(milliseconds: 50));

        // Must run tools, not chatbot simulation text
        expect(provider.phase, WorkSessionPhase.completed);
        expect(provider.timelineEvents.length, 1);
        expect(provider.timelineEvents.first.toolName, 'browser_navigate');
        expect(
          provider.timelineEvents.first.browserUrl,
          'https://www.google.com',
        );
        expect(provider.taskResult?.summary, contains('تم فتح المتصفح'));
      },
    );
  });
}
