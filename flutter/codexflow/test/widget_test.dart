import 'package:codexflow_flutter/models/app_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codexflow_flutter/main.dart';
import 'package:codexflow_flutter/navigation/notification_target.dart';
import 'package:codexflow_flutter/screens/session_detail_screen.dart';
import 'package:codexflow_flutter/state/app_model.dart';

void main() {
  testWidgets('renders CodexFlow shell', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(CodexFlowApp(prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.text('会话'), findsWidgets);
    expect(find.text('审批'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('notification session route does not stack duplicate pages', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final model = _NotificationRouteAppModel(prefs);
    final summary = _sessionSummary();
    model.dashboard = _dashboard(summary);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>.value(
        value: model,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();

    const target = NotificationTarget(
      target: NotificationTargetKind.sessionDetail,
      sessionId: 'session-notification',
    );

    model.applyNotificationTarget(target);
    await tester.pumpAndSettle();
    expect(find.byType(SessionDetailScreen), findsOneWidget);

    model.applyNotificationTarget(target);
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailScreen), findsNothing);
    expect(find.text('会话'), findsWidgets);
  });
}

class _NotificationRouteAppModel extends AppModel {
  _NotificationRouteAppModel(super.prefs);

  @override
  Future<void> startMonitorIfAllowed() async {}

  @override
  Future<void> refreshMonitorStatus() async {}

  @override
  Future<void> refreshDashboard({bool refreshSkills = true}) async {}

  @override
  Future<NotificationTarget?> takeInitialNotificationRoute() async => null;

  @override
  Future<void> setMonitorVisible(bool visible) async {}

  @override
  Future<void> loadSession(String id) async {
    final summary = dashboard.sessions.firstWhere(
      (session) => session.id == id,
    );
    sessionDetails[id] = SessionDetail(
      summary: summary,
      turns: const <TurnDetail>[],
    );
    notifyListeners();
  }
}

DashboardResponse _dashboard(SessionSummary summary) {
  return DashboardResponse(
    agent: AgentSnapshot(
      connected: true,
      startedAt: DateTime.fromMillisecondsSinceEpoch(0),
      listenAddr: '127.0.0.1:4318',
      codexBinaryPath: 'codex',
    ),
    agents: <AgentOption>[
      AgentOption(
        id: 'codex',
        name: 'Codex',
        available: true,
        isDefault: true,
        capabilities: AgentCapabilities(
          supportsInterruptTurn: true,
          supportsApprovals: true,
          supportsArchive: true,
          supportsResume: true,
          supportsHistoryImport: false,
        ),
      ),
    ],
    defaultAgent: 'codex',
    stats: DashboardStats(
      totalSessions: 1,
      loadedSessions: 1,
      activeSessions: 0,
      pendingApprovals: 0,
    ),
    sessions: <SessionSummary>[summary],
    approvals: const <PendingRequestView>[],
  );
}

SessionSummary _sessionSummary() {
  return SessionSummary(
    id: 'session-notification',
    agentId: 'codex',
    name: 'Notification Test',
    preview: 'latest message',
    cwd: '/tmp/codexflow',
    source: 'codex',
    status: 'active',
    activeFlags: const <String>[],
    loaded: true,
    updatedAt: 1777610400,
    createdAt: 1777610000,
    modelProvider: 'openai',
    branch: 'main',
    pendingApprovals: 0,
    lastTurnId: 'turn-1',
    lastTurnStatus: 'completed',
    agentNickname: '',
    agentRole: '',
    lifecycleStage: 'managed',
    historyAvailable: true,
    runtimeAvailable: true,
    runtimeAttachMode: 'managed',
    resumeAvailable: true,
    resumeBlockedReason: '',
    ended: false,
    userInitiated: true,
  );
}
