/// Compile-time configuration, supplied via --dart-define.
///
/// Example:
///   flutter run -d chrome \
///     --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
