import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../utils/app_directories.dart';
import '../config/supabase_config.dart';
import '../models/workspace.dart';
import 'assistant_provider.dart';

class WorkspaceProvider extends ChangeNotifier {
  WorkspaceProvider({this.assistants}) {
    loaded = _load();
  }

  final AssistantProvider? assistants;
  final List<Workspace> _workspaces = <Workspace>[];

  late final Future<void> loaded;

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);

  Workspace? byId(String id) {
    for (final workspace in _workspaces) {
      if (workspace.id == id) return workspace;
    }
    return null;
  }

  Future<void> _load() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        final res = await SupabaseConfig.client
            .from('workspaces')
            .select()
            .order('created_at', ascending: true);
        _workspaces.clear();
        for (final row in res as List<dynamic>) {
          final map = row as Map<String, dynamic>;
          _workspaces.add(
            Workspace(
              id: map['id'] as String,
              name: map['name'] as String,
              kind: WorkspaceKind.values.firstWhere(
                (k) => k.name == map['kind'],
                orElse: () => WorkspaceKind.managed,
              ),
              hostPath: map['host_path'] as String?,
              lastUsedAt: map['last_used_at'] != null
                  ? DateTime.tryParse(map['last_used_at'] as String)
                  : null,
              createdAt:
                  DateTime.tryParse(map['created_at'] as String? ?? '') ??
                  DateTime.now(),
              updatedAt:
                  DateTime.tryParse(map['updated_at'] as String? ?? '') ??
                  DateTime.now(),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to load workspaces from Supabase: $e');
    }
    notifyListeners();
  }

  Future<Workspace> create({
    required String name,
    WorkspaceKind kind = WorkspaceKind.managed,
    String? hostPath,
  }) async {
    await loaded;
    final now = DateTime.now().toUtc();
    final workspace = Workspace(
      id: const Uuid().v4(),
      name: name,
      kind: kind,
      hostPath: kind == WorkspaceKind.linked ? hostPath : null,
      createdAt: now,
      updatedAt: now,
    );
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        await SupabaseConfig.client.from('workspaces').insert({
          'id': workspace.id,
          'user_id': user.id,
          'name': workspace.name,
          'kind': workspace.kind.name,
          'host_path': workspace.hostPath,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Failed to create workspace in Supabase: $e');
    }
    _workspaces.add(workspace);
    notifyListeners();
    return workspace;
  }

  Future<void> update(Workspace workspace) async {
    await loaded;
    final next = workspace.copyWith(updatedAt: DateTime.now().toUtc());
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        await SupabaseConfig.client
            .from('workspaces')
            .update({
              'name': next.name,
              'kind': next.kind.name,
              'host_path': next.hostPath,
              'last_used_at': next.lastUsedAt?.toIso8601String(),
              'updated_at': next.updatedAt.toIso8601String(),
            })
            .eq('id', next.id);
      }
    } catch (e) {
      debugPrint('Failed to update workspace in Supabase: $e');
    }
    final index = _workspaces.indexWhere((item) => item.id == next.id);
    if (index >= 0) {
      _workspaces[index] = next;
    } else {
      _workspaces.add(next);
    }
    notifyListeners();
  }

  Future<void> delete(String id, {bool deleteFiles = true}) async {
    await loaded;
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        await SupabaseConfig.client.from('workspaces').delete().eq('id', id);
      }
    } catch (e) {
      debugPrint('Failed to delete workspace in Supabase: $e');
    }
    _workspaces.removeWhere((workspace) => workspace.id == id);
    notifyListeners();
  }

  Future<void> touchLastUsed(String id) async {
    await loaded;
    final existing = byId(id);
    if (existing == null) return;
    await update(existing.copyWith(lastUsedAt: DateTime.now().toUtc()));
  }

  Future<String> hostRootFor(Workspace workspace) async {
    if (workspace.kind == WorkspaceKind.linked) {
      final path = workspace.hostPath;
      if (path == null || path.isEmpty) {
        throw StateError('linked workspace missing hostPath');
      }
      return path;
    }
    final dir = await AppDirectories.workspaceFilesDir(workspace.id);
    return dir.path;
  }
}
