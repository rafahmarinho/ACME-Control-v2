import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/equipment.dart';
import '../../data/repositories/operations_repository.dart';
import '../../data/repositories/plant_repository.dart';
import '../process/equipment_control_panel.dart';
import '../trends/trend_chart.dart';

class EquipmentDetailScreen extends ConsumerWidget {
  const EquipmentDetailScreen({super.key, required this.equipmentId});
  final String equipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(equipmentByIdProvider(equipmentId));
    return AsyncValueView<Equipment?>(
      value: async,
      data: (e) {
        if (e == null) {
          return EmptyState(
            icon: Icons.precision_manufacturing_outlined,
            title: 'Equipment not found',
            message: 'It may have been removed when the demo data was reset.',
            action: OutlinedButton(onPressed: () => context.go('/equipment'), child: const Text('Back to equipment')),
          );
        }
        final wide = context.width >= 1000;
        final control = SectionCard(title: 'Status & control', icon: Icons.toggle_on_outlined, child: EquipmentControlPanel(equipment: e, showHeader: false));
        final specs = SectionCard(
          title: 'Specifications',
          icon: Icons.info_outline,
          child: Column(children: [
            LabelValue('Type', e.kind.label),
            LabelValue('Area', e.area),
            if (e.description != null) LabelValue('Description', e.description!),
            LabelValue('Manufacturer', e.manufacturer ?? '—'),
            LabelValue('Model', e.model ?? '—'),
            LabelValue('Serial number', e.serialNumber ?? '—'),
            LabelValue('Installed', fmtDate(e.installedOn)),
            if (e.isPump) LabelValue('Starts', '${e.startsCount}'),
            LabelValue('Last update', '${fmtTime(e.updatedAt)} (${timeAgo(e.updatedAt)})'),
          ]),
        );
        final trend = e.trendTag == null ? null : _MiniTrend(plantId: e.plantId, tag: e.trendTag!);
        final orders = _WorkOrders(equipment: e);
        final commands = _Commands(equipment: e);

        return SingleChildScrollView(
          child: PageBody(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: () => context.go('/equipment'), icon: const Icon(Icons.arrow_back), label: const Text('Equipment')),
              ),
              PageHeader(
                title: '${e.tag} · ${e.name}',
                subtitle: '${e.kind.label} · ${e.area}',
                actions: [
                  if (e.trendTag != null)
                    OutlinedButton.icon(onPressed: () => context.go('/trends?tag=${e.trendTag}'), icon: const Icon(Icons.show_chart), label: const Text('Open trends')),
                ],
              ),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(children: [control, const SizedBox(height: 16), specs])),
                  const SizedBox(width: 16),
                  Expanded(child: Column(children: [?trend, if (trend != null) const SizedBox(height: 16), orders, const SizedBox(height: 16), commands])),
                ])
              else
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  control,
                  const SizedBox(height: 12),
                  ?trend,
                  if (trend != null) const SizedBox(height: 12),
                  specs,
                  const SizedBox(height: 12),
                  orders,
                  const SizedBox(height: 12),
                  commands,
                ]),
            ]),
          ),
        );
      },
    );
  }
}

class _MiniTrend extends ConsumerWidget {
  const _MiniTrend({required this.plantId, required this.tag});
  final String plantId;
  final String tag;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = TrendQuery(plantId, [tag], 6);
    final data = ref.watch(trendProvider(q));
    final unit = tag.startsWith('LT') ? '%' : tag.startsWith('PT') ? 'bar' : 'm³/h';
    return SectionCard(
      title: '$tag — last 6 h',
      icon: Icons.show_chart,
      trailing: IconButton(tooltip: 'Refresh', onPressed: () => ref.invalidate(trendProvider(q)), icon: const Icon(Icons.refresh, size: 20)),
      child: AsyncValueView(value: data, data: (s) => TrendChart(series: s, unit: unit, height: 200)),
    );
  }
}

class _WorkOrders extends ConsumerWidget {
  const _WorkOrders({required this.equipment});
  final Equipment equipment;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = (ref.watch(maintenanceOrdersProvider(equipment.plantId)).value ?? const []).where((o) => o.equipmentId == equipment.id).toList();
    return SectionCard(
      title: 'Work orders',
      icon: Icons.build_outlined,
      trailing: TextButton(onPressed: () => context.go('/maintenance'), child: const Text('Maintenance')),
      child: orders.isEmpty
          ? const Text('No work orders for this asset.', style: TextStyle(color: AppColors.textMuted))
          : Column(children: [
              for (final o in orders)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => context.go('/maintenance/${o.id}'),
                  title: Text('${o.number} · ${o.title}'),
                  subtitle: Text('${titleCase(o.type)} · due ${fmtDate(o.dueDate)}'),
                  trailing: StatusChip(titleCase(o.status), color: workOrderStatusColor(o.status), dense: true),
                ),
            ]),
    );
  }
}

class _Commands extends ConsumerWidget {
  const _Commands({required this.equipment});
  final Equipment equipment;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cmds = (ref.watch(commandsProvider(equipment.plantId)).value ?? const []).where((c) => c.equipmentId == equipment.id).take(8).toList();
    return SectionCard(
      title: 'Recent commands',
      icon: Icons.history,
      child: cmds.isEmpty
          ? const Text('No commands issued for this asset.', style: TextStyle(color: AppColors.textMuted))
          : Column(children: [
              for (final c in cmds)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${c.actionLabel} — ${c.resultMessage ?? 'pending'}'),
                  subtitle: Text('${fmtShort(c.createdAt)} · ${c.requestedByName ?? 'System'}'),
                  trailing: StatusChip(titleCase(c.status), color: commandStatusColor(c.status), dense: true),
                ),
            ]),
    );
  }
}
