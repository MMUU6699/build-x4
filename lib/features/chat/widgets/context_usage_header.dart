import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/chat/chat_service.dart';
import '../../../features/home/services/context_usage_service.dart';
import '../../../shared/widgets/context_usage_details.dart';

class ContextUsageHeader extends StatefulWidget {
  const ContextUsageHeader({
    super.key,
    this.conversationId,
    this.draftText = '',
  });

  final String? conversationId;
  final String draftText;

  @override
  State<ContextUsageHeader> createState() => _ContextUsageHeaderState();
}

class _ContextUsageHeaderState extends State<ContextUsageHeader> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh(force: false);
    });
  }

  String? get _conversationId {
    final explicit = widget.conversationId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return context.read<ChatService?>()?.currentConversationId;
  }

  Future<void> _refresh({required bool force}) async {
    final id = _conversationId;
    final usage = context.read<ContextUsageService?>();
    if (id == null || usage == null) return;
    await usage.refresh(
      id,
      draftText: force ? null : widget.draftText,
      force: force,
    );
  }

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<ContextUsageService?>();
    final id = _conversationId;
    final snapshot = id == null
        ? usage?.current
        : usage?.snapshot(id) ?? usage?.current;

    return Column(
      key: const ValueKey('context-usage-header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [ContextUsageBreakdown(snapshot: snapshot)],
    );
  }
}
