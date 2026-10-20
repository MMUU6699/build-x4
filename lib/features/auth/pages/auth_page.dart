import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/auth/auth_service.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/section_card.dart';

/// Opens the account screen above the current route.
///
/// Returns true only when a real account was signed in.
Future<bool> showAuthPage(
  BuildContext context, {
  bool requireSignedIn = false,
}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) =>
          AuthPage(requireSignedIn: requireSignedIn, popOnSuccess: true),
    ),
  );
  return result == true;
}

enum _AuthMode { signIn, signUp, reset }

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    this.requireSignedIn = false,
    this.popOnSuccess = false,
  });

  /// Work needs a non-anonymous user. When true the guest shortcut is hidden.
  final bool requireSignedIn;

  /// When pushed as a route, return to the caller after a successful sign-in.
  final bool popOnSuccess;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nameController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _isLoading = false;
  String? _errorMessage;
  String? _noticeMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _errorMessage = null;
      _noticeMessage = null;
      _passwordController.clear();
      _confirmController.clear();
    });
  }

  Future<void> _submit() async {
    final auth = context.read<AuthService>();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Enter a valid email address.');
      return;
    }
    if (_mode != _AuthMode.reset && password.isEmpty) {
      setState(() => _errorMessage = 'Enter your password.');
      return;
    }
    if (_mode == _AuthMode.signUp && password.length < 8) {
      setState(
        () => _errorMessage = 'Use at least 8 characters for the password.',
      );
      return;
    }
    if (_mode == _AuthMode.signUp && _confirmController.text != password) {
      setState(() => _errorMessage = 'The passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      switch (_mode) {
        case _AuthMode.signIn:
          await auth.signIn(email: email, password: password);
          await _finishSignedIn();
        case _AuthMode.signUp:
          final result = await auth.signUp(
            email: email,
            password: password,
            displayName: _nameController.text,
          );
          if (result == AuthSignUpResult.needsEmailConfirmation) {
            if (!mounted) return;
            setState(() {
              _mode = _AuthMode.signIn;
              _passwordController.clear();
              _confirmController.clear();
              _noticeMessage =
                  'Check $email to confirm your account, then sign in here.';
            });
          } else {
            await _finishSignedIn();
          }
        case _AuthMode.reset:
          await auth.sendPasswordReset(email);
          if (!mounted) return;
          setState(() {
            _noticeMessage =
                'If an account exists for $email, a password reset email was sent.';
          });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finishSignedIn() async {
    if (!mounted) return;
    if (widget.popOnSuccess && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
      return;
    }
    // The root AuthGate watches AuthService and swaps to the home page.
  }

  Future<void> _continueAsGuest() async {
    if (widget.requireSignedIn) return;
    final auth = context.read<AuthService>();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });
    try {
      await SupabaseConfig.enableGuestMode();
      await auth.refresh();
      if (!mounted) return;
      if (widget.popOnSuccess && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _title {
    switch (_mode) {
      case _AuthMode.signIn:
        return 'Sign in';
      case _AuthMode.signUp:
        return 'Create account';
      case _AuthMode.reset:
        return 'Reset password';
    }
  }

  String get _subtitle {
    if (widget.requireSignedIn) {
      return 'Work needs a real account, so your sandbox, files, and screenshots '
          'belong to you.';
    }
    return 'Sign in to sync chats and use Work. You can also continue as a guest.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            LucideIcons.bot,
                            size: 36,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Build X',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _subtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 26),
                      SectionCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (_mode == _AuthMode.signUp) ...[
                                IosFormTextField(
                                  controller: _nameController,
                                  label: 'Display name (optional)',
                                  hintText: 'Your name',
                                  textCapitalization: TextCapitalization.words,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).nextFocus(),
                                ),
                                const SizedBox(height: 14),
                              ],
                              IosFormTextField(
                                controller: _emailController,
                                label: 'Email',
                                hintText: 'name@example.com',
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) =>
                                    FocusScope.of(context).nextFocus(),
                              ),
                              if (_mode != _AuthMode.reset) ...[
                                const SizedBox(height: 14),
                                IosFormTextField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  hintText: '••••••••',
                                  obscureText: true,
                                  textInputAction: _mode == _AuthMode.signUp
                                      ? TextInputAction.next
                                      : TextInputAction.done,
                                  onSubmitted: _mode == _AuthMode.signIn
                                      ? (_) => _submit()
                                      : null,
                                ),
                              ],
                              if (_mode == _AuthMode.signUp) ...[
                                const SizedBox(height: 14),
                                IosFormTextField(
                                  controller: _confirmController,
                                  label: 'Confirm password',
                                  hintText: '••••••••',
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                ),
                              ],
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: cs.error,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              if (_noticeMessage != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _noticeMessage!,
                                  style: TextStyle(
                                    color: cs.primary,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _isLoading ? null : _submit,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _mode == _AuthMode.reset
                                            ? 'Send reset link'
                                            : (_mode == _AuthMode.signUp
                                                  ? 'Create account'
                                                  : 'Sign in'),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                              if (_mode == _AuthMode.signIn) ...[
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => _setMode(_AuthMode.reset),
                                    child: const Text('Forgot password?'),
                                  ),
                                ),
                              ],
                              if (_mode == _AuthMode.reset) ...[
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.center,
                                  child: TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => _setMode(_AuthMode.signIn),
                                    child: const Text('Back to sign in'),
                                  ),
                                ),
                              ],
                              if (_mode != _AuthMode.reset) ...[
                                const SizedBox(height: 4),
                                TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () => _setMode(
                                          _mode == _AuthMode.signIn
                                              ? _AuthMode.signUp
                                              : _AuthMode.signIn,
                                        ),
                                  child: Text(
                                    _mode == _AuthMode.signIn
                                        ? 'New here? Create an account'
                                        : 'Already have an account? Sign in',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (!widget.requireSignedIn) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _continueAsGuest,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(LucideIcons.user, size: 18),
                          label: const Text('Continue as guest'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Guest chats stay on this device session and cannot '
                          'create a cloud computer.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Text(
                          'Guest sessions cannot open Work. Sign in above to '
                          'continue.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (canPop)
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(LucideIcons.arrowLeft, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
