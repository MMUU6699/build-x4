import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/workspace/workspace_tools_service.dart';
import 'package:Kelivo/features/home/services/built_in_tool_names.dart';

void main() {
  test('BuiltInToolNames.all contains workspace tool names', () {
    expect(BuiltInToolNames.all, containsAll(WorkspaceToolsService.toolNames));
  });
}
