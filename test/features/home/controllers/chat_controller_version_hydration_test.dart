import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/controllers/chat_controller.dart';

class _VersionService extends ChatService {
  final conversation = Conversation(id: 'c', title: 'Versions');
  final selected = <String, int>{'a': 1, 'b': 1};
  Completer<void>? writeGate;
  final writes = <(String, int)>[];
  final versions = [
    for (final group in ['a', 'b'])
      for (var v = 0; v < 2; v++)
        ChatMessage(
          id: '$group-$v',
          role: 'assistant',
          content: 'complete $group-$v',
          conversationId: 'c',
          groupId: group,
          version: v,
        ),
  ];
  @override
  Conversation? getConversation(String id) => id == 'c' ? conversation : null;
  @override
  Map<String, int> getVersionSelections(String conversationId) =>
      Map.of(selected);
  @override
  Future<List<ChatMessage>> loadMessageVersionHeaders(
    String conversationId, [
    Iterable<String>? groupIds,
  ]) async => [
    for (final m in versions.where(
      (m) => (groupIds ?? const []).contains(m.groupId),
    ))
      m.copyWith(content: ''),
  ];
  @override
  Future<void> setSelectedVersion(
    String conversationId,
    String groupId,
    int version,
  ) async {
    writes.add((groupId, version));
    await writeGate?.future;
    selected[groupId] = version;
  }

  @override
  Future<LoadedTimelinePage> loadTimelinePage(
    String conversationId, {
    int? limit,
    String? beforeRevisionId,
    String? afterRevisionId,
    bool fromStart = false,
    String? aroundRevisionId,
    int? initialTextBudget,
    int? initialMessageMin,
    int? initialMessageMax,
  }) async {
    final messages = versions
        .where(
          (m) =>
              selected[m.groupId] == m.version &&
              (aroundRevisionId == null ||
                  m.groupId == aroundRevisionId.split('-').first),
        )
        .toList();
    return LoadedTimelinePage(
      conversationId: 'c',
      stateRevision: 0,
      contextStartRevisionId: null,
      slots: [
        for (final m in messages)
          LoadedTimelineSlot(
            message: m,
            identity: ActiveTimelineSlot(
              revisionId: m.id,
              groupId: m.groupId!,
              version: m.version,
              versionCount: 2,
              logicalIndex: m.groupId == 'a' ? 0 : 1,
            ),
          ),
      ],
      hasMoreBefore: false,
      hasMoreAfter: false,
      totalSlotCount: 2,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'overlapping choices in different groups both hydrate complete bodies',
    () async {
      final service = _VersionService();
      final controller = ChatController(chatService: service);
      addTearDown(controller.dispose);
      await controller.setCurrentConversationAndLoad(service.conversation);
      expect(controller.groupedMessages['a']!.first.content, isEmpty);
      service.writeGate = Completer<void>();
      final a = controller.setSelectedVersion('a', 0);
      final b = controller.setSelectedVersion('b', 0);
      await Future<void>.delayed(Duration.zero);
      expect(controller.collapsedMessages.map((m) => m.content), [
        'complete a-1',
        'complete b-1',
      ]);
      service.writeGate!.complete();
      await Future.wait([a, b]);
      expect(controller.collapsedMessages.map((m) => m.content), [
        'complete a-0',
        'complete b-0',
      ]);
      expect(controller.versionSelections, {'a': 0, 'b': 0});
    },
  );
  test(
    'rapid choices preserve write order and navigation rejects stale hydration',
    () async {
      final service = _VersionService();
      final controller = ChatController(chatService: service);
      addTearDown(controller.dispose);
      await controller.setCurrentConversationAndLoad(service.conversation);
      service.writeGate = Completer<void>();
      final first = controller.setSelectedVersion('a', 0);
      final second = controller.setSelectedVersion('a', 1);
      service.writeGate!.complete();
      await Future.wait([first, second]);
      expect(service.writes, [('a', 0), ('a', 1)]);
      expect(controller.collapsedMessages.first.content, 'complete a-1');
      service.writeGate = Completer<void>();
      final pending = controller.setSelectedVersion('a', 0);
      controller.clearCurrentConversation();
      service.writeGate!.complete();
      await pending;
      expect(controller.collapsedMessages, isEmpty);
      expect(controller.currentConversation, isNull);
    },
  );
  test(
    'disposing while a selection writes cannot publish a stale body',
    () async {
      final service = _VersionService();
      final controller = ChatController(chatService: service);
      await controller.setCurrentConversationAndLoad(service.conversation);
      service.writeGate = Completer<void>();
      final pending = controller.setSelectedVersion('a', 0);
      controller.dispose();
      service.writeGate!.complete();
      await expectLater(pending, completes);
    },
  );
}
