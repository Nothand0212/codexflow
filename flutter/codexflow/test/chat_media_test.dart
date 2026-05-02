import 'package:codexflow_flutter/domain/chat_media.dart';
import 'package:codexflow_flutter/models/app_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMedia', () {
    test('resolves relative media URLs against the app base URL', () {
      final uri = ChatMedia.resolveMediaUri(
        baseUrl: 'http://codexflow.local:4318/root/',
        url: '/api/v1/sessions/session-1/media/media-1',
      );

      expect(
        uri.toString(),
        'http://codexflow.local:4318/api/v1/sessions/session-1/media/media-1',
      );
    });

    test('keeps absolute media URLs unchanged', () {
      final uri = ChatMedia.resolveMediaUri(
        baseUrl: 'http://codexflow.local:4318',
        url: 'https://cdn.example.test/session-1/media-1.png',
      );

      expect(uri.toString(), 'https://cdn.example.test/session-1/media-1.png');
    });

    test('returns a safe fallback URI for malformed base URLs', () {
      final uri = ChatMedia.resolveMediaUri(
        baseUrl: '://bad-url',
        url: '/api/v1/sessions/session-1/media/media-1',
      );

      expect(uri.toString(), 'http://127.0.0.1/invalid-media-url');
    });

    test('only exposes explicit image media as displayable thumbnails', () {
      final images =
          ChatMedia.displayableImageAttachments(<ChatMediaAttachment>[
            _media(
              id: 'image-kind',
              kind: 'image',
              mimeType: 'application/octet-stream',
            ),
            _media(id: 'image-mime', kind: 'file', mimeType: 'image/png'),
            _media(id: 'video', kind: 'video', mimeType: 'video/mp4'),
            _media(id: 'file', kind: 'file', mimeType: 'application/pdf'),
          ]);

      expect(images.map((item) => item.id), <String>[
        'image-kind',
        'image-mime',
      ]);
    });
  });
}

ChatMediaAttachment _media({
  required String id,
  required String kind,
  required String mimeType,
}) {
  return ChatMediaAttachment(
    id: id,
    kind: kind,
    name: '$id.bin',
    mimeType: mimeType,
    url: '/api/v1/sessions/session-1/media/$id',
    size: 100,
    width: 100,
    height: 100,
  );
}
