import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/operations.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/operations_repository.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/core_providers.dart';

class SetpointsScreen extends ConsumerStatefulWidget {
  const SetpointsScreen({super.key});
  @override
  ConsumerState<SetpointsScreen> createState() => _SetpointsScreenState();
}

class _SetpointsScreenState extends ConsumerState<SetpointsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String _proposalFilter = 'pending';

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plantId = ref.watch(selectedPlantIdProvider);
    final profile = ref.watch(currentProfileProvider).value;
    final setpoints = ref.watch(setpointsProvider(plantId));
    final proposals = ref.watch(proposalsProvider(plantId));
    final pending = (proposals.value ?? const []).where((p) => p.status == 'pending').length;
    final pad = context.isMobile ? 12.0 : 20.0;

    return Column(children: [
      PageBody(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PageHeader(
            title: 'Setpoints',
            subtitle: profile?.role.canReviewSetpoints == true
                ? 'Control parameters. Review change proposals submitted by engineers.'
                : profile?.role.canProposeSetpoints == true
                    ? 'Control parameters. Changes are proposed here and approved by a supervisor.'
                    : 'Control parameters (read-only for your role).',
          ),
          TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            const Tab(text: 'Setpoints'),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Proposals'),
              if (pending > 0) ...[const SizedBox(width: 6), Badge(label: Text('$pending'), backgroundColor: AppColors.warning, textColor: Colors.black)],
            ])),
          ]),
        ]),
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          AsyncValueView<List<Setpoint>>(
            value: setpoints,
            onRetry: () => ref.invalidate(setpointsProvider(plantId)),
            data: (list) {
              final byCat = <String, List<Setpoint>>{};
              for (final s in list) {
                byCat.putIfAbsent(s.category, () => []).add(s);
              }
              final pendingIds = (proposals.value ?? const []).where((p) => p.status == 'pending').map((p) => p.setpointId).toSet();
              return ListView(padding: EdgeInsets.all(pad), children: [
                for (final e in byCat.entries) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 8), child: Text(e.key.toUpperCase(), style: const TextStyle(color: AppColors.textMuted, fontSize: 12, letterSpacing: 1))),
                  Card(
                    child: Column(children: [
                      for (final (i, s) in e.value.indexed) ...[
                        if (i > 0) const Divider(),
                        _SetpointTile(setpoint: s, profile: profile, hasPending: pendingIds.contains(s.id)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
              ]);
            },
          ),
          Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in ['pending', 'approved', 'rejected', 'all'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(titleCase(s)), selected: _proposalFilter == s, onSelected: (_) => setState(() => _proposalFilter = s)),
                    ),
                ]),
              ),
            ),
            Expanded(
              child: AsyncValueView<List<SetpointProposal>>(
                value: proposals,
                onRetry: () => ref.invalidate(proposalsProvider(plantId)),
                data: (list) {
                  final items = list.where((p) => _proposalFilter == 'all' || p.status == _proposalFilter).toList();
                  if (items.isEmpty) {
                    return EmptyState(icon: Icons.fact_check_outlined, title: 'No ${_proposalFilter == 'all' ? '' : '$_proposalFilter '}proposals');
                  }
                  return ListView.builder(
                    padding: EdgeInsets.all(pad),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _ProposalCard(proposal: items[i], profile: profile),
                  );
                },
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }
}

class _SetpointTile extends ConsumerWidget {
  const _SetpointTile({required this.setpoint, required this.profile, required this.hasPending});
  final Setpoint setpoint;
  final Profile? profile;
  final bool hasPending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = setpoint;
    final canPropose = profile?.role.canProposeSetpoints ?? false;
    final range = (s.max - s.min) == 0 ? 0.0 : ((s.value - s.min) / (s.max - s.min)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 16,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (s.description != null) ...[const SizedBox(height: 2), Text(s.description!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13))],
              const SizedBox(height: 4),
              Text('Range ${s.format(s.min)}–${s.format(s.max)} ${s.unit} · last changed by ${s.updatedByName ?? '—'} ${timeAgo(s.updatedAt)}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ]),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 120,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${s.format(s.value)} ${s.unit}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: range, minHeight: 5, backgroundColor: AppColors.surfaceHigh)),
              ]),
            ),
            const SizedBox(width: 14),
            if (hasPending)
              const StatusChip('Pending review', color: AppColors.warning, icon: Icons.hourglass_top)
            else if (canPropose)
              OutlinedButton.icon(
                onPressed: () => _showProposeDialog(context, ref, s),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Propose change'),
              ),
          ]),
        ],
      ),
    );
  }
}

Future<void> _showProposeDialog(BuildContext context, WidgetRef ref, Setpoint s) async {
  if (!ensureOnline(context, ref)) return;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _ProposeForm(setpoint: s),
    ),
  );
  if (result == true && context.mounted) {
    showSnack(context, 'Proposal submitted. A supervisor has been notified.', color: const Color(0xFF14432F));
  }
}

