import 'dart:async';

import '../../../support/business_test_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/controllers/home_page_controller.dart';
import 'package:Kelivo/features/home/controllers/scroll_controller.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/features/home/widgets/chat_selection_delete_bar.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

class _SelectionFakeChatService extends ChatService {
  _SelectionFakeChatService({
    required this.conversation,
    required List<ChatMessage> seededMessages,
    this.versionSelections = const <String, int>{},
  }) : _messages = seededMessages;

  final Conversation conversation;
  final List<ChatMessage> _messages;
  final Map<String, int> versionSelections;
  final List<({int start, int limit})> rangeQueries =
      <({int start, int limit})>[];
  int fullLoadCalls = 0;
  int getMessageIdsCalls = 0;
  Set<String>? lastDeletedIds;
  bool? lastDeleteAllVersions;
  Completer<void>? gateProjections;

  List<ChatMessage> _activeProjections() {
    final grouped = <String, List<ChatMessage>>{};
    for (final message in _messages) {
      grouped.putIfAbsent(message.groupId ?? message.id, () => []).add(message);
    }
    final active = <ChatMessage>[];
    for (final entry in grouped.entries) {
      final selected = versionSelections[entry.key];
      active.add(
        entry.value.firstWhere(
          (message) => selected == null
              ? identical(message, entry.value.last)
              : message.version == selected,
          orElse: () => entry.value.last,
        ),
      );
    }
    return active;
  }

  @override
  Conversation? getConversation(String id) =>
      id == conversation.id ? conversation : null;

  @override
  int getMessageCount(String conversationId) => -1;

  @override
  bool isMessageCountKnown(String conversationId) => false;

  bool debugHasMessageOrderSkeleton(String conversationId) => false;

  Future<List<String>> getMessageIds(String conversationId) async {
    getMessageIdsCalls += 1;
    return _messages.map((m) => m.id).toList(growable: false);
  }

  List<ChatMessage> getMessagesRange(
    String conversationId, {
    required int start,
    required int limit,
  }) {
    rangeQueries.add((start: start, limit: limit));
    if (limit < 0) return const <ChatMessage>[];
    final end = (start + limit).clamp(0, _messages.length);
    return _messages.sublist(start.clamp(0, _messages.length), end);
  }

  @override
  Future<List<ChatMessage>> loadMessages(
    String conversationId, {
    int? limit,
    int? offset,
    bool includeFollowingAssistant = false,
    String? throughRevisionId,
  }) async {
    fullLoadCalls += 1;
    return List<ChatMessage>.of(_messages);
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
    final effectiveLimit = limit ?? 40;
    final active = _activeProjections();
    final start = (active.length - effectiveLimit).clamp(0, active.length);
    final selected = active.sublist(start);
    return LoadedTimelinePage(
      conversationId: conversationId,
      stateRevision: 0,
      contextStartRevisionId: null,
      slots: [
        for (final message in selected)
          LoadedTimelineSlot(
            identity: ActiveTimelineSlot(
              revisionId: message.id,
              groupId: message.groupId ?? message.id,
              version: message.version,
            ),
            message: message,
          ),
      ],
      hasMoreBefore: start > 0,
      hasMoreAfter: false,
      totalSlotCount: active.length,
    );
  }

  @override
  Map<String, int> getVersionSelections(String conversationId) =>
      Map<String, int>.from(versionSelections);

  List<ChatMessage> getMessagesForGroups(
    String conversationId,
    Iterable<String> groupIds,
  ) {
    final targets = groupIds.toSet();
    return _messages
        .where((m) => targets.contains(m.groupId ?? m.id))
        .toList(growable: false);
  }

  @override
  Future<List<ChatMessage>> loadMessagesForGroups(
    String conversationId,
    Iterable<String> groupIds,
  ) async => getMessagesForGroups(conversationId, groupIds);

  Map<String, int> getFirstMessageIndicesForGroups(
    String conversationId,
    Iterable<String> groupIds,
  ) => {for (final id in groupIds) id: 0};

  Future<Map<String, int>> loadFirstMessageIndicesForGroups(
    String conversationId,
    Iterable<String> groupIds,
  ) async => getFirstMessageIndicesForGroups(conversationId, groupIds);

  @override
  Future<List<ChatMessage>> loadMessagesByIds(List<String> ids) async {
    final wanted = ids.toSet();
    return _messages.where((m) => wanted.contains(m.id)).toList();
  }

