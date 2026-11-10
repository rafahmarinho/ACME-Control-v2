import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/operations.dart';
import '../../data/models/plant.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/core_providers.dart';
import '../process/process_screen.dart' show EventRow;

/// Demo control centre: scenarios, time advance, event log, integrations and data reset.
class SimulationScreen extends ConsumerStatefulWidget {
  const SimulationScreen({super.key});
  @override
  ConsumerState<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends ConsumerState<SimulationScreen> {
  String? _busy;
  String _eventQuery = '';
  String _category = 'all';

  Future<void> _do(String key, Future<Map<String, dynamic>> Function() action, String Function(Map<String, dynamic>) success) async {
    if (!ensureOnline(context, ref)) return;
    setState(() => _busy = key);
    try {
      final res = await action();
      if (mounted) showSnack(context, success(res), color: const Color(0xFF14432F));
    } catch (e) {
      if (mounted) showSnack(context, ErrorView.messageOf(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plant = ref.watch(selectedPlantProvider);
    final role = ref.watch(currentRoleProvider);
    if (plant == null) return const LoadingView();
    final state = ref.watch(plantStateProvider(plant.id)).value;
    final scenarios = ref.watch(scenariosProvider);
    final api = ref.read(apiClientProvider);
    final canSim = role?.canSimulate ?? false;
    final wide = context.width >= 1100;

    final control = _LiveControl(
      plant: plant,
      state: state,
      busy: _busy,
      enabled: canSim,
      onToggle: (v) => _do('toggle', () => api.setAutoRun(plant.id, v), (_) => v ? 'Live simulation resumed.' : 'Live simulation paused.'),
      onAdvance: (m) => _do('adv$m', () => api.advance(plant.id, m),
          (r) => 'Advanced $m min · ${r['measurementsRecorded'] ?? 0} samples · ${r['alarmsRaised'] ?? 0} new alarms · status ${r['status'] ?? '—'}'),
    );

    final scenarioCard = SectionCard(
      title: 'Scenarios',
      icon: Icons.science_outlined,
      child: AsyncValueView<List<Scenario>>(
        value: scenarios,
        onRetry: () => ref.invalidate(scenariosProvider),
        data: (list) => Column(children: [
          for (final s in list)
            _ScenarioTile(
              scenario: s,
              active: state?.scenarioId == s.id,
              busy: _busy == 'sc${s.id}',
              enabled: canSim && _busy == null,
              onActivate: () => _do('sc${s.id}', () => api.setScenario(plant.id, s.id), (_) => 'Scenario "${s.name}" activated at ${plant.shortName}.'),
            ),
        ]),
      ),
    );

    final events = _EventLog(
      plantId: plant.id,
      query: _eventQuery,
      category: _category,
      onQuery: (v) => setState(() => _eventQuery = v),
      onCategory: (v) => setState(() => _category = v),
    );

    final reset = SectionCard(
      title: 'Demo data',
      icon: Icons.restart_alt,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Restores both plants, equipment, setpoints, alarms, work orders, handovers and 12 h of trend history to the initial demo state. User accounts are kept.',
            style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.fault, side: const BorderSide(color: AppColors.fault)),
          onPressed: (role?.canResetDemo ?? false) && _busy == null
              ? () async {
                  final ok = await confirmDialog(context,
                      title: 'Reset all demo data?',
                      message: 'All operational data for both plants will be replaced with the initial demo dataset. This cannot be undone.',
                      confirmLabel: 'Reset data',
                      destructive: true);
                  if (ok && context.mounted) {
                    await _do('reset', api.resetDemo, (_) => 'Demo data restored.');
                    ref.invalidate(plantsProvider);
                    ref.invalidate(scenariosProvider);
                  }
                }
              : null,
          icon: _busy == 'reset' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restart_alt),
          label: const Text('Reset demo data'),
        ),
        if (!(role?.canResetDemo ?? false))
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Only engineers and supervisors can reset the demo data.', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
      ]),
    );

    const integrations = _Integrations();

    return SingleChildScrollView(
      child: PageBody(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PageHeader(
            title: 'Simulation',
            subtitle: 'Scenario control, time advance, event log and simulated integrations — ${plant.shortName}',
          ),
          if (!canSim)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Your role can view the simulation but not change it.', style: TextStyle(color: AppColors.warning)),
            ),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [control, const SizedBox(height: 16), scenarioCard, const SizedBox(height: 16), reset])),
              const SizedBox(width: 16),
              Expanded(child: Column(children: [events, const SizedBox(height: 16), integrations])),
            ])
          else ...[
            control,
            const SizedBox(height: 12),
            scenarioCard,
            const SizedBox(height: 12),
            events,
            const SizedBox(height: 12),
            integrations,
            const SizedBox(height: 12),
            reset,
          ],
        ]),
      ),
    );
  }
}

