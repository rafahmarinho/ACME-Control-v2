import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/operations.dart';

const trendPalette = [AppColors.water, AppColors.running, AppColors.warning, AppColors.secondary, Color(0xFFF472B6), Color(0xFFFB923C), Color(0xFFA3E635)];

/// Multi-series time chart for process measurements (same unit per chart).
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.series, this.unit = '', this.height = 300, this.colors = trendPalette, this.minY, this.maxY});

  final Map<String, List<Measurement>> series;
  final String unit;
  final double height;
  final List<Color> colors;
  final double? minY;
  final double? maxY;

  /// Down-samples long series to keep the chart responsive.
  static List<Measurement> _thin(List<Measurement> list, int max) {
    if (list.length <= max) return list;
    final step = list.length / max;
    return [for (var i = 0; i < max; i++) list[(i * step).floor()], list.last];
  }

  @override
  Widget build(BuildContext context) {
    final entries = series.entries.where((e) => e.value.isNotEmpty).toList();
    if (entries.isEmpty) {
      return SizedBox(height: height, child: const Center(child: Text('No samples in the selected time range.', style: TextStyle(color: AppColors.textMuted))));
    }
    final all = entries.expand((e) => e.value).toList();
    final minX = all.map((m) => m.ts.millisecondsSinceEpoch).reduce(math.min).toDouble();
    final maxX = all.map((m) => m.ts.millisecondsSinceEpoch).reduce(math.max).toDouble();
    var lo = minY ?? all.map((m) => m.value).reduce(math.min);
    var hi = maxY ?? all.map((m) => m.value).reduce(math.max);
    if (hi - lo < 1e-6) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.1;
    lo = minY ?? (lo - pad);
    hi = maxY ?? (hi + pad);
    final span = maxX - minX;
    final fmt = span > 36 * 3600e3 ? DateFormat('MMM d HH:mm') : DateFormat('HH:mm');

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX <= minX ? minX + 1 : maxX,
          minY: lo,
          maxY: hi,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            drawVerticalLine: true,
            getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFF1F2A36), strokeWidth: 1),
            getDrawingVerticalLine: (_) => const FlLine(color: Color(0xFF1A242F), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: true, border: Border.all(color: AppColors.outline)),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                getTitlesWidget: (v, meta) => Text(unit == 'bar' ? v.toStringAsFixed(1) : v.toStringAsFixed(0), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: span <= 0 ? null : span / 5,
                getTitlesWidget: (v, meta) {
                  if (v == meta.min || v == meta.max) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(fmt.format(DateTime.fromMillisecondsSinceEpoch(v.toInt())), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceHighest,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${entries[s.barIndex].key}  ${s.y.toStringAsFixed(unit == 'bar' ? 2 : 1)} $unit\n${DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(s.x.toInt()))}',
                    TextStyle(color: colors[s.barIndex % colors.length], fontWeight: FontWeight.w600, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            for (final (i, e) in entries.indexed)
              LineChartBarData(
                spots: [for (final m in _thin(e.value, 600)) FlSpot(m.ts.millisecondsSinceEpoch.toDouble(), m.value)],
                isCurved: true,
                curveSmoothness: 0.15,
                preventCurveOverShooting: true,
                barWidth: 2,
                color: colors[i % colors.length],
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: entries.length == 1, color: colors[i % colors.length].withValues(alpha: 0.10)),
              ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}