  @override
  Future<List<String>> loadMessageIdsForGroups(
    String conversationId,
    Iterable<String> groupIds,
  ) async {
    final targets = groupIds.toSet();
    return [
      for (final message in _messages)
        if (targets.contains(message.groupId ?? message.id)) message.id,
    ];
  }

  @override
  Future<List<ChatMessage>> loadSelectedMessageProjections(
    String conversationId,
  ) async {
    // Collapsed selected projections — not a full ID skeleton / getMessageIds.
    fullLoadCalls += 1;
    final gate = gateProjections;
    if (gate != null) await gate.future;
    return _activeProjections();
  }

  @override
  Future<Set<String>> deleteMessages({
    required String conversationId,
    required Iterable<String> messageIds,
    Map<String, dynamic>? versionSelectionChanges,
  }) async {
    lastDeletedIds = Set<String>.of(messageIds);
    return lastDeletedIds!;
  }
}

ChatMessage _msg({
  required String id,
  required String role,
  String? groupId,
  int version = 0,
  String conversationId = 'conversation-1',
}) {
  return ChatMessage(
    id: id,
    role: role,
    content: id,
    conversationId: conversationId,
    groupId: groupId ?? id,
    version: version,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('multi-version selection without full order (Issue 4)', () {
    testWidgets(
      'two-version group shows both delete options after window+group preload',
      (tester) async {
        final service = _SelectionFakeChatService(
          conversation: Conversation(
            id: 'conversation-1',
            title: 'Chat',
            messageIds: const ['user-1', 'a-v0', 'a-v1'],
          ),
          seededMessages: [
            _msg(id: 'user-1', role: 'user'),
            _msg(id: 'a-v0', role: 'assistant', groupId: 'answer', version: 0),
            _msg(id: 'a-v1', role: 'assistant', groupId: 'answer', version: 1),
          ],
          versionSelections: const {'answer': 1},
        );
        HomePageController? controller;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) =>
                    SettingsProvider(createBusinessTestPreferences()),
              ),
              ChangeNotifierProvider<ChatService>.value(value: service),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: _ControllerHarness(
                onCreated: (value) => controller = value,
              ),
            ),
          ),
        );
        await controller!.chatController.setCurrentConversationAndLoad(
          service.conversation,
        );
        await tester.pumpAndSettle();

        final collapsed = controller!.chatController
            .allCollapsedMessagesForCurrentConversation();
        expect(collapsed.map((m) => m.id), ['user-1', 'a-v1']);

        // Idle cache warm-up may call loadMessages after first paint; that is
        // unrelated to multi-version detection. Snapshot before selection.
        final loadsBeforeSelection = service.fullLoadCalls;

        controller!.startMessageSelection(
          messageIndex: 1,
          messageList: collapsed,
          mode: ChatSelectionMode.delete,
        );
        await tester.pump();

        expect(controller!.selectedMessagesIncludeMultipleVersions, isTrue);
        expect(service.rangeQueries.where((q) => q.limit < 0), isEmpty);
        expect(service.fullLoadCalls, loadsBeforeSelection);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) =>
                    SettingsProvider(createBusinessTestPreferences()),
              ),
              ChangeNotifierProvider<ChatService>.value(value: service),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ChatSelectionDeleteBar(
                  hasMultiVersionSelection:
                      controller!.selectedMessagesIncludeMultipleVersions,
                  onDeleteCurrentVersions: () {},
                  onDeleteAllVersions: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Delete This Version'), findsOneWidget);
        expect(find.text('Delete All Versions'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('single-version selection shows normal delete only', (
      tester,
    ) async {
      final service = _SelectionFakeChatService(
        conversation: Conversation(
          id: 'conversation-1',
          title: 'Chat',
          messageIds: const ['user-1', 'assistant-1'],
        ),
        seededMessages: [
          _msg(id: 'user-1', role: 'user'),
          _msg(id: 'assistant-1', role: 'assistant'),
        ],
      );
      HomePageController? controller;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider<ChatService>.value(value: service),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: _ControllerHarness(onCreated: (value) => controller = value),
          ),
        ),
      );
      await controller!.chatController.setCurrentConversationAndLoad(
        service.conversation,
      );
      await tester.pumpAndSettle();

      final collapsed = controller!.chatController
          .allCollapsedMessagesForCurrentConversation();
      controller!.startMessageSelection(
        messageIndex: 1,
        messageList: collapsed,
        mode: ChatSelectionMode.delete,
      );
      expect(controller!.selectedMessagesIncludeMultipleVersions, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatSelectionDeleteBar(
              hasMultiVersionSelection:
                  controller!.selectedMessagesIncludeMultipleVersions,
              onDeleteCurrentVersions: () {},
              onDeleteAllVersions: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Delete This Version'), findsNothing);
      expect(find.text('Delete All Versions'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'delete current version vs delete all versions use async group paths',
      (tester) async {
        final service = _SelectionFakeChatService(
          conversation: Conversation(
            id: 'conversation-1',
            title: 'Chat',
            messageIds: const ['user-1', 'a-v0', 'a-v1'],
          ),
          seededMessages: [
            _msg(id: 'user-1', role: 'user'),
            _msg(id: 'a-v0', role: 'assistant', groupId: 'answer', version: 0),
            _msg(id: 'a-v1', role: 'assistant', groupId: 'answer', version: 1),
          ],
          versionSelections: const {'answer': 1},
        );
        HomePageController? controller;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) =>
                    SettingsProvider(createBusinessTestPreferences()),
              ),
              ChangeNotifierProvider<ChatService>.value(value: service),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: _ControllerHarness(
                onCreated: (value) => controller = value,
              ),
            ),
          ),
        );
        await controller!.chatController.setCurrentConversationAndLoad(
          service.conversation,
        );
        await tester.pumpAndSettle();

        final collapsed = controller!.chatController
            .allCollapsedMessagesForCurrentConversation();
        controller!.startMessageSelection(
          messageIndex: 1,
          messageList: collapsed,
          mode: ChatSelectionMode.delete,
        );
        // startMessageSelection pairs the prior user turn; isolate the
        // multi-version assistant group so delete paths exercise group APIs.
        controller!.toggleSelection('user-1', false);

        await controller!.deleteSelectedMessages(deleteAllVersions: false);
        expect(service.lastDeletedIds, {'a-v1'});

        controller!.startMessageSelection(
          messageIndex: 1,
          messageList: collapsed,
          mode: ChatSelectionMode.delete,
        );
        controller!.toggleSelection('user-1', false);
        await controller!.deleteSelectedMessages(deleteAllVersions: true);
        expect(service.lastDeletedIds, {'a-v0', 'a-v1'});
        expect(service.rangeQueries.where((q) => q.limit < 0), isEmpty);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('selection UI covers full history projection (Issue B)', () {
    testWidgets(
      'select-all outside window keeps multi-version UI and allSelected truth',
      (tester) async {
        final seeded = <ChatMessage>[
          _msg(id: 'user-old', role: 'user'),
          _msg(
            id: 'a-v0',
            role: 'assistant',
            groupId: 'early-answer',
            version: 0,
          ),
          _msg(
            id: 'a-v1',
            role: 'assistant',
            groupId: 'early-answer',
            version: 1,
          ),
          for (var i = 0; i < 42; i++) ...[
            _msg(id: 'u-$i', role: 'user'),
            _msg(id: 'a-$i', role: 'assistant'),
          ],
        ];
        final service = _SelectionFakeChatService(
          conversation: Conversation(
            id: 'conversation-1',
            title: 'Long chat',
            messageIds: seeded.map((m) => m.id).toList(),
          ),
          seededMessages: seeded,
          versionSelections: const {'early-answer': 1},
        );

        HomePageController? controller;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) =>
                    SettingsProvider(createBusinessTestPreferences()),
              ),
              ChangeNotifierProvider<ChatService>.value(value: service),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: _ControllerHarness(
                onCreated: (value) => controller = value,
              ),
            ),
          ),
        );
        await controller!.chatController.setCurrentConversationAndLoad(
          service.conversation,
        );
        await tester.pumpAndSettle();

        final windowIds = controller!.chatController.collapsedMessages
            .map((m) => m.id)
            .toSet();
        expect(windowIds.contains('a-v1'), isFalse);
        expect(windowIds.length, lessThanOrEqualTo(40));
        expect(
          controller!.chatController.collapsedMessages.length,
          lessThan(seeded.length),
        );

        final idsBeforeSelect = service.getMessageIdsCalls;
        final rangesBeforeSelect = service.rangeQueries.length;

        controller!.startMessageSelection(
          messageIndex: 0,
          messageList: controller!.chatController.collapsedMessages,
          mode: ChatSelectionMode.delete,
        );
        controller!.selectAll();
        await tester.pumpAndSettle();

        expect(controller!.selectedItems.contains('a-v1'), isTrue);
        expect(controller!.selectedMessagesIncludeMultipleVersions, isTrue);
        expect(controller!.allSelectableMessagesSelected, isTrue);

        // Mini-map style deselect of the out-of-window multi-version item.
        controller!.toggleSelection('a-v1', false);
        await tester.pump();
        expect(controller!.allSelectableMessagesSelected, isFalse);
        expect(controller!.selectedItems.contains('a-v1'), isFalse);

        expect(service.getMessageIdsCalls, idsBeforeSelect);
        expect(service.rangeQueries.where((q) => q.limit < 0), isEmpty);
        expect(service.rangeQueries.length, rangesBeforeSelect);
        expect(
          service.debugHasMessageOrderSkeleton(service.conversation.id),
          isFalse,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('stale select-all must not pollute next selection (P2)', () {
    testWidgets(
      'select-all incomplete → cancel → new selection → stale query ignored',
      (tester) async {
        final service = _SelectionFakeChatService(
          conversation: Conversation(
            id: 'conversation-1',
            title: 'Chat',
            messageIds: const [
              'user-1',
              'assistant-1',
              'user-2',
              'assistant-2',
            ],
          ),
          seededMessages: [
            _msg(id: 'user-1', role: 'user'),
            _msg(id: 'assistant-1', role: 'assistant'),
            _msg(id: 'user-2', role: 'user'),
            _msg(id: 'assistant-2', role: 'assistant'),
          ],
        );
        service.gateProjections = Completer<void>();

        HomePageController? controller;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) =>
                    SettingsProvider(createBusinessTestPreferences()),
              ),
              ChangeNotifierProvider<ChatService>.value(value: service),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: _ControllerHarness(
                onCreated: (value) => controller = value,
              ),
            ),
          ),
        );
        await controller!.chatController.setCurrentConversationAndLoad(
          service.conversation,
        );
        await tester.pumpAndSettle();

        final collapsed = controller!.chatController
            .allCollapsedMessagesForCurrentConversation();
        controller!.startMessageSelection(
          messageIndex: 0,
          messageList: collapsed,
          mode: ChatSelectionMode.delete,
        );
        // Anchor pairing may select user+assistant; isolate a known baseline.
        controller!.toggleSelection('assistant-1', false);
        controller!.toggleSelection('user-2', false);
        controller!.toggleSelection('assistant-2', false);
        expect(controller!.selectedItems, {'user-1'});

        controller!.selectAll();
        await tester.pump();
        expect(service.fullLoadCalls, greaterThan(0));
        // Projection still gated — selection must not jump to full history yet.
        expect(controller!.selectedItems, {'user-1'});

        controller!.cancelSelection();
        expect(controller!.selecting, isFalse);
        expect(controller!.selectedItems, isEmpty);

        controller!.startMessageSelection(
          messageIndex: 2,
          messageList: collapsed,
          mode: ChatSelectionMode.delete,
        );
        // New selection: only the newly chosen pair (user-2 + assistant-2).
        expect(controller!.selectedItems.contains('user-2'), isTrue);
        expect(controller!.selectedItems.contains('user-1'), isFalse);
        final newSelection = Set<String>.of(controller!.selectedItems);

        // Stale select-all finishes — must not merge old conversation ids.
        service.gateProjections!.complete();
        await tester.pumpAndSettle();

        expect(controller!.selectedItems, newSelection);
        expect(controller!.selectedItems.contains('user-1'), isFalse);
        expect(controller!.allSelectableMessagesSelected, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}

class _ControllerHarness extends StatefulWidget {
  const _ControllerHarness({required this.onCreated});

  final ValueChanged<HomePageController> onCreated;

  @override
  State<_ControllerHarness> createState() => _ControllerHarnessState();
}

class _ControllerHarnessState extends State<_ControllerHarness>
    with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _inputBarKey = GlobalKey();
  final _inputFocus = FocusNode();
  final _inputController = TextEditingController();
  final _mediaController = ChatInputBarController();
  final _scrollController = ChatAutoFollowScrollController();
  late final HomePageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HomePageController(
      context: context,
      vsync: this,
      scaffoldKey: _scaffoldKey,
      inputBarKey: _inputBarKey,
      inputFocus: _inputFocus,
      inputController: _inputController,
      mediaController: _mediaController,
      scrollController: _scrollController,
    );
    widget.onCreated(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(key: _scaffoldKey);
}
