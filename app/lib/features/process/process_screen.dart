import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/operations.dart';
import '../../data/models/plant.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/app_settings.dart';
import 'equipment_control_panel.dart';
import 'process_diagram.dart';

/// Main HMI view: live diagram, KPIs, selected equipment controls, alarms and events.
class ProcessScreen extends ConsumerStatefulWidget {
  const ProcessScreen({super.key});
  @override
  ConsumerState<ProcessScreen> createState() => _ProcessScreenState();
}

class _ProcessScreenState extends ConsumerState<ProcessScreen> {
  String? _selected = 'P-101';

  void _select(BuildContext context, String plantId, String tag) {
    setState(() => _selected = tag);
    if (context.isMobile || MediaQuery.sizeOf(context).width < 1100) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppColors.surface,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => Consumer(builder: (ctx, ref, _) {
            final e = ref.watch(equipmentByTagProvider(plantId))[tag];
            if (e == null) return const LoadingView();
            return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
              EquipmentControlPanel(
                equipment: e,
                onOpenDetails: () {
                  Navigator.pop(ctx);
                  context.go('/equipment/${e.id}');
                },
              ),
            ]);
          }),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final plant = ref.watch(selectedPlantProvider);
    final plantsAsync = ref.watch(plantsProvider);
    if (plant == null) {
      return AsyncValueView(value: plantsAsync, data: (_) => const EmptyState(icon: Icons.factory_outlined, title: 'No plants available'), onRetry: () => ref.invalidate(plantsProvider));
    }
    final equipmentAsync = ref.watch(equipmentProvider(plant.id));
    final state = ref.watch(plantStateProvider(plant.id)).value;
    final settings = ref.watch(appSettingsProvider);
    final mobile = context.isMobile;
    final sidePanel = MediaQuery.sizeOf(context).width >= 1100;

    return AsyncValueView(
      value: equipmentAsync,
      onRetry: () => ref.invalidate(equipmentProvider(plant.id)),
      loading: const LoadingView(message: 'Connecting to plant…'),
      data: (list) {
        final byTag = {for (final e in list) e.tag: e};
        final diagram = ProcessDiagram(
          equipment: byTag,
          selectedTag: _selected,
          portrait: mobile,
          animate: settings.animations,
          enable3d: settings.diagram3d,
          onToggle3d: (v) => ref.read(appSettingsProvider.notifier).update(settings.copyWith(diagram3d: v)),
          onSelect: (tag) => _select(context, plant.id, tag),
        );

        final header = _ProcessHeader(plant: plant, state: state);
        final kpis = _KpiStrip(state: state, tanks: (byTag['T-101']?.levelPct, byTag['T-102']?.levelPct));
        final alarms = _AlarmSummary(plantId: plant.id);
        final events = _RecentEvents(plantId: plant.id);

        if (mobile) {
          return ListView(padding: const EdgeInsets.all(12), children: [
            header,
            const SizedBox(height: 10),
            kpis,
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(aspectRatio: 600 / 1150, child: Padding(padding: const EdgeInsets.all(4), child: diagram)),
            ),
            const SizedBox(height: 6),
            const Text('Tap a tank, pump, valve or instrument to see details and controls.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 12),
            alarms,
            const SizedBox(height: 12),
            events,
          ]);
        }

        final selected = _selected == null ? null : byTag[_selected!];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header,
            const SizedBox(height: 14),
            kpis,
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(height: 600, child: Padding(padding: const EdgeInsets.all(6), child: diagram)),
                ),
              ),
              if (sidePanel) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 370,
                  child: SectionCard(
                    title: 'Selected equipment',
                    icon: Icons.ads_click,
                    child: selected == null
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Text('Click any equipment on the diagram to view its state and controls.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                          )
                        : EquipmentControlPanel(equipment: selected, onOpenDetails: () => context.go('/equipment/${selected.id}')),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: alarms),
              const SizedBox(width: 16),
              Expanded(child: events),
            ]),
          ]),
        );
      },
    );
  }
}

