import 'package:codexflow_flutter/navigation/mobile_notification_route_coordinator.dart';
import 'package:codexflow_flutter/navigation/notification_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens a session route once while it is opening or active', () {
    final coordinator = MobileNotificationRouteCoordinator();
    const target = NotificationTarget(
      target: NotificationTargetKind.sessionDetail,
      sessionId: 'session-a',
    );

    final first = coordinator.begin(target);

    expect(first.action, MobileNotificationRouteAction.showSessionDetail);
    expect(first.sessionId, 'session-a');

    final whileOpening = coordinator.begin(target);
    expect(whileOpening.action, MobileNotificationRouteAction.ignore);

    coordinator.markSessionOpened('session-a');

    final whileActive = coordinator.begin(target);
    expect(whileActive.action, MobileNotificationRouteAction.ignore);

    coordinator.markSessionClosed('session-a');

    final afterClose = coordinator.begin(target);
    expect(afterClose.action, MobileNotificationRouteAction.showSessionDetail);
  });

  test('different session route replaces the current Chat Timeline', () {
    final coordinator = MobileNotificationRouteCoordinator();
    const firstTarget = NotificationTarget(
      target: NotificationTargetKind.sessionDetail,
      sessionId: 'session-a',
    );
    const secondTarget = NotificationTarget(
      target: NotificationTargetKind.sessionDetail,
      sessionId: 'session-b',
    );

    expect(
      coordinator.begin(firstTarget).action,
      MobileNotificationRouteAction.showSessionDetail,
    );
    coordinator.markSessionOpened('session-a');

    final second = coordinator.begin(secondTarget);

    expect(second.action, MobileNotificationRouteAction.showSessionDetail);
    expect(second.sessionId, 'session-b');
    expect(second.replaceCurrentDetail, isTrue);
  });

  test('empty session route becomes an error notice', () {
    final coordinator = MobileNotificationRouteCoordinator();
    const target = NotificationTarget(
      target: NotificationTargetKind.sessionDetail,
    );

    final decision = coordinator.begin(target);

    expect(decision.action, MobileNotificationRouteAction.showNotice);
    expect(decision.noticeIsError, isTrue);
    expect(decision.notice, isNotEmpty);
  });

  test('approval and dashboard routes map to idempotent actions', () {
    final coordinator = MobileNotificationRouteCoordinator();
    const approvalTarget = NotificationTarget(
      target: NotificationTargetKind.approvals,
      approvalId: 'approval-1',
      sessionId: 'session-a',
    );

    final approval = coordinator.begin(approvalTarget);
    expect(approval.action, MobileNotificationRouteAction.showApprovals);
    expect(approval.approvalId, 'approval-1');
    expect(approval.sessionId, 'session-a');

    final dashboard = coordinator.begin(NotificationTarget.dashboard());
    expect(dashboard.action, MobileNotificationRouteAction.showDashboard);
  });
}
