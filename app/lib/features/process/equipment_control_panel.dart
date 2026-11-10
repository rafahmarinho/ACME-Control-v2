import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/equipment.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/app_settings.dart';
import '../../data/services/core_providers.dart';

/// Sends a control command through the API and reports the process response.
Future<void> sendEquipmentCommand(BuildContext context, WidgetRef ref, Equipment e, String action) async {
  if (!ensureOnline(context, ref)) return;
  const labels = {
    'start': 'Start',
    'stop': 'Stop',
    'open': 'Open',
    'close': 'Close',
    'set_auto': 'Switch to AUTO',
    'set_manual': 'Switch to MANUAL',
  };
  final label = labels[action] ?? action;
  final isOperate = !action.startsWith('set_');
  if (isOperate && ref.read(appSettingsProvider).confirmCommands) {
    final ok = await confirmDialog(
      context,
      title: '$label ${e.tag}?',
      message: '${e.name}\n\nThis command is sent to the plant immediately. Interlocks may prevent the equipment from reaching the requested state.',
      confirmLabel: label,
      destructive: action == 'stop' || action == 'close',
    );
    if (!ok || !context.mounted) return;
  }
  try {
    final res = await ref.read(apiClientProvider).sendCommand(plantId: e.plantId, equipmentId: e.id, action: action);
    if (!context.mounted) return;
    final status = res['status'] as String? ?? 'completed';
    final msg = res['message'] as String? ?? 'Command sent.';
    showSnack(
      context,
      '${titleCase(status)}: $msg',
      error: status == 'rejected',
      color: status == 'completed' ? const Color(0xFF14432F) : status == 'blocked' ? const Color(0xFF4A3608) : null,
    );
  } catch (err) {
    if (context.mounted) showSnack(context, ErrorView.messageOf(err), error: true);
  }
}

class EquipmentControlPanel extends ConsumerStatefulWidget {
  const EquipmentControlPanel({super.key, required this.equipment, this.onOpenDetails, this.showHeader = true});
  final Equipment equipment;
  final VoidCallback? onOpenDetails;
  final bool showHeader;

  @override
  ConsumerState<EquipmentControlPanel> createState() => _EquipmentControlPanelState();
}

class _EquipmentControlPanelState extends ConsumerState<EquipmentControlPanel> {
  String? _busyAction;

  Future<void> _run(String action) async {
    setState(() => _busyAction = action);
    await sendEquipmentCommand(context, ref, widget.equipment, action);
    if (mounted) setState(() => _busyAction = null);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.equipment;
    final role = ref.watch(currentRoleProvider);
    final online = ref.watch(isOnlineProvider);
    final canCommand = role?.canCommand ?? false;

    String? blockedReason;
    if (!canCommand) {
      blockedReason = 'Your role (${role?.label ?? '—'}) has view-only access to equipment controls.';
    } else if (!online) {
      blockedReason = 'Control actions require a connection.';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (widget.showHeader) ...[
        Row(children: [
          _KindIcon(kind: e.kind, color: stateColor(e.actualState)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.tag, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(e.name, style: const TextStyle(color: AppColors.textMuted)),
            ]),
          ),
          if (widget.onOpenDetails != null)
            IconButton(tooltip: 'Open asset details', onPressed: widget.onOpenDetails, icon: const Icon(Icons.open_in_new)),
        ]),
        const SizedBox(height: 14),
      ],
      Wrap(spacing: 6, runSpacing: 6, children: [
        StatusChip(stateLabel(e.actualState), color: stateColor(e.actualState)),
        if (e.controlMode != null)
          StatusChip(e.isAuto ? 'AUTO' : 'MANUAL', color: e.isAuto ? AppColors.secondary : AppColors.warning, icon: e.isAuto ? Icons.smart_toy_outlined : Icons.pan_tool_outlined),
        if (e.inMaintenance) const StatusChip('In maintenance', color: AppColors.lockout, icon: Icons.lock_outline),
        if (e.faultActive) const StatusChip('Fault injected', color: AppColors.fault, icon: Icons.bolt),
      ]),
      if (e.isControllable) ...[
        const SizedBox(height: 14),
        _RequestedVsActual(equipment: e),
      ],
      const SizedBox(height: 14),
      _Readings(equipment: e),
      if (e.isControllable) ...[
        const SizedBox(height: 16),
        const Text('CONTROL MODE', style: TextStyle(fontSize: 11, color: AppColors.textMuted, letterSpacing: 1)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(minimumSize: const Size(0, 46)),
          segments: const [
            ButtonSegment(value: 'auto', label: Text('AUTO'), icon: Icon(Icons.smart_toy_outlined)),
            ButtonSegment(value: 'manual', label: Text('MANUAL'), icon: Icon(Icons.pan_tool_outlined)),
          ],
          selected: {e.controlMode ?? 'auto'},
          onSelectionChanged: blockedReason != null || _busyAction != null
              ? null
              : (s) => _run(s.first == 'auto' ? 'set_auto' : 'set_manual'),
        ),
        const SizedBox(height: 14),
        const Text('OPERATE', style: TextStyle(fontSize: 11, color: AppColors.textMuted, letterSpacing: 1)),
        const SizedBox(height: 6),
        Row(children: [
          for (final (i, a) in (e.isPump
                  ? [('start', 'Start', Icons.play_arrow_rounded, AppColors.running), ('stop', 'Stop', Icons.stop_rounded, AppColors.fault)]
                  : [('open', 'Open', Icons.unfold_more, AppColors.running), ('close', 'Close', Icons.unfold_less, AppColors.fault)])
              .indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  backgroundColor: a.$4.withValues(alpha: 0.18),
                  foregroundColor: a.$4,
                  disabledBackgroundColor: AppColors.surfaceHigh,
                  side: BorderSide(color: a.$4.withValues(alpha: 0.5)),
                ),
                onPressed: blockedReason != null || e.isAuto || _busyAction != null ? null : () => _run(a.$1),
                icon: _busyAction == a.$1
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(a.$3),
                label: Text(a.$2),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        if (blockedReason != null)
          _Hint(icon: Icons.lock_outline, text: blockedReason)
        else if (e.isAuto)
          const _Hint(icon: Icons.info_outline, text: 'In AUTO the control logic operates this equipment. Switch to MANUAL to start/stop or open/close it.'),
      ],
    ]);
  }
}