class _ProcessHeader extends ConsumerWidget {
  const _ProcessHeader({required this.plant, required this.state});
  final Plant plant;
  final PlantState? state;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenarios = ref.watch(scenariosProvider).value ?? const [];
    final scenario = scenarios.where((s) => s.id == state?.scenarioId).firstOrNull;
    final status = state?.status ?? 'normal';
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(plant.name, style: TextStyle(fontSize: context.isMobile ? 18 : 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${plant.location} · Process overview', style: const TextStyle(color: AppColors.textMuted)),
        ]),
        Wrap(spacing: 8, runSpacing: 6, children: [
          StatusChip(
            switch (status) { 'alarm' => 'Plant in alarm', 'warning' => 'Plant warning', _ => 'Plant normal' },
            color: plantStatusColor(status),
            icon: status == 'normal' ? Icons.check_circle_outline : Icons.warning_amber_rounded,
          ),
          if (scenario != null) StatusChip('Scenario: ${scenario.name}', color: scenario.id == 'normal' ? AppColors.info : AppColors.warning, icon: Icons.science_outlined),
          if (state != null)
            Tooltip(
              message: 'Simulation clock (plant time). Updated ${timeAgo(state!.updatedAt)}',
              child: StatusChip('Sim ${fmtShort(state!.simTime)}', color: state!.autoRun ? AppColors.running : AppColors.warning, icon: state!.autoRun ? Icons.play_circle_outline : Icons.pause_circle_outline),
            ),
        ]),
      ],
    );
  }
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.state, required this.tanks});
  final PlantState? state;
  final (double?, double?) tanks;
  @override
  Widget build(BuildContext context) {
    final s = state;
    final tiles = [
      KpiTile(label: 'Raw water inflow', value: fmtNum(s?.inletFlow, digits: 0), unit: 'm³/h', icon: Icons.south_east),
      KpiTile(label: 'Transfer flow', value: fmtNum(s?.transferFlow, digits: 0), unit: 'm³/h', icon: Icons.sync_alt),
      KpiTile(label: 'Distribution flow', value: fmtNum(s?.distributionFlow, digits: 0), unit: 'm³/h', icon: Icons.north_east, color: AppColors.running),
      KpiTile(label: 'Network demand', value: fmtNum(s?.demand, digits: 0), unit: 'm³/h', icon: Icons.location_city, color: AppColors.secondary),
      KpiTile(label: 'T-101 level', value: fmtNum(tanks.$1), unit: '%', icon: Icons.water, color: AppColors.water),
      KpiTile(label: 'T-102 level', value: fmtNum(tanks.$2), unit: '%', icon: Icons.water, color: AppColors.water),
      KpiTile(label: 'Transfer pressure', value: fmtNum(s?.transferPressure, digits: 2), unit: 'bar', icon: Icons.speed, color: (s?.transferPressure ?? 0) >= 6 ? AppColors.fault : AppColors.primary),
      KpiTile(label: 'Header pressure', value: fmtNum(s?.distributionPressure, digits: 2), unit: 'bar', icon: Icons.speed, color: (s?.distributionPressure ?? 0) >= 6 ? AppColors.fault : AppColors.primary),
    ];
    if (context.isMobile) {
      return SizedBox(
        height: 86,
        child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: tiles.length, separatorBuilder: (_, _) => const SizedBox(width: 8), itemBuilder: (_, i) => tiles[i]),
      );
    }
    return Wrap(spacing: 10, runSpacing: 10, children: tiles);
  }
}

class _AlarmSummary extends ConsumerWidget {
  const _AlarmSummary({required this.plantId});
  final String plantId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarms = ref.watch(plantOpenAlarmsProvider(plantId));
    return SectionCard(
      title: 'Active alarms',
      icon: Icons.notifications_active_outlined,
      trailing: TextButton(onPressed: () => context.go('/alarms'), child: Text('View all (${alarms.length})')),
      child: alarms.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_outline, color: AppColors.running),
                SizedBox(width: 8),
                Text('No active alarms', style: TextStyle(color: AppColors.textMuted)),
              ]),
            )
          : Column(children: [for (final a in alarms.take(5)) AlarmRow(alarm: a, dense: true)]),
    );
  }
}

class AlarmRow extends StatelessWidget {
  const AlarmRow({super.key, required this.alarm, this.dense = false, this.trailing, this.onTap, this.selected = false});
  final Alarm alarm;
  final bool dense;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final color = priorityColor(alarm.priority.name);
    final blink = alarm.state == 'active';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 8 : 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.10) : (blink ? color.withValues(alpha: 0.08) : AppColors.surfaceHigh),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(alarm.tag, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                StatusChip(alarm.priority.label, color: color, dense: true),
                const SizedBox(width: 6),
                if (!dense) StatusChip(alarm.stateLabel, color: alarm.needsAck ? AppColors.warning : AppColors.textMuted, dense: true),
              ]),
              const SizedBox(height: 4),
              Text(alarm.message, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '${fmtShort(alarm.when)}${alarm.value != null ? ' · value ${alarm.value!.toStringAsFixed(1)}' : ''}'
                '${alarm.acknowledgedByName != null ? ' · ack. by ${alarm.acknowledgedByName}' : ''}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }
}

class _RecentEvents extends ConsumerWidget {
  const _RecentEvents({required this.plantId});
  final String plantId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider(plantId));
    return SectionCard(
      title: 'Recent events',
      icon: Icons.history,
      trailing: TextButton(onPressed: () => context.go('/simulation'), child: const Text('Event log')),
      child: AsyncValueView(
        value: events,
        loading: const LoadingView(),
        data: (list) => list.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Text('No events yet.', style: TextStyle(color: AppColors.textMuted)))
            : Column(children: [for (final e in list.take(7)) EventRow(event: e)]),
      ),
    );
  }
}

class EventRow extends StatelessWidget {
  const EventRow({super.key, required this.event});
  final EventLog event;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 9, color: severityColor(event.severity))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.message, style: const TextStyle(fontSize: 13)),
              Text('${fmtShort(event.createdAt)} · ${titleCase(event.category)}${event.actorName != null ? ' · ${event.actorName}' : ''}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ]),
          ),
        ]),
      );
}
