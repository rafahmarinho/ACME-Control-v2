import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/equipment.dart';
import '../../data/models/operations.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/operations_repository.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/core_providers.dart';

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});
  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  String _status = 'open';
  String _priority = 'all';
  String _query = '';
  bool _mine = false;

  @override
  Widget build(BuildContext context) {
    final plantId = ref.watch(selectedPlantIdProvider);
    final profile = ref.watch(currentProfileProvider).value;
    final orders = ref.watch(maintenanceOrdersProvider(plantId));
    final canPlan = profile?.role.canPlanMaintenance ?? false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: profile == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showWorkOrderForm(context, ref, profile, plantId),
              icon: const Icon(Icons.add),
              label: Text(canPlan ? 'New work order' : 'Request maintenance'),
            ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: PageBody(
            padding: EdgeInsets.fromLTRB(context.isMobile ? 12 : 20, context.isMobile ? 12 : 20, context.isMobile ? 12 : 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const PageHeader(title: 'Maintenance', subtitle: 'Work orders, lockout/tagout and attachments (synchronised with the CMMS)'),
              SearchField(hint: 'Search number, title or equipment', onChanged: (v) => setState(() => _query = v.trim().toLowerCase())),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (v, l) in [('open', 'Open'), ('requested', 'Requested'), ('scheduled', 'Scheduled'), ('in_progress', 'In progress'), ('completed', 'Completed'), ('all', 'All')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(l), selected: _status == v, onSelected: (_) => setState(() => _status = v)),
                    ),
                  const SizedBox(width: 8),
                  DropdownButtonHideUnderline(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.outline)),
                      child: DropdownButton<String>(
                        value: _priority,
                        onChanged: (v) => setState(() => _priority = v ?? 'all'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Any priority')),
                          DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                          DropdownMenuItem(value: 'high', child: Text('High')),
                          DropdownMenuItem(value: 'medium', child: Text('Medium')),
                          DropdownMenuItem(value: 'low', child: Text('Low')),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(label: const Text('Assigned to me'), selected: _mine, onSelected: (v) => setState(() => _mine = v)),
                ]),
              ),
              const SizedBox(height: 12),
            ]),
          ),
        ),
        ...orders.when(
          loading: () => [const SliverFillRemaining(child: LoadingView())],
          error: (e, _) => [SliverFillRemaining(child: ErrorView(error: e, onRetry: () => ref.invalidate(maintenanceOrdersProvider(plantId))))],
          data: (list) {
            final items = list.where((o) {
              if (_status == 'open' && o.isClosed) return false;
              if (_status != 'open' && _status != 'all' && o.status != _status) return false;
              if (_priority != 'all' && o.priority != _priority) return false;
              if (_mine && o.assignedTo != profile?.id) return false;
              if (_query.isNotEmpty && !'${o.number} ${o.title} ${o.equipmentTag ?? ''}'.toLowerCase().contains(_query)) return false;
              return true;
            }).toList();
            if (items.isEmpty) {
              return [const SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Icons.build_circle_outlined, title: 'No work orders match your filters'))];
            }
            return [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(context.isMobile ? 12 : 20, 0, context.isMobile ? 12 : 20, 96),
                sliver: SliverList.builder(itemCount: items.length, itemBuilder: (_, i) => _OrderTile(order: items[i])),
              ),
            ];
          },
        ),
      ]),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final MaintenanceOrder order;
  @override
  Widget build(BuildContext context) {
    final o = order;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/maintenance/${o.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(width: 4, height: 54, decoration: BoxDecoration(color: priorityColor(o.priority), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${o.number} · ${o.title}', style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  '${o.equipmentTag ?? 'No equipment'} · ${titleCase(o.type)} · ${titleCase(o.priority)} priority · '
                  '${o.assignedToName != null ? 'Assigned to ${o.assignedToName}' : 'Unassigned'}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  StatusChip(titleCase(o.status), color: workOrderStatusColor(o.status), dense: true),
                  if (o.lockoutApplied) const StatusChip('LOTO applied', color: AppColors.lockout, dense: true, icon: Icons.lock),
                  if (o.requiresLockout && !o.lockoutApplied && !o.isClosed) const StatusChip('Requires LOTO', color: AppColors.textMuted, dense: true, icon: Icons.lock_open),
                  if (o.isOverdue) const StatusChip('Overdue', color: AppColors.fault, dense: true),
                  if (o.dueDate != null) StatusChip('Due ${fmtDate(o.dueDate)}', color: AppColors.textMuted, dense: true),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}

/// Create a work order (planners) or a maintenance request (operators).
Future<void> showWorkOrderForm(BuildContext context, WidgetRef ref, Profile profile, String plantId, {Equipment? equipment}) async {
  if (!ensureOnline(context, ref)) return;
  final created = await showModalBottomSheet<MaintenanceOrder>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _WorkOrderForm(profile: profile, plantId: plantId, equipment: equipment),
    ),
  );
  if (created != null && context.mounted) {
    showSnack(context, '${created.number} created and sent to the CMMS.', color: const Color(0xFF14432F));
    context.go('/maintenance/${created.id}');
  }
}

class _WorkOrderForm extends ConsumerStatefulWidget {
  const _WorkOrderForm({required this.profile, required this.plantId, this.equipment});
  final Profile profile;
  final String plantId;
  final Equipment? equipment;
  @override
  ConsumerState<_WorkOrderForm> createState() => _WorkOrderFormState();
}

class _WorkOrderFormState extends ConsumerState<_WorkOrderForm> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  late String? _equipmentId = widget.equipment?.id;
  String _type = 'corrective';
  String _priority = 'medium';
  bool _lockout = false;
  DateTime? _due = DateTime.now().add(const Duration(days: 7));
  String? _assigneeId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit(List<Equipment> equipment, List<Profile> people) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final eq = equipment.where((e) => e.id == _equipmentId).firstOrNull;
      final assignee = people.where((p) => p.id == _assigneeId).firstOrNull;
      final order = await ref.read(maintenanceRepositoryProvider).create(
            author: widget.profile,
            plantId: widget.plantId,
            equipment: eq,
            title: _title.text,
            description: _desc.text,
            type: _type,
            priority: _priority,
            requiresLockout: _lockout,
            dueDate: _due,
            assignee: assignee,
          );
      try {
        await ref.read(apiClientProvider).cmmsSync(order.id);
      } catch (_) {
        // CMMS sync is best-effort; the work order is already saved.
      }
      if (mounted) Navigator.pop(context, order);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorView.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final equipment = ref.watch(equipmentProvider(widget.plantId)).value ?? const <Equipment>[];
    final people = (ref.watch(allProfilesProvider).value ?? const <Profile>[]).where((p) => p.role == UserRole.maintenance || p.role == UserRole.engineer).toList();
    final canPlan = widget.profile.role.canPlanMaintenance;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(canPlan ? 'New work order' : 'Request maintenance', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(canPlan ? 'Plan and assign maintenance work.' : 'Your request will be reviewed and scheduled by the maintenance team.',
                  style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 16),
              if (_error != null) ...[Text(_error!, style: const TextStyle(color: AppColors.fault)), const SizedBox(height: 10)],
              DropdownButtonFormField<String?>(
                initialValue: _equipmentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Equipment'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— General / no specific asset —')),
                  for (final e in equipment) DropdownMenuItem(value: e.id, child: Text('${e.tag} · ${e.name}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _equipmentId = v;
                  final eq = equipment.where((e) => e.id == v).firstOrNull;
                  if (eq != null && eq.isPump) _lockout = true;
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Bearing noise on drive end'),
                validator: (v) => (v?.trim().length ?? 0) < 5 ? 'Enter a short descriptive title (min. 5 characters)' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Description', hintText: 'What did you observe? Any safety concerns?'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'corrective', child: Text('Corrective')),
                      DropdownMenuItem(value: 'preventive', child: Text('Preventive')),
                      DropdownMenuItem(value: 'inspection', child: Text('Inspection')),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? 'corrective'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Low')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'high', child: Text('High')),
                      DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                    ],
                    onChanged: (v) => setState(() => _priority = v ?? 'medium'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: _due ?? DateTime.now(),
                  );
                  if (d != null) setState(() => _due = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Due date', suffixIcon: Icon(Icons.event)),
                  child: Text(fmtDate(_due)),
                ),
              ),
              if (canPlan) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _assigneeId,
                  decoration: const InputDecoration(labelText: 'Assign to'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Unassigned')),
                    for (final p in people) DropdownMenuItem(value: p.id, child: Text('${p.displayName} (${p.role.label})')),
                  ],
                  onChanged: (v) => setState(() => _assigneeId = v),
                ),
              ],
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _lockout,
                onChanged: (v) => setState(() => _lockout = v),
                title: const Text('Requires lockout/tagout (LOTO)'),
                subtitle: const Text('The equipment must be isolated before work starts.'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : () => _submit(equipment, people),
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                label: Text(canPlan ? 'Create work order' : 'Submit request'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
