import 'package:codexflow_flutter/domain/session_groups.dart';
import 'package:codexflow_flutter/models/app_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('groupSessionsForAgent', () {
    test(
      'includes discovered sessions in the history group with history_only',
      () {
        final historyOnly = _session(
          id: 'history-only',
          lifecycleStage: 'history_only',
        );
        final discovered = _session(
          id: 'discovered',
          lifecycleStage: 'discovered',
        );
        final managed = _session(id: 'managed', lifecycleStage: 'managed');

        final groups = groupSessionsForAgent(
          sessions: <SessionSummary>[historyOnly, discovered, managed],
          approvals: const <PendingRequestView>[],
          selectedAgentId: 'codex',
        );

        expect(groups.history, <SessionSummary>[historyOnly, discovered]);
        expect(groups.managed, <SessionSummary>[managed]);
      },
    );

    test(
      'pending approval count uses approvals filtered by threadId instead of session summary counts',
      () {
        final selectedSession = _session(
          id: 'selected-session',
          pendingApprovals: 12,
        );
        final otherAgentSession = _session(
          id: 'other-agent-session',
          agentId: 'claude',
          pendingApprovals: 20,
        );
        final selectedApproval = _approval(
          id: 'selected-approval',
          threadId: selectedSession.id,
        );
        final otherAgentApproval = _approval(
          id: 'other-agent-approval',
          threadId: otherAgentSession.id,
        );
        final orphanApproval = _approval(
          id: 'orphan-approval',
          threadId: 'missing-session',
        );

        final groups = groupSessionsForAgent(
          sessions: <SessionSummary>[selectedSession, otherAgentSession],
          approvals: <PendingRequestView>[
            selectedApproval,
            otherAgentApproval,
            orphanApproval,
          ],
          selectedAgentId: 'codex',
        );

        expect(groups.pendingApprovals, <PendingRequestView>[selectedApproval]);
        expect(groups.pendingApprovalCount, 1);
      },
    );
  });
}

SessionSummary _session({
  required String id,
  String agentId = 'codex',
  String lifecycleStage = 'managed',
  String status = 'idle',
  bool loaded = false,
  bool ended = false,
  int pendingApprovals = 0,
}) {
  return SessionSummary(
    id: id,
    agentId: agentId,
    name: id,
    preview: '',
    cwd: '/tmp',
    source: 'test',
    status: status,
    activeFlags: const <String>[],
    loaded: loaded,
    updatedAt: 0,
    createdAt: 0,
    modelProvider: '',
    branch: '',
    pendingApprovals: pendingApprovals,
    lastTurnId: '',
    lastTurnStatus: '',
    agentNickname: '',
    agentRole: '',
    lifecycleStage: lifecycleStage,
    historyAvailable: false,
    runtimeAvailable: false,
    runtimeAttachMode: '',
    resumeAvailable: true,
    resumeBlockedReason: '',
    ended: ended,
  );
}

PendingRequestView _approval({required String id, required String threadId}) {
  return PendingRequestView(
    id: id,
    method: 'test',
    kind: 'choice',
    threadId: threadId,
    turnId: '',
    itemId: '',
    reason: '',
    summary: '',
    choices: const <String>[],
    createdAt: DateTime.utc(2026, 5, 1),
    params: const <String, dynamic>{},
  );
}
