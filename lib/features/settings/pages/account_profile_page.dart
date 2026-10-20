import 'package:flutter/material.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:provider/provider.dart';

import '../../../core/services/auth/auth_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../auth/pages/auth_page.dart';

class AccountProfilePage extends StatefulWidget {
  const AccountProfilePage({super.key});

  @override
  State<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _nameInitialized = false;
  bool _savingName = false;
  bool _changingPassword = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_nameInitialized) return;
    final auth = context.read<AuthService>();
    if (auth.isSignedIn) {
      _nameController.text = auth.displayName;
      _emailController.text = auth.email;
      _nameInitialized = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final auth = context.read<AuthService>();
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showAppSnackBar(
        context,
        message: 'Display name cannot be empty.',
        type: NotificationType.warning,
      );
      return;
    }
    setState(() => _savingName = true);
    try {
      await auth.updateDisplayName(name);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: 'Display name saved.',
        type: NotificationType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: AuthService.friendlyError(e),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changePassword() async {
    final auth = context.read<AuthService>();
    final current = _currentPasswordController.text;
    final next = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (current.isEmpty || next.isEmpty) {
      showAppSnackBar(
        context,
        message: 'Enter your current and new password.',
        type: NotificationType.warning,
      );
      return;
    }
    if (next.length < 8) {
      showAppSnackBar(
        context,
        message: 'Use at least 8 characters for the new password.',
        type: NotificationType.warning,
      );
      return;
    }
    if (next != confirm) {
      showAppSnackBar(
        context,
        message: 'The new passwords do not match.',
        type: NotificationType.warning,
      );
      return;
    }
    setState(() => _changingPassword = true);
    try {
      await auth.updatePassword(currentPassword: current, newPassword: next);
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      showAppSnackBar(
        context,
        message: 'Password updated.',
        type: NotificationType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: AuthService.friendlyError(e),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Chat history stays in your account. You can sign in again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final auth = context.read<AuthService>();
    await auth.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          size: 20,
          onTap: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Account',
          style: TextStyle(fontSize: 17, fontWeight: AppFontWeights.semibold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: !auth.isSignedIn
                  ? _SignedOutCard(auth: auth)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionCard(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                _Avatar(auth: auth),
                                const SizedBox(height: 14),
                                Text(
                                  auth.displayName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  auth.email.isEmpty ? 'Signed in' : auth.email,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SectionCard(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Profile',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                IosFormTextField(
                                  controller: _nameController,
                                  label: 'Display name',
                                  hintText: 'Your name',
                                  textCapitalization: TextCapitalization.words,
                                  onSubmitted: (_) => _saveName(),
                                ),
                                const SizedBox(height: 14),
                                IosFormTextField(
                                  controller: _emailController,
                                  label: 'Email',
                                  enabled: false,
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _savingName ? null : _saveName,
                                  child: _savingName
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Save display name'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SectionCard(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Change password',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                IosFormTextField(
                                  controller: _currentPasswordController,
                                  label: 'Current password',
                                  obscureText: true,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 14),
                                IosFormTextField(
                                  controller: _newPasswordController,
                                  label: 'New password',
                                  obscureText: true,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 14),
                                IosFormTextField(
                                  controller: _confirmPasswordController,
                                  label: 'Confirm new password',
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _changePassword(),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton(
                                  onPressed: _changingPassword
                                      ? null
                                      : _changePassword,
                                  child: _changingPassword
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Update password'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: _signOut,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.error,
                            side: BorderSide(
                              color: cs.error.withValues(alpha: 0.35),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          icon: const Icon(Lucide.Power, size: 18),
                          label: const Text('Sign out'),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (auth.avatarUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          auth.avatarUrl,
          width: 84,
          height: 84,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialAvatar(cs),
        ),
      );
    }
    return _initialAvatar(cs);
  }

  Widget _initialAvatar(ColorScheme cs) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primary.withValues(alpha: 0.12),
      ),
      alignment: Alignment.center,
      child: Text(
        auth.initials,
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _SignedOutCard extends StatelessWidget {
  const _SignedOutCard({required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Lucide.User, size: 36, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              auth.isAnonymous
                  ? 'You are using a guest session'
                  : 'You are signed out',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sign in with a real account to sync your profile and use Work.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => showAuthPage(context, requireSignedIn: true),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
