import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/equipment.dart';
import '../models/operations.dart';
import '../models/profile.dart';
import '../services/core_providers.dart';
import 'auth_repository.dart';
import 'live_query.dart';

/// Client-side audit entries for actions the client performs directly
/// (allowed by RLS for the 'maintenance' and 'handover' categories).
Future<void> logEvent(Ref ref, {required String plantId, required String category, required String message, required Profile actor, String severity = 'info'}) async {
  try {
    await ref.read(supabaseProvider).from('events').insert({
      'plant_id': plantId,
      'category': category,
      'severity': severity,
      'message': message,
      'actor_id': actor.id,
      'actor_name': actor.displayName,
    });
  } catch (_) {
    // Audit logging must never block the user action.
  }
}

/// Same as [logEvent], callable from widgets.
Future<void> logEventFromWidget(WidgetRef ref, {required String plantId, required String category, required String message, required Profile actor}) async {
  try {
    await ref.read(supabaseProvider).from('events').insert({
      'plant_id': plantId,
      'category': category,
      'severity': 'info',
      'message': message,
      'actor_id': actor.id,
      'actor_name': actor.displayName,
    });
  } catch (_) {}
}

// Setpoints ------------------------------------------------------------------------

final setpointsProvider = StreamProvider.family<List<Setpoint>, String>((ref, plantId) {
  ref.watch(currentUserIdProvider);
  return liveQuery<Setpoint>(
    ref,
    cacheKey: 'setpoints.$plantId',
    query: (db) => db.from('setpoints').stream(primaryKey: ['id']).eq('plant_id', plantId),
    parse: Setpoint.fromJson,
    transform: (items) => items..sort((a, b) => '${a.category}${a.name}'.compareTo('${b.category}${b.name}')),
  );
});

final proposalsProvider = StreamProvider.family<List<SetpointProposal>, String>((ref, plantId) {
  ref.watch(currentUserIdProvider);
  return liveQuery<SetpointProposal>(
    ref,
    cacheKey: 'proposals.$plantId',
    query: (db) => db.from('setpoint_proposals').stream(primaryKey: ['id']).eq('plant_id', plantId).order('created_at').limit(100),
    parse: SetpointProposal.fromJson,
  );
});

// Maintenance ----------------------------------------------------------------------

final maintenanceOrdersProvider = StreamProvider.family<List<MaintenanceOrder>, String>((ref, plantId) {
  ref.watch(currentUserIdProvider);
  return liveQuery<MaintenanceOrder>(
    ref,
    cacheKey: 'maintenance.$plantId',
    query: (db) => db.from('maintenance_orders').stream(primaryKey: ['id']).eq('plant_id', plantId).order('created_at').limit(200),
    parse: MaintenanceOrder.fromJson,
  );
});

final attachmentsProvider = FutureProvider.family<List<MaintenanceAttachment>, String>((ref, orderId) => cachedFetch(
      ref,
      cacheKey: 'attachments.$orderId',
      query: (db) => db.from('maintenance_attachments').select().eq('order_id', orderId).order('created_at', ascending: false),
      parse: MaintenanceAttachment.fromJson,
    ));

class MaintenanceRepository {
  MaintenanceRepository(this.ref);
  final Ref ref;
  SupabaseClient get _db => ref.read(supabaseProvider);

  Future<MaintenanceOrder> create({
    required Profile author,
    required String plantId,
    Equipment? equipment,
    required String title,
    String? description,
    required String type,
    required String priority,
    required bool requiresLockout,
    DateTime? dueDate,
    Profile? assignee,
  }) async {
    final planned = author.role.canPlanMaintenance;
    final row = await _db
        .from('maintenance_orders')
        .insert({
          'plant_id': plantId,
          'equipment_id': equipment?.id,
          'equipment_tag': equipment?.tag,
          'title': title.trim(),
          'description': description?.trim(),
          'type': type,
          'priority': priority,
          'status': planned && assignee != null ? 'scheduled' : 'requested',
          'requires_lockout': requiresLockout,
          'due_date': dueDate?.toIso8601String().substring(0, 10),
          'assigned_to': planned ? assignee?.id : null,
          'assigned_to_name': planned ? assignee?.displayName : null,
          'created_by': author.id,
          'created_by_name': author.displayName,
        })
        .select()
        .single();
    await logEvent(ref, plantId: plantId, category: 'maintenance', message: '${row['number']} created: ${title.trim()}', actor: author);
    return MaintenanceOrder.fromJson(row);
  }

  Future<void> update(String id, Map<String, dynamic> fields) async {
    await _db.from('maintenance_orders').update(fields).eq('id', id);
  }

