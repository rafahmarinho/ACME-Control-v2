import 'json.dart';

enum UserRole {
  operator('Operator'),
  engineer('Engineer'),
  supervisor('Supervisor'),
  maintenance('Maintenance');

  const UserRole(this.label);
  final String label;

  static UserRole parse(String? v) =>
      UserRole.values.firstWhere((r) => r.name == v, orElse: () => UserRole.operator);

  bool get canCommand => this == operator || this == supervisor;
  bool get canProposeSetpoints => this == engineer || this == supervisor;
  bool get canReviewSetpoints => this == supervisor;
  bool get canLockout => this == maintenance || this == supervisor;
  bool get canPlanMaintenance => this == maintenance || this == engineer || this == supervisor;
  bool get canSimulate => this == operator || this == engineer || this == supervisor;
  bool get canResetDemo => this == engineer || this == supervisor;
  bool get canWriteHandover => this == operator || this == supervisor || this == maintenance;

  String get description => switch (this) {
        operator => 'Monitors the process, operates pumps and valves, acknowledges alarms.',
        engineer => 'Analyses trends, proposes setpoint changes and runs simulation scenarios.',
        supervisor => 'Full control, reviews setpoint proposals and acknowledges handovers.',
        maintenance => 'Manages work orders, applies lockout/tagout on equipment.',
      };
}

class Profile {
  const Profile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.jobTitle,
    this.phone,
    this.avatarUrl,
    this.preferences = const {},
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? jobTitle;
  final String? phone;
  final String? avatarUrl;
  final Json preferences;

  String get displayName => fullName.isNotEmpty ? fullName : email;
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory Profile.fromJson(Json j) => Profile(
        id: j['id'] as String,
        email: asString(j['email']) ?? '',
        fullName: asString(j['full_name']) ?? '',
        role: UserRole.parse(asString(j['role'])),
        jobTitle: asString(j['job_title']),
        phone: asString(j['phone']),
        avatarUrl: asString(j['avatar_url']),
        preferences: asJson(j['preferences']),
      );
}
