import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shown when [AppConfig] still has placeholder credentials, so the app gives
/// clear guidance instead of crashing on launch.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 12),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.settings_suggest_outlined,
                color: AppColors.textPrimary,
                size: 28,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Almost there.',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 30,
                  ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Add your backend keys to connect Supabase and Cloudinary.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 28),
            const _Step(
              n: '1',
              title: 'Run the database schema',
              body: 'Open Supabase → SQL Editor and run supabase/schema.sql '
                  '(creates the profiles + projects tables and policies).',
            ),
            const _Step(
              n: '2',
              title: 'Add your Supabase keys',
              body: 'In lib/config/app_config.dart set supabaseUrl and '
                  'supabaseAnonKey from Project Settings → API.',
            ),
            const _Step(
              n: '3',
              title: 'Add your Cloudinary preset',
              body: 'Set cloudinaryCloudName and create an UNSIGNED upload '
                  'preset, then set cloudinaryUploadPreset.',
            ),
            const _Step(
              n: '4',
              title: 'Hot restart',
              body: 'Restart the app — this screen disappears once all four '
                  'values are filled in.',
              last: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String title;
  final String body;
  final bool last;

  const _Step({
    required this.n,
    required this.title,
    required this.body,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                n,
                style: const TextStyle(
                  color: AppColors.onCream,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
