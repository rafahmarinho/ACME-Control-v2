import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/operations.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/core_providers.dart';
import '../process/process_screen.dart' show AlarmRow;

class AlarmsScreen extends ConsumerStatefulWidget {
  const AlarmsScreen({super.key});
  @override
  ConsumerState<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends ConsumerState<AlarmsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final Set<AlarmPriority> _priorities = {};
  String _state = 'all';
  String _query = '';
  int _historyDays = 7;
  final Set<String> _selected = {};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Alarm> _filter(List<Alarm> list) => list.where((a) {
        if (_priorities.isNotEmpty && !_priorities.contains(a.priority)) return false;
        if (_state == 'unack' && !a.needsAck) return false;
        if (_state == 'active' && !a.isConditionActive) return false;
        if (_state == 'cleared' && a.isConditionActive) return false;
        if (_query.isNotEmpty && !'${a.tag} ${a.message} ${a.code}'.toLowerCase().contains(_query.toLowerCase())) return false;
        return true;
      }).toList();

  Future<void> _acknowledge(List<String> ids) async {
    if (ids.isEmpty || !ensureOnline(context, ref)) return;
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Acknowledge ${ids.length} alarm${ids.length == 1 ? '' : 's'}'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: comment,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Comment (optional)', hintText: 'e.g. Operator dispatched to check level transmitter'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Acknowledge')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await runAction(context, () async {
      final n = await ref.read(alarmRepositoryProvider).acknowledge(ids, comment: comment.text);
      setState(_selected.clear);
      if (n == 0) throw Exception('These alarms were already acknowledged.');
    }, success: 'Alarm${ids.length == 1 ? '' : 's'} acknowledged.');
  }

  @override
  Widget build(BuildContext context) {
    final plantId = ref.watch(selectedPlantIdProvider);
    final openAsync = ref.watch(openAlarmsProvider);
    final open = _filter(ref.watch(plantOpenAlarmsProvider(plantId)));
    final online = ref.watch(isOnlineProvider);
    final unackIds = open.where((a) => a.needsAck).map((a) => a.id).toList();

    return Column(children: [
      PageBody(
        padding: EdgeInsets.fromLTRB(context.isMobile ? 12 : 20, context.isMobile ? 12 : 20, context.isMobile ? 12 : 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PageHeader(
            title: 'Alarms',
            subtitle: 'Prioritised alarm list with acknowledgement and history',
            actions: [
              if (_selected.isNotEmpty)
                FilledButton.icon(
                  onPressed: online ? () => _acknowledge(_selected.toList()) : null,
                  icon: const Icon(Icons.done_all),
                  label: Text('Acknowledge selected (${_selected.length})'),
                ),
              OutlinedButton.icon(
                onPressed: online && unackIds.isNotEmpty ? () => _acknowledge(unackIds) : null,
                icon: const Icon(Icons.done_all),
                label: Text('Acknowledge all (${unackIds.length})'),
              ),
            ],
          ),
          SearchField(hint: 'Search tag or message', onChanged: (v) => setState(() => _query = v.trim())),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final p in AlarmPriority.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(p.label),
                    avatar: Icon(Icons.circle, size: 10, color: priorityColor(p.name)),
                    selected: _priorities.contains(p),
                    onSelected: (v) => setState(() => v ? _priorities.add(p) : _priorities.remove(p)),
                  ),
                ),
              const SizedBox(width: 8),
              for (final (v, l) in [('all', 'Any state'), ('unack', 'Unacknowledged'), ('active', 'Condition active'), ('cleared', 'Cleared')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(l), selected: _state == v, onSelected: (_) => setState(() => _state = v)),
                ),
            ]),
          ),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Open (${open.length})'), const Tab(text: 'History')],
          ),
        ]),
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          // Open alarms (live)
          openAsync.hasError && !openAsync.hasValue
              ? ErrorView(error: openAsync.error!, onRetry: () => ref.invalidate(openAlarmsProvider))
              : !openAsync.hasValue
                  ? const LoadingView()
                  : open.isEmpty
                      ? const EmptyState(icon: Icons.check_circle_outline, title: 'No open alarms', message: 'All alarm conditions are clear for this plant.')
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: context.isMobile ? 12 : 20, vertical: 12),
                          itemCount: open.length,
                          itemBuilder: (_, i) {
                            final a = open[i];
                            return AlarmRow(
                              alarm: a,
                              selected: _selected.contains(a.id),
                              onTap: a.needsAck ? () => setState(() => _selected.contains(a.id) ? _selected.remove(a.id) : _selected.add(a.id)) : null,
                              trailing: a.needsAck
                                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                                      Checkbox(value: _selected.contains(a.id), onChanged: (v) => setState(() => v == true ? _selected.add(a.id) : _selected.remove(a.id))),
                                      if (!context.isMobile)
                                        TextButton(onPressed: online ? () => _acknowledge([a.id]) : null, child: const Text('Ack')),
                                    ])
                                  : const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.check, color: AppColors.textMuted, size: 18)),
                            );
                          },
                        ),
          // History
          Consumer(builder: (context, ref, _) {
            final q = AlarmHistoryQuery(plantId, days: _historyDays);
            final hist = ref.watch(alarmHistoryProvider(q));
            return Column(children: [
              Padding(
                padding: EdgeInsets.fromLTRB(context.isMobile ? 12 : 20, 10, context.isMobile ? 12 : 20, 0),
                child: Row(children: [
                  const Text('Period:', style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(width: 8),
                  for (final d in [1, 7, 30])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: Text(d == 1 ? '24 h' : '$d days'), selected: _historyDays == d, onSelected: (_) => setState(() => _historyDays = d)),
                    ),
                  const Spacer(),
                  IconButton(tooltip: 'Refresh', onPressed: () => ref.invalidate(alarmHistoryProvider(q)), icon: const Icon(Icons.refresh)),
                ]),
              ),
              Expanded(
                child: AsyncValueView(
                  value: hist,
                  onRetry: () => ref.invalidate(alarmHistoryProvider(q)),
                  data: (list) {
                    final items = _filter(list);
                    if (items.isEmpty) return const EmptyState(icon: Icons.history, title: 'No alarms in this period');
                    return ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: context.isMobile ? 12 : 20, vertical: 12),
                      itemCount: items.length,
                      itemBuilder: (_, i) => AlarmRow(alarm: items[i]),
                    );
                  },
                ),
              ),
            ]);
          }),
        ]),
      ),
    ]);
  }
}
