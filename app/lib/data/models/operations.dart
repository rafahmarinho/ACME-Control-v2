import 'json.dart';

enum AlarmPriority {
  critical('Critical', 0),
  high('High', 1),
  medium('Medium', 2),
  low('Low', 3);

  const AlarmPriority(this.label, this.rank);
  final String label;
  final int rank;
  static AlarmPriority parse(String? v) =>
      AlarmPriority.values.firstWhere((p) => p.name == v, orElse: () => AlarmPriority.low);
}

class Alarm {
  const Alarm({
    required this.id,
    required this.plantId,
    this.equipmentId,
    required this.code,
    required this.tag,
    required this.message,
    required this.priority,
    required this.state,
    this.value,
    required this.raisedAt,
    this.simRaisedAt,
    this.acknowledgedByName,
    this.acknowledgedAt,
    this.ackComment,
    this.clearedAt,
  });

  final String id;
  final String plantId;
  final String? equipmentId;
  final String code;
  final String tag;
  final String message;
  final AlarmPriority priority;
  final String state; // active | acknowledged | rtn_unack | closed
  final double? value;
  final DateTime raisedAt;
  final DateTime? simRaisedAt;
  final String? acknowledgedByName;
  final DateTime? acknowledgedAt;
  final String? ackComment;
  final DateTime? clearedAt;

  bool get needsAck => state == 'active' || state == 'rtn_unack';
  bool get isConditionActive => state == 'active' || state == 'acknowledged';
  bool get isOpen => state != 'closed';
  DateTime get when => simRaisedAt ?? raisedAt;

  String get stateLabel => switch (state) {
        'active' => 'Active · Unacknowledged',
        'acknowledged' => 'Active · Acknowledged',
        'rtn_unack' => 'Cleared · Unacknowledged',
        _ => 'Closed',
      };

  factory Alarm.fromJson(Json j) => Alarm(
        id: j['id'] as String,
        plantId: asString(j['plant_id']) ?? '',
        equipmentId: asString(j['equipment_id']),
        code: asString(j['code']) ?? '',
        tag: asString(j['tag']) ?? '',
        message: asString(j['message']) ?? '',
        priority: AlarmPriority.parse(asString(j['priority'])),
        state: asString(j['state']) ?? 'active',
        value: asDouble(j['value']),
        raisedAt: asDate(j['raised_at']) ?? DateTime.now(),
        simRaisedAt: asDate(j['sim_raised_at']),
        acknowledgedByName: asString(j['acknowledged_by_name']),
        acknowledgedAt: asDate(j['acknowledged_at']),
        ackComment: asString(j['ack_comment']),
        clearedAt: asDate(j['cleared_at']),
      );
}

class ControlCommand {
  const ControlCommand({
    required this.id,
    required this.plantId,
    this.equipmentId,
    required this.tag,
    required this.action,
    this.requestedState,
    required this.status,
    this.resultMessage,
    this.requestedByName,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final String plantId;
  final String? equipmentId;
  final String tag;
  final String action;
  final String? requestedState;
  final String status; // pending | in_progress | completed | blocked | rejected | failed
  final String? resultMessage;
  final String? requestedByName;
  final DateTime createdAt;
  final DateTime? completedAt;

  String get actionLabel => switch (action) {
        'start' => 'Start',
        'stop' => 'Stop',
        'open' => 'Open',
        'close' => 'Close',
        'set_auto' => 'Set AUTO',
        'set_manual' => 'Set MANUAL',
        _ => action,
      };

  factory ControlCommand.fromJson(Json j) => ControlCommand(
        id: j['id'] as String,
        plantId: asString(j['plant_id']) ?? '',
        equipmentId: asString(j['equipment_id']),
        tag: asString(j['tag']) ?? '',
        action: asString(j['action']) ?? '',
        requestedState: asString(j['requested_state']),
        status: asString(j['status']) ?? 'pending',
        resultMessage: asString(j['result_message']),
        requestedByName: asString(j['requested_by_name']),
        createdAt: asDate(j['created_at']) ?? DateTime.now(),
        completedAt: asDate(j['completed_at']),
      );
}

class Setpoint {
  const Setpoint({
    required this.id,
    required this.plantId,
    required this.key,
    required this.name,
    this.description,
    required this.category,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    this.updatedByName,
    this.updatedAt,
  });

  final String id;
  final String plantId;
  final String key;
  final String name;
  final String? description;
  final String category;
  final String unit;
  final double value;
  final double min;
  final double max;
  final double step;
  final String? updatedByName;
  final DateTime? updatedAt;

  String format(double v) => step < 1 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);

  factory Setpoint.fromJson(Json j) => Setpoint(
        id: j['id'] as String,
        plantId: asString(j['plant_id']) ?? '',
        key: asString(j['key']) ?? '',
        name: asString(j['name']) ?? '',
        description: asString(j['description']),
        category: asString(j['category']) ?? 'Control',
        unit: asString(j['unit']) ?? '',
        value: asDoubleOr(j['value']),
        min: asDoubleOr(j['min_value']),
        max: asDoubleOr(j['max_value'], 100),
        step: asDoubleOr(j['step'], 1),
        updatedByName: asString(j['updated_by_name']),
        updatedAt: asDate(j['updated_at']),
      );
}

class SetpointProposal {
  const SetpointProposal({
    required this.id,
    required this.setpointId,
    required this.plantId,
    required this.setpointName,
    required this.unit,
    required this.currentValue,
    required this.proposedValue,
    required this.reason,
    required this.status,
    this.proposedBy,
    this.proposedByName,
    this.reviewedByName,
    this.reviewNote,
    required this.createdAt,
    this.reviewedAt,
  });

