import 'package:codexflow_flutter/models/app_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses session detail page metadata', () {
    final detail = SessionDetail.fromJson(<String, dynamic>{
      'summary': _summaryJson(),
      'turns': <Map<String, dynamic>>[_turnJson('turn-2')],
      'page': <String, dynamic>{
        'turnOffset': 0,
        'turnLimit': 1,
        'totalTurns': 3,
        'hasMoreBefore': true,
      },
    });

    expect(detail.page.turnOffset, 0);
    expect(detail.page.turnLimit, 1);
    expect(detail.page.totalTurns, 3);
    expect(detail.page.hasMoreBefore, isTrue);
  });

  test('merges earlier session detail pages before the current page', () {
    final current = SessionDetail.fromJson(<String, dynamic>{
      'summary': _summaryJson(),
      'turns': <Map<String, dynamic>>[_turnJson('turn-2')],
      'page': <String, dynamic>{
        'turnOffset': 0,
        'turnLimit': 1,
        'totalTurns': 3,
        'hasMoreBefore': true,
      },
    });
    final earlier = SessionDetail.fromJson(<String, dynamic>{
      'summary': _summaryJson(),
      'turns': <Map<String, dynamic>>[_turnJson('turn-0'), _turnJson('turn-1')],
      'page': <String, dynamic>{
        'turnOffset': 1,
        'turnLimit': 2,
        'totalTurns': 3,
        'hasMoreBefore': false,
      },
    });

    final merged = current.mergeEarlier(earlier);

    expect(merged.turns.map((turn) => turn.id), <String>[
      'turn-0',
      'turn-1',
      'turn-2',
    ]);
    expect(merged.page.totalTurns, 3);
    expect(merged.page.hasMoreBefore, isFalse);
  });

  test('parses media attachments on turn items', () {
    final detail = SessionDetail.fromJson(<String, dynamic>{
      'summary': _summaryJson(),
      'turns': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'turn-media',
          'status': 'completed',
          'startedAt': 1,
          'completedAt': 2,
          'durationMs': 1000,
          'error': '',
          'diff': '',
          'planExplanation': '',
          'plan': <Map<String, dynamic>>[],
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'user-media',
              'type': 'userMessage',
              'body': 'screenshot attached',
              'media': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'media-1',
                  'kind': 'image',
                  'name': 'screen.png',
                  'mimeType': 'image/png',
                  'url': '/api/v1/sessions/session-paged/media/media-1',
                  'size': 100,
                  'width': 640,
                  'height': 360,
                },
              ],
            },
          ],
        },
      ],
      'page': <String, dynamic>{
        'turnOffset': 0,
        'turnLimit': 1,
        'totalTurns': 1,
        'hasMoreBefore': false,
      },
    });

    final media = detail.turns.single.items.single.media;
    expect(media, hasLength(1));
    expect(media.single.name, 'screen.png');
    expect(media.single.url, '/api/v1/sessions/session-paged/media/media-1');
    expect(media.single.width, 640);
  });
}

Map<String, dynamic> _summaryJson() {
  return <String, dynamic>{
    'id': 'session-paged',
    'agentId': 'codex',
    'name': 'Paged',
    'preview': '',
    'cwd': '/tmp/paged',
    'source': 'codex',
    'status': 'active',
    'activeFlags': <String>[],
    'loaded': true,
    'updatedAt': 1,
    'createdAt': 1,
    'modelProvider': 'openai',
    'branch': 'main',
    'pendingApprovals': 0,
    'lastTurnId': 'turn-2',
    'lastTurnStatus': 'completed',
    'agentNickname': '',
    'agentRole': '',
    'lifecycleStage': 'managed',
    'historyAvailable': true,
    'runtimeAvailable': true,
    'runtimeAttachMode': 'managed',
    'resumeAvailable': true,
    'resumeBlockedReason': '',
    'ended': false,
  };
}

Map<String, dynamic> _turnJson(String id) {
  return <String, dynamic>{
    'id': id,
    'status': 'completed',
    'startedAt': 1,
    'completedAt': 2,
    'durationMs': 1000,
    'error': '',
    'diff': '',
    'planExplanation': '',
    'plan': <Map<String, dynamic>>[],
    'items': <Map<String, dynamic>>[],
  };
}
