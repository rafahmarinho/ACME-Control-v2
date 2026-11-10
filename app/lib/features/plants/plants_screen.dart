import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/plant.dart';
import '../../data/repositories/operations_repository.dart';
import '../../data/repositories/plant_repository.dart';

class PlantsScreen extends ConsumerWidget {
  const PlantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plants = ref.watch(plantsProvider);
    return SingleChildScrollView(
      child: PageBody(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const PageHeader(title: 'Plants', subtitle: 'Fleet overview of the water treatment plants you operate'),
          AsyncValueView(
            value: plants,
            onRetry: () => ref.invalidate(plantsProvider),
            data: (list) => LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 900 ? 2 : 1;
              final w = (c.maxWidth - (cols - 1) * 16) / cols;
              return Wrap(spacing: 16, runSpacing: 16, children: [for (final p in list) SizedBox(width: w, child: _PlantCard(plant: p))]);
            }),
          ),
        ]),
      ),
    );
  }
}

class _PlantCard extends ConsumerWidget {
  const _PlantCard({required this.plant});
  final Plant plant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(plantStateProvider(plant.id)).value;
    final eq = ref.watch(equipmentByTagProvider(plant.id));
    final alarms = ref.watch(plantOpenAlarmsProvider(plant.id));
    final orders = ref.watch(maintenanceOrdersProvider(plant.id)).value ?? const [];
    final scenarios = ref.watch(scenariosProvider).value ?? const [];
    final selected = ref.watch(selectedPlantIdProvider) == plant.id;
    final status = state?.status ?? 'normal';
    final scenario = scenarios.where((s) => s.id == state?.scenarioId).firstOrNull;
    final runningPumps = eq.values.where((e) => e.isPump && e.actualState == 'running').length;
    final totalPumps = eq.values.where((e) => e.isPump).length;
    final openOrders = orders.where((o) => !o.isClosed).length;
    final critical = alarms.where((a) => a.priority.rank <= 1 && a.isConditionActive).length;

    Widget level(String tag) {
      final t = eq[tag];
      final v = (t?.levelPct ?? 0) / 100;
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$tag · ${t?.name ?? ''}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: v.clamp(0, 1), minHeight: 10, backgroundColor: AppColors.surfaceHigh, color: stateColor(t?.actualState)),
          ),
          const SizedBox(height: 4),
          Text('${fmtNum(t?.levelPct)} %', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.outline, width: selected ? 1.6 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: plantStatusColor(status).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.factory, color: plantStatusColor(status)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plant.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text('${plant.code} · ${plant.location}', style: const TextStyle(color: AppColors.textMuted)),
              ]),
            ),
            StatusChip(titleCase(status), color: plantStatusColor(status)),
          ]),
          if (plant.description != null) ...[
            const SizedBox(height: 12),
            Text(plant.description!, style: const TextStyle(color: Color(0xFFB4C2D0))),
          ],
          const SizedBox(height: 16),
          Row(children: [level('T-101'), const SizedBox(width: 16), level('T-102')]),
          const SizedBox(height: 16),
          Wrap(spacing: 18, runSpacing: 10, children: [
            _Stat('Inflow', '${fmtNum(state?.inletFlow, digits: 0)} m³/h'),
            _Stat('Distribution', '${fmtNum(state?.distributionFlow, digits: 0)} m³/h'),
            _Stat('Header pressure', '${fmtNum(state?.distributionPressure, digits: 2)} bar'),
            _Stat('Pumps running', '$runningPumps / $totalPumps'),
            _Stat('Open alarms', '${alarms.length}${critical > 0 ? ' ($critical high+)' : ''}', color: critical > 0 ? AppColors.fault : null),
            _Stat('Open work orders', '$openOrders'),
            _Stat('Capacity', '${plant.designCapacity.toStringAsFixed(0)} m³/h'),
            _Stat('Scenario', scenario?.name ?? '—'),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  ref.read(selectedPlantIdProvider.notifier).select(plant.id);
                  context.go('/process');
                },
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Open process view'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () {
                ref.read(selectedPlantIdProvider.notifier).select(plant.id);
                context.go('/alarms');
              },
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('Alarms'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 130,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis),
        ]),
      );
}