class _ProposeForm extends ConsumerStatefulWidget {
  const _ProposeForm({required this.setpoint});
  final Setpoint setpoint;
  @override
  ConsumerState<_ProposeForm> createState() => _ProposeFormState();
}

class _ProposeFormState extends ConsumerState<_ProposeForm> {
  final _form = GlobalKey<FormState>();
  late double _value = widget.setpoint.value;
  late final _valueCtl = TextEditingController(text: widget.setpoint.format(_value));
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _valueCtl.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).proposeSetpoint(widget.setpoint.id, _value, _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorView.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.setpoint;
    final divisions = ((s.max - s.min) / s.step).round();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text('Propose change: ${s.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Current value ${s.format(s.value)} ${s.unit}. The change takes effect only after supervisor approval.', style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 18),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.fault)),
                const SizedBox(height: 10),
              ],
              Row(children: [
                Expanded(
                  child: Slider(
                    value: _value.clamp(s.min, s.max),
                    min: s.min,
                    max: s.max,
                    divisions: divisions > 0 && divisions <= 1000 ? divisions : null,
                    label: '${s.format(_value)} ${s.unit}',
                    onChanged: (v) => setState(() {
                      _value = double.parse(s.format(v));
                      _valueCtl.text = s.format(_value);
                    }),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _valueCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: InputDecoration(suffixText: s.unit, labelText: 'New value'),
                    onChanged: (v) {
                      final d = double.tryParse(v);
                      if (d != null) setState(() => _value = d);
                    },
                    validator: (v) {
                      final d = double.tryParse(v ?? '');
                      if (d == null) return 'Enter a number';
                      if (d < s.min || d > s.max) return '${s.format(s.min)}–${s.format(s.max)}';
                      if (d == s.value) return 'Unchanged';
                      return null;
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Reason for the change', hintText: 'Explain why this change is needed and any risks considered'),
                validator: (v) => (v?.trim().length ?? 0) < 10 ? 'Please explain the reason (at least 10 characters)' : null,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                label: const Text('Submit for review'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ProposalCard extends ConsumerWidget {
  const _ProposalCard({required this.proposal, required this.profile});
  final SetpointProposal proposal;
  final Profile? profile;

  Future<void> _review(BuildContext context, WidgetRef ref, bool approve) async {
    if (!ensureOnline(context, ref)) return;
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve change?' : 'Reject proposal?'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${proposal.setpointName}: ${proposal.currentValue} → ${proposal.proposedValue} ${proposal.unit}'),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: InputDecoration(labelText: approve ? 'Note (optional)' : 'Reason for rejection (required)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: approve ? null : FilledButton.styleFrom(backgroundColor: AppColors.fault, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Approve & apply' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(
      context,
      () => ref.read(apiClientProvider).reviewProposal(proposal.id, approve, note.text.trim().isEmpty ? null : note.text.trim()),
      success: approve ? 'Approved — the new setpoint is active.' : 'Proposal rejected.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = proposal;
    final canReview = (profile?.role.canReviewSetpoints ?? false) && p.status == 'pending';
    final own = p.proposedBy != null && p.proposedBy == profile?.id;
    final color = switch (p.status) { 'approved' => AppColors.running, 'rejected' => AppColors.fault, 'pending' => AppColors.warning, _ => AppColors.textMuted };
    final delta = p.proposedValue - p.currentValue;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(p.setpointName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            StatusChip(titleCase(p.status), color: color),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Text('${p.currentValue}', style: const TextStyle(fontSize: 20, color: AppColors.textMuted)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.arrow_forward, size: 18)),
            Text('${p.proposedValue} ${p.unit}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            StatusChip('${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}', color: delta > 0 ? AppColors.info : AppColors.secondary, dense: true),
          ]),
          const SizedBox(height: 10),
          Text(p.reason),
          const SizedBox(height: 8),
          Text('Proposed by ${p.proposedByName ?? '—'} · ${fmtShort(p.createdAt)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          if (p.reviewedByName != null)
            Text('Reviewed by ${p.reviewedByName} · ${fmtShort(p.reviewedAt)}${p.reviewNote != null ? ' — “${p.reviewNote}”' : ''}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          if (canReview) ...[
            const SizedBox(height: 12),
            if (own)
              const Text('You submitted this proposal — another supervisor must review it.', style: TextStyle(color: AppColors.warning, fontSize: 13))
            else
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: () => _review(context, ref, true), icon: const Icon(Icons.check), label: const Text('Approve'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: () => _review(context, ref, false), icon: const Icon(Icons.close), label: const Text('Reject'))),
              ]),
          ],
        ]),
      ),
    );
  }
}
