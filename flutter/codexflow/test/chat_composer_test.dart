import 'dart:typed_data';

import 'package:codexflow_flutter/domain/chat_composer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('beginSubmit rejects empty drafts and duplicate submissions', () {
    expect(
      ChatComposer.beginSubmit(
        prompt: '   ',
        attachments: const <ChatComposerAttachment>[],
        isSubmitting: false,
      ),
      isNull,
    );
    expect(
      ChatComposer.beginSubmit(
        prompt: 'hello',
        attachments: const <ChatComposerAttachment>[],
        isSubmitting: true,
      ),
      isNull,
    );
  });

  test('beginSubmit snapshots prompt and image upload ids for submission', () {
    final attachments = <ChatComposerAttachment>[
      ChatComposerAttachment(
        id: 'local-1',
        uploadId: 'upload-1',
        name: 'screen.png',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    ];

    final attempt = ChatComposer.beginSubmit(
      prompt: '  inspect screenshot  ',
      attachments: attachments,
      isSubmitting: false,
    );

    expect(attempt, isNotNull);
    expect(attempt!.prompt, 'inspect screenshot');
    expect(attempt.imageUploadIds, <String>['upload-1']);
    expect(attempt.pendingMessage.body, 'inspect screenshot');
    expect(attempt.pendingMessage.attachments.single.name, 'screen.png');

    attachments.clear();
    expect(attempt.attachments, hasLength(1));
    expect(attempt.pendingMessage.attachments, hasLength(1));
  });

  test('canSubmit allows attachments without text', () {
    expect(
      ChatComposer.canSubmit(
        prompt: '',
        attachments: <ChatComposerAttachment>[
          ChatComposerAttachment(
            id: 'local-1',
            uploadId: 'upload-1',
            name: 'screen.png',
            bytes: Uint8List(0),
          ),
        ],
        isSubmitting: false,
      ),
      isTrue,
    );
  });
}
