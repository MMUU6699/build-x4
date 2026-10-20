import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/work/models/work_task_result.dart';
import 'package:Kelivo/features/work/models/work_tool_event.dart';
import 'package:Kelivo/features/work/models/work_turn.dart';

void main() {
  test('WorkTurn persists prompt, events, attachments and resume state', () {
    final turn = WorkTurn(
      id: 'turn_1',
      conversationId: 'conv_1',
      prompt: 'do the work',
      introMessage: 'starting',
      question: 'which file?',
      pendingToolCallId: 'ask_9',
      events: [
        WorkToolEvent(
          id: 'call_1',
          stepId: 'step_1',
          toolName: 'browser_navigate',
          toolCategory: 'browser',
          brief: 'Open the page',
          screenshotUrl: 'https://expired.example/shot.png',
          screenshotPath: 'user/conv/call_1.png',
          status: 'completed',
          timestamp: DateTime.utc(2026, 10, 20, 12),
        ),
      ],
      finalAnswer: 'done',
      result: WorkTaskResult(
        summary: 'done',
        attachments: const [
          WorkAttachment(
            name: 'report.pdf',
            path: '/tmp/report.pdf',
            fileType: 'pdf',
          ),
        ],
        completedAt: DateTime.utc(2026, 10, 20, 12, 1),
      ),
      durationSeconds: 42,
      status: 'completed',
      startedAt: DateTime.utc(2026, 10, 20, 12),
    );

    final json = turn.toJson();

    expect(json['screenshot_url'], isNull);
    final rawEvents = json['events']! as List<dynamic>;
    expect((rawEvents.single as Map)['screenshot_url'], isNull);
    expect(
      (rawEvents.single as Map)['screenshot_path'],
      'user/conv/call_1.png',
    );

    final restored = WorkTurn.fromJson(json);
    expect(restored.id, 'turn_1');
    expect(restored.prompt, 'do the work');
    expect(restored.introMessage, 'starting');
    expect(restored.question, 'which file?');
    expect(restored.pendingToolCallId, 'ask_9');
    expect(restored.events.single.id, 'call_1');
    expect(restored.events.single.screenshotPath, 'user/conv/call_1.png');
    expect(restored.finalAnswer, 'done');
    expect(restored.durationSeconds, 42);
    expect(restored.result!.attachments.single.path, '/tmp/report.pdf');
  });

  test('a waiting turn can be resumed and later completed', () {
    final waiting = WorkTurn(
      id: 'turn_2',
      conversationId: 'conv_1',
      prompt: 'sign in',
      status: 'waiting',
      pendingToolCallId: 'ask_2',
      startedAt: DateTime.now(),
    );
    final restored = WorkTurn.fromJson(waiting.toJson());
    expect(restored.isWaiting, isTrue);
    expect(restored.pendingToolCallId, 'ask_2');

    final completed = restored.copyWith(
      status: 'completed',
      finalAnswer: 'signed in',
      pendingToolCallId: '',
      durationSeconds: 3,
    );
    expect(completed.isWaiting, isFalse);
    expect(completed.isCompleted, isTrue);
    expect(completed.pendingToolCallId, isEmpty);
    expect(completed.finalAnswer, 'signed in');
  });
}
