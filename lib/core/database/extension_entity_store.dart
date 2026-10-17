import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ExtensionEntity {
  final String id;
  final String kind;
  final Map<String, dynamic> payload;

  const ExtensionEntity({
    required this.id,
    required this.kind,
    required this.payload,
  });
}

class ExtensionEntityStore {
  static const kindSkill = 'skill';

  Future<ExtensionEntity?> get(String kind, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('ext_entity_${kind}_$id');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ExtensionEntity(id: id, kind: kind, payload: json);
    } catch (_) {
      return null;
    }
  }

  Future<List<ExtensionEntity>> listByKind(String kind) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'ext_entity_${kind}_';
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix));
    final result = <ExtensionEntity>[];
    for (final key in keys) {
      final id = key.substring(prefix.length);
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          result.add(ExtensionEntity(id: id, kind: kind, payload: json));
        } catch (_) {}
      }
    }
    return result;
  }

  Future<void> delete(String kind, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ext_entity_${kind}_$id');
  }

  Future<void> upsert(
    String kind,
    String id,
    Map<String, dynamic> payload,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ext_entity_${kind}_$id', jsonEncode(payload));
  }
}
