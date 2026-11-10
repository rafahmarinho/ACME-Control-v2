/// Compile-time configuration, supplied with
/// `--dart-define-from-file=env/dev.json` (see env/env.example.json).
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon / publishable key (safe to ship in the client).
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Base URL of the ACME Control API on Vercel (no trailing slash).
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3001',
  );

  /// Web URL used in password-recovery emails, e.g. https://acme-control.vercel.app
  static const webAppUrl = String.fromEnvironment('WEB_APP_URL');

  /// Deep link used by the mobile apps for password recovery.
  static const mobileRedirectUrl = 'io.acmecontrol.app://reset-callback';

  /// Optional: pre-fills the password when a demo account chip is tapped.
  static const demoPassword = String.fromEnvironment('DEMO_PASSWORD');

  static const appVersion = '1.0.0';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
