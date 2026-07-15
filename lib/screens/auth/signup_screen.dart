import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'auth_widgets.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _toast('Fill in your name, email and password.');
      return;
    }
    if (password.length < 6) {
      _toast('Password must be at least 6 characters.');
      return;
    }
    setState(() => _loading = true);
    try {
      final signedIn =
          await SupabaseService.instance.signUp(email, password, name);
      if (!mounted) return;
      if (signedIn) {
        // AuthGate swaps to the app automatically.
        Navigator.of(context).pop();
      } else {
        // Email confirmation is enabled on the project.
        Navigator.of(context).pop();
        _toast('Check your inbox to confirm your email, then sign in.');
      }
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not sign up: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              'Create your account.',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 32,
                  ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Start turning showroom doubts into decisions.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 36),
            AuthField(
              controller: _name,
              label: 'Full name',
              hint: 'Your name',
              icon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 18),
            AuthField(
              controller: _email,
              label: 'Email',
              hint: 'you@studio.com',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 18),
            AuthField(
              controller: _password,
              label: 'Password',
              hint: 'At least 6 characters',
              icon: Icons.lock_outline_rounded,
              obscure: _obscure,
              textInputAction: TextInputAction.done,
              suffix: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: 28),
            AuthButton(
              label: 'Create account',
              loading: _loading,
              onPressed: _signUp,
            ),
          ],
        ),
      ),
    );
  }
}
