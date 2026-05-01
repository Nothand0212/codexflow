import 'package:codexflow_flutter/models/app_models.dart';
import 'package:codexflow_flutter/screens/session_detail_screen.dart';
import 'package:codexflow_flutter/state/app_model.dart';
import 'package:codexflow_flutter/theme/palette.dart';
import 'package:codexflow_flutter/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens session detail scrolled to the latest message', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final model = _StaticAppModel(prefs);
    final summary = _sessionSummary();
    final detail = SessionDetail(
      summary: summary,
      turns: List<TurnDetail>.generate(36, (index) => _turn(index)),
    );
    model.dashboard = _dashboard(summary);
    model.sessionDetails[summary.id] = detail;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>.value(
        value: model,
        child: MaterialApp(home: SessionDetailScreen(sessionId: summary.id)),
      ),
    );
    for (var index = 0; index < 6; index += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final timeline = tester.widget<ListView>(find.byType(ListView).first);
    final controller = timeline.controller;
    expect(controller, isNotNull);
    expect(controller!.hasClients, isTrue);
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(
      (controller.position.pixels - controller.position.maxScrollExtent).abs(),
      lessThanOrEqualTo(1),
    );
    expect(find.text('agent message 35'), findsOneWidget);
  });

  testWidgets('session detail hides execution details from the chat timeline', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final model = _StaticAppModel(prefs);
    final summary = _sessionSummary();
    final detail = SessionDetail(
      summary: summary,
      turns: <TurnDetail>[_turnWithExecutionDetails()],
    );
    model.dashboard = _dashboard(
      summary,
      approvals: <PendingRequestView>[_approval(summary.id)],
    );
    model.sessionDetails[summary.id] = detail;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>.value(
        value: model,
        child: MaterialApp(home: SessionDetailScreen(sessionId: summary.id)),
      ),
    );
    for (var index = 0; index < 6; index += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('user asks for final answer'), findsOneWidget);
    expect(find.text('final answer only'), findsOneWidget);
    expect(find.text('思考过程'), findsNothing);
    expect(find.text('执行细节'), findsNothing);
    expect(find.text('待审批'), findsNothing);
    expect(find.textContaining('private reasoning'), findsNothing);
    expect(find.textContaining('echo hidden'), findsNothing);
    expect(find.textContaining('hidden file change'), findsNothing);
    expect(find.textContaining('hidden plan step'), findsNothing);
    expect(find.textContaining('hidden diff'), findsNothing);
  });

  testWidgets('session detail initially renders the latest message page', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final model = _StaticAppModel(prefs);
    final summary = _sessionSummary(lastTurnId: 'turn-119');
    final detail = SessionDetail(
      summary: summary,
      turns: List<TurnDetail>.generate(120, (index) => _turn(index)),
    );
    model.dashboard = _dashboard(summary);
    model.sessionDetails[summary.id] = detail;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>.value(
        value: model,
        child: MaterialApp(home: SessionDetailScreen(sessionId: summary.id)),
      ),
    );
    for (var index = 0; index < 6; index += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('agent message 119'), findsOneWidget);

    final timeline = tester.widget<ListView>(find.byType(ListView).first);
    timeline.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('加载更早消息'), findsOneWidget);

    await tester.tap(find.text('加载更早消息'));
    await tester.pumpAndSettle();

    expect(find.text('agent message 40'), findsOneWidget);
  });

  testWidgets('session detail loads earlier turns from the backend page', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final model = _PagingAppModel(prefs);
    final summary = _sessionSummary(lastTurnId: 'turn-119');
    final detail = SessionDetail(
      summary: summary,
      turns: List<TurnDetail>.generate(40, (index) => _turn(index + 80)),
      page: const SessionDetailPage(
        turnOffset: 0,
        turnLimit: 40,
        totalTurns: 120,
        hasMoreBefore: true,
      ),
    );
    model.dashboard = _dashboard(summary);
    model.sessionDetails[summary.id] = detail;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>.value(
        value: model,
        child: MaterialApp(home: SessionDetailScreen(sessionId: summary.id)),
      ),
    );
    for (var index = 0; index < 6; index += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('agent message 119'), findsOneWidget);
    final timeline = tester.widget<ListView>(find.byType(ListView).first);
    timeline.controller!.jumpTo(0);
    await tester.pumpAndSettle();

    await tester.tap(find.text('加载更早消息'));
    await tester.pumpAndSettle();

    expect(model.loadEarlierCalls, 1);
    timeline.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('user message 40'), findsOneWidget);
  });

  testWidgets('session detail shows processing animation for running turns', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final model = _StaticAppModel(prefs);
    final summary = _sessionSummary(
      lastTurnId: 'turn-running',
      lastTurnStatus: 'inProgress',
    );
    final detail = SessionDetail(
      summary: summary,
      turns: <TurnDetail>[_userOnlyTurn('turn-running')],
    );
    model.dashboard = _dashboard(summary);
    model.sessionDetails[summary.id] = detail;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>.value(
        value: model,
        child: MaterialApp(home: SessionDetailScreen(sessionId: summary.id)),
      ),
    );
    for (var index = 0; index < 6; index += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('Codex 正在处理'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('skills sheet sorts, searches, and inserts selected skill', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final model = _StaticAppModel(prefs)
      ..skills = <AgentSkill>[
        AgentSkill(
          name: 'tdd',
          description: 'Test-driven development',
          insertText: r'$tdd ',
        ),
        AgentSkill(
          name: 'grill-with-docs',
          description: 'Challenge plans against docs',
          insertText: r'$grill-with-docs ',
        ),
        AgentSkill(
          name: 'brainstorming',
          description: 'Creative planning',
          insertText: r'$brainstorming ',
        ),
      ];
    final summary = _sessionSummary();
    model.dashboard = _dashboard(summary);
    model.sessionDetails[summary.id] = SessionDetail(
      summary: summary,
      turns: <TurnDetail>[_turn(0)],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>.value(
        value: model,
        child: MaterialApp(home: SessionDetailScreen(sessionId: summary.id)),
      ),
    );
    for (var index = 0; index < 6; index += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.tap(find.text('Skills'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.text('brainstorming'), findsOneWidget);
    expect(find.text('grill-with-docs'), findsOneWidget);
    expect(find.text('tdd'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('brainstorming')).dy,
      lessThan(tester.getTopLeft(find.text('grill-with-docs')).dy),
    );
    expect(
      tester.getTopLeft(find.text('grill-with-docs')).dy,
      lessThan(tester.getTopLeft(find.text('tdd')).dy),
    );

    await tester.enterText(find.byType(TextField).last, 'grill');
    await tester.pumpAndSettle();

    expect(find.text('brainstorming'), findsNothing);
    expect(find.text('grill-with-docs'), findsOneWidget);
    expect(find.text('tdd'), findsNothing);

    await tester.tap(find.text('grill-with-docs'));
    await tester.pumpAndSettle();

    final inserted = find.byType(EditableText).evaluate().any((element) {
      final widget = element.widget as EditableText;
      return widget.controller.text == r'$grill-with-docs ';
    });
    expect(inserted, isTrue);
  });

  testWidgets('markdown inline code remains readable on light chat bubbles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownBodyBlock(raw: 'Use `codexflow-agent.service` now'),
        ),
      ),
    );

    final codeSpan = _textSpanContaining(tester, 'codexflow-agent.service');

    expect(codeSpan, isNotNull);
    expect(codeSpan!.style?.color, Palette.ink);
    expect(codeSpan.style?.backgroundColor, isNotNull);
  });
}

