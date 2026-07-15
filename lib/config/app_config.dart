import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Backend configuration for Supabase + Cloudinary, loaded from `.env`
/// (copy `.env.example` to `.env` and fill it in before running):
///  • Supabase   → Project Settings → API  (Project URL + anon/public key)
///  • Cloudinary → Dashboard (Cloud name) and
///                 Settings → Upload → Upload presets → create an UNSIGNED preset
///
/// Until every value is filled in, the app shows a setup screen instead of
/// crashing. See [supabase/schema.sql] for the database tables + RLS policies.
class AppConfig {
  AppConfig._();

  static String _env(String key) => dotenv.maybeGet(key) ?? '';

  // ── Supabase ──────────────────────────────────────────────────────────────
  static String get supabaseUrl => _env('SUPABASE_URL');
  static String get supabaseAnonKey => _env('SUPABASE_ANON_KEY');

  // ── Cloudinary ────────────────────────────────────────────────────────────
  static String get cloudinaryCloudName => _env('CLOUDINARY_CLOUD_NAME');
  static String get cloudinaryUploadPreset => _env('CLOUDINARY_UPLOAD_PRESET');

  /// True once all placeholders above have been replaced with real values.
  static bool get isConfigured =>
      !_isPlaceholder(supabaseUrl) &&
      !_isPlaceholder(supabaseAnonKey) &&
      !_isPlaceholder(cloudinaryCloudName) &&
      !_isPlaceholder(cloudinaryUploadPreset);

  static bool get isCloudinaryConfigured =>
      !_isPlaceholder(cloudinaryCloudName) &&
      !_isPlaceholder(cloudinaryUploadPreset);

  static bool _isPlaceholder(String v) => v.isEmpty || v.startsWith('YOUR_');
}
