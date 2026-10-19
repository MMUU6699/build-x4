import 'package:flutter/foundation.dart';
import '../../config/supabase_config.dart';
import '../../../features/work/models/work_tool_event.dart';

class WorkEventPersistenceService {
  const WorkEventPersistenceService();

  Future<void> saveToolEvent(String conversationId, WorkToolEvent event) async {
    if (SupabaseConfig.isUnconfigured) return;
    try {
      final client = SupabaseConfig.client;
      final data = event.toJson();
      data['conversation_id'] = conversationId;

      await client.from('work_tool_events').upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('Failed to save work tool event: $e');
    }
  }

  Future<List<WorkToolEvent>> fetchToolEvents(String conversationId) async {
    if (SupabaseConfig.isUnconfigured) return [];
    try {
      final client = SupabaseConfig.client;
      final response = await client
          .from('work_tool_events')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      return (response as List<dynamic>).map((item) {
        return WorkToolEvent.fromJson(Map<String, dynamic>.from(item as Map));
      }).toList();
    } catch (e) {
      debugPrint('Failed to fetch work tool events: $e');
      return [];
    }
  }

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

  Future<String?> uploadScreenshot({
    required String conversationId,
    required String eventId,
    required Uint8List bytes,
  }) async {
    if (SupabaseConfig.isUnconfigured) return null;
    try {
      final client = SupabaseConfig.client;
      final user = client.auth.currentUser;
      final userId = user?.id ?? 'guest';
      final path = '$userId/$conversationId/$eventId.png';

      await client.storage
          .from('workspace_screenshots')
          .uploadBinary(path, bytes);

      // Create signed URL valid for 7 days
      final signedUrl = await client.storage
          .from('workspace_screenshots')
          .createSignedUrl(path, 60 * 60 * 24 * 7);

      return signedUrl;
    } catch (e) {
      debugPrint('Failed to upload screenshot to Supabase Storage: $e');
      return null;
    }
  }
}
