import 'package:codexflow_flutter/domain/chat_timeline.dart';
import 'package:codexflow_flutter/models/app_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'window keeps newest conversation items and filters execution details',
    () {
      final detail = SessionDetail(
        summary: _summary(),
        turns: <TurnDetail>[
          _turn('turn-1', <TurnItem>[
            _item('user-1', 'userMessage', 'first user'),
            _item('reasoning-1', 'reasoning', 'private reasoning'),
            _item('agent-1', 'agentMessage', 'first agent'),
          ]),
          _turn('turn-2', <TurnItem>[
            _item('command-1', 'commandExecution', 'echo hidden'),
          ]),
          _turn('turn-3', <TurnItem>[
            _item('user-3', 'userMessage', 'latest user'),
            _item('agent-3', 'agentMessage', 'latest agent'),
          ]),
        ],
      );

      final window = ChatTimeline.buildWindow(
        detail: detail,
        visibleMessageLimit: 3,
      );

      expect(window.items.map((item) => item.id), <String>[
        'agent-1',
        'user-3',
        'agent-3',
      ]);
      expect(window.hiddenCount, 1);
      expect(window.totalCount, 4);
    },
  );

  test('signature changes when approvals or media attachments change', () {
    final detail = SessionDetail(
      summary: _summary(),
      turns: <TurnDetail>[
        _turn('turn-1', <TurnItem>[_item('agent-1', 'agentMessage', 'reply')]),
      ],
    );
    final withMedia = SessionDetail(
      summary: _summary(),
      turns: <TurnDetail>[
        _turn('turn-1', <TurnItem>[
          _item(
            'agent-1',
            'agentMessage',
            'reply',
            media: <ChatMediaAttachment>[
              ChatMediaAttachment(
                id: 'media-1',
                kind: 'image',
                name: 'screen.png',
                mimeType: 'image/png',
                url: '/api/v1/sessions/session-timeline/media/media-1',
                size: 42,
                width: 640,
                height: 360,
              ),
            ],
          ),
        ]),
      ],
    );

    final first = ChatTimeline.signature(
      detail: detail,
      approvals: const <PendingRequestView>[],
    );
    final second = ChatTimeline.signature(
      detail: withMedia,
      approvals: const <PendingRequestView>[],
    );
    final third = ChatTimeline.signature(
      detail: withMedia,
      approvals: <PendingRequestView>[_approval()],
    );

    expect(first, isNot(second));
    expect(second, isNot(third));
  });

  test('agent processing excludes ended sessions and manual action states', () {
    expect(
      ChatTimeline.isAgentProcessing(
        summary: _summary(lastTurnStatus: 'inProgress'),
        approvals: const <PendingRequestView>[],
      ),
      isTrue,
    );
    expect(
      ChatTimeline.isAgentProcessing(
        summary: _summary(
          lastTurnStatus: 'inProgress',
          activeFlags: const <String>['waitingOnApproval'],
        ),
        approvals: const <PendingRequestView>[],
      ),
      isFalse,
    );
    expect(
      ChatTimeline.isAgentProcessing(
        summary: _summary(lastTurnStatus: 'inProgress'),
        approvals: <PendingRequestView>[_approval()],
      ),
      isFalse,
    );
    expect(
      ChatTimeline.isAgentProcessing(
        summary: _summary(lastTurnStatus: 'inProgress', ended: true),
        approvals: const <PendingRequestView>[],
      ),
      isFalse,
    );
  });
}

SessionSummary _summary({
  String lastTurnStatus = 'completed',
  List<String> activeFlags = const <String>[],
  bool ended = false,
}) {
  return SessionSummary(
    id: 'session-timeline',
    agentId: 'codex',
    name: 'Timeline',
    preview: '',
    cwd: '/tmp/timeline',
    source: 'codex',
    status: 'active',
    activeFlags: activeFlags,
    loaded: true,
    updatedAt: 1,
    createdAt: 1,
    modelProvider: 'openai',
    branch: 'main',
    pendingApprovals: 0,
    lastTurnId: 'turn-1',
    lastTurnStatus: lastTurnStatus,
    agentNickname: '',
    agentRole: '',
    lifecycleStage: 'managed',
    historyAvailable: true,
    runtimeAvailable: true,
    runtimeAttachMode: 'managed',
    resumeAvailable: true,
    resumeBlockedReason: '',
    ended: ended,
    userInitiated: true,
  );
}

TurnDetail _turn(String id, List<TurnItem> items) {
  return TurnDetail(
    id: id,
    status: 'completed',
    startedAt: 1,
    completedAt: 2,
    durationMs: 1000,
    error: '',
    diff: '',
    planExplanation: '',
    plan: const <PlanStep>[],
    items: items,
  );
}

TurnItem _item(
  String id,
  String type,
  String body, {
  List<ChatMediaAttachment> media = const <ChatMediaAttachment>[],
}) {
  return TurnItem(
    id: id,
    type: type,
    title: type,
    body: body,
    status: '',
    auxiliary: '',
    metadata: const <String, String>{},
    media: media,
  );
}

PendingRequestView _approval() {
  return PendingRequestView(
    id: 'approval-1',
    method: 'item/commandExecution/requestApproval',
    kind: 'command',
    threadId: 'session-timeline',
    turnId: 'turn-1',
    itemId: 'command-1',
    reason: '',
    summary: 'Run command',
    choices: const <String>['accept', 'reject'],
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    params: const <String, dynamic>{},
  );
}
