import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

final _time = DateFormat('HH:mm:ss');
final _short = DateFormat('MMM d, HH:mm');
final _date = DateFormat('MMM d, yyyy');
final _full = DateFormat('EEE, MMM d yyyy · HH:mm');

String fmtTime(DateTime? d) => d == null ? '—' : _time.format(d);
String fmtShort(DateTime? d) => d == null ? '—' : _short.format(d);
String fmtDate(DateTime? d) => d == null ? '—' : _date.format(d);
String fmtFull(DateTime? d) => d == null ? '—' : _full.format(d);

String fmtNum(num? v, {int digits = 1}) => v == null ? '—' : v.toStringAsFixed(digits);

String timeAgo(DateTime? d) {
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  if (diff.isNegative || diff.inSeconds < 10) return 'just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return fmtDate(d);
}

String fmtBytes(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

String titleCase(String s) => s
    .replaceAll('_', ' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// Human-readable equipment state.
String stateLabel(String? s) => switch (s) {
      null => '—',
      'locked_out' => 'Locked out',
      'rtn_unack' => 'Cleared (unack.)',
      _ => titleCase(s),
    };

Color stateColor(String? s) => switch (s) {
      'running' || 'open' => AppColors.running,
      'stopped' || 'closed' => AppColors.stopped,
      'opening' || 'closing' => AppColors.transition,
      'fault' || 'overflow' || 'empty' => AppColors.fault,
      'interlocked' || 'high' || 'low' => AppColors.warning,
      'locked_out' => AppColors.lockout,
      'normal' => AppColors.water,
      _ => AppColors.textMuted,
    };

Color priorityColor(String p) => switch (p) {
      'critical' || 'urgent' => AppColors.critical,
      'high' => const Color(0xFFFF8A4C),
      'medium' => AppColors.warning,
      _ => AppColors.info,
    };

Color commandStatusColor(String s) => switch (s) {
      'completed' => AppColors.running,
      'in_progress' || 'pending' => AppColors.transition,
      'blocked' => AppColors.warning,
      'rejected' || 'failed' => AppColors.fault,
      _ => AppColors.textMuted,
    };

Color workOrderStatusColor(String s) => switch (s) {
      'requested' => AppColors.info,
      'scheduled' => AppColors.secondary,
      'in_progress' => AppColors.warning,
      'completed' => AppColors.running,
      _ => AppColors.textMuted,
    };

Color plantStatusColor(String s) => switch (s) {
      'alarm' => AppColors.fault,
      'warning' => AppColors.warning,
      _ => AppColors.running,
    };

Color severityColor(String s) => switch (s) {
      'critical' => AppColors.fault,
      'warning' => AppColors.warning,
      _ => AppColors.info,
    };
