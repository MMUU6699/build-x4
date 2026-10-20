import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/services/workspace/work_event_persistence_service.dart';
import 'package:Kelivo/features/work/models/work_task_result.dart';
import 'package:Kelivo/features/work/models/work_tool_event.dart';
import 'package:Kelivo/features/work/models/work_turn.dart';
import 'package:Kelivo/features/work/providers/work_session_provider.dart';
import 'package:Kelivo/features/work/widgets/work_computer_modal_sheet.dart';
import 'package:Kelivo/features/work/widgets/work_turn_widget.dart';

class _Persistence extends WorkEventPersistenceService {
  const _Persistence([this.turns = const []]);

  final List<WorkTurn> turns;

  @override
  Future<void> saveWorkTurn(WorkTurn turn) async {}

  @override
  Future<List<WorkTurn>> fetchWorkTurns(String conversationId) async => turns;

  @override
  Future<String?> createScreenshotUrl(String path) async => null;
}

void main() {
  testWidgets('tool brief opens the computer once through the provider', (
    tester,
  ) async {
    final event = WorkToolEvent(
      id: 'call_1',
      stepId: 'step_1',
      toolName: 'browser_navigate',
      toolCategory: 'browser',
      brief: 'فتح الصفحة',
      status: 'running',
      timestamp: DateTime.now(),
    );
    final turn = WorkTurn(
      id: 'turn_1',
      conversationId: 'conv_1',
      prompt: 'open',
      status: 'running',
      events: [event],
      startedAt: DateTime.now(),
    );
    final provider = WorkSessionProvider(
      persistenceService: _Persistence([turn]),
    );
    await provider.loadSessionForConversation('conv_1');

    await tester.pumpWidget(
      ChangeNotifierProvider<WorkSessionProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(body: WorkTurnWidget(turn: turn)),
        ),
      ),
    );

    await tester.tap(find.text('فتح الصفحة'));
    await tester.pump();

    expect(provider.isComputerOpen, isTrue);
    expect(provider.computerEvent!.id, 'call_1');
    // The turn never opens the sheet itself; HomePage owns the single sheet.
    expect(find.byType(WorkComputerModalSheet), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('completed turn shows the real duration, answer and status', (
    tester,
  ) async {
    final turn = WorkTurn(
      id: 'turn_2',
      conversationId: 'conv_1',
      prompt: 'do it',
      finalAnswer: 'تم إنشاء الملف.',
      result: WorkTaskResult(
        summary: 'تم إنشاء الملف.',
        completedAt: DateTime.now(),
      ),
      durationSeconds: 7,
      status: 'completed',
      startedAt: DateTime.now(),
    );
    final provider = WorkSessionProvider(
      persistenceService: const _Persistence(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<WorkSessionProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(body: WorkTurnWidget(turn: turn)),
        ),
      ),
    );

    expect(find.text('Worked for 7s'), findsOneWidget);
    expect(find.text('تم إنشاء الملف.'), findsOneWidget);
    expect(find.text('Task completed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('failed turn shows the real error and a retry action', (
    tester,
  ) async {
    final turn = WorkTurn(
      id: 'turn_3',
      conversationId: 'conv_1',
      prompt: 'do it',
      error: 'Browser blocked the request.',
      status: 'error',
      durationSeconds: 2,
      startedAt: DateTime.now(),
    );
    final provider = WorkSessionProvider(
      persistenceService: const _Persistence(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<WorkSessionProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(body: WorkTurnWidget(turn: turn)),
        ),
      ),
    );

    expect(find.text('Browser blocked the request.'), findsOneWidget);
    expect(find.byTooltip('Run again'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}
