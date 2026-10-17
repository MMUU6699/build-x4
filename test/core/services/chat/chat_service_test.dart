import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatService service;

  setUp(() {
    service = ChatService();
  });

  test('initial state is uninitialized with no conversations', () {
    expect(service.getAllConversations(), isEmpty);
    expect(service.currentConversationId, isNull);
    expect(service.currentConversation, isNull);
  });

  test(
    'createConversation adds conversation and setCurrentConversation selects it',
    () async {
      final conv = await service.createConversation(
        id: 'conv-1',
        title: 'Test Chat',
        isTemporary: true,
      );

      expect(conv.id, 'conv-1');
      expect(conv.title, 'Test Chat');
      expect(service.getConversation('conv-1'), isNotNull);
      expect(service.getAllConversations().length, 1);

      service.setCurrentConversation('conv-1');
      expect(service.currentConversationId, 'conv-1');
      expect(service.currentConversation?.id, 'conv-1');
    },
  );

  test('temporary conversation flag tracking', () {
    expect(service.isTemporaryConversation('temp-1'), isFalse);
    service.setTemporaryConversation('temp-1', true);
    expect(service.isTemporaryConversation('temp-1'), isTrue);
    service.setTemporaryConversation('temp-1', false);
    expect(service.isTemporaryConversation('temp-1'), isFalse);
  });

  test(
    'addMessage stores message in cache and updates message count',
    () async {
      await service.createConversation(
        id: 'conv-2',
        title: 'Chat 2',
        isTemporary: true,
      );

      final msg = await service.addMessage(
        conversationId: 'conv-2',
        role: 'user',
        parts: const [TextPart('Hello Build X')],
      );

      expect(service.getMessageCount('conv-2'), 1);
      final messages = service.getMessages('conv-2');
      expect(messages.length, 1);
      expect(messages.first.id, msg.id);
      expect((messages.first.parts.first as TextPart).text, 'Hello Build X');
    },
  );
}
