import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../desktop/desktop_home_page.dart';
import '../../../features/home/pages/home_page.dart';
import '../../../shared/responsive/screen_type_helper.dart';
import '../pages/auth_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSubscription;
  bool _isAuthenticated = SupabaseConfig.isAuthenticated;

  @override
  void initState() {
    super.initState();
    _authSubscription = SupabaseConfig.client.auth.onAuthStateChange.listen((
      data,
    ) {
      final session = data.session;
      final authed = session != null || SupabaseConfig.isGuestMode;
      if (authed != _isAuthenticated && mounted) {
        setState(() {
          _isAuthenticated = authed;
        });
      }
    });

    SupabaseConfig.authStateNotifier.addListener(_onAuthStateNotifierChanged);
  }

  void _onAuthStateNotifierChanged() {
    final authed = SupabaseConfig.isAuthenticated;
    if (authed != _isAuthenticated && mounted) {
      setState(() {
        _isAuthenticated = authed;
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    SupabaseConfig.authStateNotifier.removeListener(
      _onAuthStateNotifierChanged,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return const AuthPage();
    }

    if (ResponsiveHelper.isDesktop(context)) {
      return const DesktopHomePage();
    }
    return const HomePage();
  }
}
