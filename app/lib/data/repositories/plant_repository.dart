import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/equipment.dart';
import '../models/json.dart';
import '../models/operations.dart';
import '../models/plant.dart';
import '../services/core_providers.dart';
import 'auth_repository.dart';
import 'live_query.dart';

// Plants & scenarios ---------------------------------------------------------

final plantsProvider = FutureProvider<List<Plant>>((ref) {
  ref.watch(currentUserIdProvider);
  return cachedFetch(
    ref,
    cacheKey: 'plants',
    query: (db) => db.from('plants').select().order('name', ascending: false),
    parse: Plant.fromJson,
    preferCache: true,
  );
});

final scenariosProvider = FutureProvider<List<Scenario>>((ref) => cachedFetch(
      ref,
      cacheKey: 'scenarios',
      query: (db) => db.from('scenarios').select().order('sort_order', ascending: true),
      parse: Scenario.fromJson,
      preferCache: true,
    ));

/// Selected plant, remembered across sessions.
class SelectedPlantNotifier extends Notifier<String> {
  static const _key = 'selected_plant';
  @override
  String build() => ref.read(sharedPrefsProvider).getString(_key) ?? 'north-valley';

  void select(String plantId) {
    state = plantId;
    ref.read(sharedPrefsProvider).setString(_key, plantId);
  }
}

final selectedPlantIdProvider = NotifierProvider<SelectedPlantNotifier, String>(SelectedPlantNotifier.new);

final selectedPlantProvider = Provider<Plant?>((ref) {
  final id = ref.watch(selectedPlantIdProvider);
  final plants = ref.watch(plantsProvider).value ?? const [];
  for (final p in plants) {
    if (p.id == id) return p;
  }
  return plants.isEmpty ? null : plants.first;
});

// Live process data ------------------------------------------------------------

final plantStatesProvider = StreamProvider<Map<String, PlantState>>((ref) {
  ref.watch(currentUserIdProvider);
  return liveQuery<PlantState>(
    ref,
    cacheKey: 'plant_state',
    query: (db) => db.from('plant_state').stream(primaryKey: ['plant_id']),
    parse: PlantState.fromJson,
  ).map((list) => {for (final s in list) s.plantId: s});
});

final plantStateProvider = Provider.family<AsyncValue<PlantState?>, String>((ref, plantId) {
  return ref.watch(plantStatesProvider).whenData((m) => m[plantId]);
});

final equipmentProvider = StreamProvider.family<List<Equipment>, String>((ref, plantId) {
  ref.watch(currentUserIdProvider);
  return liveQuery<Equipment>(
    ref,
    cacheKey: 'equipment.$plantId',
    query: (db) => db.from('equipment').stream(primaryKey: ['id']).eq('plant_id', plantId),
    parse: Equipment.fromJson,
    transform: (items) => items..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
  );
});

final equipmentByTagProvider = Provider.family<Map<String, Equipment>, String>((ref, plantId) {
  final list = ref.watch(equipmentProvider(plantId)).value ?? const [];
  return {for (final e in list) e.tag: e};
});

/// Finds an equipment row by id across both plants.
final equipmentByIdProvider = Provider.family<AsyncValue<Equipment?>, String>((ref, id) {
  final plants = ref.watch(plantsProvider).value ?? const [];
  AsyncValue<Equipment?> result = const AsyncLoading();
  var loaded = 0;
  for (final p in plants) {
    final v = ref.watch(equipmentProvider(p.id));
    if (v.hasValue) {
      loaded++;
      for (final e in v.value!) {
        if (e.id == id) return AsyncData(e);
      }
    } else if (v.hasError) {
      result = AsyncError(v.error!, v.stackTrace ?? StackTrace.current);
    }
  }
  if (plants.isNotEmpty && loaded == plants.length) return const AsyncData(null);
  return result;
});

// Alarms ---------------------------------------------------------------------------

/// Open (not closed) alarms across all plants, newest first.
final openAlarmsProvider = StreamProvider<List<Alarm>>((ref) {
  ref.watch(currentUserIdProvider);
  return liveQuery<Alarm>(
    ref,
    cacheKey: 'alarms.open',
    query: (db) => db
        .from('alarms')
        .stream(primaryKey: ['id'])
        .inFilter('state', ['active', 'acknowledged', 'rtn_unack'])
        .order('raised_at')
        .limit(300),
    parse: Alarm.fromJson,
    transform: (items) => items
      ..sort((a, b) {
        final p = a.priority.rank.compareTo(b.priority.rank);
        return p != 0 ? p : b.when.compareTo(a.when);
      }),
  );
});

final plantOpenAlarmsProvider = Provider.family<List<Alarm>, String>((ref, plantId) {
  return (ref.watch(openAlarmsProvider).value ?? const []).where((a) => a.plantId == plantId).toList();
});

final unackedAlarmCountProvider = Provider.family<int, String>((ref, plantId) {
  return ref.watch(plantOpenAlarmsProvider(plantId)).where((a) => a.needsAck).length;
});

class AlarmHistoryQuery {
  const AlarmHistoryQuery(this.plantId, {this.days = 7});
  final String plantId;
  final int days;
  @override
  bool operator ==(Object other) => other is AlarmHistoryQuery && other.plantId == plantId && other.days == days;
  @override
  int get hashCode => Object.hash(plantId, days);
}

final alarmHistoryProvider = FutureProvider.family<List<Alarm>, AlarmHistoryQuery>((ref, q) {
  return cachedFetch(
    ref,
    cacheKey: 'alarms.history.${q.plantId}.${q.days}',
    query: (db) => db
        .from('alarms')
        .select()
        .eq('plant_id', q.plantId)
        .gte('raised_at', DateTime.now().subtract(Duration(days: q.days)).toUtc().toIso8601String())
        .order('raised_at', ascending: false)
        .limit(500),
    parse: Alarm.fromJson,
  );
});

