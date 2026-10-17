import 'package:flutter/foundation.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import 'draft_token_counter.dart';

enum ContextUsageState { none, computing, exact, estimated, stale }

typedef ContextUsageConfiguration = ({
  Object settings,
  String? memorySnapshotHash,
});

class ContextUsageBuckets {
  const ContextUsageBuckets({
    this.system = 0,
    this.injections = 0,
    this.history = 0,
    this.tools = 0,
    this.attachments = 0,
    this.draft = 0,
    this.memory = 0,
    this.worldBook = 0,
    this.skills = 0,
    this.workspace = 0,
    this.search = 0,
    this.mcpTools = 0,
  });

  final int system;
  final int injections;
  final int history;
  final int tools;
  final int attachments;
  final int draft;
  final int memory;
  final int worldBook;
  final int skills;
  final int workspace;
  final int search;
  final int mcpTools;

  int get nonDraftTotal =>
      system +
      injections +
      history +
      tools +
      attachments +
      memory +
      worldBook +
      skills +
      workspace +
      search +
      mcpTools;

  int get total => nonDraftTotal + draft;

  ContextUsageBuckets copyWith({
    int? system,
    int? injections,
    int? history,
    int? tools,
    int? attachments,
    int? draft,
    int? memory,
    int? worldBook,
    int? skills,
    int? workspace,
    int? search,
    int? mcpTools,
  }) {
    return ContextUsageBuckets(
      system: system ?? this.system,
      injections: injections ?? this.injections,
      history: history ?? this.history,
      tools: tools ?? this.tools,
      attachments: attachments ?? this.attachments,
      draft: draft ?? this.draft,
      memory: memory ?? this.memory,
      worldBook: worldBook ?? this.worldBook,
      skills: skills ?? this.skills,
      workspace: workspace ?? this.workspace,
      search: search ?? this.search,
      mcpTools: mcpTools ?? this.mcpTools,
    );
  }
}

ContextUsageBuckets? calibrateContextUsageBuckets({
  required ContextUsageBuckets estimated,
  required int anchorTotal,
}) {
  if (anchorTotal < 0) return null;
  final nonDraft = estimated.nonDraftTotal;
  if (nonDraft == 0) return null;
  final scale = anchorTotal / nonDraft;
  var s = (estimated.system * scale).round();
  var inj = (estimated.injections * scale).round();
  var h = (estimated.history * scale).round();
  var t = (estimated.tools * scale).round();
  var a = (estimated.attachments * scale).round();
  var m = (estimated.memory * scale).round();
  var wb = (estimated.worldBook * scale).round();
  var sk = (estimated.skills * scale).round();
  var w = (estimated.workspace * scale).round();
  var sr = (estimated.search * scale).round();
  var mcp = (estimated.mcpTools * scale).round();

  var currentSum = s + inj + h + t + a + m + wb + sk + w + sr + mcp;
  var diff = anchorTotal - currentSum;
  if (diff != 0) {
    h = (h + diff).clamp(0, anchorTotal);
    currentSum = s + inj + h + t + a + m + wb + sk + w + sr + mcp;
    diff = anchorTotal - currentSum;
    s = (s + diff).clamp(0, anchorTotal);
  }

  return ContextUsageBuckets(
    system: s,
    injections: inj,
    history: h,
    tools: t,
    attachments: a,
    memory: m,
    worldBook: wb,
    skills: sk,
    workspace: w,
    search: sr,
    mcpTools: mcp,
    draft: estimated.draft,
  );
}

class ContextUsageSnapshot {
  const ContextUsageSnapshot({
    required this.state,
    required this.buckets,
    required this.usedTokens,
    required this.contextWindow,
    required this.conversationId,
    required this.revision,
    required this.providerKey,
    required this.modelId,
    required this.assistantId,
    required this.computedAt,
    this.calibrated = false,
  });

  final ContextUsageState state;
  final ContextUsageBuckets buckets;
  final int usedTokens;
  final int? contextWindow;
  final String conversationId;
  final int revision;
  final String providerKey;
  final String modelId;
  final String? assistantId;
  final DateTime computedAt;
  final bool calibrated;

  double? get ratio {
    final window = contextWindow;
    if (window == null || window <= 0) return null;
    return usedTokens / window;
  }

