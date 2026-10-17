import 'package:flutter/material.dart';

/// Cloud sandbox status chip (always ready in Daytona cloud mode).
class EnvironmentStatusChip extends StatelessWidget {
  const EnvironmentStatusChip({super.key, this.onTap});

  static const chipKey = ValueKey<String>('workspace-env-status-chip');
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