class _LiveControl extends ConsumerWidget {
  const _LiveControl({required this.plant, required this.state, required this.busy, required this.enabled, required this.onToggle, required this.onAdvance});
  final Plant plant;
  final PlantState? state;
  final String? busy;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onAdvance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticker = ref.watch(simulationTickerProvider);
    final s = state;
    return SectionCard(
      title: 'Live simulation',
      icon: Icons.play_circle_outline,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s?.autoRun ?? false,
          onChanged: enabled && busy == null && s != null ? onToggle : null,
          title: Text(s?.autoRun == true ? 'Running in real time' : 'Paused'),
          subtitle: Text(s?.autoRun == true
              ? 'The process advances while this app is open in the foreground (${ticker.lastTickAt == null ? 'waiting for first tick' : 'last tick ${timeAgo(ticker.lastTickAt)}'}).'
              : 'Tanks and flows are frozen. Use "Advance" to step the process manually.'),
        ),
        if (ticker.lastError != null) Text('Last tick failed: ${ticker.lastError}', style: const TextStyle(color: AppColors.warning, fontSize: 12)),
        const Divider(height: 24),
        LabelValue('Simulation clock', fmtFull(s?.simTime)),
        LabelValue('Tick', '${s?.tick ?? 0}'),
        LabelValue('Plant status', titleCase(s?.status ?? 'normal'), valueColor: plantStatusColor(s?.status ?? 'normal')),
        const SizedBox(height: 12),
        const Text('ADVANCE SIMULATION', style: TextStyle(fontSize: 11, color: AppColors.textMuted, letterSpacing: 1)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (m, l) in [(1, '+1 min'), (15, '+15 min'), (60, '+1 hour'), (240, '+4 hours')])
            FilledButton.tonal(
              onPressed: enabled && busy == null ? () => onAdvance(m) : null,
              child: busy == 'adv$m' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l),
            ),
        ]),
        const SizedBox(height: 6),
        const Text('Advancing runs the full process model (control logic, interlocks, alarms) and records trend samples.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ]),
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({required this.scenario, required this.active, required this.busy, required this.enabled, required this.onActivate});
  final Scenario scenario;
  final bool active;
  final bool busy;
  final bool enabled;
  final VoidCallback onActivate;
  @override
  Widget build(BuildContext context) {
    final s = scenario;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: active ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? AppColors.primary : AppColors.outline),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (active) ...[const SizedBox(width: 8), const StatusChip('Active', color: AppColors.primary, dense: true)],
            ]),
            const SizedBox(height: 4),
            Text(s.description, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              'Inflow ×${s.inflowFactor} · Demand ×${s.demandFactor}${s.faultTags.isNotEmpty ? ' · Faults: ${s.faultTags.join(', ')}' : ''}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        if (!active)
          OutlinedButton(
            onPressed: enabled ? onActivate : null,
            child: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Activate'),
          ),
      ]),
    );
  }
}

class _EventLog extends ConsumerWidget {
  const _EventLog({required this.plantId, required this.query, required this.category, required this.onQuery, required this.onCategory});
  final String plantId;
  final String query;
  final String category;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider(plantId));
    const cats = ['all', 'process', 'alarm', 'command', 'setpoint', 'maintenance', 'simulation', 'handover', 'integration'];
    return SectionCard(
      title: 'Event log',
      icon: Icons.receipt_long_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SearchField(hint: 'Search events', onChanged: (v) => onQuery(v.trim().toLowerCase())),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final c in cats)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(c == 'all' ? 'All' : titleCase(c)), selected: category == c, onSelected: (_) => onCategory(c)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        AsyncValueView<List<EventLog>>(
          value: events,
          onRetry: () => ref.invalidate(eventsProvider(plantId)),
          loading: const LoadingView(),
          data: (list) {
            final items = list.where((e) => (category == 'all' || e.category == category) && (query.isEmpty || e.message.toLowerCase().contains(query))).toList();
            if (items.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('No events match.', style: TextStyle(color: AppColors.textMuted)));
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: ListView.builder(shrinkWrap: true, itemCount: items.length, itemBuilder: (_, i) => EventRow(event: items[i])),
            );
          },
        ),
      ]),
    );
  }
}

class _Integrations extends ConsumerWidget {
  const _Integrations();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(integrationStatusProvider);
    final log = ref.watch(integrationLogProvider);
    return SectionCard(
      title: 'External integrations (simulated)',
      icon: Icons.hub_outlined,
      trailing: IconButton(tooltip: 'Refresh', onPressed: () => ref.invalidate(integrationStatusProvider), icon: const Icon(Icons.refresh, size: 20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AsyncValueView<List<IntegrationSystem>>(
          value: status,
          onRetry: () => ref.invalidate(integrationStatusProvider),
          loading: const LoadingView(),
          data: (systems) => Column(children: [
            for (final s in systems)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  switch (s.id) { 'sms_gateway' => Icons.sms_outlined, 'cmms' => Icons.build_circle_outlined, 'historian' => Icons.storage_outlined, _ => Icons.email_outlined },
                  color: s.status == 'online' ? AppColors.running : AppColors.warning,
                ),
                title: Text('${s.name} · ${s.vendor}'),
                subtitle: Text('${s.description}\nLast activity ${timeAgo(s.lastActivityAt)} · ${s.messages24h} msgs/24 h · ${s.latencyMs} ms', style: const TextStyle(fontSize: 12)),
                isThreeLine: true,
                trailing: StatusChip(titleCase(s.status), color: s.status == 'online' ? AppColors.running : AppColors.warning, dense: true),
              ),
          ]),
        ),
        const Divider(height: 20),
        const Text('RECENT MESSAGES', style: TextStyle(fontSize: 11, color: AppColors.textMuted, letterSpacing: 1)),
        const SizedBox(height: 6),
        AsyncValueView<List<IntegrationLogEntry>>(
          value: log,
          loading: const LoadingView(),
          data: (entries) => entries.isEmpty
              ? const Text('No messages yet.', style: TextStyle(color: AppColors.textMuted))
              : Column(children: [
                  for (final e in entries.take(12))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 92, child: Text(e.system.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700))),
                        Expanded(child: Text(e.message, style: const TextStyle(fontSize: 12))),
                        const SizedBox(width: 8),
                        Text(fmtTime(e.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ]),
                    ),
                ]),
        ),
      ]),
    );
  }
}
