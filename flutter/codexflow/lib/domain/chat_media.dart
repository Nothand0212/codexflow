import '../models/app_models.dart';

class ChatMedia {
  const ChatMedia._();

  static Uri resolveMediaUri({required String baseUrl, required String url}) {
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }

    final base = Uri.tryParse(baseUrl);
    if (base != null && base.hasScheme && parsed != null) {
      return base.resolveUri(parsed);
    }

    return Uri(scheme: 'http', host: '127.0.0.1', path: '/invalid-media-url');
  }

  static List<ChatMediaAttachment> displayableImageAttachments(
    Iterable<ChatMediaAttachment> media,
  ) {
    return media.where((item) => item.isImage).toList(growable: false);
  }
}
