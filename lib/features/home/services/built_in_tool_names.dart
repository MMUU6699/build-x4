import '../../../core/services/workspace/workspace_tools_service.dart';

/// Client-side built-in function names that tools must not collide with.
abstract final class BuiltInToolNames {
  static Set<String> get all => {...WorkspaceToolsService.toolNames};
}
