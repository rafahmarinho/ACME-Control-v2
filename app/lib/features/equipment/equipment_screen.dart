import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/equipment.dart';
import '../../data/repositories/plant_repository.dart';
import '../process/equipment_control_panel.dart';

class EquipmentScreen extends ConsumerStatefulWidget {
  const EquipmentScreen({super.key});
  @override
  ConsumerState<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends ConsumerState<EquipmentScreen> {
  String _query = '';
  EquipmentKind? _kind;
  String _status = 'all';

  bool _matches(Equipment e) {
    if (_kind != null && e.kind != _kind) return false;
    switch (_status) {
      case 'active':
        if (!e.isActive) return false;
      case 'inactive':
        if (!(e.actualState == 'stopped' || e.actualState == 'closed')) return false;
      case 'abnormal':
        if (!e.isAbnormal && !e.hasMismatch) return false;
      case 'maintenance':
        if (!e.inMaintenance) return false;
      case 'manual':
        if (!e.isManual) return false;
    }
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return '${e.tag} ${e.name} ${e.area} ${e.manufacturer ?? ''} ${e.model ?? ''}'.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final plantId = ref.watch(selectedPlantIdProvider);
    final async = ref.watch(equipmentProvider(plantId));

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: PageBody(
          padding: EdgeInsets.fromLTRB(context.isMobile ? 12 : 20, context.isMobile ? 12 : 20, context.isMobile ? 12 : 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PageHeader(title: 'Equipment', subtitle: 'Assets, live state and requested vs. actual status'),
            SearchField(hint: 'Search tag, name, area or model', onChanged: (v) => setState(() => _query = v.trim())),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final k in [null, ...EquipmentKind.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(k == null ? 'All types' : '${k.label}s'),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                  ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.outline)),
                    child: DropdownButton<String>(
                      value: _status,
                      onChanged: (v) => setState(() => _status = v ?? 'all'),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Any status')),
                        DropdownMenuItem(value: 'active', child: Text('Running / open')),
                        DropdownMenuItem(value: 'inactive', child: Text('Stopped / closed')),
                        DropdownMenuItem(value: 'abnormal', child: Text('Abnormal or mismatch')),
                        DropdownMenuItem(value: 'maintenance', child: Text('In maintenance')),
                        DropdownMenuItem(value: 'manual', child: Text('Manual mode')),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
      ...async.when(
        loading: () => [const SliverFillRemaining(child: LoadingView())],
        error: (e, _) => [SliverFillRemaining(child: ErrorView(error: e, onRetry: () => ref.invalidate(equipmentProvider(plantId))))],
        data: (list) {
          final items = list.where(_matches).toList();
          if (items.isEmpty) {
            return [
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(icon: Icons.search_off, title: 'No equipment matches your filters', message: 'Try a different search term or clear the filters.'),
              ),
            ];
          }
          return [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(context.isMobile ? 12 : 20, 0, context.isMobile ? 12 : 20, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 420, mainAxisExtent: 148, crossAxisSpacing: 12, mainAxisSpacing: 12),
                delegate: SliverChildBuilderDelegate((context, i) => _EquipmentCard(equipment: items[i]), childCount: items.length),
              ),
            ),
          ];
        },
      ),
    ]);
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.equipment});
  final Equipment equipment;
  @override
  Widget build(BuildContext context) {
    final e = equipment;
    final color = stateColor(e.actualState);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/equipment/${e.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
                child: Icon(equipmentIcon(e.kind), color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.tag, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(e.name, style: const TextStyle(color: AppColors.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
                ]),
              ),
              Text(e.primaryReading, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
            const Spacer(),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusChip(stateLabel(e.actualState), color: color, dense: true),
              if (e.controlMode != null) StatusChip(e.isAuto ? 'AUTO' : 'MANUAL', color: e.isAuto ? AppColors.secondary : AppColors.warning, dense: true),
              if (e.hasMismatch) StatusChip('Requested: ${stateLabel(e.requestedState)}', color: AppColors.warning, dense: true, icon: Icons.compare_arrows),
              if (e.inMaintenance) const StatusChip('LOTO', color: AppColors.lockout, dense: true, icon: Icons.lock_outline),
            ]),
            const SizedBox(height: 6),
            Text('${e.area} · ${e.manufacturer ?? ''} ${e.model ?? ''}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}