  Future<void> uploadAttachment({
    required String orderId,
    required Profile user,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$orderId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _db.storage.from('maintenance-files').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    await _db.from('maintenance_attachments').insert({
      'order_id': orderId,
      'file_path': path,
      'file_name': fileName,
      'size_bytes': bytes.length,
      'content_type': contentType,
      'uploaded_by': user.id,
      'uploaded_by_name': user.displayName,
    });
  }

  Future<String> signedUrl(String path) => _db.storage.from('maintenance-files').createSignedUrl(path, 300);

  Future<void> deleteAttachment(MaintenanceAttachment a) async {
    await _db.storage.from('maintenance-files').remove([a.filePath]);
    await _db.from('maintenance_attachments').delete().eq('id', a.id);
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) => MaintenanceRepository(ref));

// Shift handover -------------------------------------------------------------------

final handoversProvider = StreamProvider.family<List<ShiftHandover>, String>((ref, plantId) {
  ref.watch(currentUserIdProvider);
  return liveQuery<ShiftHandover>(
    ref,
    cacheKey: 'handovers.$plantId',
    query: (db) => db.from('shift_handovers').stream(primaryKey: ['id']).eq('plant_id', plantId).order('created_at').limit(60),
    parse: ShiftHandover.fromJson,
  );
});

class HandoverRepository {
  HandoverRepository(this.ref);
  final Ref ref;
  SupabaseClient get _db => ref.read(supabaseProvider);

  Future<void> create({
    required Profile author,
    required String plantId,
    required String shift,
    required String summary,
    String? openIssues,
    String? safetyNotes,
    String? equipmentNotes,
    required Map<String, dynamic> snapshot,
  }) async {
    await _db.from('shift_handovers').insert({
      'plant_id': plantId,
      'shift': shift,
      'shift_date': DateTime.now().toIso8601String().substring(0, 10),
      'author_id': author.id,
      'author_name': author.displayName,
      'summary': summary.trim(),
      'open_issues': _nullIfEmpty(openIssues),
      'safety_notes': _nullIfEmpty(safetyNotes),
      'equipment_notes': _nullIfEmpty(equipmentNotes),
      'snapshot': snapshot,
      'status': 'submitted',
    });
    await logEvent(ref,
        plantId: plantId,
        category: 'handover',
        message: '${shift[0].toUpperCase()}${shift.substring(1)} shift handover submitted by ${author.displayName}.',
        actor: author);
  }

  Future<void> acknowledge(ShiftHandover h, Profile user) async {
    final res = await _db
        .from('shift_handovers')
        .update({
          'status': 'acknowledged',
          'acknowledged_by': user.id,
          'acknowledged_by_name': user.displayName,
          'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', h.id)
        .select('id');
    if (res.isEmpty) throw Exception('This handover could not be acknowledged (already acknowledged, or you wrote it).');
  }

  static String? _nullIfEmpty(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
}

final handoverRepositoryProvider = Provider<HandoverRepository>((ref) => HandoverRepository(ref));

// Global search ----------------------------------------------------------------------

class SearchHit {
  const SearchHit({required this.kind, required this.title, required this.subtitle, required this.plantId, required this.route});
  final String kind; // equipment | alarm | work_order | event
  final String title;
  final String subtitle;
  final String plantId;
  final String route;
}

final searchProvider = FutureProvider.family<List<SearchHit>, String>((ref, rawQuery) async {
  final q = rawQuery.trim();
  if (q.length < 2) return const [];
  final db = ref.read(supabaseProvider);
  final like = '%${q.replaceAll('%', '').replaceAll(',', ' ')}%';

  final results = await Future.wait([
    db.from('equipment').select('id, plant_id, tag, name, kind, area').or('tag.ilike.$like,name.ilike.$like,area.ilike.$like').limit(20),
    db.from('alarms').select('id, plant_id, tag, message, priority, state').or('tag.ilike.$like,message.ilike.$like').order('raised_at', ascending: false).limit(15),
    db.from('maintenance_orders').select('id, plant_id, number, title, status, equipment_tag').or('number.ilike.$like,title.ilike.$like,equipment_tag.ilike.$like').limit(15),
    db.from('events').select('id, plant_id, message, category, created_at').ilike('message', like).order('id', ascending: false).limit(15),
  ]);

  return [
    for (final r in results[0])
      SearchHit(kind: 'equipment', title: '${r['tag']} · ${r['name']}', subtitle: '${r['kind']} · ${r['area']}', plantId: r['plant_id'] as String, route: '/equipment/${r['id']}'),
    for (final r in results[2])
      SearchHit(kind: 'work_order', title: '${r['number']} · ${r['title']}', subtitle: 'Work order · ${r['status']}${r['equipment_tag'] != null ? ' · ${r['equipment_tag']}' : ''}', plantId: r['plant_id'] as String, route: '/maintenance/${r['id']}'),
    for (final r in results[1])
      SearchHit(kind: 'alarm', title: '${r['tag']} · ${r['message']}', subtitle: 'Alarm · ${r['priority']} · ${r['state']}', plantId: r['plant_id'] as String, route: '/alarms'),
    for (final r in results[3])
      if (r['plant_id'] != null)
        SearchHit(kind: 'event', title: '${r['message']}', subtitle: 'Event · ${r['category']}', plantId: r['plant_id'] as String, route: '/simulation'),
  ];
});