class _RequestedVsActual extends StatelessWidget {
  const _RequestedVsActual({required this.equipment});
  final Equipment equipment;
  @override
  Widget build(BuildContext context) {
    final e = equipment;
    final mismatch = e.hasMismatch;
    Widget box(String label, String value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, letterSpacing: 0.8)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        box('REQUESTED${e.isAuto ? ' (AUTO)' : ''}', stateLabel(e.requestedState), AppColors.textMuted.withValues(alpha: 0.9)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(mismatch ? Icons.compare_arrows : Icons.arrow_forward, color: mismatch ? AppColors.warning : AppColors.textMuted, size: 20),
        ),
        box('ACTUAL', stateLabel(e.actualState), stateColor(e.actualState)),
      ]),
      if (e.interlockReason != null) ...[
        const SizedBox(height: 8),
        _Hint(icon: Icons.warning_amber_rounded, text: e.interlockReason!, color: e.inMaintenance ? AppColors.lockout : AppColors.warning),
      ],
    ]);
  }
}

class _Readings extends StatelessWidget {
  const _Readings({required this.equipment});
  final Equipment equipment;
  @override
  Widget build(BuildContext context) {
    final e = equipment;
    final items = <(String, String)>[
      if (e.isTank) ...[
        ('Level', '${fmtNum(e.levelPct)} %'),
        ('Volume', '${fmtNum(e.volumeM3, digits: 0)} / ${fmtNum(e.capacityM3, digits: 0)} m³'),
      ],
      if (e.isPump) ...[
        ('Flow', '${fmtNum(e.flow, digits: 0)} m³/h'),
        ('Speed', '${fmtNum(e.speedPct, digits: 0)} %'),
        ('Discharge', '${fmtNum(e.pressureBar, digits: 2)} bar'),
        ('Rated flow', '${fmtNum(e.ratedFlow, digits: 0)} m³/h'),
        ('Run hours', fmtNum(e.runHours, digits: 0)),
        ('Health', '${fmtNum(e.healthPct, digits: 0)} %'),
      ],
      if (e.isValve) ...[
        ('Position', '${fmtNum(e.positionPct, digits: 0)} %'),
        ('Flow', '${fmtNum(e.flow, digits: 0)} m³/h'),
        ('Health', '${fmtNum(e.healthPct, digits: 0)} %'),
      ],
      if (e.isInstrument) ('Value', e.primaryReading),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 420 ? 3 : 2;
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (k, v) in items)
          Container(
            width: w,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.outline)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(height: 2),
              Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
          ),
      ]);
    });
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.color = AppColors.textMuted});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color == AppColors.textMuted ? AppColors.textMuted : color, fontSize: 13))),
      ]);
}

class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind, required this.color});
  final EquipmentKind kind;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
        child: Icon(equipmentIcon(kind), color: color),
      );
}

IconData equipmentIcon(EquipmentKind k) => switch (k) {
      EquipmentKind.tank => Icons.propane_tank_outlined,
      EquipmentKind.pump => Icons.settings_input_component_outlined,
      EquipmentKind.valve => Icons.tune,
      EquipmentKind.instrument => Icons.speed,
    };
