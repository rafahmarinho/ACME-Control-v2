import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/auth_repository.dart';
import 'app_shell.dart';
import 'navigation.dart';

/// Mobile "More" tab: every section that is not a bottom tab, filtered by role.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;
    if (profile == null) return const LoadingView();
    final tabPaths = mobileTabs.map((t) => t.path).toSet();
    final sections = sectionsFor(profile.role).where((s) => !tabPaths.contains(s.path)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: UserAvatar(profile: profile, radius: 24),
            title: Text(profile.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${profile.role.label} · ${profile.email}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profile'),
          ),
        ),
        const SizedBox(height: 16),
        const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text('OPERATIONS', style: TextStyle(color: AppColors.textMuted, fontSize: 12, letterSpacing: 1))),
        Card(
          child: Column(children: [
            for (final (i, s) in sections.indexed) ...[
              if (i > 0) const Divider(indent: 56),
              ListTile(
                minTileHeight: 56,
                leading: Icon(s.icon, color: AppColors.primary),
                title: Text(s.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(s.path),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text('ACCOUNT', style: TextStyle(color: AppColors.textMuted, fontSize: 12, letterSpacing: 1))),
        Card(
          child: Column(children: [
            ListTile(minTileHeight: 56, leading: const Icon(Icons.search), title: const Text('Search'), onTap: () => context.go('/search')),
            const Divider(indent: 56),
            ListTile(minTileHeight: 56, leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () => context.go('/settings')),
            const Divider(indent: 56),
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.logout, color: AppColors.fault),
              title: const Text('Sign out'),
              onTap: () async {
                if (await confirmDialog(context, title: 'Sign out', message: 'Sign out of ACME Control on this device?', confirmLabel: 'Sign out')) {
                  await ref.read(authRepositoryProvider).signOut();
                }
              },
            ),
          ]),
        ),
      ],
    );
  }
}
