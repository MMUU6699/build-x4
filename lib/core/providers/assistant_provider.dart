import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/assistant.dart';
import '../services/chat/chat_service.dart';
import '../services/preferences/app_preferences.dart';
import '../../l10n/app_localizations.dart';

class AssistantProvider extends ChangeNotifier {
  static const String _currentAssistantKey = 'current_assistant_id_v1';
  static const String _orphanedAssistantKey =
      'orphaned_conversations_assistant_id_v1';

  final BusinessPreferences _preferences;
  final List<Assistant> _assistants = <Assistant>[];
  String? _currentAssistantId;
  String? _orphanedAssistantId;
  final ChatService? chatService;

  List<Assistant> get assistants => List.unmodifiable(_assistants);
  String? get currentAssistantId => currentAssistant?.id;
  Assistant? get currentAssistant {
    final idx = _assistants.indexWhere((a) => a.id == _currentAssistantId);
    if (idx != -1) return _assistants[idx];
    if (_assistants.isNotEmpty) return _assistants.first;
    return null;
  }

  bool get currentSearchEnabled => false;

  AssistantProvider({
    this.chatService,
    List<Assistant>? initialAssistants,
    BusinessPreferences? preferences,
  }) : _preferences = preferences ?? BusinessPreferences() {
    if (initialAssistants != null) {
      _assistants.addAll(initialAssistants);
    }
    final savedCurrent = _preferences.getString(_currentAssistantKey);
    if (savedCurrent != null && _assistants.any((a) => a.id == savedCurrent)) {
      _currentAssistantId = savedCurrent;
    } else if (_assistants.isNotEmpty) {
      _currentAssistantId = _assistants.first.id;
    }

    final savedOrphaned = _preferences.getString(_orphanedAssistantKey);
    if (savedOrphaned != null &&
        _assistants.any((a) => a.id == savedOrphaned)) {
      _orphanedAssistantId = savedOrphaned;
    } else if (_assistants.isNotEmpty) {
      _orphanedAssistantId = _assistants.first.id;
    }

    loaded = _load();
  }

  late final Future<void> loaded;

