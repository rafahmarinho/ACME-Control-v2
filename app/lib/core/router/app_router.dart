import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/auth_repository.dart';
import '../../features/alarms/alarms_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/commands/commands_screen.dart';
import '../../features/equipment/equipment_detail_screen.dart';
import '../../features/equipment/equipment_screen.dart';
import '../../features/handover/handover_screen.dart';
import '../../features/maintenance/maintenance_detail_screen.dart';
import '../../features/maintenance/maintenance_screen.dart';
import '../../features/plants/plants_screen.dart';
import '../../features/process/process_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/setpoints/setpoints_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/shell/more_screen.dart';
import '../../features/shell/navigation.dart';
import '../../features/simulation/simulation_screen.dart';
import '../../features/trends/trends_screen.dart';

const _publicPaths = ['/login', '/forgot-password', '/reset-password'];

/// Bridges Riverpod auth/profile changes to go_router's refreshListenable.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(currentProfileProvider, (_, _) => notifyListeners());
  }
}

/// Set when Supabase reports a PASSWORD_RECOVERY session.
class PasswordRecoveryNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final passwordRecoveryProvider = NotifierProvider<PasswordRecoveryNotifier, bool>(PasswordRecoveryNotifier.new);

NoTransitionPage<void> _page(GoRouterState s, Widget child) => NoTransitionPage(key: s.pageKey, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/process',
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;
      final signedIn = ref.read(authRepositoryProvider).session != null;
      final isPublic = _publicPaths.contains(path);

      if (ref.read(passwordRecoveryProvider) && path != '/reset-password') return '/reset-password';
      if (!signedIn) {
        if (isPublic) return null;
        final from = state.uri.toString();
        return from == '/' || from == '/process' ? '/login' : '/login?from=${Uri.encodeComponent(from)}';
      }
      if (path == '/login' || path == '/forgot-password' || path == '/') {
        final from = state.uri.queryParameters['from'];
        return from != null && from.startsWith('/') ? from : '/process';
      }
      final role = ref.read(currentRoleProvider);
      if (role != null && !isPublic && !canAccessPath(role, path)) return '/process';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/process'),
      GoRoute(path: '/login', builder: (_, s) => const LoginScreen()),
      GoRoute(path: '/forgot-password', builder: (_, s) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (_, s) => const ResetPasswordScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/process', pageBuilder: (_, s) => _page(s, const ProcessScreen())),
          GoRoute(path: '/plants', pageBuilder: (_, s) => _page(s, const PlantsScreen())),
          GoRoute(path: '/alarms', pageBuilder: (_, s) => _page(s, const AlarmsScreen())),
          GoRoute(
            path: '/equipment',
            pageBuilder: (_, s) => _page(s, const EquipmentScreen()),
            routes: [
              GoRoute(path: ':id', builder: (_, s) => EquipmentDetailScreen(equipmentId: s.pathParameters['id']!)),
            ],
          ),
          GoRoute(path: '/trends', pageBuilder: (_, s) => _page(s, TrendsScreen(initialTag: s.uri.queryParameters['tag']))),
          GoRoute(path: '/commands', pageBuilder: (_, s) => _page(s, const CommandsScreen())),
          GoRoute(path: '/setpoints', pageBuilder: (_, s) => _page(s, const SetpointsScreen())),
          GoRoute(
            path: '/maintenance',
            pageBuilder: (_, s) => _page(s, const MaintenanceScreen()),
            routes: [
              GoRoute(path: ':id', builder: (_, s) => MaintenanceDetailScreen(orderId: s.pathParameters['id']!)),
            ],
          ),
          GoRoute(path: '/handover', pageBuilder: (_, s) => _page(s, const HandoverScreen())),
          GoRoute(path: '/simulation', pageBuilder: (_, s) => _page(s, const SimulationScreen())),
          GoRoute(path: '/search', pageBuilder: (_, s) => _page(s, const SearchScreen())),
          GoRoute(path: '/profile', pageBuilder: (_, s) => _page(s, const ProfileScreen())),
          GoRoute(path: '/settings', pageBuilder: (_, s) => _page(s, const SettingsScreen())),
          GoRoute(path: '/more', pageBuilder: (_, s) => _page(s, const MoreScreen())),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.explore_off_outlined, size: 40),
          const SizedBox(height: 12),
          Text('Page not found: ${state.uri.path}'),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => context.go('/process'), child: const Text('Go to process view')),
        ]),
      ),
    ),
  );
});
