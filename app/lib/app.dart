import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/auth_repository.dart';
import 'data/services/core_providers.dart';

class AcmeControlApp extends StatelessWidget {
  const AcmeControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Env.isConfigured) {
      return MaterialApp(
        title: 'ACME Control',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const _MissingConfigScreen(),
      );
    }
    return const _RouterApp();
  }
}

class _RouterApp extends ConsumerStatefulWidget {
  const _RouterApp();
  @override
  ConsumerState<_RouterApp> createState() => _RouterAppState();
}

class _RouterAppState extends ConsumerState<_RouterApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Pause live updates in the background (mobile) and resume on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    ref.read(appForegroundProvider.notifier).set(foreground);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (_, next) {
      final event = next.value?.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        ref.read(passwordRecoveryProvider.notifier).set(true);
        ref.read(routerProvider).go('/reset-password');
      }
    });
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'ACME Control',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.settings_suggest_outlined, size: 48, color: AppColors.warning),
              SizedBox(height: 16),
              Text('ACME Control is not configured', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text(
                'Build the app with --dart-define-from-file=env/dev.json containing SUPABASE_URL, '
                'SUPABASE_ANON_KEY and API_BASE_URL. See README.md.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            ]),
          ),
        ),
      );
}