  Future<void> _load() async {
    try {
      await _preferences.load();
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        final res = await SupabaseConfig.client
            .from('assistants')
            .select()
            .order('created_at', ascending: true);
        _assistants.clear();
        for (final row in res as List<dynamic>) {
          final map = row as Map<String, dynamic>;
          final settings = map['settings'] is Map
              ? map['settings'] as Map<String, dynamic>
              : <String, dynamic>{};
          _assistants.add(
            Assistant(
              id: map['id'] as String,
              name: map['name'] as String? ?? 'Build X Assistant',
              systemPrompt: map['prompt'] as String? ?? '',
              avatar: map['avatar'] as String?,
              background: map['background'] as String?,
              temperature: (settings['temperature'] as num?)?.toDouble(),
              topP: (settings['topP'] as num?)?.toDouble(),
              maxTokens: (settings['maxTokens'] as num?)?.toInt(),
            ),
          );
        }
      }
      final savedCurrent = _preferences.getString(_currentAssistantKey);
      if (savedCurrent != null &&
          _assistants.any((a) => a.id == savedCurrent)) {
        _currentAssistantId = savedCurrent;
      } else if (_assistants.isNotEmpty && _currentAssistantId == null) {
        _currentAssistantId = _assistants.first.id;
      }

      final savedOrphaned = _preferences.getString(_orphanedAssistantKey);
      if (savedOrphaned != null &&
          _assistants.any((a) => a.id == savedOrphaned)) {
        _orphanedAssistantId = savedOrphaned;
      } else if (_assistants.isNotEmpty && _orphanedAssistantId == null) {
        _orphanedAssistantId = _assistants.first.id;
      }
    } catch (e) {
      debugPrint('Failed to load assistants: $e');
    }
    notifyListeners();
  }

  void ensureDefaults(BuildContext context) {
    if (_assistants.isEmpty) {
      final l10n = AppLocalizations.of(context);
      final defaultName = l10n?.homePageDefaultAssistant ?? 'Build X Assistant';
      final defaultAssistant = Assistant(
        id: const Uuid().v4(),
        name: defaultName,
        systemPrompt:
            'You are Build X, an autonomous cloud AI coding assistant.',
      );
      _assistants.add(defaultAssistant);
      _currentAssistantId = defaultAssistant.id;
      _orphanedAssistantId = defaultAssistant.id;
      _preferences.setString(_currentAssistantKey, defaultAssistant.id);
      _preferences.setString(_orphanedAssistantKey, defaultAssistant.id);
      _persistAssistant(defaultAssistant);
      notifyListeners();
    }
  }

  Future<void> _persistAssistant(Assistant a) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        await SupabaseConfig.client.from('assistants').upsert({
          'id': a.id,
          'user_id': user.id,
          'name': a.name,
          'prompt': a.systemPrompt,
          'avatar': a.avatar,
          'background': a.background,
          'settings': {
            'temperature': a.temperature,
            'topP': a.topP,
            'maxTokens': a.maxTokens,
          },
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Failed to persist assistant: $e');
    }
  }

  Future<void> setCurrentAssistant(String id) async {
    await loaded;
    if (getById(id) == null) return;
    if (_currentAssistantId == id) return;
    _currentAssistantId = id;
    await _preferences.setString(_currentAssistantKey, id);
    notifyListeners();
  }

  Assistant? getById(String id) {
    final idx = _assistants.indexWhere((a) => a.id == id);
    if (idx == -1) return null;
    return _assistants[idx];
  }

  Assistant? resolveConversationAssistant(String? assistantId) {
    if (assistantId == null) return currentAssistant;
    return getById(assistantId) ??
        getById(_orphanedAssistantId ?? '') ??
        _assistants.firstOrNull;
  }

  List<Map<String, String>> getPresetMessagesForAssistant(String? assistantId) {
    return const <Map<String, String>>[];
  }

  Future<String> addAssistant({String? name, BuildContext? context}) async {
    final a = Assistant(
      id: const Uuid().v4(),
      name:
          name ??
          (context != null
              ? AppLocalizations.of(context)!.assistantProviderNewAssistantName
              : 'New Assistant'),
      systemPrompt: '',
    );
    _assistants.add(a);
    if (_orphanedAssistantId == null) {
      _orphanedAssistantId = a.id;
      await _preferences.setString(_orphanedAssistantKey, a.id);
    }
    if (_currentAssistantId == null) {
      _currentAssistantId = a.id;
      await _preferences.setString(_currentAssistantKey, a.id);
    }
    await _persistAssistant(a);
    notifyListeners();
    return a.id;
  }

  Future<void> updateAssistant(Assistant updated) async {
    final idx = _assistants.indexWhere((a) => a.id == updated.id);
    if (idx == -1) return;
    _assistants[idx] = updated;
    await _persistAssistant(updated);
    notifyListeners();
  }

  Future<String?> duplicateAssistant(
    String id, {
    AppLocalizations? l10n,
  }) async {
    final original = getById(id);
    if (original == null) return null;
    final copySuffix = l10n?.assistantSettingsCopySuffix ?? ' (Copy)';
    final newAssistant = original.copyWith(
      id: const Uuid().v4(),
      name: '${original.name}$copySuffix',
    );
    _assistants.add(newAssistant);
    await _persistAssistant(newAssistant);
    notifyListeners();
    return newAssistant.id;
  }

  Future<void> reorderAssistants(dynamic a, [dynamic b]) async {
    if (a is int && b is int) {
      var oldIndex = a;
      var newIndex = b;
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _assistants.removeAt(oldIndex);
      _assistants.insert(newIndex, item);
      notifyListeners();
      return;
    }
    if (a is List<String>) {
      final map = {for (final ast in _assistants) ast.id: ast};
      _assistants.clear();
      for (final id in a) {
        if (map.containsKey(id)) {
          _assistants.add(map[id]!);
        }
      }
      notifyListeners();
    }
  }

  Future<void> reorderAssistantsWithin({
    List<String>? subsetIds,
    int? oldIndex,
    int? newIndex,
    String? tagId,
  }) async {
    final effectiveOld = oldIndex ?? 0;
    final effectiveNew = newIndex ?? 0;
    await reorderAssistants(effectiveOld, effectiveNew);
  }

  Future<bool> deleteAssistant(String id) async {
    final idx = _assistants.indexWhere((a) => a.id == id);
    if (idx == -1) return false;
    if (_assistants.length <= 1) return false;
    _assistants.removeAt(idx);
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        await SupabaseConfig.client.from('assistants').delete().eq('id', id);
      }
    } catch (_) {}
    if (_currentAssistantId == id) {
      _currentAssistantId = _assistants.firstOrNull?.id;
      if (_currentAssistantId != null) {
        await _preferences.setString(
          _currentAssistantKey,
          _currentAssistantId!,
        );
      }
    }
    if (_orphanedAssistantId == id) {
      _orphanedAssistantId = _assistants.firstOrNull?.id;
      if (_orphanedAssistantId != null) {
        await _preferences.setString(
          _orphanedAssistantKey,
          _orphanedAssistantId!,
        );
      }
    }
    notifyListeners();
    return true;
  }

  Future<void> clearModelSelectionsForProvider(String providerKey) async {
    // Model is fixed to mistral-medium-latest
  }

  Future<void> reorderAssistantRegex({
    required String assistantId,
    required int oldIndex,
    required int newIndex,
  }) async {}
}
