import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/app_settings.dart';
import '../../data/services/core_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _health;
  bool _checking = false;

  Future<void> _checkApi() async {
    setState(() {
      _checking = true;
      _health = null;
    });
    try {
      final r = await ref.read(apiClientProvider).health();
      _health = 'API online · v${r['version']} · Supabase ${r['supabaseConfigured'] == true ? 'configured' : 'NOT configured'}';
    } catch (e) {
      _health = ErrorView.messageOf(e);
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appSettingsProvider);
    final n = ref.read(appSettingsProvider.notifier);
    final plants = ref.watch(plantsProvider).value ?? const [];
    final selected = ref.watch(selectedPlantIdProvider);
    final profile = ref.watch(currentProfileProvider).value;

    Future<void> savePref(String key, Object value) async {
      if (profile == null) return;
      final prefs = {...profile.preferences, key: value};
      try {
        await ref.read(currentProfileProvider.notifier).save({'preferences': prefs});
      } catch (_) {
        // Device settings still apply even if the profile cannot be updated.
      }
    }

    return SingleChildScrollView(
      child: PageBody(
        maxWidth: 820,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const PageHeader(title: 'Settings', subtitle: 'Preferences for this device and your account'),
          SectionCard(
            title: 'General',
            icon: Icons.tune,
            child: Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Default plant'),
                subtitle: const Text('Opened when you start the app'),
                trailing: DropdownButton<String>(
                  value: plants.any((p) => p.id == selected) ? selected : null,
                  items: [for (final p in plants) DropdownMenuItem(value: p.id, child: Text(p.shortName))],
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(selectedPlantIdProvider.notifier).select(v);
                    savePref('default_plant', v);
                  },
                ),
              ),
              const ListTile(contentPadding: EdgeInsets.zero, title: Text('Language'), subtitle: Text('English (United States)'), trailing: Text('EN')),
              const ListTile(contentPadding: EdgeInsets.zero, title: Text('Units'), subtitle: Text('Metric — m³, m³/h, bar, %')),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Process display',
            icon: Icons.monitor,
            child: Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Animated water flow'),
                subtitle: const Text('Moving particles, spinning impellers and tank ripples'),
                value: s.animations,
                onChanged: (v) => n.update(s.copyWith(animations: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('3D perspective diagram'),
                subtitle: const Text('Tilted plant view you can orbit by dragging'),
                value: s.diagram3d,
                onChanged: (v) => n.update(s.copyWith(diagram3d: v)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Live update interval'),
                subtitle: const Text('How often the simulation is advanced while the app is open'),
                trailing: DropdownButton<int>(
                  value: s.tickIntervalSec,
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 s')),
                    DropdownMenuItem(value: 4, child: Text('4 s')),
                    DropdownMenuItem(value: 8, child: Text('8 s')),
                    DropdownMenuItem(value: 15, child: Text('15 s')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await n.update(s.copyWith(tickIntervalSec: v));
                    ref.invalidate(simulationTickerProvider);
                  },
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Controls & notifications',
            icon: Icons.notifications_outlined,
            child: Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Confirm before sending commands'),
                subtitle: const Text('Ask for confirmation before start/stop/open/close'),
                value: s.confirmCommands,
                onChanged: (v) => n.update(s.copyWith(confirmCommands: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Alarm sound'),
                subtitle: const Text('Audible annunciation for new high-priority alarms (simulated)'),
                value: s.alarmSound,
                onChanged: (v) {
                  n.update(s.copyWith(alarmSound: v));
                  savePref('alarm_sound', v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('SMS paging for critical alarms'),
                subtitle: Text('Pages ${profile?.phone ?? 'your phone number'} via the SMS gateway (simulated)'),
                value: s.criticalPush,
                onChanged: (v) {
                  n.update(s.copyWith(criticalPush: v));
                  savePref('sms_paging', v);
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Offline data',
            icon: Icons.offline_pin_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('The latest plant data is stored on this device so you can review it without a connection. Control actions always require a connection.',
                  style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final n = await ref.read(cacheServiceProvider).clear();
                    if (context.mounted) showSnack(context, 'Cleared $n cached datasets. They will be downloaded again when online.');
                  },
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Clear offline cache'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'About',
            icon: Icons.info_outline,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const LabelValue('Application', 'ACME Control ${Env.appVersion}'),
              LabelValue('API endpoint', Env.apiBaseUrl),
              LabelValue('Supabase project', Uri.tryParse(Env.supabaseUrl)?.host ?? '—'),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: _checking ? null : _checkApi,
                  icon: _checking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.health_and_safety_outlined),
                  label: const Text('Check API connection'),
                ),
                const SizedBox(width: 12),
                if (_health != null) Expanded(child: Text(_health!, style: const TextStyle(fontSize: 13))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
