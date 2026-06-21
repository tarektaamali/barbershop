import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  assert(
    Env.isConfigured,
    'Missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY. Pass them with --dart-define.',
  );

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );

  runApp(const ProviderScope(child: App()));
}
