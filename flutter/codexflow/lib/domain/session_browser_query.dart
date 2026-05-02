import '../models/app_models.dart';
import 'session_groups.dart';

enum SessionBrowserFilter { all, loaded, active }

class SessionBrowserQueryResult {
  const SessionBrowserQueryResult({
    required this.visibleSessions,
    required this.totalCount,
  });

  final List<SessionSummary> visibleSessions;
  final int totalCount;
}

class SessionBrowserQuery {
  const SessionBrowserQuery._();

  static SessionBrowserQueryResult apply({
    required SessionGroups groups,
    required SessionBrowserFilter filter,
    required String query,
  }) {
    final sessions = _sortedSessions(_sessionsForFilter(groups, filter));
    final normalizedQuery = query.trim().toLowerCase();
    final visibleSessions = normalizedQuery.isEmpty
        ? sessions
        : sessions
              .where((session) => _matchesQuery(session, normalizedQuery))
              .toList(growable: false);
    return SessionBrowserQueryResult(
      visibleSessions: visibleSessions,
      totalCount: sessions.length,
    );
  }

  static List<SessionSummary> _sessionsForFilter(
    SessionGroups groups,
    SessionBrowserFilter filter,
  ) {
    switch (filter) {
      case SessionBrowserFilter.loaded:
        return groups.sessions.where((session) => session.loaded).toList();
      case SessionBrowserFilter.active:
        return groups.sessions
            .where((session) => session.status == 'active' && !session.isEnded)
            .toList();
      case SessionBrowserFilter.all:
        return groups.sessions;
    }
  }

  static List<SessionSummary> _sortedSessions(List<SessionSummary> sessions) {
    final sorted = <SessionSummary>[...sessions];
    sorted.sort((left, right) {
      if (left.updatedAt == right.updatedAt) {
        return left.id.compareTo(right.id);
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return sorted;
  }

  static bool _matchesQuery(SessionSummary session, String query) {
    final haystack = <String>[
      session.displayName,
      session.preview,
      session.cwd,
      session.branch,
      session.source,
      session.status,
      session.lifecycleStage,
      session.modelProvider,
      session.id,
    ].join('\n').toLowerCase();
    return haystack.contains(query);
  }
}
