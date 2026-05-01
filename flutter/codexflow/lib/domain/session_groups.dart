import '../models/app_models.dart';

class SessionGroups {
  const SessionGroups({
    required this.sessions,
    required this.managed,
    required this.ended,
    required this.runtimeAvailable,
    required this.history,
    required this.pendingApprovals,
  });

  final List<SessionSummary> sessions;
  final List<SessionSummary> managed;
  final List<SessionSummary> ended;
  final List<SessionSummary> runtimeAvailable;
  final List<SessionSummary> history;
  final List<PendingRequestView> pendingApprovals;

  int get loadedCount => sessions.where((session) => session.loaded).length;

  int get activeCount => sessions
      .where((session) => session.status == 'active' && !session.isEnded)
      .length;

  int get pendingApprovalCount => pendingApprovals.length;
}

SessionGroups groupSessionsForAgent({
  required List<SessionSummary> sessions,
  required List<PendingRequestView> approvals,
  required String selectedAgentId,
}) {
  final filteredSessions = sessions
      .where(
        (session) =>
            session.agentId == selectedAgentId && session.userInitiated,
      )
      .toList();
  final allowedSessionIds = filteredSessions
      .map((session) => session.id)
      .toSet();
  final filteredApprovals = approvals
      .where((approval) => allowedSessionIds.contains(approval.threadId))
      .toList();

  return SessionGroups(
    sessions: filteredSessions,
    managed: filteredSessions
        .where((session) => session.lifecycleStage == 'managed')
        .toList(),
    ended: filteredSessions
        .where((session) => session.lifecycleStage == 'ended')
        .toList(),
    runtimeAvailable: filteredSessions
        .where((session) => session.lifecycleStage == 'runtime_available')
        .toList(),
    history: filteredSessions
        .where(
          (session) =>
              session.lifecycleStage == 'history_only' ||
              session.lifecycleStage == 'discovered',
        )
        .toList(),
    pendingApprovals: filteredApprovals,
  );
}
