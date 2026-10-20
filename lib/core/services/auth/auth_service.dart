import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';

enum AuthStatus { signedOut, anonymous, signedIn }

enum AuthSignUpResult { signedIn, needsEmailConfirmation }

/// Single source of truth for the Supabase session and the real profile.
///
/// Chat is allowed for anonymous sessions; Work requires [AuthStatus.signedIn].
class AuthService extends ChangeNotifier {
  AuthService() {
    _subscription = SupabaseConfig.client.auth.onAuthStateChange.listen((_) {
      unawaited(_refresh());
    });
    unawaited(_refresh());
  }

  StreamSubscription<AuthState>? _subscription;
  AuthStatus _status = AuthStatus.signedOut;
  User? _user;
  String? _displayName;
  String? _avatarUrl;
  bool _initialized = false;

  AuthStatus get status => _status;
  User? get user => _user;
  bool get initialized => _initialized;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  bool get isAnonymous => _status == AuthStatus.anonymous;
  bool get isSignedOut => _status == AuthStatus.signedOut;

  String get email => _user?.email?.trim() ?? '';

  String get displayName {
    if (isAnonymous) return 'Guest';
    if (isSignedOut) return '';
    final explicit = _displayName?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final meta = _user?.userMetadata;
    final metaName = (meta?['full_name'] ?? meta?['name'])?.toString().trim();
    if (metaName != null && metaName.isNotEmpty) return metaName;
    final local = email.split('@').first.trim();
    return local.isEmpty ? 'Account' : local;
  }

  String get avatarUrl => _avatarUrl?.trim() ?? '';

  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return _firstLetter(parts.first);
    return '${_firstLetter(parts.first)}${_firstLetter(parts.last)}';
  }

  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    final user = SupabaseConfig.client.auth.currentUser;
    _user = user;
    if (user == null) {
      _status = AuthStatus.signedOut;
      _displayName = null;
      _avatarUrl = null;
    } else if (user.isAnonymous) {
      _status = AuthStatus.anonymous;
      _displayName = null;
      _avatarUrl = null;
    } else {
      _status = AuthStatus.signedIn;
      await _loadProfile();
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    final user = _user;
    if (user == null || user.isAnonymous) return;
    try {
      final row = await SupabaseConfig.client
          .from('profiles')
          .select('display_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      _displayName = row?['display_name'] as String?;
      _avatarUrl = row?['avatar_url'] as String?;
    } catch (e) {
      debugPrint('[AuthService] profile load failed: $e');
    }
  }

  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    _ensureConfigured();
    final res = await SupabaseConfig.client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        if (displayName.trim().isNotEmpty) 'full_name': displayName.trim(),
      },
    );
    if (res.user == null) {
      throw const AuthException('Sign-up did not create a user.');
    }
    if (res.session == null) return AuthSignUpResult.needsEmailConfirmation;
    await SupabaseConfig.disableGuestMode();
    await _ensureProfile(displayName);
    await _refresh();
    return AuthSignUpResult.signedIn;
  }

  Future<void> signIn({required String email, required String password}) async {
    _ensureConfigured();
    await SupabaseConfig.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await SupabaseConfig.disableGuestMode();
    await _ensureProfile('');
    await _refresh();
  }

  Future<void> sendPasswordReset(String email) async {
    _ensureConfigured();
    await SupabaseConfig.client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> updateDisplayName(String name) async {
    final user = _user;
    if (user == null || user.isAnonymous) {
      throw const AuthException('Sign in with a real account first.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const AuthException('Display name cannot be empty.');
    }
    await SupabaseConfig.client.auth.updateUser(
      UserAttributes(data: {'full_name': trimmed}),
    );
    await SupabaseConfig.client.from('profiles').upsert({
      'id': user.id,
      'display_name': trimmed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
    _displayName = trimmed;
    notifyListeners();
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _ensureConfigured();
    if (newPassword.length < 8) {
      throw const AuthException('Use at least 8 characters for the password.');
    }
    final user = _user;
    if (user == null || user.isAnonymous) {
      throw const AuthException('Sign in with a real account first.');
    }
    if (email.isNotEmpty && currentPassword.isNotEmpty) {
      await SupabaseConfig.client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    }
    await SupabaseConfig.client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  Future<void> signOut() async {
    await SupabaseConfig.client.auth.signOut();
    await SupabaseConfig.disableGuestMode();
    await _refresh();
  }

  Future<void> _ensureProfile(String displayName) async {
    final user = _user;
    if (user == null || user.isAnonymous) return;
    final explicit = displayName.trim();
    final meta = user.userMetadata;
    final metaName = (meta?['full_name'] ?? meta?['name'])?.toString().trim();
    final fallback = email.split('@').first.trim();
    final name = explicit.isNotEmpty
        ? explicit
        : (metaName != null && metaName.isNotEmpty
              ? metaName
              : (fallback.isEmpty ? 'User' : fallback));
    try {
      await SupabaseConfig.client.from('profiles').upsert({
        'id': user.id,
        'display_name': name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id');
      _displayName = name;
    } catch (e) {
      // Auth still succeeded; the profile page falls back to the auth email.
      debugPrint('[AuthService] profile upsert failed: $e');
    }
  }

  void _ensureConfigured() {
    if (SupabaseConfig.isUnconfigured) {
      throw const AuthException(
        'Supabase is not configured in this build. Add SUPABASE_URL and '
        'SUPABASE_ANON_KEY before signing in.',
      );
    }
  }

  static String _firstLetter(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '' : trimmed.substring(0, 1).toUpperCase();
  }

  static String friendlyError(Object error) {
    if (error is AuthException) {
      final code = error.code?.toLowerCase() ?? '';
      final message = error.message.toLowerCase();
      if (code == 'invalid_credentials' || message.contains('invalid login')) {
        return 'Email or password is incorrect.';
      }
      if (code == 'email_not_confirmed' || message.contains('not confirmed')) {
        return 'Confirm your email before signing in. Check your inbox.';
      }
      if (code == 'user_already_exists' ||
          code == 'email_exists' ||
          message.contains('already registered')) {
        return 'An account with this email already exists. Sign in instead.';
      }
      if (code == 'weak_password' || message.contains('password should be')) {
        return 'Choose a stronger password (at least 8 characters).';
      }
      if (code.contains('rate_limit') || message.contains('rate limit')) {
        return 'Too many attempts. Wait a few minutes and try again.';
      }
      if (code == 'signup_disabled') {
        return 'New sign-ups are disabled for this project.';
      }
      if (code == 'anonymous_provider_disabled') {
        return 'Guest mode is disabled for this project.';
      }
      return error.message;
    }
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('ClientException')) {
      return 'Cannot reach the server. Check your connection and try again.';
    }
    return 'Something went wrong. Try again.';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
