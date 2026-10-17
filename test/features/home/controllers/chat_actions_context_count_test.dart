import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatService service;

  setUp(() async {
    service = ChatService();
    await service.init();
  });

  tearDown(() {
    service.dispose();
  });

  test('limited context uses assistant size', () async {
    final draft = await service.createConversation(title: 'Chat');
    for (var i = 0; i < 20; i++) {
      await service.addMessage(
        conversationId: draft.id,
        role: i.isEven ? 'user' : 'assistant',
        content: 'message $i',
      );
    }

    final limit = await ChatActions.resolveContextReadLimit(
      assistant: const Assistant(
        id: 'assistant-1',
        name: 'Limited',
        contextMessageSize: 64,
        limitContextMessages: true,
      ),
      resolvePersistedCount: () async => service.resolveMessageCount(draft.id),
    );

    expect(limit, 64);
  });

  test('temporary conversation uses memory count', () async {
    final draft = await service.createDraftConversation(
      title: 'Temp',
      temporary: true,
    );
    await service.addMessage(
      conversationId: draft.id,
      role: 'user',
      content: 'hello',
    );
    await service.addMessage(
      conversationId: draft.id,
      role: 'assistant',
      content: 'hi',
    );

    final count = service.resolveMessageCount(draft.id);
    expect(count, 2);
  });

  test('new draft uses memory count', () async {
    final draft = await service.createDraftConversation(title: 'Draft');
    final count = service.resolveMessageCount(draft.id);
    expect(count, 0);

    final limit = await ChatActions.resolveContextReadLimit(
      assistant: const Assistant(
        id: 'assistant-1',
        name: 'Unlimited',
        limitContextMessages: false,
      ),
      resolvePersistedCount: () async => service.resolveMessageCount(draft.id),
    );
    expect(limit, Assistant.maxContextMessageSize);
  });
}
