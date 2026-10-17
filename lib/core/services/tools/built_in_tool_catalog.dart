import '../workspace/workspace_tools_service.dart';

enum BuiltInToolGroup { search, memory, local, workspace }

class BuiltInToolCatalogEntry {
  const BuiltInToolCatalogEntry({
    required this.name,
    required this.defaultDefinition,
    required this.group,
  });

  final String name;
  final Map<String, dynamic> defaultDefinition;
  final BuiltInToolGroup group;

  String? get defaultDescription {
    final function = defaultDefinition['function'];
    if (function is! Map) return null;
    final desc = function['description'];
    return desc is String ? desc : null;
  }
}

/// Ungated catalog of built-in tool schemas for Build X.
abstract final class BuiltInToolCatalog {
  BuiltInToolCatalog._();

  static List<BuiltInToolCatalogEntry> entries({
    dynamic lang,
    bool legacyMemoryMode = false,
  }) {
    final out = <BuiltInToolCatalogEntry>[];
    for (final definition in WorkspaceToolsService.definitions()) {
      final name = _toolName(definition);
      if (name != null) {
        out.add(
          BuiltInToolCatalogEntry(
            name: name,
            defaultDefinition: definition,
            group: BuiltInToolGroup.workspace,
          ),
        );
      }
    }
    return out;
  }

  static String? _toolName(Map<String, dynamic> def) {
    final function = def['function'];
    if (function is! Map) return null;
    final name = function['name'];
    return name is String ? name : null;
  }
}
