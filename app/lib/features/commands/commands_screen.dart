import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/equipment.dart';
import '../../data/models/operations.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/core_providers.dart';
import '../process/equipment_control_panel.dart';

class CommandsScreen extends ConsumerStatefulWidget {
  const CommandsScreen({super.key});
  @override
  ConsumerState<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends ConsumerState<CommandsScreen> {
  String _status = 'all';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final plantId = ref.watch(selectedPlantIdProvider);
    final equipment = (ref.watch(equipmentProvider(plantId)).value ?? const <Equipment>[]).where((e) => e.isControllable).toList();
    final commands = ref.watch(commandsProvider(plantId));
    final wide = context.width >= 1100;

    final console = SectionCard(
      title: 'Operator console',
      icon: Icons.toggle_on_outlined,
      child: equipment.isEmpty
          ? const LoadingView()
          : Column(children: [for (final e in equipment) _ConsoleRow(equipment: e)]),
    );

    final log = SectionCard(
      title: 'Command log',
      icon: Icons.receipt_long_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SearchField(hint: 'Search tag, user or result', onChanged: (v) => setState(() => _query = v.trim().toLowerCase())),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final s in ['all', 'completed', 'in_progress', 'blocked', 'rejected'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(s == 'all' ? 'All' : titleCase(s)), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        AsyncValueView<List<ControlCommand>>(
          value: commands,
          onRetry: () => ref.invalidate(commandsProvider(plantId)),
          data: (list) {
            final items = list.where((c) {
              if (_status != 'all' && c.status != _status) return false;
              if (_query.isEmpty) return true;
              return '${c.tag} ${c.requestedByName ?? ''} ${c.resultMessage ?? ''} ${c.action}'.toLowerCase().contains(_query);
            }).toList();
            if (items.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: EmptyState(icon: Icons.inbox_outlined, title: 'No commands match'));
            return Column(children: [for (final c in items.take(80)) _CommandTile(command: c)]);
          },
        ),
      ]),
    );

    return SingleChildScrollView(
      child: PageBody(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const PageHeader(
            title: 'Commands',
            subtitle: 'Operate pumps and valves and review the command audit trail. Results reflect the real process response.',
          ),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: console),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: log),
            ])
          else ...[
            console,
            const SizedBox(height: 12),
            log,
          ],
        ]),
      ),
    );
  }
}

class _ConsoleRow extends ConsumerWidget {
  const _ConsoleRow({required this.equipment});
  final Equipment equipment;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = equipment;
    final canCommand = (ref.watch(currentRoleProvider)?.canCommand ?? false) && ref.watch(isOnlineProvider);
    final on = e.isPump ? 'start' : 'open';
    final off = e.isPump ? 'stop' : 'close';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(10)),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 8,
        spacing: 8,
        children: [
          InkWell(
            onTap: () => context.go('/equipment/${e.id}'),
            child: SizedBox(
              width: 210,
              child: Row(children: [
                Icon(equipmentIcon(e.kind), color: stateColor(e.actualState), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.tag, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(e.name, style: const TextStyle(color: AppColors.textMuted, fontSize: 11), overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
          ),
          SizedBox(
            width: 170,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Req: ${stateLabel(e.requestedState)}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              Text('Act: ${stateLabel(e.actualState)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: stateColor(e.actualState))),
            ]),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 40)),
              segments: const [ButtonSegment(value: 'auto', label: Text('A')), ButtonSegment(value: 'manual', label: Text('M'))],
              selected: {e.controlMode ?? 'auto'},
              onSelectionChanged: canCommand ? (s) => sendEquipmentCommand(context, ref, e, s.first == 'auto' ? 'set_auto' : 'set_manual') : null,
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: e.isPump ? 'Start' : 'Open',
              onPressed: canCommand && e.isManual ? () => sendEquipmentCommand(context, ref, e, on) : null,
              icon: Icon(e.isPump ? Icons.play_arrow : Icons.unfold_more, color: canCommand && e.isManual ? AppColors.running : null),
            ),
            IconButton.filledTonal(
              tooltip: e.isPump ? 'Stop' : 'Close',
              onPressed: canCommand && e.isManual ? () => sendEquipmentCommand(context, ref, e, off) : null,
              icon: Icon(e.isPump ? Icons.stop : Icons.unfold_less, color: canCommand && e.isManual ? AppColors.fault : null),
            ),
          ]),
        ],
      ),
    );
  }
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({required this.command});
  final ControlCommand command;
  @override
  Widget build(BuildContext context) {
    final c = command;
    final color = commandStatusColor(c.status);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.actionLabel} ${c.tag}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (c.resultMessage != null) ...[const SizedBox(height: 2), Text(c.resultMessage!, style: const TextStyle(fontSize: 13))],
            const SizedBox(height: 2),
            Text('${fmtShort(c.createdAt)} · ${c.requestedByName ?? 'System'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ),
        StatusChip(titleCase(c.status), color: color, dense: true),
      ]),
    );
  }
}