class _StaticAppModel extends AppModel {
  _StaticAppModel(super.prefs);

  @override
  Future<void> refreshDashboard({bool refreshSkills = true}) async {}

  @override
  Future<void> loadSession(String id) async {}
}

class _PagingAppModel extends _StaticAppModel {
  _PagingAppModel(super.prefs);

  int loadEarlierCalls = 0;

  @override
  Future<void> loadEarlierSessionTurns(String id) async {
    loadEarlierCalls += 1;
    final current = sessionDetails[id]!;
    sessionDetails[id] = current.mergeEarlier(
      SessionDetail(
        summary: current.summary,
        turns: List<TurnDetail>.generate(40, (index) => _turn(index + 40)),
        page: const SessionDetailPage(
          turnOffset: 40,
          turnLimit: 40,
          totalTurns: 120,
          hasMoreBefore: true,
        ),
      ),
    );
    notifyListeners();
  }
}

DashboardResponse _dashboard(
  SessionSummary summary, {
  List<PendingRequestView> approvals = const <PendingRequestView>[],
}) {
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
    approvals: approvals,
  );
}

SessionSummary _sessionSummary({
  String lastTurnId = 'turn-35',
  String lastTurnStatus = 'completed',
}) {
  return SessionSummary(
    id: 'session-scroll-test',
    agentId: 'codex',
    name: 'Scroll Test',
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
    lastTurnId: lastTurnId,
    lastTurnStatus: lastTurnStatus,
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

TurnDetail _userOnlyTurn(String id) {
  return TurnDetail(
    id: id,
    status: 'inProgress',
    startedAt: 1777610000,
    completedAt: 0,
    durationMs: 0,
    error: '',
    diff: '',
    planExplanation: '',
    plan: const <PlanStep>[],
    items: <TurnItem>[
      TurnItem(
        id: 'user-$id',
        type: 'userMessage',
        title: '',
        body: 'start a long task',
        status: '',
        auxiliary: '',
        metadata: const <String, String>{},
      ),
    ],
  );
}

TurnDetail _turn(int index) {
  return TurnDetail(
    id: 'turn-$index',
    status: 'completed',
    startedAt: 1777610000 + index,
    completedAt: 1777610001 + index,
    durationMs: 1000,
    error: '',
    diff: '',
    planExplanation: '',
    plan: const <PlanStep>[],
    items: <TurnItem>[
      TurnItem(
        id: 'user-$index',
        type: 'userMessage',
        title: '',
        body: 'user message $index',
        status: '',
        auxiliary: '',
        metadata: const <String, String>{},
      ),
      TurnItem(
        id: 'agent-$index',
        type: 'agentMessage',
        title: '',
        body: 'agent message $index',
        status: '',
        auxiliary: '',
        metadata: const <String, String>{},
      ),
    ],
  );
}

TurnDetail _turnWithExecutionDetails() {
  return TurnDetail(
    id: 'turn-details',
    status: 'completed',
    startedAt: 1777610500,
    completedAt: 1777610510,
    durationMs: 10000,
    error: 'hidden error',
    diff: 'hidden diff',
    planExplanation: 'hidden plan explanation',
    plan: <PlanStep>[PlanStep(step: 'hidden plan step', status: 'completed')],
    items: <TurnItem>[
      TurnItem(
        id: 'user-details',
        type: 'userMessage',
        title: '',
        body: 'user asks for final answer',
        status: '',
        auxiliary: '',
        metadata: const <String, String>{},
      ),
      TurnItem(
        id: 'reasoning-details',
        type: 'reasoning',
        title: 'reasoning',
        body: 'private reasoning should not render',
        status: '',
        auxiliary: '',
        metadata: const <String, String>{},
      ),
      TurnItem(
        id: 'command-details',
        type: 'commandExecution',
        title: 'command',
        body: 'echo hidden',
        status: 'completed',
        auxiliary: 'hidden command output',
        metadata: const <String, String>{},
      ),
      TurnItem(
        id: 'file-details',
        type: 'fileChange',
        title: 'file',
        body: 'hidden file change',
        status: '',
        auxiliary: '',
        metadata: const <String, String>{},
      ),
      TurnItem(
        id: 'agent-details',
        type: 'agentMessage',
        title: '',
        body: 'final answer only',
        status: '',
        auxiliary: '',
        metadata: const <String, String>{},
      ),
    ],
  );
}

PendingRequestView _approval(String sessionId) {
  return PendingRequestView(
    id: 'approval-hidden',
    method: 'shell',
    kind: 'command',
    threadId: sessionId,
    turnId: 'turn-details',
    itemId: 'command-details',
    reason: 'hidden approval reason',
    summary: 'hidden approval summary',
    choices: const <String>['accept', 'reject'],
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    params: const <String, dynamic>{},
  );
}

TextSpan? _textSpanContaining(WidgetTester tester, String text) {
  for (final element in find.byType(RichText).evaluate()) {
    final widget = element.widget as RichText;
    final found = _findTextSpan(widget.text, text);
    if (found != null) {
      return found;
    }
  }

  for (final element in find.byType(SelectableText).evaluate()) {
    final widget = element.widget as SelectableText;
    final span = widget.textSpan;
    if (span == null) {
      continue;
    }
    final found = _findTextSpan(span, text);
    if (found != null) {
      return found;
    }
  }
  return null;
}

TextSpan? _findTextSpan(InlineSpan span, String text) {
  if (span is! TextSpan) {
    return null;
  }
  if (span.text == text) {
    return span;
  }
  final children = span.children;
  if (children == null) {
    return null;
  }
  for (final child in children) {
    final found = _findTextSpan(child, text);
    if (found != null) {
      return found;
    }
  }
  return null;
}