class AlarmRepository {
  AlarmRepository(this.ref);
  final Ref ref;

  Future<int> acknowledge(List<String> ids, {String? comment}) async {
    final res = await ref.read(supabaseProvider).rpc('acknowledge_alarms', params: {
      'p_ids': ids,
      'p_comment': (comment == null || comment.trim().isEmpty) ? null : comment.trim(),
    });
    return (res as num?)?.toInt() ?? 0;
  }
}

final alarmRepositoryProvider = Provider<AlarmRepository>((ref) => AlarmRepository(ref));

// Commands, events, integrations ------------------------------------------------------

final commandsProvider = StreamProvider.family<List<ControlCommand>, String>((ref, plantId) {
  ref.watch(currentUserIdProvider);
  return liveQuery<ControlCommand>(
    ref,
    cacheKey: 'commands.$plantId',
    query: (db) => db.from('commands').stream(primaryKey: ['id']).eq('plant_id', plantId).order('created_at').limit(150),
    parse: ControlCommand.fromJson,
  );
});

final eventsProvider = StreamProvider.family<List<EventLog>, String>((ref, plantId) {
  ref.watch(currentUserIdProvider);
  return liveQuery<EventLog>(
    ref,
    cacheKey: 'events.$plantId',
    query: (db) => db.from('events').stream(primaryKey: ['id']).eq('plant_id', plantId).order('id').limit(250),
    parse: EventLog.fromJson,
  );
});

final integrationLogProvider = StreamProvider<List<IntegrationLogEntry>>((ref) {
  ref.watch(currentUserIdProvider);
  return liveQuery<IntegrationLogEntry>(
    ref,
    cacheKey: 'integration_log',
    query: (db) => db.from('integration_log').stream(primaryKey: ['id']).order('id').limit(60),
    parse: IntegrationLogEntry.fromJson,
  );
});

final integrationStatusProvider = FutureProvider<List<IntegrationSystem>>((ref) async {
  final res = await ref.watch(apiClientProvider).integrationStatus();
  return ((res['systems'] as List?) ?? const []).map((e) => IntegrationSystem.fromJson(asJson(e))).toList();
});

// Trends ------------------------------------------------------------------------------

class TrendQuery {
  const TrendQuery(this.plantId, this.tags, this.hours);
  final String plantId;
  final List<String> tags;
  final int hours;
  @override
  bool operator ==(Object other) =>
      other is TrendQuery && other.plantId == plantId && other.hours == hours && other.tags.join(',') == tags.join(',');
  @override
  int get hashCode => Object.hash(plantId, hours, tags.join(','));
}

final trendProvider = FutureProvider.family<Map<String, List<Measurement>>, TrendQuery>((ref, q) async {
  if (q.tags.isEmpty) return {};
  // Use the simulation clock as "now" (the plant can run ahead of wall-clock time).
  final simNow = ref.read(plantStateProvider(q.plantId)).value?.simTime ?? DateTime.now();
  final to = simNow.add(const Duration(minutes: 1));
  final from = simNow.subtract(Duration(hours: q.hours));
  // Server-side bucketing keeps every range under PostgREST's max-rows limit.
  final rows = await cachedFetch<Measurement>(
    ref,
    cacheKey: 'trend.${q.plantId}.${q.tags.join('_')}.${q.hours}',
    query: (db) async {
      final res = await db.rpc('trend_series', params: {
        'p_plant': q.plantId,
        'p_tags': q.tags,
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
        'p_points': 300,
      });
      return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    },
    parse: Measurement.fromJson,
  );
  final out = <String, List<Measurement>>{for (final t in q.tags) t: []};
  for (final m in rows) {
    out[m.tag]?.add(m);
  }
  for (final l in out.values) {
    l.sort((a, b) => a.ts.compareTo(b.ts));
  }
  return out;
});

// Simulation ticker --------------------------------------------------------------------

class TickerStatus {
  const TickerStatus({this.running = false, this.lastTickAt, this.lastError});
  final bool running;
  final DateTime? lastTickAt;
  final String? lastError;
}

/// Drives the live simulation while the app is in the foreground and online:
/// calls POST /api/simulation/tick for the selected plant every few seconds.
class SimulationTicker extends Notifier<TickerStatus> {
  Timer? _timer;
  bool _busy = false;

  static const intervalKey = 'settings.tick_interval';

  @override
  TickerStatus build() {
    final live = ref.watch(liveSyncProvider);
    final uid = ref.watch(currentUserIdProvider);
    final plantId = ref.watch(selectedPlantIdProvider);
    final autoRun = ref.watch(plantStateProvider(plantId).select((s) => s.value?.autoRun ?? false));
    final seconds = ref.read(sharedPrefsProvider).getInt(intervalKey) ?? 4;

    ref.onDispose(() => _timer?.cancel());
    if (!live || uid == null || !autoRun) return const TickerStatus();

    _timer = Timer.periodic(Duration(seconds: seconds), (_) => _tick(plantId));
    Future.microtask(() => _tick(plantId));
    return const TickerStatus(running: true);
  }

  Future<void> _tick(String plantId) async {
    if (_busy || !ref.mounted) return;
    _busy = true;
    try {
      await ref.read(apiClientProvider).tick(plantId);
      if (!ref.mounted) return;
      state = TickerStatus(running: true, lastTickAt: DateTime.now());
    } catch (e) {
      if (!ref.mounted) return;
      state = TickerStatus(running: true, lastTickAt: state.lastTickAt, lastError: e.toString());
    } finally {
      _busy = false;
    }
  }
}

final simulationTickerProvider = NotifierProvider<SimulationTicker, TickerStatus>(SimulationTicker.new);
