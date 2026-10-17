import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/services/context_usage_service.dart';

import '../../../support/business_test_harness.dart';

class _FakeChatService extends ChatService {
  final Map<String, List<ChatMessage>> _messages = {};

  void setMessages(String conversationId, List<ChatMessage> messages) {
    _messages[conversationId] = messages;
  }

  @override
  List<ChatMessage> getMessages(String conversationId) =>
      _messages[conversationId] ?? const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContextUsageBuckets', () {
    test('nonDraftTotal and total calculate correctly', () {
      const buckets = ContextUsageBuckets(
        system: 10,
        injections: 5,
        history: 20,
        tools: 15,
        attachments: 8,
        memory: 2,
        worldBook: 3,
        skills: 4,
        workspace: 6,
        search: 7,
        mcpTools: 9,
        draft: 12,
      );
      expect(buckets.nonDraftTotal, 89);
      expect(buckets.total, 101);
    });

    test('copyWith updates specified fields', () {
      const buckets = ContextUsageBuckets(system: 10, draft: 5);
      final updated = buckets.copyWith(system: 20, draft: 15);
      expect(updated.system, 20);
      expect(updated.draft, 15);
    });
  });

  group('calibrateContextUsageBuckets', () {
    test('scales and pushes residual', () {
      const estimated = ContextUsageBuckets(
        system: 10,
        injections: 10,
        history: 10,
        tools: 10,
        attachments: 11,
        draft: 5,
      );
      final calibrated = calibrateContextUsageBuckets(
        estimated: estimated,
        anchorTotal: 100,
      )!;
      expect(calibrated.nonDraftTotal, 100);
      expect(calibrated.draft, 5);
      expect(
        calibrateContextUsageBuckets(
          estimated: const ContextUsageBuckets(draft: 3),
          anchorTotal: 50,
        ),
        isNull,
      );
    });
  });

  group('ContextUsageService', () {
    late SettingsProvider settings;
    late AssistantProvider assistants;
    late _FakeChatService chatService;
    late ContextUsageService usageService;

    setUp(() {
      settings = SettingsProvider(createBusinessTestPreferences());
      assistants = AssistantProvider(
        initialAssistants: [
          const Assistant(
            id: 'test-assistant',
            name: 'Test Assistant',
            systemPrompt: 'You are a helpful assistant for coding.',
          ),
        ],
      );
      chatService = _FakeChatService();
      usageService = ContextUsageService(
        settings: settings,
        assistants: assistants,
        chatService: chatService,
      );
    });

    tearDown(() {
      usageService.dispose();
      assistants.dispose();
      settings.dispose();
    });

    test(
      'refresh computes snapshot from assistant and chat messages',
      () async {
        chatService.setMessages('conv-1', [
          ChatMessage(
            id: 'm1',
            role: 'user',
            content: 'Hello world',
            conversationId: 'conv-1',
            totalTokens: 5,
          ),
          ChatMessage(
            id: 'm2',
            role: 'assistant',
            content: 'Hello there, how can I help?',
            conversationId: 'conv-1',
            totalTokens: 12,
          ),
        ]);

        await usageService.refresh('conv-1');

        final snapshot = usageService.snapshot('conv-1');
        expect(snapshot, isNotNull);
        expect(snapshot!.state, ContextUsageState.exact);
        expect(snapshot.modelId, 'mistral-medium-latest');
        expect(snapshot.providerKey, 'mistral');
        expect(snapshot.buckets.history, 17);
        expect(snapshot.contextWindow, 32768);
        expect(snapshot.ratio, isNotNull);
        expect(snapshot.ratio!, greaterThan(0));
      },
    );

    test(
      'setActiveConversation and reset manage active conversation state',
      () async {
        chatService.setMessages('conv-1', [
          ChatMessage(
            id: 'm1',
            role: 'user',
            content: 'test',
            conversationId: 'conv-1',
          ),
        ]);

        usageService.setActiveConversation('conv-1');
        await usageService.refresh('conv-1');
        expect(usageService.snapshot('conv-1'), isNotNull);

        usageService.reset('conv-1');
        expect(usageService.snapshot('conv-1'), isNull);
      },
    );

    test('updateDraft updates draft token count in snapshot', () async {
      await usageService.refresh('conv-1');
      usageService.updateDraft('conv-1', 'This is a long draft prompt.');
      final snapshot = usageService.snapshot('conv-1');
      expect(snapshot, isNotNull);
    });
  });
}