  final String id;
  final String setpointId;
  final String plantId;
  final String setpointName;
  final String unit;
  final double currentValue;
  final double proposedValue;
  final String reason;
  final String status; // pending | approved | rejected | withdrawn
  final String? proposedBy;
  final String? proposedByName;
  final String? reviewedByName;
  final String? reviewNote;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  factory SetpointProposal.fromJson(Json j) => SetpointProposal(
        id: j['id'] as String,
        setpointId: asString(j['setpoint_id']) ?? '',
        plantId: asString(j['plant_id']) ?? '',
        setpointName: asString(j['setpoint_name']) ?? '',
        unit: asString(j['unit']) ?? '',
        currentValue: asDoubleOr(j['current_value']),
        proposedValue: asDoubleOr(j['proposed_value']),
        reason: asString(j['reason']) ?? '',
        status: asString(j['status']) ?? 'pending',
        proposedBy: asString(j['proposed_by']),
        proposedByName: asString(j['proposed_by_name']),
        reviewedByName: asString(j['reviewed_by_name']),
        reviewNote: asString(j['review_note']),
        createdAt: asDate(j['created_at']) ?? DateTime.now(),
        reviewedAt: asDate(j['reviewed_at']),
      );
}

class MaintenanceOrder {
  const MaintenanceOrder({
    required this.id,
    required this.number,
    required this.plantId,
    this.equipmentId,
    this.equipmentTag,
    required this.title,
    this.description,
    required this.type,
    required this.priority,
    required this.status,
    required this.requiresLockout,
    required this.lockoutApplied,
    this.assignedTo,
    this.assignedToName,
    this.createdByName,
    this.dueDate,
    this.startedAt,
    this.completedAt,
    this.completionNotes,
    this.externalRef,
    required this.createdAt,
  });

  final String id;
  final String number;
  final String plantId;
  final String? equipmentId;
  final String? equipmentTag;
  final String title;
  final String? description;
  final String type;
  final String priority;
  final String status;
  final bool requiresLockout;
  final bool lockoutApplied;
  final String? assignedTo;
  final String? assignedToName;
  final String? createdByName;
  final DateTime? dueDate;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? completionNotes;
  final String? externalRef;
  final DateTime createdAt;

  bool get isClosed => status == 'completed' || status == 'cancelled';
  bool get isOverdue => !isClosed && dueDate != null && dueDate!.isBefore(DateTime.now().subtract(const Duration(days: 1)));

