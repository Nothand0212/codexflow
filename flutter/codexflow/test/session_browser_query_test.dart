import 'package:codexflow_flutter/domain/session_browser_query.dart';
import 'package:codexflow_flutter/domain/session_groups.dart';
import 'package:codexflow_flutter/models/app_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters loaded sessions and sorts by latest update first', () {
    final result = SessionBrowserQuery.apply(
      groups: SessionGroups(
        sessions: <SessionSummary>[
          _session('older-loaded', loaded: true, updatedAt: 10),
          _session('newer-unloaded', loaded: false, updatedAt: 30),
          _session('newer-loaded', loaded: true, updatedAt: 20),
        ],
        managed: const <SessionSummary>[],
        ended: const <SessionSummary>[],
        runtimeAvailable: const <SessionSummary>[],
        history: const <SessionSummary>[],
        pendingApprovals: const <PendingRequestView>[],
      ),
      filter: SessionBrowserFilter.loaded,
      query: '',
    );

    expect(result.totalCount, 2);
    expect(result.visibleSessions.map((session) => session.id), <String>[
      'newer-loaded',
      'older-loaded',
    ]);
  });

  test('active filter excludes ended sessions', () {
    final result = SessionBrowserQuery.apply(
      groups: SessionGroups(
        sessions: <SessionSummary>[
          _session('active', status: 'active'),
          _session('ended-active', status: 'active', ended: true),
          _session('idle', status: 'idle'),
        ],
        managed: const <SessionSummary>[],
        ended: const <SessionSummary>[],
        runtimeAvailable: const <SessionSummary>[],
        history: const <SessionSummary>[],
        pendingApprovals: const <PendingRequestView>[],
      ),
      filter: SessionBrowserFilter.active,
      query: '',
    );

    expect(result.visibleSessions.map((session) => session.id), <String>[
      'active',
    ]);
  });

  test('query matches session identity, path, branch, source, and preview', () {
    final result = SessionBrowserQuery.apply(
      groups: SessionGroups(
        sessions: <SessionSummary>[
          _session(
            'slam-session',
            cwd: '/home/lin/Projects/phad_slam',
            branch: 'feature/vio',
            preview: 'optimize tracking',
          ),
          _session(
            'codexflow-session',
            cwd: '/home/lin/Projects/codexflow_ws',
            branch: 'android-apk-notifications',
            source: 'codex',
            preview: 'notification route',
          ),
        ],
        managed: const <SessionSummary>[],
        ended: const <SessionSummary>[],
        runtimeAvailable: const <SessionSummary>[],
        history: const <SessionSummary>[],
        pendingApprovals: const <PendingRequestView>[],
      ),
      filter: SessionBrowserFilter.all,
      query: 'apk-notifications',
    );

    expect(result.visibleSessions.map((session) => session.id), <String>[
      'codexflow-session',
    ]);
  });
}

SessionSummary _session(
  String id, {
  bool loaded = true,
  int updatedAt = 1,
  String status = 'active',
  bool ended = false,
  String cwd = '/tmp/work',
  String branch = 'main',
  String source = 'codex',
  String preview = '',
}) {
  return SessionSummary(
    id: id,
    agentId: 'codex',
    name: '',
    preview: preview,
    cwd: cwd,
    source: source,
    status: status,
    activeFlags: const <String>[],
    loaded: loaded,
    updatedAt: updatedAt,
    createdAt: 1,
    modelProvider: 'openai',
    branch: branch,
    pendingApprovals: 0,
    lastTurnId: '',
    lastTurnStatus: '',
    agentNickname: '',
    agentRole: '',
    lifecycleStage: 'managed',
    historyAvailable: true,
    runtimeAvailable: true,
    runtimeAttachMode: '',
    resumeAvailable: true,
    resumeBlockedReason: '',
    ended: ended,
    userInitiated: true,
  );
}
