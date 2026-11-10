import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/operations.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/operations_repository.dart';
import '../../data/repositories/plant_repository.dart';

String currentShift([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h >= 6 && h < 14) return 'day';
  if (h >= 14 && h < 22) return 'evening';
  return 'night';
}

class HandoverScreen extends ConsumerStatefulWidget {
  const HandoverScreen({super.key});
  @override
  ConsumerState<HandoverScreen> createState() => _HandoverScreenState();
}

class _HandoverScreenState extends ConsumerState<HandoverScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final plantId = ref.watch(selectedPlantIdProvider);
    final profile = ref.watch(currentProfileProvider).value;
    final list = ref.watch(handoversProvider(plantId));
    final canWrite = profile?.role.canWriteHandover ?? false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canWrite && profile != null
          ? FloatingActionButton.extended(onPressed: () => _openForm(context, profile, plantId), icon: const Icon(Icons.edit_note), label: const Text('New handover'))
          : null,
      body: SingleChildScrollView(
        child: PageBody(
          maxWidth: 1000,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PageHeader(title: 'Shift handover', subtitle: 'Structured shift logs, acknowledged by the incoming shift'),
            Wrap(spacing: 8, children: [
              for (final (v, l) in [('all', 'All'), ('submitted', 'Awaiting acknowledgement'), ('acknowledged', 'Acknowledged')])
                ChoiceChip(label: Text(l), selected: _filter == v, onSelected: (_) => setState(() => _filter = v)),
            ]),
            const SizedBox(height: 12),
            AsyncValueView<List<ShiftHandover>>(
              value: list,
              onRetry: () => ref.invalidate(handoversProvider(plantId)),
              data: (items) {
                final shown = items.where((h) => _filter == 'all' || h.status == _filter).toList();
                if (shown.isEmpty) return const EmptyState(icon: Icons.swap_horiz, title: 'No handovers yet', message: 'Create the first handover at the end of your shift.');
                return Column(children: [for (final h in shown) _HandoverCard(handover: h, profile: profile), const SizedBox(height: 80)]);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, Profile profile, String plantId) async {
    if (!ensureOnline(context, ref)) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom), child: _HandoverForm(profile: profile, plantId: plantId)),
    );
    if (ok == true && context.mounted) showSnack(context, 'Handover submitted. The incoming shift can now acknowledge it.', color: const Color(0xFF14432F));
  }
}

class _HandoverCard extends ConsumerWidget {
  const _HandoverCard({required this.handover, required this.profile});
  final ShiftHandover handover;
  final Profile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = handover;
    final pending = h.status == 'submitted';
    final canAck = pending && profile != null && h.authorId != profile!.id;
    final snap = h.snapshot;

    Widget block(String title, String? text, IconData icon) => text == null || text.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(text),
              ])),
            ]),
          );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(h.shift == 'night' ? Icons.nights_stay_outlined : h.shift == 'evening' ? Icons.wb_twilight : Icons.wb_sunny_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${titleCase(h.shift)} shift · ${fmtDate(h.shiftDate)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('by ${h.authorName ?? '—'} · ${fmtShort(h.createdAt)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ]),
            ),
            StatusChip(pending ? 'Awaiting ack.' : 'Acknowledged', color: pending ? AppColors.warning : AppColors.running),
          ]),
          const SizedBox(height: 12),
          Text(h.summary),
          block('Open issues', h.openIssues, Icons.report_problem_outlined),
          block('Safety notes', h.safetyNotes, Icons.health_and_safety_outlined),
          block('Equipment notes', h.equipmentNotes, Icons.precision_manufacturing_outlined),
          if (snap.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (snap['active_alarms'] != null) StatusChip('Alarms: ${snap['active_alarms']}', color: AppColors.info, dense: true),
              if (snap['t101_level'] != null) StatusChip('T-101: ${snap['t101_level']} %', color: AppColors.water, dense: true),
              if (snap['t102_level'] != null) StatusChip('T-102: ${snap['t102_level']} %', color: AppColors.water, dense: true),
              if (snap['running_pumps'] != null) StatusChip('Pumps running: ${snap['running_pumps']}', color: AppColors.running, dense: true),
              if (snap['scenario'] != null) StatusChip('Scenario: ${snap['scenario']}', color: AppColors.secondary, dense: true),
            ]),
          ],
          if (!pending && h.acknowledgedByName != null) ...[
            const SizedBox(height: 10),
            Text('Acknowledged by ${h.acknowledgedByName} · ${fmtShort(h.acknowledgedAt)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
          if (canAck) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                if (!ensureOnline(context, ref)) return;
                await runAction(context, () => ref.read(handoverRepositoryProvider).acknowledge(h, profile!), success: 'Handover acknowledged.');
              },
              icon: const Icon(Icons.how_to_reg),
              label: const Text('Acknowledge — I have read and accept this handover'),
            ),
          ] else if (pending && profile != null && h.authorId == profile!.id) ...[
            const SizedBox(height: 10),
            const Text('Waiting for the incoming shift to acknowledge.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ]),
      ),
    );
  }
}

