import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/operations.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/core_providers.dart';
import 'trend_chart.dart';

class _Group {
  const _Group(this.name, this.unit, this.tags);
  final String name;
  final String unit;
  final List<(String, String)> tags;
}

const _groups = [
  _Group('Levels', '%', [('LT-101', 'Raw water tank'), ('LT-102', 'Clearwell')]),
  _Group('Flows', 'm³/h', [('FT-101', 'Raw water inflow'), ('FT-102', 'Transfer flow'), ('FT-201', 'Distribution flow')]),
  _Group('Pressures', 'bar', [('PT-101', 'Transfer discharge'), ('PT-201', 'Distribution header')]),
];

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key, this.initialTag});
  final String? initialTag;
  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  late int _group;
  late Set<String> _tags;
  int _hours = 6;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    final gi = widget.initialTag == null ? 0 : _groups.indexWhere((g) => g.tags.any((t) => t.$1 == widget.initialTag));
    _group = gi < 0 ? 0 : gi;
    _tags = widget.initialTag != null && gi >= 0 ? {widget.initialTag!} : _groups[_group].tags.map((t) => t.$1).toSet();
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && ref.read(liveSyncProvider)) ref.invalidate(trendProvider);
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  void _copyCsv(Map<String, List<Measurement>> data) {
    final fmt = DateFormat("yyyy-MM-dd'T'HH:mm:ss");
    final b = StringBuffer('timestamp,tag,value\n');
    for (final e in data.entries) {
      for (final m in e.value) {
        b.writeln('${fmt.format(m.ts)},${e.key},${m.value}');
      }
    }
    Clipboard.setData(ClipboardData(text: b.toString()));
    showSnack(context, 'Copied ${data.values.fold<int>(0, (s, l) => s + l.length)} samples as CSV to the clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final plantId = ref.watch(selectedPlantIdProvider);
    final group = _groups[_group];
    final ordered = group.tags.map((t) => t.$1).where(_tags.contains).toList();
    final q = TrendQuery(plantId, ordered, _hours);
    final data = ref.watch(trendProvider(q));

    return SingleChildScrollView(
      child: PageBody(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PageHeader(
            title: 'Trends',
            subtitle: 'Historical process values (simulation clock)',
            actions: [
              OutlinedButton.icon(onPressed: () => ref.invalidate(trendProvider(q)), icon: const Icon(Icons.refresh), label: const Text('Refresh')),
              OutlinedButton.icon(onPressed: data.hasValue ? () => _copyCsv(data.value!) : null, icon: const Icon(Icons.copy_all), label: const Text('Copy CSV')),
            ],
          ),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [for (final (i, g) in _groups.indexed) ButtonSegment(value: i, label: Text('${g.name} (${g.unit})'))],
            selected: {_group},
            onSelectionChanged: (s) => setState(() {
              _group = s.first;
              _tags = _groups[_group].tags.map((t) => t.$1).toSet();
            }),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, t) in group.tags.indexed)
              FilterChip(
                avatar: Icon(Icons.show_chart, size: 16, color: trendPalette[ordered.contains(t.$1) ? ordered.indexOf(t.$1) : i]),
                label: Text('${t.$1} · ${t.$2}'),
                selected: _tags.contains(t.$1),
                onSelected: (v) => setState(() {
                  if (v) {
                    _tags.add(t.$1);
                  } else if (_tags.length > 1) {
                    _tags.remove(t.$1);
                  }
                }),
              ),
            const SizedBox(width: 12),
            for (final h in [1, 6, 12, 24])
              ChoiceChip(label: Text('$h h'), selected: _hours == h, onSelected: (_) => setState(() => _hours = h)),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: '${group.name} — last $_hours h',
            icon: Icons.show_chart,
            child: AsyncValueView(
              value: data,
              onRetry: () => ref.invalidate(trendProvider(q)),
              loading: const SizedBox(height: 340, child: LoadingView(message: 'Loading samples…')),
              data: (s) => TrendChart(series: s, unit: group.unit, height: context.isMobile ? 260 : 360, minY: group.unit == '%' ? 0 : null, maxY: group.unit == '%' ? 100 : null),
            ),
          ),
          const SizedBox(height: 16),
          if (data.hasValue) _StatsTable(data: data.value!, unit: group.unit),
        ]),
      ),
    );
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.data, required this.unit});
  final Map<String, List<Measurement>> data;
  final String unit;
  @override
  Widget build(BuildContext context) {
    String f(double v) => unit == 'bar' ? v.toStringAsFixed(2) : v.toStringAsFixed(1);
    return SectionCard(
      title: 'Statistics',
      icon: Icons.analytics_outlined,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
          columns: const [
            DataColumn(label: Text('Tag')),
            DataColumn(label: Text('Last'), numeric: true),
            DataColumn(label: Text('Min'), numeric: true),
            DataColumn(label: Text('Max'), numeric: true),
            DataColumn(label: Text('Average'), numeric: true),
            DataColumn(label: Text('Samples'), numeric: true),
          ],
          rows: [
            for (final e in data.entries)
              if (e.value.isNotEmpty)
                DataRow(cells: [
                  DataCell(Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(Text('${f(e.value.last.value)} $unit')),
                  DataCell(Text(f(e.value.map((m) => m.value).reduce(math.min)))),
                  DataCell(Text(f(e.value.map((m) => m.value).reduce(math.max)))),
                  DataCell(Text(f(e.value.fold<double>(0, (s, m) => s + m.value) / e.value.length))),
                  DataCell(Text('${e.value.length}')),
                ]),
          ],
        ),
      ),
    );
  }
}
