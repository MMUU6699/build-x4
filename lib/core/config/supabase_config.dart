import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();

  static const String _guestModeKey = 'build_x_guest_bypass_v1';
  static final ValueNotifier<bool> authStateNotifier = ValueNotifier<bool>(
    false,
  );

  static bool _guestMode = false;
  static bool get isGuestMode => _guestMode;

  static bool get isUnconfigured =>
      supabaseUrl.contains('your-project.supabase.co') ||
      supabaseAnonKey.contains('your-anon-key');

  static Future<void> enableGuestMode() async {
    _guestMode = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_guestModeKey, true);
    } catch (_) {}
    if (!isUnconfigured && client.auth.currentSession == null) {
      try {
        await client.auth.signInAnonymously();
      } catch (e) {
        debugPrint('[SupabaseConfig] Anonymous sign in error: $e');
      }
    }
    authStateNotifier.value = true;
  }

  static Future<void> disableGuestMode() async {
    _guestMode = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_guestModeKey);
    } catch (_) {}
    authStateNotifier.value = isAuthenticated;
  }

  static Future<void> loadSavedGuestMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _guestMode = prefs.getBool(_guestModeKey) ?? false;
    } catch (_) {}
    if (_guestMode && !isUnconfigured && client.auth.currentSession == null) {
      try {
        await client.auth.signInAnonymously();
      } catch (e) {
        debugPrint('[SupabaseConfig] Anonymous sign in on load error: $e');
      }
    }
    authStateNotifier.value = isAuthenticated;
  }

  static Future<String?> ensureValidToken() async {
    if (isUnconfigured) return null;
    if (client.auth.currentSession == null) {
      try {
        await client.auth.signInAnonymously();
      } catch (e) {
        debugPrint('[SupabaseConfig] Anonymous sign in failed: $e');
      }
    }
    return client.auth.currentSession?.accessToken;
  }

  // Supabase URL & Anon Key with fallback constants or environment overrides.
  static const String defaultUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://owgpuolvfqfjhezuohyf.supabase.co',
  );

  static const String defaultAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im93Z3B1b2x2ZnFmamhlenVvaHlmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIzMjAwMTMsImV4cCI6MjEwNzg5NjAxM30.99gurLpTbQOPOpEds6EUd0m4Vc0GuodloO-GVbIW0DM',
  );

  static String get supabaseUrl => defaultUrl;
  static String get supabaseAnonKey => defaultAnonKey;

  static SupabaseClient? _mockClient;

  static void setMockClient(SupabaseClient? mock) {
    _mockClient = mock;
  }

  static SupabaseClient get client {
    if (_mockClient != null) return _mockClient!;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return _mockClient ??= SupabaseClient(
        supabaseUrl,
        supabaseAnonKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
    }
  }

  static User? get currentUser => client.auth.currentUser;

  static Session? get currentSession => client.auth.currentSession;

  static bool get isAuthenticated => _guestMode || currentSession != null;
}