class _HandoverForm extends ConsumerStatefulWidget {
  const _HandoverForm({required this.profile, required this.plantId});
  final Profile profile;
  final String plantId;
  @override
  ConsumerState<_HandoverForm> createState() => _HandoverFormState();
}

class _HandoverFormState extends ConsumerState<_HandoverForm> {
  final _form = GlobalKey<FormState>();
  String _shift = currentShift();
  final _summary = TextEditingController();
  final _issues = TextEditingController();
  final _safety = TextEditingController();
  final _equipment = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill equipment notes with the current abnormal conditions.
    final eq = ref.read(equipmentProvider(widget.plantId)).value ?? const [];
    final abnormal = eq.where((e) => e.inMaintenance || e.isAbnormal || e.isManual).map((e) {
      final bits = [
        if (e.inMaintenance) 'locked out',
        if (e.isManual) 'in MANUAL',
        if (e.isAbnormal && !e.inMaintenance) e.actualState.replaceAll('_', ' '),
      ];
      return '${e.tag}: ${bits.join(', ')}';
    }).toList();
    if (abnormal.isNotEmpty) _equipment.text = abnormal.join('\n');
  }

  @override
  void dispose() {
    for (final c in [_summary, _issues, _safety, _equipment]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _snapshot() {
    final eq = ref.read(equipmentByTagProvider(widget.plantId));
    final state = ref.read(plantStateProvider(widget.plantId)).value;
    final scenarios = ref.read(scenariosProvider).value ?? const [];
    return {
      'active_alarms': ref.read(plantOpenAlarmsProvider(widget.plantId)).where((a) => a.isConditionActive).length,
      't101_level': eq['T-101']?.levelPct?.toStringAsFixed(1),
      't102_level': eq['T-102']?.levelPct?.toStringAsFixed(1),
      'running_pumps': eq.values.where((e) => e.isPump && e.actualState == 'running').length,
      'scenario': scenarios.where((s) => s.id == state?.scenarioId).firstOrNull?.name,
    };
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(handoverRepositoryProvider).create(
            author: widget.profile,
            plantId: widget.plantId,
            shift: _shift,
            summary: _summary.text,
            openIssues: _issues.text,
            safetyNotes: _safety.text,
            equipmentNotes: _equipment.text,
            snapshot: _snapshot(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorView.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              const Text('New shift handover', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (_error != null) ...[Text(_error!, style: const TextStyle(color: AppColors.fault)), const SizedBox(height: 10)],
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'day', label: Text('Day'), icon: Icon(Icons.wb_sunny_outlined)),
                  ButtonSegment(value: 'evening', label: Text('Evening'), icon: Icon(Icons.wb_twilight)),
                  ButtonSegment(value: 'night', label: Text('Night'), icon: Icon(Icons.nights_stay_outlined)),
                ],
                selected: {_shift},
                onSelectionChanged: (s) => setState(() => _shift = s.first),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Plant snapshot (attached automatically)', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text('Active alarms ${snap['active_alarms']} · T-101 ${snap['t101_level'] ?? '—'} % · T-102 ${snap['t102_level'] ?? '—'} % · '
                      'Pumps running ${snap['running_pumps']} · ${snap['scenario'] ?? ''}'),
                ]),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _summary,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Shift summary *', hintText: 'Overall plant condition, key events, production'),
                validator: (v) => (v?.trim().length ?? 0) < 15 ? 'Write a short summary (at least 15 characters)' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _issues, maxLines: 3, decoration: const InputDecoration(labelText: 'Open issues / follow-ups')),
              const SizedBox(height: 12),
              TextFormField(controller: _safety, maxLines: 2, decoration: const InputDecoration(labelText: 'Safety notes (permits, LOTO, incidents)')),
              const SizedBox(height: 12),
              TextFormField(controller: _equipment, maxLines: 3, decoration: const InputDecoration(labelText: 'Equipment notes')),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                label: const Text('Submit handover'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
