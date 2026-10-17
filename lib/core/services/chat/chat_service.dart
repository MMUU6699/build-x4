import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../config/supabase_config.dart';
import '../../database/composer_draft_store.dart';
import '../../database/chat_database_repository.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../models/generation_run.dart';
import '../../models/message_part.dart';

final class ActiveTimelineSlot {
  const ActiveTimelineSlot({
    required this.revisionId,
    required this.groupId,
    required this.version,
    this.versionCount = 1,
    this.logicalIndex = 0,
  });

  final String revisionId;
  final String groupId;
  final int version;
  final int versionCount;
  final int logicalIndex;

  String get slotId => revisionId;
}

final class LoadedTimelineSlot {
  const LoadedTimelineSlot({required this.identity, required this.message});

  final ActiveTimelineSlot identity;
  final ChatMessage message;
}

final class LoadedTimelinePage {
  LoadedTimelinePage({
    required this.conversationId,
    required this.stateRevision,
    required this.contextStartRevisionId,
    required List<LoadedTimelineSlot> slots,
    required this.hasMoreBefore,
    required this.hasMoreAfter,
    required this.totalSlotCount,
  }) : slots = List.unmodifiable(slots);

  final String conversationId;
  final int stateRevision;
  final String? contextStartRevisionId;
  final List<LoadedTimelineSlot> slots;
  final bool hasMoreBefore;
  final bool hasMoreAfter;
  final int totalSlotCount;

  String? get beforeRevisionId => hasMoreBefore && slots.isNotEmpty
      ? slots.first.identity.revisionId
      : null;
  String? get afterRevisionId =>
      hasMoreAfter && slots.isNotEmpty ? slots.last.identity.revisionId : null;
}

class ChatService extends ChangeNotifier {
  ChatService();

  static const int defaultInitialMessageMin = 2;
  static const int defaultInitialMessageMax = 240;
  static const int defaultTimelineInitialSlots = 40;
  static const int defaultInitialTextBudget = 20000;
  static const int defaultHistoryPageSize = 20;
  static const int defaultLoadedWindowMax = 360;
  static bool timelineCacheFastPathEnabled = true;

  static final Map<String, Conversation> _sharedConversations = {};
  static final Map<String, List<ChatMessage>> _sharedMessages = {};

  @visibleForTesting
  static void resetSharedStorageForTesting() {
    _sharedConversations.clear();
    _sharedMessages.clear();
  }

  final Map<String, Conversation> _conversationsCache = {};
  final Map<String, List<ChatMessage>> _messagesCache = {};
  final Set<String> _temporaryConversations = {};

  int _conversationListRevision = 0;
  int get conversationListRevision => _conversationListRevision;

  void _bumpConversationListRevision() {
    _conversationListRevision++;
  }

  String? _currentConversationId;
  String? get currentConversationId => _currentConversationId;
  Conversation? get currentConversation => _currentConversationId != null
      ? getConversation(_currentConversationId!)
      : null;

  String _defaultTitle = 'New Chat';
  final ComposerDraftStore composerDrafts = ComposerDraftStore();
  Map<String, dynamic> Function(String? assistantId)? newConversationExtras;

  bool _initialized = false;
  bool get isInitialized => _initialized;
  bool get initialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        final res = await SupabaseConfig.client
            .from('conversations')
            .select()
            .order('updated_at', ascending: false);

        _conversationsCache.clear();
        for (final row in res as List<dynamic>) {
          final map = row as Map<String, dynamic>;
          final c = _mapToConversation(map);
          _conversationsCache[c.id] = c;
          _sharedConversations[c.id] = c;
        }

