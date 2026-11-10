import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/operations.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/operations_repository.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/core_providers.dart';

class MaintenanceDetailScreen extends ConsumerWidget {
  const MaintenanceDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plants = ref.watch(plantsProvider).value ?? const [];
    MaintenanceOrder? order;
    var loading = false;
    Object? error;
    for (final p in plants) {
      final v = ref.watch(maintenanceOrdersProvider(p.id));
      if (v.hasValue) {
        order ??= v.value!.where((o) => o.id == orderId).firstOrNull;
      } else if (v.hasError) {
        error = v.error;
      } else {
        loading = true;
      }
    }
    final profile = ref.watch(currentProfileProvider).value;
    if (order == null) {
      if (loading || plants.isEmpty) return const LoadingView();
      if (error != null) return ErrorView(error: error);
      return EmptyState(
        icon: Icons.build_outlined,
        title: 'Work order not found',
        action: OutlinedButton(onPressed: () => context.go('/maintenance'), child: const Text('Back to maintenance')),
      );
    }
    final o = order;
    final wide = context.width >= 1000;

    final details = SectionCard(
      title: 'Details',
      icon: Icons.description_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (o.description != null && o.description!.isNotEmpty) ...[Text(o.description!), const SizedBox(height: 12)],
        LabelValue('Equipment', o.equipmentTag ?? '—'),
        LabelValue('Type', titleCase(o.type)),
        LabelValue('Priority', titleCase(o.priority), valueColor: priorityColor(o.priority)),
        LabelValue('Assigned to', o.assignedToName ?? 'Unassigned'),
        LabelValue('Requested by', o.createdByName ?? '—'),
        LabelValue('Created', fmtFull(o.createdAt)),
        LabelValue('Due', fmtDate(o.dueDate), valueColor: o.isOverdue ? AppColors.fault : null),
        if (o.startedAt != null) LabelValue('Started', fmtFull(o.startedAt)),
        if (o.completedAt != null) LabelValue('Completed', fmtFull(o.completedAt)),
        if (o.completionNotes != null) LabelValue('Completion notes', o.completionNotes!),
        LabelValue('CMMS reference', o.externalRef ?? 'Not synchronised'),
      ]),
    );

    final actions = profile == null ? const SizedBox.shrink() : _Workflow(order: o, profile: profile);
    final files = profile == null ? const SizedBox.shrink() : _Attachments(order: o, profile: profile);

    return SingleChildScrollView(
      child: PageBody(
        maxWidth: 1200,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => context.go('/maintenance'), icon: const Icon(Icons.arrow_back), label: const Text('Maintenance')),
          ),
          PageHeader(
            title: '${o.number} · ${o.title}',
            subtitle: 'Work order',
            actions: [
              StatusChip(titleCase(o.status), color: workOrderStatusColor(o.status)),
              if (o.lockoutApplied) const StatusChip('LOTO applied', color: AppColors.lockout, icon: Icons.lock),
            ],
          ),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: details),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: Column(children: [actions, const SizedBox(height: 16), files])),
            ])
          else ...[
            actions,
            const SizedBox(height: 12),
            details,
            const SizedBox(height: 12),
            files,
          ],
        ]),
      ),
    );
  }
}

class _Workflow extends ConsumerWidget {
  const _Workflow({required this.order, required this.profile});
  final MaintenanceOrder order;
  final Profile profile;

  Future<void> _setStatus(BuildContext context, WidgetRef ref, String status, {String? notes}) async {
    if (!ensureOnline(context, ref)) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await runAction(context, () async {
      if (status == 'completed' && order.lockoutApplied) {
        throw Exception('Release the lockout before completing this work order.');
      }
      await ref.read(maintenanceRepositoryProvider).update(order.id, {
        'status': status,
        if (status == 'in_progress' && order.startedAt == null) 'started_at': now,
        if (status == 'completed') 'completed_at': now,
        if (notes != null) 'completion_notes': notes,
        if (status == 'scheduled' && order.assignedTo == null && profile.role == UserRole.maintenance) ...{
          'assigned_to': profile.id,
          'assigned_to_name': profile.displayName,
        },
      });
      await logEventFromWidget(ref, plantId: order.plantId, category: 'maintenance', actor: profile, message: '${order.number} ${status.replaceAll('_', ' ')}: ${order.title}');
    }, success: '${order.number} is now ${titleCase(status).toLowerCase()}.');
  }

