import 'dart:convert';

enum NotificationTargetKind { dashboard, approvals, sessionDetail }

class NotificationTarget {
  const NotificationTarget({
    required this.target,
    this.approvalId = '',
    this.sessionId = '',
    this.turnId = '',
    this.status = '',
  });

  factory NotificationTarget.dashboard() =>
      const NotificationTarget(target: NotificationTargetKind.dashboard);

  final NotificationTargetKind target;
  final String approvalId;
  final String sessionId;
  final String turnId;
  final String status;

  static NotificationTarget fromJsonString(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) {
        return NotificationTarget.dashboard();
      }
      final rawTarget = decoded['target']?.toString() ?? 'dashboard';
      final kind = switch (rawTarget) {
        'approvals' => NotificationTargetKind.approvals,
        'sessionDetail' => NotificationTargetKind.sessionDetail,
        _ => NotificationTargetKind.dashboard,
      };
      return NotificationTarget(
        target: kind,
        approvalId: decoded['approvalId']?.toString() ?? '',
        sessionId: decoded['sessionId']?.toString() ?? '',
        turnId: decoded['turnId']?.toString() ?? '',
        status: decoded['status']?.toString() ?? '',
      );
    } catch (_) {
      return NotificationTarget.dashboard();
    }
  }
}
