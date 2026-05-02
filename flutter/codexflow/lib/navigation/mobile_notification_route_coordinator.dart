import 'notification_target.dart';

enum MobileNotificationRouteAction {
  showDashboard,
  showApprovals,
  showSessionDetail,
  showNotice,
  ignore,
}

class MobileNotificationRouteDecision {
  const MobileNotificationRouteDecision({
    required this.action,
    this.sessionId = '',
    this.approvalId = '',
    this.notice = '',
    this.noticeIsError = false,
    this.replaceCurrentDetail = false,
  });

  factory MobileNotificationRouteDecision.showDashboard() {
    return const MobileNotificationRouteDecision(
      action: MobileNotificationRouteAction.showDashboard,
    );
  }

  factory MobileNotificationRouteDecision.showApprovals({
    required String approvalId,
    required String sessionId,
  }) {
    return MobileNotificationRouteDecision(
      action: MobileNotificationRouteAction.showApprovals,
      approvalId: approvalId,
      sessionId: sessionId,
    );
  }

  factory MobileNotificationRouteDecision.showSessionDetail({
    required String sessionId,
    required bool replaceCurrentDetail,
  }) {
    return MobileNotificationRouteDecision(
      action: MobileNotificationRouteAction.showSessionDetail,
      sessionId: sessionId,
      replaceCurrentDetail: replaceCurrentDetail,
    );
  }

  factory MobileNotificationRouteDecision.showNotice({
    required String notice,
    required bool isError,
  }) {
    return MobileNotificationRouteDecision(
      action: MobileNotificationRouteAction.showNotice,
      notice: notice,
      noticeIsError: isError,
    );
  }

  factory MobileNotificationRouteDecision.ignore() {
    return const MobileNotificationRouteDecision(
      action: MobileNotificationRouteAction.ignore,
    );
  }

  final MobileNotificationRouteAction action;
  final String sessionId;
  final String approvalId;
  final String notice;
  final bool noticeIsError;
  final bool replaceCurrentDetail;
}

class MobileNotificationRouteCoordinator {
  String? _openingSessionId;
  String? _activeSessionId;

  MobileNotificationRouteDecision begin(NotificationTarget target) {
    switch (target.target) {
      case NotificationTargetKind.dashboard:
        return MobileNotificationRouteDecision.showDashboard();
      case NotificationTargetKind.approvals:
        return MobileNotificationRouteDecision.showApprovals(
          approvalId: target.approvalId,
          sessionId: target.sessionId,
        );
      case NotificationTargetKind.sessionDetail:
        return _beginSessionDetail(target.sessionId);
    }
  }

  void markSessionOpened(String sessionId) {
    final normalized = sessionId.trim();
    if (_openingSessionId == normalized) {
      _openingSessionId = null;
    }
    if (normalized.isNotEmpty) {
      _activeSessionId = normalized;
    }
  }

  void markSessionClosed(String sessionId) {
    final normalized = sessionId.trim();
    if (_activeSessionId == normalized) {
      _activeSessionId = null;
    }
    if (_openingSessionId == normalized) {
      _openingSessionId = null;
    }
  }

  void markSessionOpenFailed(String sessionId) {
    final normalized = sessionId.trim();
    if (_openingSessionId == normalized) {
      _openingSessionId = null;
    }
  }

  MobileNotificationRouteDecision _beginSessionDetail(String rawSessionId) {
    final sessionId = rawSessionId.trim();
    if (sessionId.isEmpty) {
      return MobileNotificationRouteDecision.showNotice(
        notice: '通知缺少会话信息。',
        isError: true,
      );
    }
    if (_openingSessionId == sessionId || _activeSessionId == sessionId) {
      return MobileNotificationRouteDecision.ignore();
    }
    final replaceCurrentDetail = _activeSessionId != null;
    _openingSessionId = sessionId;
    return MobileNotificationRouteDecision.showSessionDetail(
      sessionId: sessionId,
      replaceCurrentDetail: replaceCurrentDetail,
    );
  }
}
