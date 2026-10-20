import 'package:flutter/foundation.dart';
import '../../config/supabase_config.dart';
import '../../../features/work/models/work_turn.dart';

class WorkEventPersistenceService {
  const WorkEventPersistenceService();

  Future<void> recordIntegrationStatus({
    required String provider,
    required String status,
    String? details,
  }) async {
    if (SupabaseConfig.isUnconfigured) return;
    try {
      final client = SupabaseConfig.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      await client.from('integrations').upsert({
        'user_id': user.id,
        'provider': provider,
        'status': status,
        'details': details ?? '',
        'last_checked_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,provider');
    } catch (e) {
      debugPrint('Failed to record integration status for $provider: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchIntegrationStatus(String provider) async {
    if (SupabaseConfig.isUnconfigured) return null;
    try {
      final client = SupabaseConfig.client;
      final user = client.auth.currentUser;
      if (user != null) {
        final res = await client
            .from('integrations')
            .select()
            .eq('user_id', user.id)
            .eq('provider', provider)
            .maybeSingle();
        if (res != null) return Map<String, dynamic>.from(res);
      }

      final globalRes = await client
          .from('integrations')
          .select()
          .isFilter('user_id', null)
          .eq('provider', provider)
          .maybeSingle();

      return globalRes != null ? Map<String, dynamic>.from(globalRes) : null;
    } catch (e) {
      debugPrint('Failed to fetch integration status for $provider: $e');
      return null;
    }
  }

  Future<List<WorkTurn>> fetchWorkTurns(String conversationId) async {
    if (SupabaseConfig.isUnconfigured) return [];
    try {
      final client = SupabaseConfig.client;
      final user = client.auth.currentUser;
      if (user == null) return [];
      final rows = await client
          .from('work_turns')
          .select()
          .eq('conversation_id', conversationId)
          .eq('user_id', user.id)
          .order('started_at', ascending: true);
      return (rows as List<dynamic>)
          .map(
            (row) => WorkTurn.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
    } catch (e) {
      debugPrint('Failed to fetch work turns: $e');
      return [];
    }
  }

  Future<void> saveWorkTurn(WorkTurn turn) async {
    if (SupabaseConfig.isUnconfigured) return;
    try {
      final client = SupabaseConfig.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      final data = turn.toJson();
      data['user_id'] = user.id;
      await client.from('work_turns').upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('Failed to save work turn: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadAgentHistory(
    String conversationId,
  ) async {
    if (SupabaseConfig.isUnconfigured) return [];
    try {
      final client = SupabaseConfig.client;
      final user = client.auth.currentUser;
      if (user == null) return [];
      final row = await client
          .from('work_agent_messages')
          .select('messages')
          .eq('conversation_id', conversationId)
          .eq('user_id', user.id)
          .maybeSingle();
      final raw = row?['messages'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    } catch (e) {
      debugPrint('Failed to load agent history: $e');
    }
    return [];
  }

  Future<void> saveAgentHistory(
    String conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    if (SupabaseConfig.isUnconfigured) return;
    try {
      final client = SupabaseConfig.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      await client.from('work_agent_messages').upsert({
        'conversation_id': conversationId,
        'user_id': user.id,
        'messages': messages,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'conversation_id');
    } catch (e) {
      debugPrint('Failed to save agent history: $e');
    }
  }

  Future<String?> createScreenshotUrl(String path) async {
    if (SupabaseConfig.isUnconfigured || path.isEmpty) return null;
    try {
      return await SupabaseConfig.client.storage
          .from('workspace_screenshots')
          .createSignedUrl(path, 3600);
    } catch (e) {
      debugPrint('Failed to sign screenshot path: $e');
      return null;
    }
  }

  Future<void> updateWorkSession({
    required String conversationId,
    String? workspaceId,
    required String phase,
    DateTime? startedAt,
    DateTime? endedAt,
  }) async {
    if (SupabaseConfig.isUnconfigured) return;
    try {
      final client = SupabaseConfig.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      final payload = <String, dynamic>{
        'conversation_id': conversationId,
        'user_id': user.id,
        'phase': phase,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (workspaceId != null) {
        payload['workspace_id'] = workspaceId;
      }
      if (startedAt != null) {
        payload['started_at'] = startedAt.toIso8601String();
      }
      if (endedAt != null) {
        payload['ended_at'] = endedAt.toIso8601String();
      }

      await client
          .from('work_sessions')
          .upsert(payload, onConflict: 'conversation_id');
    } catch (e) {
      debugPrint('Failed to update work session: $e');
    }
  }
}
