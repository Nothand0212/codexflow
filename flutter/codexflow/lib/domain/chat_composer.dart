import 'dart:typed_data';

class ChatComposerAttachment {
  const ChatComposerAttachment({
    required this.id,
    required this.uploadId,
    required this.name,
    required this.bytes,
  });

  final String id;
  final String uploadId;
  final String name;
  final Uint8List bytes;
}

class PendingChatComposerMessage {
  const PendingChatComposerMessage({
    required this.body,
    required this.attachments,
  });

  final String body;
  final List<ChatComposerAttachment> attachments;
}

class ChatComposerSubmitAttempt {
  const ChatComposerSubmitAttempt({
    required this.prompt,
    required this.attachments,
    required this.pendingMessage,
  });

  final String prompt;
  final List<ChatComposerAttachment> attachments;
  final PendingChatComposerMessage pendingMessage;

  List<String> get imageUploadIds => attachments
      .map((item) => item.uploadId.trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
}

class ChatComposer {
  const ChatComposer._();

  static bool canSubmit({
    required String prompt,
    required List<ChatComposerAttachment> attachments,
    required bool isSubmitting,
  }) {
    if (isSubmitting) {
      return false;
    }
    return prompt.trim().isNotEmpty || attachments.isNotEmpty;
  }

  static ChatComposerSubmitAttempt? beginSubmit({
    required String prompt,
    required List<ChatComposerAttachment> attachments,
    required bool isSubmitting,
  }) {
    if (!canSubmit(
      prompt: prompt,
      attachments: attachments,
      isSubmitting: isSubmitting,
    )) {
      return null;
    }

    final trimmedPrompt = prompt.trim();
    final attachmentSnapshot = List<ChatComposerAttachment>.unmodifiable(
      attachments,
    );
    return ChatComposerSubmitAttempt(
      prompt: trimmedPrompt,
      attachments: attachmentSnapshot,
      pendingMessage: PendingChatComposerMessage(
        body: trimmedPrompt,
        attachments: attachmentSnapshot,
      ),
    );
  }
}