  Future<void> _lockout(BuildContext context, WidgetRef ref, bool apply) async {
    if (!ensureOnline(context, ref)) return;
    final ok = await confirmDialog(
      context,
      title: apply ? 'Apply lockout on ${order.equipmentTag}?' : 'Release lockout on ${order.equipmentTag}?',
      message: apply
          ? 'The equipment will be stopped and isolated. It cannot run until the lockout is released, even if operators request it.'
          : 'Confirm all personnel are clear and guards are refitted. The equipment returns to service in a stopped state.',
      confirmLabel: apply ? 'Apply LOTO' : 'Release LOTO',
      destructive: apply,
    );
    if (!ok || !context.mounted) return;
    await runAction(context, () => ref.read(apiClientProvider).setLockout(order.id, apply),
        success: apply ? 'Lockout applied — ${order.equipmentTag} is isolated.' : 'Lockout released — ${order.equipmentTag} returned to service.');
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete work order'),
        content: SizedBox(
          width: 440,
          child: TextField(controller: notes, maxLines: 4, decoration: const InputDecoration(labelText: 'Completion notes', hintText: 'Work performed, parts used, findings')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
        ],
      ),
    );
    if (ok == true && context.mounted) await _setStatus(context, ref, 'completed', notes: notes.text.trim().isEmpty ? 'Completed.' : notes.text.trim());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = order;
    final canPlan = profile.role.canPlanMaintenance;
    final canLock = profile.role.canLockout && o.equipmentId != null;
    final online = ref.watch(isOnlineProvider);
    final steps = ['requested', 'scheduled', 'in_progress', 'completed'];
    final current = o.status == 'cancelled' ? -1 : steps.indexOf(o.status);

    return SectionCard(
      title: 'Workflow',
      icon: Icons.route_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (final (i, s) in steps.indexed) ...[
            Expanded(
              child: Column(children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: i <= current ? workOrderStatusColor(s) : AppColors.surfaceHigh,
                  child: Icon(i < current ? Icons.check : Icons.circle, size: i < current ? 15 : 8, color: i <= current ? Colors.black : AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(titleCase(s), style: TextStyle(fontSize: 11, color: i <= current ? Colors.white : AppColors.textMuted), textAlign: TextAlign.center),
              ]),
            ),
          ],
        ]),
        if (o.status == 'cancelled') const Padding(padding: EdgeInsets.only(top: 8), child: Text('This work order was cancelled.', style: TextStyle(color: AppColors.textMuted))),
        const SizedBox(height: 16),
        if (!canPlan && !canLock)
          const Text('Your role can view this work order. The maintenance team updates its status.', style: TextStyle(color: AppColors.textMuted))
        else ...[
          if (canPlan && o.status == 'requested')
            FilledButton.icon(onPressed: online ? () => _setStatus(context, ref, 'scheduled') : null, icon: const Icon(Icons.event_available), label: const Text('Approve & schedule')),
          if (canPlan && (o.status == 'scheduled' || o.status == 'requested')) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(onPressed: online ? () => _setStatus(context, ref, 'in_progress') : null, icon: const Icon(Icons.play_arrow), label: const Text('Start work')),
          ],
          if (canLock && !o.isClosed && o.requiresLockout || canLock && o.lockoutApplied) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.lockout, side: const BorderSide(color: AppColors.lockout)),
              onPressed: online ? () => _lockout(context, ref, !o.lockoutApplied) : null,
              icon: Icon(o.lockoutApplied ? Icons.lock_open : Icons.lock),
              label: Text(o.lockoutApplied ? 'Release lockout (LOTO)' : 'Apply lockout (LOTO)'),
            ),
          ],
          if (canPlan && o.status == 'in_progress') ...[
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: online ? () => _complete(context, ref) : null, icon: const Icon(Icons.task_alt), label: const Text('Complete work order')),
          ],
          if (canPlan && !o.isClosed) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: online
                  ? () async {
                      if (o.lockoutApplied) {
                        showSnack(context, 'Release the lockout before cancelling.', error: true);
                        return;
                      }
                      if (await confirmDialog(context, title: 'Cancel ${o.number}?', message: 'The work order will be closed without completion.', confirmLabel: 'Cancel work order', destructive: true) &&
                          context.mounted) {
                        await _setStatus(context, ref, 'cancelled');
                      }
                    }
                  : null,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel work order'),
            ),
          ],
        ],
      ]),
    );
  }
}

