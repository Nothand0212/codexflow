import '../models/app_models.dart';

class ChatTimelineWindow {
  const ChatTimelineWindow({
    required this.items,
    required this.hiddenCount,
    required this.totalCount,
  });

  final List<TurnItem> items;
  final int hiddenCount;
  final int totalCount;
}

class ChatTimeline {
  const ChatTimeline._();

  static ChatTimelineWindow buildWindow({
    required SessionDetail detail,
    required int visibleMessageLimit,
  }) {
    final newestItems = <TurnItem>[];
    var totalCount = 0;
    for (final turn in detail.turns.reversed) {
      for (final item in turn.items.reversed) {
        if (!isConversationItem(item)) {
          continue;
        }
        totalCount += 1;
        if (newestItems.length < visibleMessageLimit) {
          newestItems.add(item);
        }
      }
    }
    return ChatTimelineWindow(
      items: newestItems.reversed.toList(growable: false),
      hiddenCount: totalCount - newestItems.length,
      totalCount: totalCount,
    );
  }

  static bool isConversationItem(TurnItem item) {
    return item.type == 'userMessage' || item.type == 'agentMessage';
  }

  static bool isAgentProcessing({
    required SessionSummary? summary,
    required List<PendingRequestView> approvals,
  }) {
    if (summary == null || summary.isEnded) {
      return false;
    }
    if (approvals.isNotEmpty || summary.hasWaitingState) {
      return false;
    }
    return summary.lastTurnStatus == 'inProgress';
  }

  static String signature({
    required SessionDetail detail,
    required List<PendingRequestView> approvals,
  }) {
    final turnParts = detail.turns
        .map((turn) {
          return <String>[
            turn.id,
            turn.status,
            '${turn.items.length}',
            '${turn.durationMs}',
            turn.error,
            turn.items
                .map(
                  (item) => <String>[
                    item.id,
                    item.type,
                    item.status,
                    '${item.body.length}',
                    '${item.auxiliary.length}',
                    '${item.media.length}',
                    item.media
                        .map((media) => '${media.id}:${media.url}')
                        .join(';'),
                  ].join(':'),
                )
                .join(','),
          ].join(':');
        })
        .join('|');
    final approvalParts = approvals
        .map((approval) => '${approval.id}:${approval.turnId}:${approval.kind}')
        .join('|');
    return '$turnParts#$approvalParts';
  }
}