  ContextUsageSnapshot copyWith({
    ContextUsageState? state,
    ContextUsageBuckets? buckets,
    int? usedTokens,
    int? contextWindow,
    String? conversationId,
    int? revision,
    String? providerKey,
    String? modelId,
    String? assistantId,
    DateTime? computedAt,
    bool? calibrated,
  }) {
    return ContextUsageSnapshot(
      state: state ?? this.state,
      buckets: buckets ?? this.buckets,
      usedTokens: usedTokens ?? this.usedTokens,
      contextWindow: contextWindow ?? this.contextWindow,
      conversationId: conversationId ?? this.conversationId,
      revision: revision ?? this.revision,
      providerKey: providerKey ?? this.providerKey,
      modelId: modelId ?? this.modelId,
      assistantId: assistantId ?? this.assistantId,
      computedAt: computedAt ?? this.computedAt,
      calibrated: calibrated ?? this.calibrated,
    );
  }
}

class ContextUsageService extends ChangeNotifier {
  ContextUsageService({
    required this.chatService,
    required this.settings,
    required this.assistants,
    dynamic instructions,
    dynamic worldBooks,
    dynamic memories,
    dynamic assemble,
    Duration staleRefreshDelay = const Duration(milliseconds: 800),
  }) {
    settings.addListener(_onChanged);
    assistants.addListener(_onChanged);
  }

  final ChatService chatService;
  final SettingsProvider settings;
  final AssistantProvider assistants;

  final Map<String, ContextUsageSnapshot> _snapshots = {};
  final Map<String, DraftTokenCounter> _draftCounters = {};
  String? _activeConversationId;

  String? get activeConversationId => _activeConversationId;

  ContextUsageSnapshot? get current {
    final id = _activeConversationId;
    if (id == null) return null;
    return _snapshots[id];
  }

  ContextUsageSnapshot? snapshot(String conversationId) =>
      _snapshots[conversationId];

  void _onChanged() {
    if (_activeConversationId != null) {
      refresh(_activeConversationId!);
    }
  }

  void updateDraft(String conversationId, String text) {
    _draftCounters
        .putIfAbsent(
          conversationId,
          () => DraftTokenCounter(
            onCountChanged: (count) {
              final existing = _snapshots[conversationId];
              if (existing != null) {
                final newBuckets = existing.buckets.copyWith(draft: count);
                _snapshots[conversationId] = existing.copyWith(
                  buckets: newBuckets,
                  usedTokens: newBuckets.total,
                );
                notifyListeners();
              }
            },
          ),
        )
        .update(text);
  }

  void setActiveConversation(String? conversationId) {
    if (_activeConversationId == conversationId) return;
    _activeConversationId = conversationId;
    if (conversationId != null) {
      refresh(conversationId);
    }
    notifyListeners();
  }

  Future<void> refresh(
    String conversationId, {
    String? draftText,
    bool force = false,
  }) async {
    if (draftText != null) {
      updateDraft(conversationId, draftText);
    }
    final messages = chatService.getMessages(conversationId);
    int historyTokens = 0;
    for (final m in messages) {
      historyTokens += (m.totalTokens ?? (m.content.length ~/ 4));
    }

    final assistant = assistants.currentAssistant;
    final systemTokens = (assistant?.systemPrompt.length ?? 0) ~/ 4;
    final draftTokens = _draftCounters[conversationId]?.tokens ?? 0;

    final buckets = ContextUsageBuckets(
      system: systemTokens,
      history: historyTokens,
      draft: draftTokens,
    );

    _snapshots[conversationId] = ContextUsageSnapshot(
      state: ContextUsageState.exact,
      buckets: buckets,
      usedTokens: buckets.total,
      contextWindow: 32768,
      conversationId: conversationId,
      revision: 1,
      providerKey: 'mistral',
      modelId: 'mistral-medium-latest',
      assistantId: assistant?.id,
      computedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void bindAssembler(dynamic assemble) {}
  Future<void> recordUsage({
    required String conversationId,
    required String providerKey,
    required String modelId,
    String? assistantId,
    dynamic usage,
    dynamic assistantMessage,
    dynamic requestConfiguration,
    dynamic requestRevision,
  }) async {}
  void reset(String conversationId) {
    _snapshots.remove(conversationId);
    _draftCounters.remove(conversationId);
    notifyListeners();
  }

  @override
  void dispose() {
    settings.removeListener(_onChanged);
    assistants.removeListener(_onChanged);
    super.dispose();
  }
}