class _Attachments extends ConsumerStatefulWidget {
  const _Attachments({required this.order, required this.profile});
  final MaintenanceOrder order;
  final Profile profile;
  @override
  ConsumerState<_Attachments> createState() => _AttachmentsState();
}

class _AttachmentsState extends ConsumerState<_Attachments> {
  bool _uploading = false;

  Future<void> _upload() async {
    if (!ensureOnline(context, ref)) return;
    final picked = await FilePicker.pickFiles();
    final file = picked.firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) showSnack(context, 'Files must be 10 MB or smaller.', error: true);
      return;
    }
    setState(() => _uploading = true);
    final ext = (file.extension ?? '').toLowerCase();
    final type = switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      _ => 'application/octet-stream',
    };
    if (!mounted) return;
    await runAction(context, () async {
      await ref.read(maintenanceRepositoryProvider).uploadAttachment(
            orderId: widget.order.id,
            user: widget.profile,
            fileName: file.name,
            bytes: bytes,
            contentType: type,
          );
      ref.invalidate(attachmentsProvider(widget.order.id));
    }, success: '${file.name} uploaded.');
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _open(MaintenanceAttachment a) async {
    await runAction(context, () async {
      final url = await ref.read(maintenanceRepositoryProvider).signedUrl(a.filePath);
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) throw Exception('Could not open the file.');
    });
  }

  Future<void> _delete(MaintenanceAttachment a) async {
    if (!await confirmDialog(context, title: 'Delete attachment?', message: '${a.fileName} will be permanently removed.', confirmLabel: 'Delete', destructive: true)) return;
    if (!mounted) return;
    await runAction(context, () async {
      await ref.read(maintenanceRepositoryProvider).deleteAttachment(a);
      ref.invalidate(attachmentsProvider(widget.order.id));
    }, success: 'Attachment deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(attachmentsProvider(widget.order.id));
    return SectionCard(
      title: 'Attachments',
      icon: Icons.attach_file,
      trailing: TextButton.icon(
        onPressed: _uploading ? null : _upload,
        icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file),
        label: const Text('Upload'),
      ),
      child: AsyncValueView<List<MaintenanceAttachment>>(
        value: files,
        onRetry: () => ref.invalidate(attachmentsProvider(widget.order.id)),
        loading: const LoadingView(),
        data: (list) => list.isEmpty
            ? const Text('No files yet. Upload photos, inspection reports or datasheets.', style: TextStyle(color: AppColors.textMuted))
            : Column(children: [
                for (final a in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon((a.contentType ?? '').startsWith('image/') ? Icons.image_outlined : Icons.insert_drive_file_outlined),
                    title: Text(a.fileName, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${fmtBytes(a.sizeBytes)} · ${a.uploadedByName ?? '—'} · ${fmtShort(a.createdAt)}'),
                    onTap: () => _open(a),
                    trailing: a.uploadedBy == widget.profile.id || widget.profile.role == UserRole.supervisor
                        ? IconButton(tooltip: 'Delete', onPressed: () => _delete(a), icon: const Icon(Icons.delete_outline))
                        : null,
                  ),
              ]),
      ),
    );
  }
}
