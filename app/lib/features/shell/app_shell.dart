import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/core_providers.dart';
import 'navigation.dart';

/// Responsive application frame: navigation rail on desktop/tablet, bottom tabs on phones.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    ref.watch(simulationTickerProvider); // keeps the live simulation ticking while the shell is visible

    ref.listen<bool>(isOnlineProvider, (prev, next) {
      if (prev == false && next) showSnack(context, 'Back online — live updates resumed.', color: const Color(0xFF14432F));
      if (prev == true && !next) showSnack(context, 'Connection lost — showing the last received data (read-only).', error: true);
    });

    final profile = profileAsync.value;
    if (profile == null) {
      return Scaffold(
        body: profileAsync.hasError
            ? ErrorView(error: profileAsync.error!, onRetry: () => ref.invalidate(currentProfileProvider))
            : const LoadingView(message: 'Loading your workspace…'),
      );
    }

    final sections = sectionsFor(profile.role);
    final mobile = context.isMobile;

    final body = Column(children: [
      const _OfflineBanner(),
      Expanded(child: child),
    ]);

    if (mobile) {
      final tabIndex = _mobileIndex(location);
      return Scaffold(
        appBar: _TopBar(profile: profile, location: location, compact: true),
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: tabIndex,
          onDestinationSelected: (i) => context.go(mobileTabs[i].path),
          destinations: [
            for (final t in mobileTabs)
              NavigationDestination(
                icon: t.path == '/alarms' ? _AlarmBadgeIcon(icon: t.icon) : Icon(t.icon),
                selectedIcon: Icon(t.selected),
                label: t.label,
              ),
          ],
        ),
      );
    }

    final selected = sections.indexWhere((s) => location == s.path || location.startsWith('${s.path}/'));
    return Scaffold(
      appBar: _TopBar(profile: profile, location: location, compact: false),
      body: Row(children: [
        NavigationRail(
          extended: context.isWide,
          minExtendedWidth: 210,
          selectedIndex: selected < 0 ? null : selected,
          onDestinationSelected: (i) => context.go(sections[i].path),
          labelType: context.isWide ? NavigationRailLabelType.none : NavigationRailLabelType.all,
          destinations: [
            for (final s in sections)
              NavigationRailDestination(
                icon: s == AppSection.alarms ? _AlarmBadgeIcon(icon: s.icon) : Icon(s.icon),
                selectedIcon: Icon(s.selectedIcon),
                label: Text(s.label),
              ),
          ],
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: context.isWide
                    ? _RoleBadge(role: profile.role)
                    : Tooltip(message: profile.role.label, child: const Icon(Icons.badge_outlined, color: AppColors.textMuted)),
              ),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]),
    );
  }

  int _mobileIndex(String loc) {
    for (var i = 0; i < mobileTabs.length - 1; i++) {
      if (loc == mobileTabs[i].path || loc.startsWith('${mobileTabs[i].path}/')) return i;
    }
    return mobileTabs.length - 1;
  }
}

class _TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const _TopBar({required this.profile, required this.location, required this.compact});
  final Profile profile;
  final String location;
  final bool compact;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      toolbarHeight: 60,
      titleSpacing: 16,
      title: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.water, AppColors.waterDeep]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.water_drop, size: 19, color: Colors.white),
        ),
        const SizedBox(width: 10),
        if (!compact) ...[
          const Text('ACME Control', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(width: 20),
        ],
        const Flexible(child: _PlantSwitcher()),
      ]),
      actions: [
        const _ConnectionBadge(),
        IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: () => context.go('/search')),
        if (!compact)
          IconButton(tooltip: 'Alarms', icon: const _AlarmBadgeIcon(icon: Icons.notifications_outlined), onPressed: () => context.go('/alarms')),
        _UserMenu(profile: profile),
        const SizedBox(width: 8),
      ],
      bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
    );
  }
}

