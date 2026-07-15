import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../main_shell.dart';
import 'login_screen.dart';

/// Shows the app when a session exists, otherwise the login flow.
/// Rebuilds automatically on sign in / sign out.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: SupabaseService.instance.authChanges,
      builder: (context, _) {
        final session = SupabaseService.instance.currentSession;
        if (session != null) return const MainShell();
        return const LoginScreen();
      },
    );
  }
}