        if (_currentConversationId == null && _conversationsCache.isNotEmpty) {
          _currentConversationId = getAllConversations().first.id;
        }
      } else {
        _conversationsCache.clear();
        _conversationsCache.addAll(_sharedConversations);
        if (_currentConversationId == null && _conversationsCache.isNotEmpty) {
          _currentConversationId = getAllConversations().first.id;
        }
      }
    } catch (e) {
      debugPrint('Failed to load conversations from Supabase: $e');
      _conversationsCache.clear();
      _conversationsCache.addAll(_sharedConversations);
      if (_currentConversationId == null && _conversationsCache.isNotEmpty) {
        _currentConversationId = getAllConversations().first.id;
      }
    }
    _initialized = true;
    _bumpConversationListRevision();
    notifyListeners();
  }

  Conversation _mapToConversation(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'New Chat',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
      messageIds: const <String>[],
      isPinned: map['is_pinned'] as bool? ?? false,
      assistantId: map['assistant_id'] as String?,
      truncateIndex: -1,
      versionSelections: const <String, int>{},
      chatSuggestions: const <String>[],
      extras: map['mistral_conversation_id'] != null
          ? {'mistral_conversation_id': map['mistral_conversation_id']}
          : const <String, dynamic>{},
    );
  }

  ChatMessage _mapToChatMessage(Map<String, dynamic> map) {
    List<MessagePart> parts = [];
    final rawParts = map['parts'];
    if (rawParts is List) {
      for (final p in rawParts) {
        if (p is Map) {
          final kind = (p['kind'] ?? '').toString();
          final payload = (p['payload'] ?? '').toString();
          try {
            parts.add(MessagePart.fromRow(kind, payload));
          } catch (_) {}
        }
      }
    }
    if (parts.isEmpty && map['content'] != null) {
      parts = [TextPart(map['content'] as String)];
    }

    return ChatMessage(
      id: map['id'] as String,
      role: map['role'] as String? ?? 'user',
      parts: parts,
      timestamp:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      conversationId: map['conversation_id'] as String,
      promptTokens: map['prompt_tokens'] as int?,
      completionTokens: map['completion_tokens'] as int?,
      totalTokens: map['total_tokens'] as int?,
      durationMs: map['duration_ms'] as int?,
      version: 0,
      groupId: map['id'] as String,
    );
  }

  void setDefaultConversationTitle(String title) {
    _defaultTitle = title;
  }

  bool isMessageCountKnown(String conversationId) => true;

  Map<String, int> getVersionSelections(String conversationId) {
    return _conversationsCache[conversationId]?.versionSelections ??
        const <String, int>{};
  }

  int contextRevision(String conversationId) => 0;

  bool isTemporaryConversation(String? id) {
    if (id == null) return false;
    return _temporaryConversations.contains(id);
  }

  void setTemporaryConversation(String id, bool temporary) {
    if (temporary) {
      _temporaryConversations.add(id);
    } else {
      _temporaryConversations.remove(id);
    }
  }

  List<Conversation> getAllConversations() {
    final list = _conversationsCache.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  List<Conversation> getAllCompleteConversations() => getAllConversations();

  List<Conversation> getPinnedConversations() {
    return getAllConversations().where((c) => c.isPinned).toList();
  }

  Conversation? getConversation(String id) {
    return _conversationsCache[id];
  }

  Conversation? getCompleteConversation(String id) {
    return _conversationsCache[id];
  }

  void setCurrentConversation(String? id) {
    if (_currentConversationId == id) return;
    _currentConversationId = id;
    notifyListeners();
  }

  int getMessageCount(String conversationId) {
    return _messagesCache[conversationId]?.length ?? 0;
  }

  int getMessageIndex(String conversationId, String messageId) {
    final list = _messagesCache[conversationId];
    if (list == null) return -1;
    return list.indexWhere((m) => m.id == messageId);
  }

  List<ChatMessage> getMessages(String conversationId) {
    return _messagesCache[conversationId] ?? const <ChatMessage>[];
  }

  Future<Conversation> createConversation({
    String? id,
    String? title,
    String? assistantId,
    String? workspaceId,
    Map<String, dynamic>? extras,
    bool isTemporary = false,
  }) async {
    final newId = id ?? const Uuid().v4();
    final now = DateTime.now().toUtc();
    final effectiveTitle = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : _defaultTitle;

    final conversation = Conversation(
      id: newId,
      title: effectiveTitle,
      createdAt: now,
      updatedAt: now,
      messageIds: const <String>[],
      assistantId: assistantId,
      extras:
          extras ??
          (newConversationExtras?.call(assistantId) ??
              const <String, dynamic>{}),
    );

    _conversationsCache[newId] = conversation;
    _messagesCache[newId] = [];

    if (isTemporary) {
      _temporaryConversations.add(newId);
    } else {
      _sharedConversations[newId] = conversation;
      try {
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null) {
          await SupabaseConfig.client.from('conversations').insert({
            'id': newId,
            'user_id': user.id,
            'title': effectiveTitle,
            'assistant_id': assistantId,
            'workspace_id': workspaceId,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          });
        }
      } catch (e) {
        debugPrint('Failed to insert conversation into Supabase: $e');
      }
    }

    _currentConversationId = newId;
    _bumpConversationListRevision();
    notifyListeners();
    return conversation;
  }

  Future<Conversation> createDraftConversation({
    String? assistantId,
    String? title,
    bool reuseNewEntry = false,
    bool? temporary,
  }) {
    return createConversation(
      assistantId: assistantId,
      title: title,
      isTemporary: temporary ?? true,
    );
  }

  Future<void> updateConversationTitle(String id, String title) async {
    final c = _conversationsCache[id];
    if (c == null) return;
    final updated = c.copyWith(title: title, updatedAt: DateTime.now().toUtc());
    _conversationsCache[id] = updated;
    if (!isTemporaryConversation(id)) {
      _sharedConversations[id] = updated;
    }
    _bumpConversationListRevision();
    notifyListeners();

    if (!isTemporaryConversation(id)) {
      try {
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null) {
          await SupabaseConfig.client
              .from('conversations')
              .update({
                'title': title,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', id);
        }
      } catch (e) {
        debugPrint('Failed to update title in Supabase: $e');
      }
    }
  }

  Future<void> toggleConversationPinned(String id) async {
    final c = _conversationsCache[id];
    if (c == null) return;
    final updated = c.copyWith(isPinned: !c.isPinned);
    _conversationsCache[id] = updated;
    if (!isTemporaryConversation(id)) {
      _sharedConversations[id] = updated;
    }
    _bumpConversationListRevision();
    notifyListeners();

    if (!isTemporaryConversation(id)) {
      try {
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null) {
          await SupabaseConfig.client
              .from('conversations')
              .update({'is_pinned': updated.isPinned})
              .eq('id', id);
        }
      } catch (e) {
        debugPrint('Failed to toggle pin in Supabase: $e');
      }
    }
  }

  dynamic get chatRepositoryOrNull => null;

  int resolveMessageCount(String conversationId) {
    return getMessages(conversationId).length;
  }

  Future<List<ChatMessage>> loadSelectedContextMessages(
    String conversationId, {
    int? truncateIndex,
    int? limit,
    String? throughRevisionId,
    bool includeFollowingAssistant = false,
  }) async {
    var msgs = getMessages(conversationId);
    if (throughRevisionId != null) {
      final idx = msgs.indexWhere((m) => m.id == throughRevisionId);
      if (idx >= 0) {
        var end = idx + 1;
        if (includeFollowingAssistant &&
            end < msgs.length &&
            msgs[end].role == 'assistant') {
          end++;
        }
        msgs = msgs.sublist(0, end);
      }
    }
    if (truncateIndex != null &&
        truncateIndex >= 0 &&
        truncateIndex < msgs.length) {
      msgs = msgs.sublist(0, truncateIndex + 1);
    }
    if (limit != null && limit > 0 && msgs.length > limit) {
      msgs = msgs.sublist(msgs.length - limit);
    }
    return msgs;
  }

  Future<void> togglePinConversation(String id) => toggleConversationPinned(id);

  Future<void> updateConversationExtras(
    String id,
    Map<String, dynamic> Function(Map<String, dynamic> extras) updater,
  ) async {
    final c = _conversationsCache[id];
    if (c == null) return;
    final updatedExtras = updater(Map<String, dynamic>.from(c.extras));
    final updated = c.copyWith(extras: updatedExtras);
    _conversationsCache[id] = updated;
    if (!isTemporaryConversation(id)) {
      _sharedConversations[id] = updated;
    }
    _bumpConversationListRevision();
    notifyListeners();

    if (!isTemporaryConversation(id)) {
      try {
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null) {
          await SupabaseConfig.client
              .from('conversations')
              .update({'extras': updatedExtras})
              .eq('id', id);
        }
      } catch (e) {
        debugPrint('Failed to update extras in Supabase: $e');
      }
    }
  }

  Future<bool> _deleteConversationInternal(
    String id, {
    bool notify = true,
  }) async {
    final existedInCache = _conversationsCache.remove(id) != null;
    final existedInShared = _sharedConversations.remove(id) != null;
    _messagesCache.remove(id);
    _sharedMessages.remove(id);
    _temporaryConversations.remove(id);
    if (_currentConversationId == id) {
      _currentConversationId = _conversationsCache.keys.firstOrNull;
    }
    final removed = existedInCache || existedInShared;
    if (removed && notify) {
      _bumpConversationListRevision();
      notifyListeners();
    }

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        await SupabaseConfig.client.from('conversations').delete().eq('id', id);
      }
    } catch (e) {
      debugPrint('Failed to delete conversation from Supabase: $e');
    }
    return removed;
  }

  Future<void> deleteConversation(String id) async {
    await _deleteConversationInternal(id, notify: true);
  }

  Future<Conversation> duplicateConversation(String id) async {
    final c = _conversationsCache[id];
    if (c == null) throw StateError('Conversation not found');
    final copy = await createConversation(
      title: '${c.title} (Copy)',
      assistantId: c.assistantId,
    );
    final msgs = getMessages(id);
    for (final m in msgs) {
      await appendMessageVersion(
        conversationId: copy.id,
        message: m.copyWith(id: const Uuid().v4(), conversationId: copy.id),
      );
    }
    return copy;
  }

  Future<bool> _moveConversationToAssistantInternal({
    required String conversationId,
    required String? assistantId,
    bool notify = true,
  }) async {
    final c = _conversationsCache[conversationId];
    if (c == null) return false;
    if (c.assistantId == assistantId) return true;
    final updated = c.copyWith(assistantId: assistantId);
    _conversationsCache[conversationId] = updated;
    if (!isTemporaryConversation(conversationId)) {
      _sharedConversations[conversationId] = updated;
    }
    if (notify) {
      _bumpConversationListRevision();
      notifyListeners();
    }

    if (!isTemporaryConversation(conversationId)) {
      try {
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null) {
          await SupabaseConfig.client
              .from('conversations')
              .update({
                'assistant_id': assistantId,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', conversationId);
        }
      } catch (e) {
        debugPrint('Failed to move conversation in Supabase: $e');
        return false;
      }
    }
    return true;
  }

  Future<bool> moveConversationToAssistant({
    required String conversationId,
    required String? assistantId,
  }) => _moveConversationToAssistantInternal(
    conversationId: conversationId,
    assistantId: assistantId,
    notify: true,
  );

  Future<int> deleteConversations(Iterable<String> ids) async {
    var count = 0;
    final seen = <String>{};
    for (final id in ids) {
      if (id.isEmpty || !seen.add(id)) continue;
      if (await _deleteConversationInternal(id, notify: false)) {
        count++;
      }
    }
    if (count > 0) {
      _bumpConversationListRevision();
      notifyListeners();
    }
    return count;
  }

  Future<int> moveConversationsToAssistant({
    required Iterable<String> conversationIds,
    required String? assistantId,
  }) async {
    var count = 0;
    final seen = <String>{};
    for (final id in conversationIds) {
      if (id.isEmpty || !seen.add(id)) continue;
      final ok = await _moveConversationToAssistantInternal(
        conversationId: id,
        assistantId: assistantId,
        notify: false,
      );
      if (ok) count++;
    }
    if (count > 0) {
      _bumpConversationListRevision();
      notifyListeners();
    }
    return count;
  }

  Future<void> setConversationsPinned(
    Iterable<String> ids,
    bool isPinned,
  ) async {
    var changed = false;
    final seen = <String>{};
    for (final id in ids) {
      if (id.isEmpty || !seen.add(id)) continue;
      final c = _conversationsCache[id];
      if (c != null && c.isPinned != isPinned) {
        final updated = c.copyWith(isPinned: isPinned);
        _conversationsCache[id] = updated;
        if (!isTemporaryConversation(id)) {
          _sharedConversations[id] = updated;
        }
        changed = true;

        if (!isTemporaryConversation(id)) {
          try {
            final user = SupabaseConfig.client.auth.currentUser;
            if (user != null) {
              await SupabaseConfig.client
                  .from('conversations')
                  .update({'is_pinned': isPinned})
                  .eq('id', id);
            }
          } catch (e) {
            debugPrint('Failed to update pin in Supabase: $e');
          }
        }
      }
    }
    if (changed) {
      _bumpConversationListRevision();
      notifyListeners();
    }
  }

  Future<void> clearConversationSuggestions(String id) async {
    final c = _conversationsCache[id];
    if (c != null) {
      _conversationsCache[id] = c.copyWith(chatSuggestions: const <String>[]);
      notifyListeners();
    }
  }

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
    var cached = _messagesCache[conversationId];
    if (cached == null) {
      try {
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null && !isTemporaryConversation(conversationId)) {
          final res = await SupabaseConfig.client
              .from('messages')
              .select()
              .eq('conversation_id', conversationId)
              .order('message_order', ascending: true);

          cached = [
            for (final row in res as List<dynamic>)
              _mapToChatMessage(row as Map<String, dynamic>),
          ];
          _messagesCache[conversationId] = cached;
        } else {
          cached = _sharedMessages[conversationId] != null
              ? List<ChatMessage>.from(_sharedMessages[conversationId]!)
              : <ChatMessage>[];
          _messagesCache[conversationId] = cached;
        }
      } catch (e) {
        debugPrint('Failed to load messages from Supabase: $e');
        cached = _sharedMessages[conversationId] != null
            ? List<ChatMessage>.from(_sharedMessages[conversationId]!)
            : <ChatMessage>[];
        _messagesCache[conversationId] = cached;
      }
    }

    // Group messages by groupId into logical timeline items
    final versionSelections = getVersionSelections(conversationId);
    final groupOrder = <String>[];
    final groups = <String, List<ChatMessage>>{};
    for (final msg in cached) {
      final gId = msg.groupId ?? msg.id;
      if (groups.putIfAbsent(gId, () => []).isEmpty) {
        groupOrder.add(gId);
      }
      groups[gId]!.add(msg);
    }

    final allSlots = <LoadedTimelineSlot>[];
    for (var i = 0; i < groupOrder.length; i++) {
      final gId = groupOrder[i];
      final gMsgs = groups[gId]!;
      gMsgs.sort((a, b) => a.version.compareTo(b.version));
      final selectedV = versionSelections[gId];
      final selectedMsg = selectedV != null
          ? gMsgs.firstWhere(
              (m) => m.version == selectedV,
              orElse: () => gMsgs.last,
            )
          : gMsgs.last;

      allSlots.add(
        LoadedTimelineSlot(
          identity: ActiveTimelineSlot(
            revisionId: selectedMsg.id,
            groupId: gId,
            version: selectedMsg.version,
            versionCount: gMsgs.length,
            logicalIndex: i,
          ),
          message: selectedMsg,
        ),
      );
    }

    final totalSlots = allSlots.length;
    final effectiveLimit = limit ?? defaultTimelineInitialSlots;

    List<LoadedTimelineSlot> resultSlots;
    bool hasMoreBefore = false;
    bool hasMoreAfter = false;

    if (aroundRevisionId != null) {
      final idx = allSlots.indexWhere(
        (s) =>
            s.identity.revisionId == aroundRevisionId ||
            s.identity.groupId == aroundRevisionId ||
            (groups[s.identity.groupId]?.any((m) => m.id == aroundRevisionId) ??
                false),
      );
      if (idx >= 0) {
        if (effectiveLimit <= 1) {
          resultSlots = [allSlots[idx]];
          hasMoreBefore = idx > 0;
          hasMoreAfter = idx < totalSlots - 1;
        } else {
          final half = effectiveLimit ~/ 2;
          final start = math.max(0, idx - half);
          final end = math.min(totalSlots, start + effectiveLimit);
          resultSlots = allSlots.sublist(start, end);
          hasMoreBefore = start > 0;
          hasMoreAfter = end < totalSlots;
        }
      } else {
        resultSlots = allSlots.take(effectiveLimit).toList();
        hasMoreAfter = totalSlots > resultSlots.length;
      }
    } else if (beforeRevisionId != null) {
      final idx = allSlots.indexWhere(
        (s) =>
            s.identity.revisionId == beforeRevisionId ||
            s.identity.groupId == beforeRevisionId ||
            (groups[s.identity.groupId]?.any((m) => m.id == beforeRevisionId) ??
                false),
      );
      if (idx > 0) {
        final start = math.max(0, idx - effectiveLimit);
        resultSlots = allSlots.sublist(start, idx);
        hasMoreBefore = start > 0;
        hasMoreAfter = idx < totalSlots;
      } else {
        resultSlots = [];
        hasMoreAfter = idx >= 0 && totalSlots > 0;
      }
    } else if (afterRevisionId != null) {
      final idx = allSlots.indexWhere(
        (s) =>
            s.identity.revisionId == afterRevisionId ||
            s.identity.groupId == afterRevisionId ||
            (groups[s.identity.groupId]?.any((m) => m.id == afterRevisionId) ??
                false),
      );
      if (idx >= 0 && idx + 1 < totalSlots) {
        final end = math.min(totalSlots, idx + 1 + effectiveLimit);
        resultSlots = allSlots.sublist(idx + 1, end);
        hasMoreBefore = true;
        hasMoreAfter = end < totalSlots;
      } else {
        resultSlots = [];
        hasMoreBefore = idx >= 0;
      }
    } else if (fromStart) {
      final end = math.min(totalSlots, effectiveLimit);
      resultSlots = allSlots.sublist(0, end);
      hasMoreBefore = false;
      hasMoreAfter = end < totalSlots;
    } else {
      // Default tail window
      final start = math.max(0, totalSlots - effectiveLimit);
      resultSlots = allSlots.sublist(start);
      hasMoreBefore = start > 0;
      hasMoreAfter = false;
    }

    return LoadedTimelinePage(
      conversationId: conversationId,
      stateRevision: 1,
      contextStartRevisionId: allSlots.firstOrNull?.identity.revisionId,
      slots: resultSlots,
      hasMoreBefore: hasMoreBefore,
      hasMoreAfter: hasMoreAfter,
      totalSlotCount: totalSlots,
    );
  }

  Future<List<ChatMessage>> loadSelectedMessageProjections(
    String conversationId,
  ) async {
    final page = await loadTimelinePage(conversationId, limit: 100000);
    return [for (final slot in page.slots) slot.message];
  }

  Future<List<MiniMapSearchHit>> searchMiniMapMatches(
    String conversationId,
    String query,
  ) async {
    final msgs = getMessages(conversationId);
    final hits = <MiniMapSearchHit>[];
    for (final m in msgs) {
      if (m.content.toLowerCase().contains(query.toLowerCase())) {
        hits.add(
          MiniMapSearchHit(
            messageId: m.id,
            matchCount: 1,
            snippet: m.content,
            snippetStart: 0,
          ),
        );
      }
    }
    return hits;
  }

  Future<List<ChatMessage>> loadMessages(
    String conversationId, {
    int? limit,
    int? offset,
    String? throughRevisionId,
    bool includeFollowingAssistant = false,
  }) async {
    var msgs = getMessages(conversationId);
    if (throughRevisionId != null) {
      final idx = msgs.indexWhere((m) => m.id == throughRevisionId);
      if (idx >= 0) {
        var end = idx + 1;
        if (includeFollowingAssistant &&
            end < msgs.length &&
            msgs[end].role == 'assistant') {
          end++;
        }
        msgs = msgs.sublist(0, end);
      }
    }
    if (offset != null && offset > 0) {
      if (offset >= msgs.length) {
        return <ChatMessage>[];
      }
      msgs = msgs.sublist(offset);
    }
    if (limit != null && limit > 0 && msgs.length > limit) {
      msgs = msgs.sublist(0, limit);
    }
    return msgs;
  }

  Future<List<ChatMessage>> loadMessageVersionHeaders(
    String conversationId, [
    Iterable<String>? groupIds,
  ]) async {
    final msgs = getMessages(conversationId);
    final isTemp = isTemporaryConversation(conversationId);
    final set = groupIds?.toSet();
    final filtered = set != null
        ? msgs.where((m) => set.contains(m.groupId ?? m.id))
        : msgs;
    return [
      for (final m in filtered)
        if (isTemp) m else m.copyWith(content: ''),
    ];
  }

  Future<ChatMessage> addMessage({
    required String conversationId,
    required String role,
    String? content,
    List<MessagePart>? parts,
    String? modelId,
    String? providerId,
    bool isStreaming = false,
    String? groupId,
    int? version,
    bool selectVersion = true,
    String? temporaryAfterGroupId,
    DateTime? reasoningStartAt,
    String? reasoningText,
  }) async {
    final effectiveParts = parts ?? [TextPart(content ?? '')];
    final msg = ChatMessage(
      id: const Uuid().v4(),
      role: role,
      parts: effectiveParts,
      timestamp: DateTime.now(),
      conversationId: conversationId,
      groupId: groupId,
      version: version ?? 0,
      isStreaming: isStreaming,
      modelId: modelId,
      providerId: providerId,
      reasoningStartAt: reasoningStartAt,
      reasoningText: reasoningText,
    );
    final added = await appendMessageVersion(
      conversationId: conversationId,
      message: msg,
    );
    if (selectVersion && groupId != null && version != null) {
      await setSelectedVersion(conversationId, groupId, version);
    }
    return added;
  }

  Future<
    ({
      ChatMessage? userMessage,
      ChatMessage assistantMessage,
      ({String id}) run,
    })
  >
  beginSendGeneration({
    required String conversationId,
    required List<MessagePart> userParts,
    required String modelId,
    required String providerId,
    dynamic draftSubmission,
  }) async {
    final userMessage = await addMessage(
      conversationId: conversationId,
      role: 'user',
      parts: userParts,
    );
    final assistantMessage = await addMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerId,
      isStreaming: true,
    );
    return (
      userMessage: userMessage,
      assistantMessage: assistantMessage,
      run: (id: const Uuid().v4()),
    );
  }

  Future<({ChatMessage assistantMessage, ({String id}) run})>
  beginRegeneration({
    required String conversationId,
    required String modelId,
    required String providerId,
    required String groupId,
    required int version,
    required bool truncateFuture,
  }) async {
    final assistantMessage = await addMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerId,
      groupId: groupId,
      version: version,
      isStreaming: true,
    );
    return (assistantMessage: assistantMessage, run: (id: const Uuid().v4()));
  }

  Future<({ChatMessage assistantMessage, ({String id}) run})>
  beginAssistantGeneration({
    required String conversationId,
    required String modelId,
    required String providerId,
    required String anchorGroupId,
    required bool truncateFuture,
  }) async {
    final assistantMessage = await addMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerId,
      isStreaming: true,
    );
    return (assistantMessage: assistantMessage, run: (id: const Uuid().v4()));
  }

  Future<void> setSelectedVersion(
    String conversationId,
    String groupId,
    int version,
  ) async {
    final c = _conversationsCache[conversationId];
    if (c != null) {
      final updatedSelections = Map<String, int>.from(c.versionSelections);
      updatedSelections[groupId] = version;
      _conversationsCache[conversationId] = c.copyWith(
        versionSelections: updatedSelections,
      );
      notifyListeners();
    }
  }

  Future<List<ChatMessage>> loadMessagesByIds(List<String> ids) async {
    final results = <ChatMessage>[];
    final found = <String>{};
    for (final cachedList in _messagesCache.values) {
      for (final msg in cachedList) {
        if (ids.contains(msg.id) && found.add(msg.id)) {
          results.add(msg);
        }
      }
    }
    for (final sharedList in _sharedMessages.values) {
      for (final msg in sharedList) {
        if (ids.contains(msg.id) && found.add(msg.id)) {
          results.add(msg);
        }
      }
    }
    return results;
  }

  Future<ChatMessage> appendMessageVersion({
    String? conversationId,
    ChatMessage? message,
    String? messageId,
    String? content,
    List<MessagePart>? parts,
    dynamic draftSubmission,
    String? targetRevisionId,
    String? expectedParentRevisionId,
  }) async {
    ChatMessage effectiveMessage;
    String effectiveConvId;
    if (message != null) {
      effectiveMessage = message;
      effectiveConvId = conversationId ?? message.conversationId;
    } else if (messageId != null) {
      ChatMessage? existing;
      String? foundConvId;
      for (final entry in _messagesCache.entries) {
        final idx = entry.value.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          existing = entry.value[idx];
          foundConvId = entry.key;
          break;
        }
      }
      effectiveConvId =
          conversationId ?? foundConvId ?? _currentConversationId ?? '';
      final maxV = await getMaxMessageVersionForGroup(
        effectiveConvId,
        existing?.groupId ?? messageId,
      );
      final newId = const Uuid().v4();
      final effectiveParts =
          parts ??
          (content != null
              ? [TextPart(content)]
              : (existing?.parts ?? const <MessagePart>[]));
      effectiveMessage = ChatMessage(
        id: newId,
        conversationId: effectiveConvId,
        groupId: existing?.groupId ?? messageId,
        version: maxV + 1,
        role: existing?.role ?? 'assistant',
        parts: effectiveParts,
        timestamp: DateTime.now().toUtc(),
      );
    } else {
      throw ArgumentError('Either message or messageId must be provided');
    }

    final list = _messagesCache.putIfAbsent(effectiveConvId, () => []);
    list.add(effectiveMessage);
    if (!isTemporaryConversation(effectiveConvId)) {
      _sharedMessages
          .putIfAbsent(effectiveConvId, () => [])
          .add(effectiveMessage);
    }

    final c = _conversationsCache[effectiveConvId];
    if (c != null) {
      _conversationsCache[effectiveConvId] = c.copyWith(
        updatedAt: DateTime.now().toUtc(),
      );
    }
    notifyListeners();

    if (!isTemporaryConversation(effectiveConvId)) {
      try {
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null) {
          final partsJson = [
            for (final part in effectiveMessage.parts)
              {'kind': part.kind, 'payload': part.encodePayload()},
          ];
          await SupabaseConfig.client.from('messages').insert({
            'id': effectiveMessage.id,
            'conversation_id': effectiveConvId,
            'user_id': user.id,
            'role': effectiveMessage.role,
            'content': effectiveMessage.content,
            'parts': partsJson,
            'prompt_tokens': effectiveMessage.promptTokens,
            'completion_tokens': effectiveMessage.completionTokens,
            'total_tokens': effectiveMessage.totalTokens,
            'duration_ms': effectiveMessage.durationMs,
            'message_order': list.length - 1,
            'created_at': effectiveMessage.timestamp.toUtc().toIso8601String(),
          });
          await SupabaseConfig.client
              .from('conversations')
              .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
              .eq('id', effectiveConvId);
        }
      } catch (e) {
        debugPrint('Failed to append message to Supabase: $e');
      }
    }

    return effectiveMessage;
  }

  Future<void> updateMessage(
    String messageId, {
    List<MessagePart>? parts,
    String? content,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
    int? durationMs,
    bool? isStreaming,
    DateTime? reasoningStartAt,
  }) async {
    for (final entry in _messagesCache.entries) {
      final list = entry.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final old = list[idx];
        final updated = old.copyWith(
          parts: parts,
          content: content,
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: totalTokens,
          durationMs: durationMs,
          isStreaming: isStreaming,
          reasoningStartAt: reasoningStartAt,
        );
        list[idx] = updated;
        notifyListeners();

        if (!isTemporaryConversation(entry.key) && isStreaming != true) {
          try {
            final user = SupabaseConfig.client.auth.currentUser;
            if (user != null) {
              final partsJson = [
                for (final part in updated.parts)
                  {'kind': part.kind, 'payload': part.encodePayload()},
              ];
              await SupabaseConfig.client
                  .from('messages')
                  .update({
                    'content': updated.content,
                    'parts': partsJson,
                    'prompt_tokens': updated.promptTokens,
                    'completion_tokens': updated.completionTokens,
                    'total_tokens': updated.totalTokens,
                    'duration_ms': updated.durationMs,
                  })
                  .eq('id', messageId);
            }
          } catch (e) {
            debugPrint('Failed to update message in Supabase: $e');
          }
        }
        break;
      }
    }
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    final list = _messagesCache[conversationId];
    if (list != null) {
      list.removeWhere((m) => m.id == messageId);
      notifyListeners();
    }
    if (!isTemporaryConversation(conversationId)) {
      try {
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null) {
          await SupabaseConfig.client
              .from('messages')
              .delete()
              .eq('id', messageId);
        }
      } catch (e) {
        debugPrint('Failed to delete message in Supabase: $e');
      }
    }
  }

  Future<String> uploadAttachment({
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    final userId = user?.id ?? 'anonymous';
    final storagePath =
        '$userId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    await SupabaseConfig.client.storage
        .from('chat-attachments')
        .uploadBinary(storagePath, bytes);
    return SupabaseConfig.client.storage
        .from('chat-attachments')
        .getPublicUrl(storagePath);
  }

  int getContextStartIndex(String conversationId) => 0;

  Future<String> generateTitleSource(String conversationId) async {
    final msgs = getMessages(conversationId);
    return msgs.map((m) => '${m.role}: ${m.content}').take(4).join('\n');
  }

  Future<void> renameConversation(String conversationId, String newTitle) {
    return updateConversationTitle(conversationId, newTitle);
  }

  Future<void> updateConversationSummary(
    String conversationId,
    String summary,
    int msgCount,
  ) async {
    final c = _conversationsCache[conversationId];
    if (c != null) {
      final updatedExtras = Map<String, dynamic>.from(c.extras);
      updatedExtras['summary'] = summary;
      final updated = c.copyWith(extras: updatedExtras);
      _conversationsCache[conversationId] = updated;
      if (!isTemporaryConversation(conversationId)) {
        _sharedConversations[conversationId] = updated;
      }
      _bumpConversationListRevision();
      notifyListeners();
    }
  }

  Future<void> updateConversationSuggestions(
    String conversationId,
    List<String> suggestions,
  ) async {
    final c = _conversationsCache[conversationId];
    if (c != null) {
      final updated = c.copyWith(chatSuggestions: suggestions);
      _conversationsCache[conversationId] = updated;
      if (!isTemporaryConversation(conversationId)) {
        _sharedConversations[conversationId] = updated;
      }
      _bumpConversationListRevision();
      notifyListeners();
    }
  }

  Future<List<ChatMessage>> loadMessagesForGroups(
    String conversationId,
    Iterable<String> groupIds,
  ) async {
    final set = groupIds.toSet();
    return getMessages(
      conversationId,
    ).where((m) => set.contains(m.groupId ?? m.id)).toList();
  }

  Future<Set<String>> deleteMessages({
    required String conversationId,
    required Iterable<String> messageIds,
    Map<String, dynamic>? versionSelectionChanges,
  }) async {
    final toDelete = messageIds.toSet();
    final list = _messagesCache[conversationId];
    if (list != null) {
      list.removeWhere((m) => toDelete.contains(m.id));
    }
    final shared = _sharedMessages[conversationId];
    if (shared != null) {
      shared.removeWhere((m) => toDelete.contains(m.id));
    }
    if (versionSelectionChanges != null && versionSelectionChanges.isNotEmpty) {
      final c = _conversationsCache[conversationId];
      if (c != null) {
        final updatedSelections = Map<String, int>.from(c.versionSelections);
        for (final entry in versionSelectionChanges.entries) {
          final val = entry.value;
          if (val is int) {
            updatedSelections[entry.key] = val;
          }
        }
        final updatedConv = c.copyWith(versionSelections: updatedSelections);
        _conversationsCache[conversationId] = updatedConv;
        if (!isTemporaryConversation(conversationId)) {
          _sharedConversations[conversationId] = updatedConv;
        }
      }
    }
    notifyListeners();
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        for (final id in toDelete) {
          await SupabaseConfig.client.from('messages').delete().eq('id', id);
        }
      }
    } catch (e) {
      debugPrint('Failed to delete messages from Supabase: $e');
    }
    return toDelete;
  }

  Future<Conversation> forkConversationAtRevision({
    required String sourceConversationId,
    required String sourceRevisionId,
    required String title,
    bool preserveVersions = true,
  }) async {
    final c = await createConversation(title: title);
    final msgs = getMessages(sourceConversationId);
    final idx = msgs.indexWhere((m) => m.id == sourceRevisionId);
    if (idx >= 0) {
      for (final m in msgs.sublist(0, idx + 1)) {
        await appendMessageVersion(
          conversationId: c.id,
          message: m.copyWith(id: const Uuid().v4(), conversationId: c.id),
        );
      }
    }
    return c;
  }

  Future<Conversation> forkConversationFromMessages({
    required String title,
    String? assistantId,
    required List<ChatMessage> sourceMessages,
  }) async {
    final c = await createConversation(title: title, assistantId: assistantId);
    for (final m in sourceMessages) {
      await appendMessageVersion(
        conversationId: c.id,
        message: m.copyWith(id: const Uuid().v4(), conversationId: c.id),
      );
    }
    return c;
  }

  Future<Conversation?> setConversationModel(
    String conversationId, {
    String? providerKey,
    String? modelId,
  }) async {
    return _conversationsCache[conversationId];
  }

  Future<Conversation?> toggleTruncateAtTail(
    String conversationId, {
    String? defaultTitle,
  }) async {
    return _conversationsCache[conversationId];
  }

  String? getProviderArtifactForMessage(ChatMessage message, String kind) =>
      null;
  List<Map<String, dynamic>> getToolEventsForMessage(ChatMessage message) =>
      const <Map<String, dynamic>>[];
  Future<void> upsertToolEvent(
    dynamic messageIdOrEvent, {
    String? id,
    String? name,
    dynamic arguments,
    String? content,
  }) async {}
  void clearConversationModelOverrides({String? providerKey}) {}
  Future<List<String>> loadMessageIdsForGroups(
    String convId,
    Iterable<String> groupIds,
  ) async => [];
  Future<Map<String, String>> resolveImageContentHashes(
    List<String> paths,
  ) async => {};
  Future<Map<String, Map<String, String>>> getImageOcrArtifacts(
    List<String> revIds,
  ) async => {};
  Future<void> upsertImageOcrArtifactItems(
    dynamic revisionId,
    dynamic items,
  ) async {}
  Future<void> restoreConversation(
    Conversation conversation,
    List<ChatMessage> messages,
  ) async {
    _conversationsCache[conversation.id] = conversation;
    _sharedConversations[conversation.id] = conversation;
    _bumpConversationListRevision();
    for (final m in messages) {
      await appendMessageVersion(conversationId: conversation.id, message: m);
    }
  }

  Future<List<ChatMessage>> loadMessagesRange(
    String conversationId, {
    int start = 0,
    int limit = 100,
    bool cacheInTimeline = false,
  }) async {
    return loadMessages(conversationId, limit: limit, offset: start);
  }

  Future<void> finalizeGenerationRunSilent({
    ChatMessage? message,
    List<Map<String, dynamic>>? toolEvents,
    String? generationRunId,
    GenerationRunState? expectedState,
    int? expectedStateRevision,
    GenerationRunState? terminalState,
    int? checkpointSeq,
    String? errorCode,
  }) async {}
  Future<GenerationRun> transitionGenerationRun({
    required String id,
    required GenerationRunState expectedState,
    required int expectedStateRevision,
    required GenerationRunState nextState,
    String? errorCode,
  }) async {
    return GenerationRun(
      id: id,
      conversationId: '',
      targetRevisionId: '',
      state: nextState,
      stateRevision: expectedStateRevision + 1,
      checkpointSeq: 0,
      errorCode: errorCode,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      terminalAt: nextState.isTerminal ? DateTime.now() : null,
    );
  }

  Future<void> updateStreamingCheckpointSilent(
    ChatMessage message,
    List<Map<String, dynamic>> toolEvents, {
    String? generationRunId,
    int? checkpointSeq,
  }) async {}

  Future<void> setProviderArtifact(
    String messageId,
    String kind,
    dynamic data,
  ) async {}

  Future<int> getMaxMessageVersionForGroup(
    String conversationId,
    String groupId,
  ) async {
    final list = _messagesCache[conversationId];
    if (list == null) return 0;
    var maxV = 0;
    for (final m in list) {
      if ((m.groupId ?? m.id) == groupId && m.version > maxV) {
        maxV = m.version;
      }
    }
    return maxV;
  }

  String migrateLegacyGeminiThoughtSignature(String text, String msgId) => text;
}