class _PlantSwitcher extends ConsumerWidget {
  const _PlantSwitcher();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plants = ref.watch(plantsProvider).value ?? const [];
    final selected = ref.watch(selectedPlantProvider);
    final states = ref.watch(plantStatesProvider).value ?? const {};
    if (selected == null) return const SizedBox.shrink();
    final status = states[selected.id]?.status ?? 'normal';
    return PopupMenuButton<String>(
      tooltip: 'Switch plant',
      onSelected: (id) => ref.read(selectedPlantIdProvider.notifier).select(id),
      itemBuilder: (_) => [
        for (final p in plants)
          PopupMenuItem(
            value: p.id,
            child: Row(children: [
              Icon(Icons.circle, size: 10, color: plantStatusColor(states[p.id]?.status ?? 'normal')),
              const SizedBox(width: 10),
              Expanded(child: Text(p.shortName)),
              if (p.id == selected.id) const Icon(Icons.check, size: 18),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.outline)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 9, color: plantStatusColor(status)),
          const SizedBox(width: 8),
          Flexible(child: Text(selected.shortName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          const Icon(Icons.expand_more, size: 18),
        ]),
      ),
    );
  }
}

class _ConnectionBadge extends ConsumerWidget {
  const _ConnectionBadge();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    final ticker = ref.watch(simulationTickerProvider);
    final plantId = ref.watch(selectedPlantIdProvider);
    final autoRun = ref.watch(plantStateProvider(plantId)).value?.autoRun ?? false;
    final (label, color, icon) = !online
        ? ('Offline', AppColors.fault, Icons.cloud_off)
        : !autoRun
            ? ('Paused', AppColors.warning, Icons.pause_circle_outline)
            : ticker.lastError != null
                ? ('API issue', AppColors.warning, Icons.sync_problem)
                : ('Live', AppColors.running, Icons.sensors);
    final tip = !online
        ? 'No connection. Data shown is the last snapshot; control actions are disabled.'
        : ticker.lastError ?? (autoRun ? 'Live simulation running — real-time updates active' : 'Live simulation paused');
    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: context.isMobile ? Icon(icon, color: color, size: 20) : StatusChip(label, color: color, icon: icon),
      ),
    );
  }
}

class _AlarmBadgeIcon extends ConsumerWidget {
  const _AlarmBadgeIcon({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plantId = ref.watch(selectedPlantIdProvider);
    final count = ref.watch(unackedAlarmCountProvider(plantId));
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      backgroundColor: AppColors.critical,
      child: Icon(icon),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.profile});
  final Profile profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      onSelected: (v) async {
        switch (v) {
          case 'profile':
            context.go('/profile');
          case 'settings':
            context.go('/settings');
          case 'logout':
            if (await confirmDialog(context, title: 'Sign out', message: 'Sign out of ACME Control on this device?', confirmLabel: 'Sign out')) {
              await ref.read(authRepositoryProvider).signOut();
            }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(profile.displayName, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
            Text('${profile.role.label} · ${profile.email}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profile'), dense: true)),
        const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings'), dense: true)),
        const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'), dense: true)),
      ],
      child: UserAvatar(profile: profile, radius: 17),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.profile, this.radius = 18});
  final Profile profile;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.surfaceHighest,
        foregroundImage: profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
        child: Text(profile.initials, style: TextStyle(fontSize: radius * 0.75, fontWeight: FontWeight.w700, color: AppColors.primary)),
      );
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final UserRole role;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 180,
        child: Tooltip(
          message: role.description,
          child: StatusChip('${role.label} view', color: AppColors.secondary, icon: Icons.badge_outlined),
        ),
      );
}

class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    if (online) return const SizedBox.shrink();
    final plantId = ref.watch(selectedPlantIdProvider);
    final savedAt = ref.read(cacheServiceProvider).savedAt('equipment.$plantId');
    return Material(
      color: const Color(0xFF3A2A0C),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          const Icon(Icons.cloud_off, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline — read-only view of data received ${savedAt == null ? 'earlier' : 'at ${fmtShort(savedAt)}'}. '
              'Updates resume automatically when the connection returns. Control actions require a connection.',
              style: const TextStyle(color: Color(0xFFFFE2A8), fontSize: 13),
            ),
          ),
        ]),
      ),
    );
  }
}
