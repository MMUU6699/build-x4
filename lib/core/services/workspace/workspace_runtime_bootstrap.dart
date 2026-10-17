import 'dart:async';
import 'daytona_workspace_runtime.dart';
import 'workspace_runtime.dart';

class WorkspaceStack {
  const WorkspaceStack({this.runtime});

  final WorkspaceRuntime? runtime;
}

/// Builds the process-wide workspace stack using Daytona across all platforms.
Future<WorkspaceStack> createWorkspaceStack() async {
  return WorkspaceStack(runtime: DaytonaWorkspaceRuntime());
}

/// Registers [stack.runtime] when present and refreshes provider status.
void applyWorkspaceStack(
  WorkspaceRuntimeProvider provider,
  WorkspaceStack stack,
) {
  final runtime = stack.runtime;
  if (runtime != null) {
    provider.register(runtime);
  }
}
