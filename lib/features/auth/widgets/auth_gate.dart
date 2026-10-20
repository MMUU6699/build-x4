import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/auth/auth_service.dart';
import '../../../desktop/desktop_home_page.dart';
import '../../../features/home/pages/home_page.dart';
import '../../../shared/responsive/screen_type_helper.dart';
import '../pages/auth_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!auth.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Chat is available to a guest session. Work enforces a real account at
    // its own boundary; the gate only decides whether the app can open.
    final canEnter =
        auth.status != AuthStatus.signedOut || SupabaseConfig.isGuestMode;
    if (!canEnter) {
      return const AuthPage();
    }

    if (ResponsiveHelper.isDesktop(context)) {
      return const DesktopHomePage();
    }
    return const HomePage();
  }
}
