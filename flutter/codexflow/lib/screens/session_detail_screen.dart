import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/app_models.dart';
import '../state/app_model.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import 'approval_screen.dart';

const int _initialTimelineMessageLimit = 80;
const int _timelineMessagePageSize = 80;

Uri resolveMediaUri(String baseUrl, String url) {
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

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late final TextEditingController _promptController;
  late final ScrollController _scrollController;
  Timer? _timer;
  int _tick = 0;
  bool _isUploadingImage = false;
  bool _isLoadingEarlierMessages = false;
  String _lastTimelineSignature = '';
  int _visibleTimelineMessageLimit = _initialTimelineMessageLimit;
  final ImagePicker _imagePicker = ImagePicker();
  final List<_ComposerAttachment> _attachments = <_ComposerAttachment>[];

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshSessionPage(refreshSkills: true));
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pollIfNeeded(),
      );
    });
  }

  @override
  void didUpdateWidget(covariant SessionDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _lastTimelineSignature = '';
      _visibleTimelineMessageLimit = _initialTimelineMessageLimit;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  SessionDetail? _detail(AppModel model) =>
      model.sessionDetails[widget.sessionId];

  SessionSummary? _summary(AppModel model) {
    final detail = _detail(model);
    if (detail != null) {
      return detail.summary;
    }
    return model.dashboard.sessions.cast<SessionSummary?>().firstWhere(
      (session) => session?.id == widget.sessionId,
      orElse: () => null,
    );
  }

  List<PendingRequestView> _sessionApprovals(AppModel model) =>
      model.approvalsFor(widget.sessionId);

  Future<void> _pollIfNeeded() async {
    if (!mounted) {
      return;
    }
    final model = context.read<AppModel>();
    final summary = _summary(model);
    final approvals = _sessionApprovals(model);
    if (summary == null) {
      await _refreshSessionPage();
      return;
    }
    if (summary.isEnded) {
      return;
    }
    if (approvals.isNotEmpty ||
        summary.hasWaitingState ||
        summary.lastTurnStatus == 'inProgress') {
      await _refreshSessionPage();
      return;
    }
    if (summary.loaded) {
      _tick += 1;
      if (_tick % 2 == 0) {
        await _refreshSessionPage();
      }
    }
  }

  Future<void> _refreshSessionPage({bool refreshSkills = false}) async {
    final model = context.read<AppModel>();
    await model.refreshDashboard(refreshSkills: refreshSkills);
    await model.loadSession(widget.sessionId);
  }

  void _scheduleScrollToBottom(String signature) {
    if (_lastTimelineSignature == signature) {
      return;
    }
    _lastTimelineSignature = signature;
    if (_isLoadingEarlierMessages) {
      return;
    }
    _scrollToBottomWhenReady();
  }

  void _scrollToBottomWhenReady({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_scrollController.hasClients) {
        if (attempt < 8) {
          _scrollToBottomWhenReady(attempt: attempt + 1);
        }
        return;
      }

      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      if ((position.pixels - target).abs() > 1) {
        _scrollController.jumpTo(target);
      }

      // Markdown layout and restored images can increase maxScrollExtent over
      // the next few frames. Keep pinning initial loads to the latest message
      // until the layout settles.
      if (attempt < 4) {
        _scrollToBottomWhenReady(attempt: attempt + 1);
      }
    });
  }

  Future<void> _loadEarlierTimelineMessages({
    required bool fetchEarlierFromServer,
  }) async {
    if (_isLoadingEarlierMessages) {
      return;
    }
    setState(() {
      _isLoadingEarlierMessages = fetchEarlierFromServer;
      _visibleTimelineMessageLimit += _timelineMessagePageSize;
    });
    if (!fetchEarlierFromServer) {
      return;
    }
    try {
      await context.read<AppModel>().loadEarlierSessionTurns(widget.sessionId);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEarlierMessages = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    if (_isUploadingImage) {
      return;
    }

    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (image == null) {
      return;
    }

    final bytes = await image.readAsBytes();
    if (!mounted) {
      return;
    }

    setState(() {
      _isUploadingImage = true;
    });
    try {
      final model = context.read<AppModel>();
      final uploaded = await model.uploadImage(
        bytes: bytes,
        fileName: image.name.isEmpty ? 'attachment.jpg' : image.name,
      );
      if (!mounted || uploaded == null) {
        return;
      }
      setState(() {
        _attachments.add(
          _ComposerAttachment(
            id: '${DateTime.now().microsecondsSinceEpoch}-${uploaded.id}',
            uploadId: uploaded.id,
            name: uploaded.name,
            bytes: bytes,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final detail = _detail(model);
    final summary = _summary(model);
    final capabilities = summary == null
        ? AgentCapabilities(
            supportsInterruptTurn: true,
            supportsApprovals: true,
            supportsArchive: true,
            supportsResume: true,
            supportsHistoryImport: false,
          )
        : model.capabilitiesForSession(summary);
    final supportsApprovals = capabilities.supportsApprovals;
    final supportsInterruptTurn = capabilities.supportsInterruptTurn;
    final supportsResume = summary == null
        ? capabilities.supportsResume
        : model.canResumeSession(summary);
    final sessionApprovals = supportsApprovals
        ? _sessionApprovals(model)
        : <PendingRequestView>[];
    final agentProcessing = _isAgentProcessing(summary, sessionApprovals);
    if (detail != null) {
      _scheduleScrollToBottom(_timelineSignature(detail, sessionApprovals));
    }

    return Scaffold(
      backgroundColor: Palette.canvas,
      appBar: AppBar(
        title: Text(
          summary?.displayName ?? '会话详情',
          style: roundedTextStyle(size: 17, weight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: PageScaffold(
        child: Column(
          children: <Widget>[
            if (model.operationNotice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (model.operationNoticeIsError
                                ? Palette.danger
                                : Palette.success)
                            .appOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    model.operationNotice,
                    style: roundedTextStyle(
                      size: 12,
                      weight: FontWeight.w500,
                      color: model.operationNoticeIsError
                          ? Palette.danger
                          : Palette.success,
                    ),
                  ),
                ),
              ),
            if (summary != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _ChatSessionHeader(summary: summary),
              ),
            Expanded(
              child: RefreshIndicator(
                color: Palette.accent,
                onRefresh: () => _refreshSessionPage(refreshSkills: true),
                child: SelectionArea(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: detail == null
                        ? <Widget>[_LoadingTimelineCard()]
                        : _timelineChildren(
                            detail,
                            _emptyStateMessage(summary),
                            agentProcessing,
                          ),
                  ),
                ),
              ),
            ),
            if (summary != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: summary.isEnded || !summary.loaded
                    ? _TakeoverCard(
                        summary: summary,
                        supportsResume: supportsResume,
                        onPressed: () async {
                          await model.resumeSession(summary);
                          await _refreshSessionPage();
                        },
                      )
                    : _ComposerCard(
                        summary: summary,
                        skills: model.skills,
                        promptController: _promptController,
                        attachments: _attachments,
                        isUploadingImage: _isUploadingImage,
                        onPickImage: _pickAndUploadImage,
                        onRemoveAttachment: (String id) {
                          setState(() {
                            _attachments.removeWhere((item) => item.id == id);
                          });
                        },
                        onSubmit: () async {
                          final sent = await model.submitPrompt(
                            session: summary,
                            prompt: _promptController.text.trim(),
                            imageUploadIds: _attachments
                                .map((item) => item.uploadId)
                                .toList(),
                          );
                          if (sent) {
                            _promptController.clear();
                            setState(() {
                              _attachments.clear();
                            });
                          }
                        },
                        supportsInterruptTurn: supportsInterruptTurn,
                        onEnd: () async {
                          await model.endSession(summary);
                          await _refreshSessionPage();
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _timelineChildren(
    SessionDetail detail,
    String emptyMessage,
    bool agentProcessing,
  ) {
    final window = _timelineWindow(detail);
    if (window.totalCount == 0) {
      return <Widget>[
        if (agentProcessing)
          const _AgentProcessingBubble()
        else
          PanelCard(
            compact: true,
            child: Text(
              emptyMessage,
              style: roundedTextStyle(
                size: 13,
                weight: FontWeight.w500,
                color: Palette.mutedInk,
              ),
            ),
          ),
      ];
    }

    final children = <Widget>[
      if (window.hiddenCount > 0 || detail.page.hasMoreBefore)
        _LoadEarlierMessagesButton(
          hiddenCount: window.hiddenCount,
          pageSize: _timelineMessagePageSize,
          loading: _isLoadingEarlierMessages,
          serverHasMoreBefore: detail.page.hasMoreBefore,
          onPressed: () => _loadEarlierTimelineMessages(
            fetchEarlierFromServer: window.hiddenCount == 0,
          ),
        ),
      ...window.items.map((item) => _TimelineItem(item: item)),
      if (agentProcessing) const _AgentProcessingBubble(),
    ];

    return children
        .map(
          (child) =>
              Padding(padding: const EdgeInsets.only(bottom: 10), child: child),
        )
        .toList();
  }

  _TimelineWindow _timelineWindow(SessionDetail detail) {
    final newestItems = <TurnItem>[];
    var totalCount = 0;
    for (final turn in detail.turns.reversed) {
      for (final item in turn.items.reversed) {
        if (!_isConversationItem(item)) {
          continue;
        }
        totalCount += 1;
        if (newestItems.length < _visibleTimelineMessageLimit) {
          newestItems.add(item);
        }
      }
    }
    return _TimelineWindow(
      items: newestItems.reversed.toList(growable: false),
      hiddenCount: totalCount - newestItems.length,
      totalCount: totalCount,
    );
  }

  bool _isConversationItem(TurnItem item) {
    return item.type == 'userMessage' || item.type == 'agentMessage';
  }

  bool _isAgentProcessing(
    SessionSummary? summary,
    List<PendingRequestView> approvals,
  ) {
    if (summary == null || summary.isEnded) {
      return false;
    }
    if (approvals.isNotEmpty || summary.hasWaitingState) {
      return false;
    }
    return summary.lastTurnStatus == 'inProgress';
  }

  String _timelineSignature(
    SessionDetail detail,
    List<PendingRequestView> approvals,
  ) {
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

  String _emptyStateMessage(SessionSummary? summary) {
    if (summary != null && summary.isEnded) {
      return '这个会话已经结束。当前没有更多 turn 可展示；如果要继续执行，先重新接管。';
    }
    if (summary?.loaded == true) {
      return '这个会话还没有 turn。你可以直接在上面输入，开始第一轮。';
    }
    return '这个会话当前没有可展示的 turn 历史。先接管后，才能继续在 CodexFlow 里执行。';
  }
}

class _TimelineWindow {
  const _TimelineWindow({
    required this.items,
    required this.hiddenCount,
    required this.totalCount,
  });

  final List<TurnItem> items;
  final int hiddenCount;
  final int totalCount;
}

class _LoadEarlierMessagesButton extends StatelessWidget {
  const _LoadEarlierMessagesButton({
    required this.hiddenCount,
    required this.pageSize,
    required this.loading,
    required this.serverHasMoreBefore,
    required this.onPressed,
  });

  final int hiddenCount;
  final int pageSize;
  final bool loading;
  final bool serverHasMoreBefore;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final count = hiddenCount < pageSize ? hiddenCount : pageSize;
    final subtitle = hiddenCount > 0
        ? '还有 $hiddenCount 条，先加载 $count 条'
        : (serverHasMoreBefore ? '从电脑端按需加载' : '');
    return Center(
      child: TextButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
        label: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              loading ? '正在加载…' : '加载更早消息',
              style: roundedTextStyle(size: 12, weight: FontWeight.w700),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: roundedTextStyle(
                  size: 10,
                  weight: FontWeight.w600,
                  color: Palette.softBlue.appOpacity(0.72),
                ),
              ),
          ],
        ),
        style: TextButton.styleFrom(
          foregroundColor: Palette.softBlue,
          backgroundColor: Palette.softBlue.appOpacity(0.10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: Palette.softBlue.appOpacity(0.16)),
          ),
        ),
      ),
    );
  }
}

class _ChatSessionHeader extends StatelessWidget {
  const _ChatSessionHeader({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.panelStrong,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: <Widget>[
          StatusPill(
            status: summary.status,
            waiting: summary.hasWaitingState,
            ended: summary.isEnded,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  summary.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: roundedTextStyle(size: 14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  summary.cwd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: roundedTextStyle(
                    size: 11,
                    weight: FontWeight.w500,
                    color: Palette.mutedInk,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingTimelineCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PanelCard(
      compact: true,
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Palette.accent,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '正在加载会话详情…',
            style: roundedTextStyle(
              size: 13,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    switch (item.type) {
      case 'userMessage':
        return _ChatBubble(
          body: item.body,
          outgoing: true,
          title: '你',
          media: item.media,
        );
      case 'agentMessage':
        return _ChatBubble(
          body: item.body,
          outgoing: false,
          title: 'Codex',
          markdown: true,
          media: item.media,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.body,
    required this.outgoing,
    required this.title,
    required this.media,
    this.markdown = false,
  });

  final String body;
  final bool outgoing;
  final String title;
  final List<ChatMediaAttachment> media;
  final bool markdown;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.78;
    final background = outgoing ? Palette.softBlue : Palette.panelStrong;
    final foreground = outgoing ? Colors.white : Palette.ink;
    final hasBody = body.trim().isNotEmpty;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(outgoing ? 16 : 4),
      bottomRight: Radius.circular(outgoing ? 4 : 16),
    );

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: borderRadius,
            border: outgoing ? null : Border.all(color: Palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: roundedTextStyle(
                  size: 11,
                  weight: FontWeight.w700,
                  color: outgoing ? Colors.white70 : Palette.mutedInk,
                ),
              ),
              if (hasBody) ...<Widget>[
                const SizedBox(height: 5),
                if (markdown && !outgoing)
                  MarkdownBodyBlock(raw: body)
                else
                  Text(
                    body,
                    style: roundedTextStyle(
                      size: 13,
                      weight: FontWeight.w500,
                      color: foreground,
                      height: 1.45,
                    ),
                  ),
              ],
              _ChatMediaStrip(media: media, hasPrecedingBody: hasBody),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMediaStrip extends StatelessWidget {
  const _ChatMediaStrip({required this.media, required this.hasPrecedingBody});

  final List<ChatMediaAttachment> media;
  final bool hasPrecedingBody;

  @override
  Widget build(BuildContext context) {
    final images = media.where((item) => item.isImage).toList(growable: false);
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }

    final baseUrl = context.read<AppModel>().baseUrlString;
    return Padding(
      padding: EdgeInsets.only(top: hasPrecedingBody ? 10 : 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: images
            .map((item) => _ChatMediaThumbnail(baseUrl: baseUrl, media: item))
            .toList(growable: false),
      ),
    );
  }
}

class _ChatMediaThumbnail extends StatelessWidget {
  const _ChatMediaThumbnail({required this.baseUrl, required this.media});

  final String baseUrl;
  final ChatMediaAttachment media;

  @override
  Widget build(BuildContext context) {
    final uri = resolveMediaUri(baseUrl, media.url);
    final aspectRatio = media.width > 0 && media.height > 0
        ? media.width / media.height
        : null;
    Widget image = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        uri.toString(),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Palette.line.appOpacity(0.28),
          alignment: Alignment.center,
          child: Icon(
            Icons.broken_image_rounded,
            color: Palette.mutedInk.appOpacity(0.72),
            size: 24,
          ),
        ),
      ),
    );
    if (aspectRatio != null) {
      image = AspectRatio(aspectRatio: aspectRatio, child: image);
    }

    return GestureDetector(
      key: ValueKey<String>('chat-media-${media.id}'),
      onTap: () => _openPreview(context, uri),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 160),
        child: image,
      ),
    );
  }

  void _openPreview(BuildContext context, Uri uri) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
          child: InteractiveViewer(
            child: Image.network(
              uri.toString(),
              key: ValueKey<String>('chat-media-preview-${media.id}'),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 320,
                height: 220,
                color: Palette.panelStrong,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_rounded,
                  color: Palette.mutedInk.appOpacity(0.72),
                  size: 32,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentProcessingBubble extends StatefulWidget {
  const _AgentProcessingBubble();

  @override
  State<_AgentProcessingBubble> createState() => _AgentProcessingBubbleState();
}

class _AgentProcessingBubbleState extends State<_AgentProcessingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.78;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Palette.panelStrong,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(color: Palette.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Palette.accent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Codex 正在处理',
                style: roundedTextStyle(
                  size: 12,
                  weight: FontWeight.w700,
                  color: Palette.ink,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List<Widget>.generate(3, (index) {
                      final phase = (_controller.value * 3 + index) % 3;
                      final scale = phase < 1
                          ? 0.72 + phase * 0.28
                          : (phase < 2 ? 1 - (phase - 1) * 0.28 : 0.72);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Palette.accent.appOpacity(
                                0.55 + scale * 0.35,
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TakeoverCard extends StatelessWidget {
  const _TakeoverCard({
    required this.summary,
    required this.supportsResume,
    required this.onPressed,
  });

  final SessionSummary summary;
  final bool supportsResume;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.refresh, size: 14, color: Palette.softBlue),
              const SizedBox(width: 8),
              Text(
                summary.isEnded ? '会话已结束' : '先接管，再继续',
                style: roundedTextStyle(size: 16, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _takeoverSummary(summary),
            style: roundedTextStyle(
              size: 13,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          ActionButton(
            title:
                (!summary.isEnded &&
                    summary.isClaudeSession &&
                    !summary.runtimeAvailable)
                ? '当前无 Runtime'
                : (summary.isEnded ? '重新接管会话' : 'Resume 并接管会话'),
            background: supportsResume
                ? Palette.softBlue
                : Palette.mutedInk.appOpacity(0.35),
            foreground: Colors.white,
            fontSize: 14,
            enabled: supportsResume,
            onPressed: () async => onPressed(),
          ),
        ],
      ),
    );
  }

  String _takeoverSummary(SessionSummary summary) {
    if (summary.isEnded) {
      return '这个会话已经在 CodexFlow 中结束了。历史记录仍然可看；如果你想继续发 prompt 或重新托管审批/状态刷新，先重新接管。';
    }
    if (summary.isClaudeSession &&
        summary.runtimeAvailable &&
        !summary.loaded) {
      return '已经检测到 Claude live runtime。接入后，这个页面才会开始跟踪运行状态、处理中断，并允许继续下一轮。';
    }
    if (summary.isClaudeSession &&
        summary.historyAvailable &&
        !summary.runtimeAvailable) {
      return '这是 Claude 历史导入记录。当前可以查看历史，但本机没有发现对应 live runtime。';
    }
    if (!summary.canResume && summary.resumeBlockedReason.isNotEmpty) {
      return summary.resumeBlockedReason;
    }
    if (summary.lastTurnStatus == 'inProgress') {
      return '这个会话可能仍在别处运行，但当前不在 CodexFlow 里托管。先接管后，CodexFlow 才能继续刷新状态、处理审批，并允许你继续 steer 或中断。';
    }
    return '这个会话现在只是历史记录，还没有被 CodexFlow 接管。接管后，这个页面才会出现“开始下一轮”或“继续引导当前 turn”的操作。';
  }
}

class _ComposerAttachment {
  _ComposerAttachment({
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

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.summary,
    required this.skills,
    required this.promptController,
    required this.attachments,
    required this.isUploadingImage,
    required this.onPickImage,
    required this.onRemoveAttachment,
    required this.onSubmit,
    required this.supportsInterruptTurn,
    required this.onEnd,
  });

  final SessionSummary summary;
  final List<AgentSkill> skills;
  final TextEditingController promptController;
  final List<_ComposerAttachment> attachments;
  final bool isUploadingImage;
  final Future<void> Function() onPickImage;
  final void Function(String id) onRemoveAttachment;
  final Future<void> Function() onSubmit;
  final bool supportsInterruptTurn;
  final Future<void> Function() onEnd;

  @override
  Widget build(BuildContext context) {
    final isSteering = summary.lastTurnStatus == 'inProgress';
    final canStopNow = !isSteering || supportsInterruptTurn;
    final accentTone = isSteering ? Palette.accent2 : Palette.accent;
    return ListenableBuilder(
      listenable: promptController,
      builder: (BuildContext context, Widget? child) {
        final trimmedPrompt = promptController.text.trim();
        final canSubmit = trimmedPrompt.isNotEmpty || attachments.isNotEmpty;
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: Palette.panelStrong,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Palette.line),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.08),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _ComposerToolButton(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Skills',
                    onTap: () => _showSkillsSheet(context),
                  ),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: isUploadingImage ? 0.45 : 1,
                    child: _ComposerToolButton(
                      icon: Icons.photo_rounded,
                      title: isUploadingImage ? '上传中…' : '添加图片',
                      onTap: isUploadingImage ? null : onPickImage,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (attachments.isNotEmpty)
                    Text(
                      '已选 ${attachments.length} 张',
                      style: roundedTextStyle(
                        size: 12,
                        weight: FontWeight.w600,
                        color: Palette.mutedInk,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: canStopNow
                        ? (isSteering ? '中断并结束' : '结束会话')
                        : '等待本轮结束',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      isSteering
                          ? Icons.stop_circle_rounded
                          : Icons.stop_circle_outlined,
                      color: canStopNow ? Palette.danger : Palette.mutedInk,
                    ),
                    onPressed: canStopNow
                        ? () async {
                            FocusScope.of(context).unfocus();
                            await onEnd();
                          }
                        : null,
                  ),
                ],
              ),
              if (attachments.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: attachments
                        .map(
                          (attachment) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    attachment.bytes,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: -6,
                                  top: -6,
                                  child: InkWell(
                                    onTap: () =>
                                        onRemoveAttachment(attachment.id),
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Icon(
                                      Icons.cancel,
                                      size: 20,
                                      color: Palette.danger,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: promptController,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: roundedTextStyle(
                        size: 14,
                        weight: FontWeight.w500,
                        color: Palette.ink,
                        height: 1.35,
                      ),
                      cursorColor: Palette.softBlue,
                      decoration: InputDecoration(
                        hintText: isSteering ? '继续当前 turn' : '输入消息',
                        hintStyle: roundedTextStyle(
                          size: 14,
                          weight: FontWeight.w500,
                          color: Palette.mutedInk,
                        ),
                        filled: true,
                        fillColor: Palette.shell,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: Palette.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: accentTone.appOpacity(0.45),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: canSubmit && !isUploadingImage
                        ? accentTone
                        : Palette.mutedInk.appOpacity(0.35),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canSubmit && !isUploadingImage
                          ? () async {
                              FocusScope.of(context).unfocus();
                              await onSubmit();
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(11),
                        child: Icon(
                          isSteering
                              ? Icons.alt_route_rounded
                              : Icons.arrow_upward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSkillsSheet(BuildContext context) async {
    final skill = await showModalBottomSheet<AgentSkill>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return _SkillsSheet(skills: skills);
      },
    );
    if (skill == null) {
      return;
    }
    _insertText(skill.insertText);
  }

  void _insertText(String value) {
    final selection = promptController.selection;
    final text = promptController.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final nextText = text.replaceRange(start, end, value);
    final offset = start + value.length;
    promptController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class _ComposerToolButton extends StatelessWidget {
  const _ComposerToolButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Palette.shell,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Palette.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: Palette.ink),
            const SizedBox(width: 6),
            Text(
              title,
              style: roundedTextStyle(
                size: 12,
                weight: FontWeight.w600,
                color: Palette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillsSheet extends StatefulWidget {
  const _SkillsSheet({required this.skills});

  final List<AgentSkill> skills;

  @override
  State<_SkillsSheet> createState() => _SkillsSheetState();
}

class _SkillsSheetState extends State<_SkillsSheet> {
  late final TextEditingController _queryController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController()..addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _queryController
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text.trim().toLowerCase();
    final skills = _sortedSkills(
      widget.skills,
    ).where((skill) => _matchesSkill(skill, query)).toList(growable: false);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        decoration: const BoxDecoration(
          color: Palette.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Palette.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _queryController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: roundedTextStyle(
                  size: 14,
                  weight: FontWeight.w600,
                  color: Palette.ink,
                ),
                decoration: InputDecoration(
                  hintText: '搜索 Skills',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Palette.mutedInk,
                  ),
                  filled: true,
                  fillColor: Palette.shell,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Palette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Palette.softBlue.appOpacity(0.45),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: skills.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            widget.skills.isEmpty ? '暂无可用 Skills' : '没有匹配项',
                            style: roundedTextStyle(
                              size: 13,
                              weight: FontWeight.w600,
                              color: Palette.mutedInk,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: skills.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: Palette.line.appOpacity(0.65),
                        ),
                        itemBuilder: (BuildContext context, int index) {
                          final skill = skills[index];
                          final subtitle = skill.description.isNotEmpty
                              ? skill.description
                              : skill.insertText.trim();
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Palette.softBlue,
                            ),
                            title: Text(
                              skill.name,
                              style: roundedTextStyle(
                                size: 14,
                                weight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: roundedTextStyle(
                                size: 12,
                                weight: FontWeight.w500,
                                color: Palette.mutedInk,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(skill),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<AgentSkill> _sortedSkills(List<AgentSkill> skills) {
    final sorted = <AgentSkill>[...skills];
    sorted.sort((left, right) {
      final leftName = left.name.toLowerCase();
      final rightName = right.name.toLowerCase();
      if (leftName == rightName) {
        return left.name.compareTo(right.name);
      }
      return leftName.compareTo(rightName);
    });
    return sorted;
  }

  bool _matchesSkill(AgentSkill skill, String query) {
    if (query.isEmpty) {
      return true;
    }
    return skill.name.toLowerCase().contains(query) ||
        skill.description.toLowerCase().contains(query) ||
        skill.insertText.toLowerCase().contains(query);
  }
}

class TurnCard extends StatelessWidget {
  const TurnCard({super.key, required this.turn, this.isLive = false});

  final TurnDetail turn;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: isLive
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Palette.warning.appOpacity(0.35),
                width: 1.5,
              ),
            )
          : null,
      child: PanelCard(
        compact: true,
        child: TurnCardBody(turn: turn, isLive: isLive),
      ),
    );
  }
}

class ActiveTurnCard extends StatelessWidget {
  const ActiveTurnCard({
    super.key,
    required this.turn,
    required this.approvals,
  });

  final TurnDetail turn;
  final List<PendingRequestView> approvals;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.warning.appOpacity(0.35), width: 1.5),
      ),
      child: PanelCard(
        compact: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (approvals.isNotEmpty) ...<Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.warning_rounded,
                    color: Palette.warning,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '当前 turn 待审批',
                    style: roundedTextStyle(
                      size: 14,
                      weight: FontWeight.w600,
                      color: Palette.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${approvals.length}',
                    style: roundedTextStyle(
                      size: 12,
                      weight: FontWeight.w700,
                      color: Palette.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...approvals.map(
                (approval) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ApprovalCardBody(
                    approval: approval,
                    showSessionLabel: false,
                    embedded: true,
                  ),
                ),
              ),
              Container(height: 1, color: Palette.line),
              const SizedBox(height: 12),
            ],
            TurnCardBody(turn: turn, isLive: true),
          ],
        ),
      ),
    );
  }
}

class TurnCardBody extends StatelessWidget {
  const TurnCardBody({super.key, required this.turn, required this.isLive});

  final TurnDetail turn;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final firstUserItem = turn.items.cast<TurnItem?>().firstWhere(
      (item) => item?.type == 'userMessage' && item!.body.trim().isNotEmpty,
      orElse: () => null,
    );
    final lastAgentItem = turn.items.reversed.cast<TurnItem?>().firstWhere(
      (item) => item?.type == 'agentMessage' && item!.body.trim().isNotEmpty,
      orElse: () => null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        _turnStatusLabel(turn.status),
                        style: roundedTextStyle(
                          size: 14,
                          weight: FontWeight.w600,
                          color: _statusTone(turn.status),
                        ),
                      ),
                      if (isLive) ...<Widget>[
                        const SizedBox(width: 6),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.sensors,
                              size: 12,
                              color: Palette.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '实时更新',
                              style: roundedTextStyle(
                                size: 11,
                                weight: FontWeight.w600,
                                color: Palette.warning,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    turn.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: roundedTextStyle(
                      size: 11,
                      weight: FontWeight.w500,
                      color: Palette.mutedInk,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            if (turn.durationMs > 0)
              Text(
                '${turn.durationMs ~/ 1000}s',
                style: roundedTextStyle(
                  size: 12,
                  weight: FontWeight.w600,
                  color: Palette.mutedInk,
                ),
              ),
          ],
        ),
        if (turn.error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            turn.error,
            style: roundedTextStyle(
              size: 13,
              weight: FontWeight.w500,
              color: Palette.danger,
            ),
          ),
        ],
        if (firstUserItem != null || lastAgentItem != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '本轮摘要',
            style: roundedTextStyle(size: 12, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (firstUserItem != null) ...<Widget>[
            ExcerptSummaryCard(
              title: '用户提示',
              icon: Icons.person_outline,
              tone: Palette.softBlue,
              raw: firstUserItem.body,
              head: 170,
              tail: 110,
            ),
            const SizedBox(height: 8),
          ],
          if (lastAgentItem != null)
            ExcerptSummaryCard(
              title: 'Agent 输出',
              icon: Icons.auto_awesome,
              tone: Palette.accent,
              raw: lastAgentItem.body,
              head: 210,
              tail: 140,
            ),
        ],
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              if (turn.plan.isNotEmpty) ...<Widget>[
                CapsuleTag(title: '计划', value: '${turn.plan.length} 步'),
                const SizedBox(width: 8),
              ],
              if (turn.diff.isNotEmpty) ...<Widget>[
                const CapsuleTag(title: 'Diff', value: '可查看'),
                const SizedBox(width: 8),
              ],
              if (turn.items.isNotEmpty)
                CapsuleTag(title: '时间线', value: '${turn.items.length} 项'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ActionButton(
          title: '查看详情',
          background: Palette.shell,
          foreground: Palette.ink,
          fontSize: 14,
          onPressed: () {
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => TurnDetailSheet(turn: turn),
            );
          },
        ),
      ],
    );
  }

  String _turnStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return '已完成';
      case 'failed':
        return '失败';
      case 'inProgress':
        return '运行中';
      default:
        return status;
    }
  }

  Color _statusTone(String status) {
    switch (status) {
      case 'completed':
        return Palette.success;
      case 'failed':
        return Palette.danger;
      case 'inProgress':
        return Palette.warning;
      default:
        return Palette.mutedInk;
    }
  }
}

class ExcerptSummaryCard extends StatelessWidget {
  const ExcerptSummaryCard({
    super.key,
    required this.title,
    required this.icon,
    required this.tone,
    required this.raw,
    required this.head,
    required this.tail,
  });

  final String title;
  final IconData icon;
  final Color tone;
  final String raw;
  final int head;
  final int tail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.appOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.appOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 12, color: tone),
              const SizedBox(width: 6),
              Text(
                title,
                style: roundedTextStyle(
                  size: 11,
                  weight: FontWeight.w600,
                  color: tone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          HeadTailExcerptBlock(
            raw: _normalizeExcerptText(raw),
            head: head,
            tail: tail,
            style: roundedTextStyle(
              size: 12,
              weight: FontWeight.w500,
              color: Palette.ink,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizeExcerptText(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    return '';
  }

  // Keep visible meaning but remove Markdown syntax noise for card excerpts.
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'^```[^\n]*\n?([\s\S]*?)\n?```$', multiLine: true),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(RegExp(r'```[\s\S]*?```'), (match) {
    final block = match.group(0) ?? '';
    return block
        .replaceAll(RegExp(r'^```[^\n]*\n?'), '')
        .replaceAll(RegExp(r'\n?```$'), '');
  });
  text = text.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAll(
    RegExp(r'^\s{0,3}(#{1,6}\s+|>\s+|[-*+]\s+|\d+\.\s+)', multiLine: true),
    '',
  );
  text = text.replaceAll(RegExp(r'^\s*([-*_]\s*){3,}$', multiLine: true), '');
  text = text.replaceAll(RegExp(r'\\([\\`*_{}\[\]()#+\-.!|>~])'), r'$1');

  // Repeatedly strip paired inline markers so nested combinations are handled.
  for (var i = 0; i < 4; i++) {
    final before = text;
    text = text.replaceAllMapped(
      RegExp(r'\*\*\*([^*\n]+)\*\*\*'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'___([^_\n]+)___'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\*\*([^*\n]+)\*\*'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'__([^_\n]+)__'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'~~([^~\n]+)~~'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\*([^*\n]+)\*'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'_([^_\n]+)_'),
      (match) => match.group(1) ?? '',
    );
    if (text == before) {
      break;
    }
  }

  text = text.replaceAll(RegExp(r'(^|\s)[*_~]+'), ' ');
  text = text.replaceAll(RegExp(r'[*_~]+(?=\s|$)'), '');
  text = text.replaceAll('|', ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

  return text;
}

class TurnDetailSheet extends StatefulWidget {
  const TurnDetailSheet({super.key, required this.turn});

  final TurnDetail turn;

  @override
  State<TurnDetailSheet> createState() => _TurnDetailSheetState();
}

class _TurnDetailSheetState extends State<TurnDetailSheet> {
  bool showPlan = true;
  bool showDiff = false;
  bool showTimeline = false;

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      minChildSize: 0.7,
      maxChildSize: 0.97,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Palette.canvas,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Palette.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    title: Text(
                      'Turn 详情',
                      style: roundedTextStyle(
                        size: 17,
                        weight: FontWeight.w600,
                      ),
                    ),
                    centerTitle: true,
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          '关闭',
                          style: roundedTextStyle(
                            size: 13,
                            weight: FontWeight.w600,
                            color: Palette.softBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  body: PageScaffold(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      children: <Widget>[
                        PanelCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Text(
                                    _turnStatusLabel(turn.status),
                                    style: roundedTextStyle(
                                      size: 16,
                                      weight: FontWeight.w600,
                                      color: _statusTone(turn.status),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (turn.durationMs > 0)
                                    Text(
                                      '${turn.durationMs ~/ 1000}s',
                                      style: roundedTextStyle(
                                        size: 12,
                                        weight: FontWeight.w600,
                                        color: Palette.mutedInk,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                turn.id,
                                style: roundedTextStyle(
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: Palette.mutedInk,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (turn.planExplanation.isNotEmpty ||
                            turn.plan.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          DisclosureSection(
                            title: '计划',
                            isExpanded: showPlan,
                            onToggle: () =>
                                setState(() => showPlan = !showPlan),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (turn
                                    .planExplanation
                                    .isNotEmpty) ...<Widget>[
                                  Text(
                                    turn.planExplanation,
                                    style: roundedTextStyle(
                                      size: 13,
                                      weight: FontWeight.w500,
                                      color: Palette.mutedInk,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                ...turn.plan.map(
                                  (step) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Container(
                                          width: 6,
                                          height: 6,
                                          margin: const EdgeInsets.only(top: 5),
                                          decoration: BoxDecoration(
                                            color: _stepColor(step.status),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${step.step} · ${_stepStatusLabel(step.status)}',
                                            style: roundedTextStyle(
                                              size: 12,
                                              weight: FontWeight.w500,
                                              color: Palette.mutedInk,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (turn.diff.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          DisclosureSection(
                            title: 'Diff',
                            isExpanded: showDiff,
                            onToggle: () =>
                                setState(() => showDiff = !showDiff),
                            child: DiffBlock(diff: turn.diff),
                          ),
                        ],
                        if (turn.items.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          DisclosureSection(
                            title: '时间线',
                            isExpanded: showTimeline,
                            onToggle: () =>
                                setState(() => showTimeline = !showTimeline),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: turn.items
                                  .map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: TimelineEntryView(item: item),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _turnStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return '已完成';
      case 'failed':
        return '失败';
      case 'inProgress':
        return '运行中';
      default:
        return status;
    }
  }

  Color _statusTone(String status) {
    switch (status) {
      case 'completed':
        return Palette.success;
      case 'failed':
        return Palette.danger;
      case 'inProgress':
        return Palette.warning;
      default:
        return Palette.mutedInk;
    }
  }

  Color _stepColor(String status) {
    switch (status) {
      case 'completed':
        return Palette.success;
      case 'in_progress':
        return Palette.warning;
      default:
        return Palette.line;
    }
  }

  String _stepStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return '已完成';
      case 'in_progress':
        return '进行中';
      default:
        return '待处理';
    }
  }
}

class DisclosureSection extends StatelessWidget {
  const DisclosureSection({
    super.key,
    required this.title,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      compact: true,
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: <Widget>[
                Text(
                  title,
                  style: roundedTextStyle(size: 12, weight: FontWeight.w600),
                ),
                const Spacer(),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Palette.ink,
                ),
              ],
            ),
          ),
          if (isExpanded) ...<Widget>[const SizedBox(height: 8), child],
        ],
      ),
    );
  }
}

class TimelineEntryView extends StatelessWidget {
  const TimelineEntryView({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final bodyPreview = normalizedDisplayText(
      item.body,
    ).headTailTruncated(maxLength: 220, head: 140, tail: 72);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.appOpacity(0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              TimelineTypeTag(item: item),
              const Spacer(),
              if (item.status.isNotEmpty)
                Text(
                  item.status,
                  style: roundedTextStyle(
                    size: 11,
                    weight: FontWeight.w600,
                    color: Palette.mutedInk,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (item.type == 'userMessage')
            HeadTailExcerptBlock(
              raw: item.body,
              head: 170,
              tail: 110,
              style: roundedTextStyle(
                size: 12,
                weight: FontWeight.w500,
                color: Palette.mutedInk,
                height: 1.45,
              ),
            )
          else if (item.type == 'agentMessage')
            MarkdownBodyBlock(raw: item.body)
          else if (item.type == 'fileChange')
            FileChangeBlock(item: item)
          else if (item.type == 'commandExecution')
            CommandExecutionBlock(item: item)
          else if (item.type == 'dynamicToolCall')
            ToolCallBlock(item: item)
          else if (item.type == 'collabAgentToolCall')
            DelegationBlock(item: item)
          else ...<Widget>[
            if (bodyPreview.isNotEmpty)
              Text(
                bodyPreview,
                style: roundedTextStyle(
                  size: 12,
                  weight: FontWeight.w500,
                  color: Palette.mutedInk,
                  height: 1.45,
                ),
              ),
            if (item.auxiliary.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              TerminalOutputBlock(text: item.auxiliary, maxVisibleLines: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class TimelineTypeTag extends StatelessWidget {
  const TimelineTypeTag({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.appOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _label,
        style: roundedTextStyle(
          size: 11,
          weight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String get _label {
    switch (item.type) {
      case 'userMessage':
        return '用户';
      case 'agentMessage':
        return 'Agent';
      case 'fileChange':
        return '文件变更';
      case 'dynamicToolCall':
        return '工具调用';
      case 'collabAgentToolCall':
        return '委托';
      default:
        return item.title;
    }
  }

  Color get _color {
    switch (item.type) {
      case 'userMessage':
        return Palette.softBlue;
      case 'agentMessage':
        return Palette.accent;
      case 'fileChange':
        return Palette.accent2;
      case 'commandExecution':
        return Palette.warning;
      case 'dynamicToolCall':
        return Palette.softBlue;
      case 'collabAgentToolCall':
        return Palette.warning;
      default:
        return Palette.mutedInk;
    }
  }
}

class ToolCallBlock extends StatelessWidget {
  const ToolCallBlock({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final tool = item.metadata['tool'] ?? '';
    final progress = item.metadata['progress'] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (tool.isNotEmpty)
          Text(
            tool,
            style: roundedTextStyle(
              size: 12,
              weight: FontWeight.w500,
              color: Palette.ink,
              fontFamily: 'monospace',
            ),
          ),
        if (tool.isNotEmpty && item.body.isNotEmpty) const SizedBox(height: 6),
        if (item.body.isNotEmpty)
          Text(
            item.body,
            style: roundedTextStyle(
              size: 12,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
              height: 1.45,
            ),
          ),
        if (progress.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '进行中：$progress',
            style: roundedTextStyle(
              size: 11,
              weight: FontWeight.w600,
              color: Palette.softBlue,
            ),
          ),
        ],
        if (item.auxiliary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          TerminalOutputBlock(text: item.auxiliary, maxVisibleLines: 10),
        ],
      ],
    );
  }
}

class DelegationBlock extends StatelessWidget {
  const DelegationBlock({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final title = item.metadata['title'] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title.isNotEmpty)
          Text(
            title,
            style: roundedTextStyle(
              size: 12,
              weight: FontWeight.w600,
              color: Palette.ink,
            ),
          ),
        if (title.isNotEmpty && item.body.isNotEmpty) const SizedBox(height: 6),
        if (item.body.isNotEmpty)
          HeadTailExcerptBlock(
            raw: item.body,
            head: 170,
            tail: 110,
            style: roundedTextStyle(
              size: 12,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
              height: 1.45,
            ),
          ),
        if (item.auxiliary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          TerminalOutputBlock(text: item.auxiliary, maxVisibleLines: 10),
        ],
      ],
    );
  }
}

class FileChangeBlock extends StatelessWidget {
  const FileChangeBlock({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final files = item.body
        .split('\n')
        .map((file) => file.trim())
        .where((file) => file.isNotEmpty)
        .toList();
    final visibleFiles = files.take(8).toList();
    final hiddenCount = files.length - visibleFiles.length;

    if (visibleFiles.isEmpty) {
      return Text(
        item.body,
        style: roundedTextStyle(
          size: 12,
          weight: FontWeight.w500,
          color: Palette.mutedInk,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ...visibleFiles.map(
          (file) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.description_outlined,
                    size: 12,
                    color: Palette.accent2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file,
                    style: roundedTextStyle(
                      size: 12,
                      weight: FontWeight.w500,
                      color: Palette.ink,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hiddenCount > 0)
          Text(
            '… 还有 $hiddenCount 个文件',
            style: roundedTextStyle(
              size: 11,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
            ),
          ),
      ],
    );
  }
}

class CommandExecutionBlock extends StatelessWidget {
  const CommandExecutionBlock({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final cwd = item.metadata['cwd'] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (cwd.isNotEmpty) ...<Widget>[
          Text(
            cwd,
            style: roundedTextStyle(
              size: 11,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (item.body.isNotEmpty) ...<Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.appOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                item.body,
                style: roundedTextStyle(
                  size: 12,
                  weight: FontWeight.w500,
                  color: Palette.ink,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (item.auxiliary.isNotEmpty)
          TerminalOutputBlock(text: item.auxiliary, maxVisibleLines: 10),
      ],
    );
  }
}

class TerminalOutputBlock extends StatelessWidget {
  const TerminalOutputBlock({
    super.key,
    required this.text,
    this.maxVisibleLines,
  });

  final String text;
  final int? maxVisibleLines;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final visibleLines = maxVisibleLines == null
        ? lines
        : lines.take(maxVisibleLines!).toList();
    final hiddenLineCount = lines.length - visibleLines.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Palette.terminalBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ...visibleLines.map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                child: Text(
                  line.isEmpty ? ' ' : line,
                  style: roundedTextStyle(
                    size: 11,
                    weight: FontWeight.w500,
                    color: Palette.terminalText,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            if (hiddenLineCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                child: Text(
                  '… 还有 $hiddenLineCount 行未显示',
                  style: roundedTextStyle(
                    size: 11,
                    weight: FontWeight.w500,
                    color: Palette.terminalMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DiffBlock extends StatelessWidget {
  const DiffBlock({super.key, required this.diff});

  final String diff;

  @override
  Widget build(BuildContext context) {
    final lines = diff.split('\n');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.appOpacity(0.8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Palette.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines
                .map(
                  (line) => Container(
                    color: _backgroundColor(line),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    child: Text(
                      line.isEmpty ? ' ' : line,
                      style: roundedTextStyle(
                        size: 11,
                        weight: FontWeight.w500,
                        color: _foregroundColor(line),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Color _backgroundColor(String line) {
    if (line.startsWith('+++') ||
        line.startsWith('---') ||
        line.startsWith('diff ') ||
        line.startsWith('@@')) {
      return Palette.softBlue.appOpacity(0.10);
    }
    if (line.startsWith('+')) {
      return Palette.success.appOpacity(0.10);
    }
    if (line.startsWith('-')) {
      return Palette.danger.appOpacity(0.10);
    }
    return Colors.transparent;
  }

  Color _foregroundColor(String line) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return Palette.success;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return Palette.danger;
    }
    if (line.startsWith('+++') ||
        line.startsWith('---') ||
        line.startsWith('diff ') ||
        line.startsWith('@@')) {
      return Palette.softBlue;
    }
    return Palette.ink;
  }
}
