import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core_providers.dart';

class AppSettings {
  const AppSettings({
    this.confirmCommands = true,
    this.animations = true,
    this.diagram3d = true,
    this.tickIntervalSec = 4,
    this.alarmSound = true,
    this.criticalPush = true,
    this.compactLists = false,
  });

  final bool confirmCommands;
  final bool animations;
  final bool diagram3d;
  final int tickIntervalSec;
  final bool alarmSound;
  final bool criticalPush;
  final bool compactLists;

  AppSettings copyWith({
    bool? confirmCommands,
    bool? animations,
    bool? diagram3d,
    int? tickIntervalSec,
    bool? alarmSound,
    bool? criticalPush,
    bool? compactLists,
  }) =>
      AppSettings(
        confirmCommands: confirmCommands ?? this.confirmCommands,
        animations: animations ?? this.animations,
        diagram3d: diagram3d ?? this.diagram3d,
        tickIntervalSec: tickIntervalSec ?? this.tickIntervalSec,
        alarmSound: alarmSound ?? this.alarmSound,
        criticalPush: criticalPush ?? this.criticalPush,
        compactLists: compactLists ?? this.compactLists,
      );
}

/// Device-local preferences (persisted in SharedPreferences).
class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final p = ref.read(sharedPrefsProvider);
    return AppSettings(
      confirmCommands: p.getBool('settings.confirm_commands') ?? true,
      animations: p.getBool('settings.animations') ?? true,
      diagram3d: p.getBool('settings.diagram_3d') ?? true,
      tickIntervalSec: p.getInt('settings.tick_interval') ?? 4,
      alarmSound: p.getBool('settings.alarm_sound') ?? true,
      criticalPush: p.getBool('settings.critical_push') ?? true,
      compactLists: p.getBool('settings.compact_lists') ?? false,
    );
  }

  Future<void> update(AppSettings s) async {
    final p = ref.read(sharedPrefsProvider);
    await p.setBool('settings.confirm_commands', s.confirmCommands);
    await p.setBool('settings.animations', s.animations);
    await p.setBool('settings.diagram_3d', s.diagram3d);
    await p.setInt('settings.tick_interval', s.tickIntervalSec);
    await p.setBool('settings.alarm_sound', s.alarmSound);
    await p.setBool('settings.critical_push', s.criticalPush);
    await p.setBool('settings.compact_lists', s.compactLists);
    state = s;
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