  factory MaintenanceOrder.fromJson(Json j) => MaintenanceOrder(
        id: j['id'] as String,
        number: asString(j['number']) ?? '',
        plantId: asString(j['plant_id']) ?? '',
        equipmentId: asString(j['equipment_id']),
        equipmentTag: asString(j['equipment_tag']),
        title: asString(j['title']) ?? '',
        description: asString(j['description']),
        type: asString(j['type']) ?? 'corrective',
        priority: asString(j['priority']) ?? 'medium',
        status: asString(j['status']) ?? 'requested',
        requiresLockout: asBool(j['requires_lockout']),
        lockoutApplied: asBool(j['lockout_applied']),
        assignedTo: asString(j['assigned_to']),
        assignedToName: asString(j['assigned_to_name']),
        createdByName: asString(j['created_by_name']),
        dueDate: asDate(j['due_date']),
        startedAt: asDate(j['started_at']),
        completedAt: asDate(j['completed_at']),
        completionNotes: asString(j['completion_notes']),
        externalRef: asString(j['external_ref']),
        createdAt: asDate(j['created_at']) ?? DateTime.now(),
      );
}

class MaintenanceAttachment {
  const MaintenanceAttachment({
    required this.id,
    required this.orderId,
    required this.filePath,
    required this.fileName,
    this.sizeBytes,
    this.contentType,
    this.uploadedBy,
    this.uploadedByName,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String filePath;
  final String fileName;
  final int? sizeBytes;
  final String? contentType;
  final String? uploadedBy;
  final String? uploadedByName;
  final DateTime createdAt;

  factory MaintenanceAttachment.fromJson(Json j) => MaintenanceAttachment(
        id: j['id'] as String,
        orderId: asString(j['order_id']) ?? '',
        filePath: asString(j['file_path']) ?? '',
        fileName: asString(j['file_name']) ?? '',
        sizeBytes: j['size_bytes'] == null ? null : asInt(j['size_bytes']),
        contentType: asString(j['content_type']),
        uploadedBy: asString(j['uploaded_by']),
        uploadedByName: asString(j['uploaded_by_name']),
        createdAt: asDate(j['created_at']) ?? DateTime.now(),
      );
}

class ShiftHandover {
  const ShiftHandover({
    required this.id,
    required this.plantId,
    required this.shift,
    required this.shiftDate,
    this.authorId,
    this.authorName,
    required this.summary,
    this.openIssues,
    this.safetyNotes,
    this.equipmentNotes,
    required this.snapshot,
    required this.status,
    this.acknowledgedByName,
    this.acknowledgedAt,
    required this.createdAt,
  });

  final String id;
  final String plantId;
  final String shift;
  final DateTime shiftDate;
  final String? authorId;
  final String? authorName;
  final String summary;
  final String? openIssues;
  final String? safetyNotes;
  final String? equipmentNotes;
  final Json snapshot;
  final String status;
  final String? acknowledgedByName;
  final DateTime? acknowledgedAt;
  final DateTime createdAt;

  factory ShiftHandover.fromJson(Json j) => ShiftHandover(
        id: j['id'] as String,
        plantId: asString(j['plant_id']) ?? '',
        shift: asString(j['shift']) ?? 'day',
        shiftDate: asDate(j['shift_date']) ?? DateTime.now(),
        authorId: asString(j['author_id']),
        authorName: asString(j['author_name']),
        summary: asString(j['summary']) ?? '',
        openIssues: asString(j['open_issues']),
        safetyNotes: asString(j['safety_notes']),
        equipmentNotes: asString(j['equipment_notes']),
        snapshot: asJson(j['snapshot']),
        status: asString(j['status']) ?? 'submitted',
        acknowledgedByName: asString(j['acknowledged_by_name']),
        acknowledgedAt: asDate(j['acknowledged_at']),
        createdAt: asDate(j['created_at']) ?? DateTime.now(),
      );
}

class EventLog {
  const EventLog({
    required this.id,
    this.plantId,
    required this.category,
    required this.severity,
    required this.message,
    this.actorName,
    this.simTime,
    required this.createdAt,
  });

  final int id;
  final String? plantId;
  final String category;
  final String severity;
  final String message;
  final String? actorName;
  final DateTime? simTime;
  final DateTime createdAt;

  factory EventLog.fromJson(Json j) => EventLog(
        id: asInt(j['id']),
        plantId: asString(j['plant_id']),
        category: asString(j['category']) ?? 'system',
        severity: asString(j['severity']) ?? 'info',
        message: asString(j['message']) ?? '',
        actorName: asString(j['actor_name']),
        simTime: asDate(j['sim_time']),
        createdAt: asDate(j['created_at']) ?? DateTime.now(),
      );
}

class Measurement {
  const Measurement(this.tag, this.value, this.ts);
  final String tag;
  final double value;
  final DateTime ts;

  factory Measurement.fromJson(Json j) =>
      Measurement(asString(j['tag']) ?? '', asDoubleOr(j['value']), asDate(j['ts']) ?? DateTime.now());
}

class IntegrationLogEntry {
  const IntegrationLogEntry({
    required this.id,
    this.plantId,
    required this.system,
    required this.action,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final String? plantId;
  final String system;
  final String action;
  final String message;
  final String status;
  final DateTime createdAt;

  factory IntegrationLogEntry.fromJson(Json j) => IntegrationLogEntry(
        id: asInt(j['id']),
        plantId: asString(j['plant_id']),
        system: asString(j['system']) ?? '',
        action: asString(j['action']) ?? '',
        message: asString(j['message']) ?? '',
        status: asString(j['status']) ?? 'delivered',
        createdAt: asDate(j['created_at']) ?? DateTime.now(),
      );
}

class IntegrationSystem {
  const IntegrationSystem({
    required this.id,
    required this.name,
    required this.vendor,
    required this.description,
    required this.status,
    required this.latencyMs,
    this.lastActivityAt,
    this.lastMessage,
    required this.messages24h,
  });

  final String id;
  final String name;
  final String vendor;
  final String description;
  final String status;
  final int latencyMs;
  final DateTime? lastActivityAt;
  final String? lastMessage;
  final int messages24h;

  factory IntegrationSystem.fromJson(Json j) => IntegrationSystem(
        id: asString(j['id']) ?? '',
        name: asString(j['name']) ?? '',
        vendor: asString(j['vendor']) ?? '',
        description: asString(j['description']) ?? '',
        status: asString(j['status']) ?? 'online',
        latencyMs: asInt(j['latencyMs']),
        lastActivityAt: asDate(j['lastActivityAt']),
        lastMessage: asString(j['lastMessage']),
        messages24h: asInt(j['messages24h']),
      );
}
