import '../models/chat_message.dart';
import '../models/conversation.dart';

class MiniMapSearchHit {
  const MiniMapSearchHit({
    required this.messageId,
    required this.matchCount,
    required this.snippet,
    required this.snippetStart,
  });

  final String messageId;
  final int matchCount;
  final String snippet;
  final int snippetStart;
}

class ChatDatabaseRepository {
  Future<List<Conversation>> getAllConversations() async => [];
  Future<Conversation?> getConversation(String id) async => null;
  Future<List<ChatMessage>> getMessages(String conversationId) async => [];
  Future<List<MiniMapSearchHit>> searchMiniMapMatches(
    String conversationId,
    String query,
  ) async => [];
  Future<Map<String, dynamic>?> getMessagePrompts(List<String> ids) async =>
      null;
  Future<dynamic> getMessagePrompt(String id) async => null;
  Future<void> freezeMessagePrompt({
    dynamic revisionId,
    dynamic conversationId,
    dynamic payload,
    dynamic carriesMemorySnapshot,
    dynamic injectedMemoryHash,
  }) async {}
  Future<bool> anyPromptCarriesMemorySnapshot(
    dynamic conversationIdOrIds,
  ) async => false;
  Future<String?> getConversationInjectedMemoryHash(
    String conversationId,
  ) async => null;
}
