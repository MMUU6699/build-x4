import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/workspace_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../core/services/workspace/tool_run_registry.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../core/services/workspace/workspace_tools_service.dart';
import 'ask_user_interaction_service.dart';
import 'tool_approval_service.dart';

class McpToolRouteSnapshot {
  const McpToolRouteSnapshot();
  bool containsExposedName(String name) => false;
}

class ToolHandlerService {
  ToolHandlerService({required this.contextProvider});

  final BuildContext contextProvider;

  WorkspaceToolsService _workspaceTools() {
    try {
      final chat = contextProvider.read<ChatService>();
      final workspaces = contextProvider.read<WorkspaceProvider>();
      Future<void> Function(String skillId)? onSkillRead;
      Future<void> Function()? onShellCompleted;
      try {
        final skills = contextProvider.read<SkillsService>();
        onSkillRead = skills.incrementUseCount;
        onShellCompleted = skills.rescan;
      } catch (_) {}
      return WorkspaceToolsService(
        registry: contextProvider.read<ToolRunRegistry>(),
        runtimeProvider: contextProvider.read<WorkspaceRuntimeProvider>(),
        updateConversationExtras: chat.updateConversationExtras,
        touchLastUsed: workspaces.touchLastUsed,
        onSkillRead: onSkillRead,
        onShellCompleted: onShellCompleted,
        isToolEnabled: (id, name) =>
            workspaces.byId(id)?.isToolEnabled(name) ?? false,
      );
    } catch (_) {
      return WorkspaceToolsService();
    }
  }

  McpToolRouteSnapshot captureMcpToolRoutes(Assistant? assistant) =>
      const McpToolRouteSnapshot();

  List<Map<String, dynamic>> buildToolDefinitions(
    SettingsProvider settings,
    Assistant? assistant,
    String providerKey,
    String modelId,
    bool hasBuiltInSearch, {
    McpToolRouteSnapshot? mcpRouteSnapshot,
    WorkspaceToolContext? workspaceContext,
    String? conversationId,
  }) {
    if (workspaceContext == null) return const [];
    return _workspaceTools().buildToolDefinitions(workspaceContext);
  }

  ToolCallHandler? buildToolCallHandler(
    SettingsProvider settings,
    Assistant? assistant, {
    ToolApprovalService? approvalService,
    AskUserInteractionService? askUserService,
    String? conversationId,
    McpToolRouteSnapshot? mcpRouteSnapshot,
    WorkspaceToolContext? workspaceContext,
  }) {
    if (workspaceContext == null) return null;
    final workspaceTools = _workspaceTools();

    return (name, args, {toolCallId}) async {
      try {
        if (WorkspaceToolsService.toolNames.contains(name)) {
          return await workspaceTools.handle(
            workspaceContext,
            name,
            args,
            toolCallId: toolCallId ?? '',
            approvalService: approvalService,
            conversationId: conversationId,
          );
        }
        return {'error': 'Unknown tool: $name'};
      } catch (e) {
        return {'error': e.toString()};
      }
    };
  }
}
