import 'package:codexflow_flutter/navigation/notification_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses manual approval target', () {
    final target = NotificationTarget.fromJsonString(
      '{"target":"approvals","approvalId":"req-1","sessionId":"s1"}',
    );

    expect(target.target, NotificationTargetKind.approvals);
    expect(target.approvalId, 'req-1');
    expect(target.sessionId, 's1');
  });

  test('parses session detail target', () {
    final target = NotificationTarget.fromJsonString(
      '{"target":"sessionDetail","sessionId":"s1","turnId":"t1","status":"completed"}',
    );

    expect(target.target, NotificationTargetKind.sessionDetail);
    expect(target.sessionId, 's1');
    expect(target.turnId, 't1');
    expect(target.status, 'completed');
  });

  test('invalid route falls back to dashboard', () {
    final target = NotificationTarget.fromJsonString('{bad json');

    expect(target.target, NotificationTargetKind.dashboard);
  });
}
