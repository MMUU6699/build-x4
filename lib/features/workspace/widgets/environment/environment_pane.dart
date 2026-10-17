import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:Kelivo/shared/widgets/section_card.dart';

/// Cloud Sandbox info and status pane powered by Daytona.
class EnvironmentPane extends StatelessWidget {
  const EnvironmentPane({super.key, this.padding, this.embedded = false});

  final EdgeInsetsGeometry? padding;
  final bool embedded;

  static const installKey = ValueKey<String>('workspace-env-install-button');
  static const cancelKey = ValueKey<String>('workspace-env-cancel-button');
  static const retryKey = ValueKey<String>('workspace-env-retry-button');
  static const repairKey = ValueKey<String>('workspace-env-repair-button');
  static const resetKey = ValueKey<String>('workspace-env-reset-button');
  static const checkUpdateKey = ValueKey<String>(
    'workspace-env-check-update-button',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: padding ?? const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Daytona Cloud Sandbox',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
          SectionCard(
            children: [
              ListTile(
                leading: Icon(LucideIcons.cloud, color: cs.primary),
                title: const Text('Status: Cloud Sandbox Ready'),
                subtitle: const Text('Isolated microVM powered by Daytona'),
                trailing: const Icon(
                  LucideIcons.checkCircle2,
                  color: Colors.green,
                ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(LucideIcons.cpu),
                title: Text('Execution Engine'),
                subtitle: Text('Daytona API & SDK (Serverless Edge Runtime)'),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(LucideIcons.shieldCheck),
                title: Text('Isolation & Security'),
                subtitle: Text(
                  'Containerized sandbox with zero local host access',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Enabled Capabilities',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
          SectionCard(
            children: const [
              ListTile(
                leading: Icon(LucideIcons.terminal),
                title: Text('Remote Shell & Command Execution'),
                subtitle: Text(
                  'Execute bash commands in Daytona cloud sandbox',
                ),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(LucideIcons.folderGit2),
                title: Text('Cloud Workspace File System'),
                subtitle: Text(
                  'Read, write, edit, and organize project repositories',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
