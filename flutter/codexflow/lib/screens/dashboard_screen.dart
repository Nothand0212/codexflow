import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/session_browser_query.dart';
import '../domain/session_groups.dart';
import '../models/app_models.dart';
import '../state/app_model.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import 'session_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final selectedAgentId = model.selectedStartAgentId;
    final sessionGroups = groupSessionsForAgent(
      sessions: model.dashboard.sessions,
      approvals: model.dashboard.approvals,
      selectedAgentId: selectedAgentId,
    );
    final filteredSessions = sessionGroups.sessions;
    final loadedCount = sessionGroups.loadedCount;
    final activeCount = sessionGroups.activeCount;

    return Scaffold(
      backgroundColor: Palette.canvas,
      appBar: AppBar(
        title: Text(
          '会话',
          style: roundedTextStyle(size: 17, weight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            tooltip: '新建会话',
            icon: const Icon(Icons.add_rounded),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (BuildContext context) => const NewSessionSheet(),
              );
            },
          ),
        ],
      ),
      body: PageScaffold(
        child: RefreshIndicator(
          color: Palette.accent,
          onRefresh: model.refreshDashboard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: <Widget>[
              if (model.operationNotice.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
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
              ],
              if (!model.isAgentOnline &&
                  model.agentConnectionError.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Palette.danger.appOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    model.agentConnectionError,
                    style: roundedTextStyle(
                      size: 12,
                      weight: FontWeight.w500,
                      color: Palette.danger,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _AgentStatusStrip(
                connected: model.isAgentOnline,
                host: _statusHost(model),
                runningCount: activeCount,
                pendingCount: sessionGroups.pendingApprovalCount,
                lastRefreshAt: model.lastDashboardRefreshAt,
              ),
              const SizedBox(height: 12),
              _HomeMetricButton(
                title: '总会话',
                value: '${filteredSessions.length}',
                icon: Icons.forum_rounded,
                tone: Palette.softBlue,
                onTap: () => _openSessionBrowser(
                  context,
                  SessionBrowserFilter.all,
                  selectedAgentId,
                ),
              ),
              const SizedBox(height: 10),
              _HomeMetricButton(
                title: '已加载',
                value: '$loadedCount',
                icon: Icons.cloud_done_rounded,
                tone: Palette.accent,
                onTap: () => _openSessionBrowser(
                  context,
                  SessionBrowserFilter.loaded,
                  selectedAgentId,
                ),
              ),
              const SizedBox(height: 10),
              _HomeMetricButton(
                title: '运行中',
                value: '$activeCount',
                icon: Icons.play_circle_fill_rounded,
                tone: Palette.accent2,
                onTap: () => _openSessionBrowser(
                  context,
                  SessionBrowserFilter.active,
                  selectedAgentId,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  _AgentSwitchButton(model: model),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (BuildContext context) =>
                            const NewSessionSheet(),
                      );
                    },
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: Text(
                      '新建',
                      style: roundedTextStyle(
                        size: 12,
                        weight: FontWeight.w700,
                        color: Palette.softBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusHost(AppModel model) {
    final listenAddr = model.dashboard.agent.listenAddr.trim();
    if (listenAddr.isNotEmpty) {
      return listenAddr;
    }
    final uri = Uri.tryParse(model.baseUrlString.trim());
    if (uri != null && uri.host.isNotEmpty) {
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.host}$port';
    }
    return 'unknown host';
  }

  void _openSessionBrowser(
    BuildContext context,
    SessionBrowserFilter filter,
    String agentId,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _SessionBrowserScreen(filter: filter, agentId: agentId),
      ),
    );
  }
}

class _AgentStatusStrip extends StatelessWidget {
  const _AgentStatusStrip({
    required this.connected,
    required this.host,
    required this.runningCount,
    required this.pendingCount,
    required this.lastRefreshAt,
  });

  final bool connected;
  final String host;
  final int runningCount;
  final int pendingCount;
  final DateTime? lastRefreshAt;

  @override
  Widget build(BuildContext context) {
    final statusColor = connected ? Palette.success : Palette.danger;
    final statusText = connected ? '在线' : '离线';
    final refreshTime = lastRefreshAt == null
        ? '未刷新'
        : TimeOfDay.fromDateTime(lastRefreshAt!).format(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Palette.panelStrong,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: roundedTextStyle(
                  size: 15,
                  weight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: roundedTextStyle(
                    size: 12,
                    weight: FontWeight.w600,
                    color: Palette.mutedInk,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _StatusDetail(label: '运行中', value: '$runningCount'),
              _StatusDetail(label: '待审批', value: '$pendingCount'),
              _StatusDetail(label: '刷新', value: refreshTime),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusDetail extends StatelessWidget {
  const _StatusDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Palette.shell,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: roundedTextStyle(
              size: 11,
              weight: FontWeight.w700,
              color: Palette.mutedInk,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: roundedTextStyle(size: 12, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HomeMetricButton extends StatelessWidget {
  const _HomeMetricButton({
    required this.title,
    required this.value,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Palette.panelStrong,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Palette.line),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.appOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: tone, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: roundedTextStyle(size: 16, weight: FontWeight.w600),
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: roundedTextStyle(size: 28, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: Palette.mutedInk,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionBrowserScreen extends StatefulWidget {
  const _SessionBrowserScreen({required this.filter, required this.agentId});

  final SessionBrowserFilter filter;
  final String agentId;

  @override
  State<_SessionBrowserScreen> createState() => _SessionBrowserScreenState();
}

class _SessionBrowserScreenState extends State<_SessionBrowserScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final sessionGroups = groupSessionsForAgent(
      sessions: model.dashboard.sessions,
      approvals: model.dashboard.approvals,
      selectedAgentId: widget.agentId,
    );
    final query = _searchController.text.trim().toLowerCase();
    final browserQuery = SessionBrowserQuery.apply(
      groups: sessionGroups,
      filter: widget.filter,
      query: query,
    );
    final visibleSessions = browserQuery.visibleSessions;

    return Scaffold(
      backgroundColor: Palette.canvas,
      appBar: AppBar(
        title: Text(
          _filterTitle(widget.filter),
          style: roundedTextStyle(size: 17, weight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: PageScaffold(
        child: RefreshIndicator(
          color: Palette.accent,
          onRefresh: model.refreshDashboard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  color: Palette.panelStrong,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Palette.line),
                ),
                child: TextField(
                  controller: _searchController,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  style: roundedTextStyle(size: 14, weight: FontWeight.w500),
                  cursorColor: Palette.softBlue,
                  decoration: InputDecoration(
                    hintText: '搜索会话、路径、分支或首条消息',
                    hintStyle: roundedTextStyle(
                      size: 14,
                      weight: FontWeight.w500,
                      color: Palette.mutedInk,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Palette.mutedInk,
                    ),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Palette.mutedInk,
                            ),
                            onPressed: _searchController.clear,
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Text(
                    '${visibleSessions.length}',
                    style: roundedTextStyle(size: 18, weight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '/ ${browserQuery.totalCount}',
                    style: roundedTextStyle(
                      size: 13,
                      weight: FontWeight.w600,
                      color: Palette.mutedInk,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '最近更新优先',
                    style: roundedTextStyle(
                      size: 12,
                      weight: FontWeight.w600,
                      color: Palette.mutedInk,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (visibleSessions.isEmpty)
                PanelCard(
                  compact: true,
                  child: Text(
                    query.isEmpty ? '暂无会话。' : '没有匹配的会话。',
                    style: roundedTextStyle(
                      size: 13,
                      weight: FontWeight.w500,
                      color: Palette.mutedInk,
                    ),
                  ),
                )
              else
                ...visibleSessions.map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SessionRow(session: session),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _filterTitle(SessionBrowserFilter filter) {
    switch (filter) {
      case SessionBrowserFilter.loaded:
        return '已加载';
      case SessionBrowserFilter.active:
        return '运行中';
      case SessionBrowserFilter.all:
        return '总会话';
    }
  }
}

class _AgentSwitchButton extends StatelessWidget {
  const _AgentSwitchButton({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    AgentOption? selected;
    for (final option in model.startAgentOptions) {
      if (option.id == model.selectedStartAgentId) {
        selected = option;
        break;
      }
    }
    final selectedName = selected?.name ?? 'Codex';

    return PopupMenuButton<String>(
      tooltip: '切换 Agent',
      onSelected: (String value) {
        model.setSelectedStartAgent(value);
      },
      itemBuilder: (BuildContext context) {
        return model.startAgentOptions.map((option) {
          final isSelected = option.id == model.selectedStartAgentId;
          return PopupMenuItem<String>(
            value: option.id,
            enabled: option.available,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    option.name,
                    style: roundedTextStyle(
                      size: 13,
                      weight: FontWeight.w600,
                      color: option.available ? Palette.ink : Palette.mutedInk,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Palette.softBlue,
                  ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Palette.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.account_tree_rounded,
              size: 14,
              color: Palette.ink,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                selectedName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: roundedTextStyle(size: 12, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more_rounded, size: 14, color: Palette.ink),
          ],
        ),
      ),
    );
  }
}

class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    final canArchive = !session.loaded || session.isEnded;
    final tags = <Widget>[
      CapsuleTag(title: '托管', value: session.loaded ? '已接管' : '未接管'),
      if (session.isClaudeSession)
        CapsuleTag(
          title: '链路',
          value: session.runtimeAvailable ? 'Runtime' : 'History',
        ),
      if (session.loaded && session.runtimeAttachMode.isNotEmpty)
        CapsuleTag(
          title: '接管',
          value: session.runtimeAttachMode == 'resumed_existing'
              ? '现有 Runtime'
              : (session.runtimeAttachMode == 'opened_from_history'
                    ? '历史新开'
                    : '新建 Runtime'),
        ),
      CapsuleTag(title: '来源', value: session.source),
      CapsuleTag(
        title: '分支',
        value: session.branch.isEmpty ? '未识别' : session.branch,
      ),
      if (session.pendingApprovals > 0)
        CapsuleTag(title: '待处理', value: '${session.pendingApprovals}')
      else if (session.hasWaitingState)
        CapsuleTag(title: '待处理', value: '等待'),
      if (session.lastTurnStatus.isNotEmpty)
        CapsuleTag(
          title: '最近一轮',
          value: _lastTurnStatusLabel(session.lastTurnStatus),
        ),
    ];

    return PanelCard(
      compact: true,
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        session.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: roundedTextStyle(
                          size: 15,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        session.cwd,
                        style: roundedTextStyle(
                          size: 12,
                          weight: FontWeight.w500,
                          color: Palette.mutedInk,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '更新 ${session.updatedAtDisplay}',
                        style: roundedTextStyle(
                          size: 11,
                          weight: FontWeight.w600,
                          color: Palette.mutedInk,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    StatusPill(
                      status: session.status,
                      waiting: session.hasWaitingState,
                      ended: session.isEnded,
                    ),
                    if (canArchive) ...<Widget>[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: PopupMenuButton<String>(
                          tooltip: '更多操作',
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.more_horiz_rounded,
                            size: 20,
                            color: Palette.mutedInk,
                          ),
                          onSelected: (value) async {
                            if (value == 'archive') {
                              await context.read<AppModel>().archiveSession(
                                session,
                              );
                            }
                          },
                          itemBuilder: (context) => <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'archive',
                              child: Text(
                                session.isEnded ? '归档已结束会话' : '从列表移除',
                                style: roundedTextStyle(
                                  size: 13,
                                  weight: FontWeight.w600,
                                  color: Palette.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (session.previewSummary.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                session.previewSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: roundedTextStyle(
                  size: 13,
                  weight: FontWeight.w500,
                  color: Palette.mutedInk,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    tags
                        .expand(
                          (tag) => <Widget>[tag, const SizedBox(width: 8)],
                        )
                        .toList()
                      ..removeLast(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailScreen(sessionId: session.id),
      ),
    );
  }

  String _lastTurnStatusLabel(String status) {
    switch (status) {
      case 'inProgress':
        return '运行中';
      case 'completed':
        return '已完成';
      case 'failed':
        return '失败';
      default:
        return status;
    }
  }
}

class NewSessionSheet extends StatefulWidget {
  const NewSessionSheet({super.key});

  @override
  State<NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<NewSessionSheet> {
  late final TextEditingController _cwdController;
  late final TextEditingController _promptController;
  bool _isCreating = false;
  String _submitError = '';

  @override
  void initState() {
    super.initState();
    _cwdController = TextEditingController();
    _promptController = TextEditingController();
  }

  @override
  void dispose() {
    _cwdController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _cwdController,
        _promptController,
      ]),
      builder: (BuildContext context, Widget? child) {
        final trimmedCwd = _cwdController.text.trim();
        final trimmedPrompt = _promptController.text.trim();
        final canCreate = trimmedCwd.isNotEmpty && trimmedPrompt.isNotEmpty;

        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.7,
          maxChildSize: 0.96,
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
                        centerTitle: true,
                        title: Text(
                          '新建会话',
                          style: roundedTextStyle(
                            size: 17,
                            weight: FontWeight.w600,
                          ),
                        ),
                        leading: TextButton(
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
                      ),
                      body: PageScaffold(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                          children: <Widget>[
                            PanelCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Palette.softBlue.appOpacity(
                                            0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '受控会话',
                                          style: roundedTextStyle(
                                            size: 11,
                                            weight: FontWeight.w700,
                                            color: Palette.softBlue,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '2 项必填',
                                        style: roundedTextStyle(
                                          size: 11,
                                          weight: FontWeight.w700,
                                          color: Palette.mutedInk,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '新建会话',
                                    style: roundedTextStyle(
                                      size: 26,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '填写目录和首条提示，CodexFlow 会立即建立一个可继续的会话。',
                                    style: roundedTextStyle(
                                      size: 13,
                                      weight: FontWeight.w500,
                                      color: Palette.mutedInk,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: <Widget>[
                                      Text(
                                        '工作目录',
                                        style: roundedTextStyle(
                                          size: 14,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '绝对路径或 ~/repo',
                                        style: roundedTextStyle(
                                          size: 11,
                                          weight: FontWeight.w500,
                                          color: Palette.mutedInk,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  CodexTextField(
                                    controller: _cwdController,
                                    hintText:
                                        '/Users/hebicheng/workspace/aicoding-helper',
                                    monospaced: true,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: <Widget>[
                                      Text(
                                        '首条提示',
                                        style: roundedTextStyle(
                                          size: 14,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        trimmedPrompt.isEmpty
                                            ? '未填写'
                                            : '${trimmedPrompt.length} 字',
                                        style: roundedTextStyle(
                                          size: 11,
                                          weight: FontWeight.w500,
                                          color: trimmedPrompt.isEmpty
                                              ? Palette.mutedInk
                                              : Palette.softBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  CodexTextField(
                                    controller: _promptController,
                                    hintText: '例如：继续实现剩余部分，并补上验证。',
                                    maxLines: 7,
                                    minLines: 7,
                                    autocapitalization:
                                        TextCapitalization.sentences,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: <Widget>[
                                      const Icon(
                                        Icons.auto_awesome,
                                        size: 14,
                                        color: Palette.softBlue,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '支持 `~/...` 路径，创建后会立即出现在会话列表。',
                                          style: roundedTextStyle(
                                            size: 12,
                                            weight: FontWeight.w500,
                                            color: Palette.mutedInk,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_submitError.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Palette.danger.appOpacity(0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _submitError,
                                        style: roundedTextStyle(
                                          size: 13,
                                          weight: FontWeight.w500,
                                          color: Palette.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  ActionButton(
                                    title: _isCreating ? '创建中…' : '创建会话',
                                    background: Palette.accent,
                                    foreground: Colors.white,
                                    fontSize: 14,
                                    icon: _isCreating ? null : Icons.add,
                                    enabled: canCreate && !_isCreating,
                                    onPressed: () async {
                                      if (!canCreate || _isCreating) {
                                        return;
                                      }
                                      final appModel = context.read<AppModel>();
                                      final navigator = Navigator.of(context);
                                      FocusScope.of(context).unfocus();
                                      setState(() {
                                        _isCreating = true;
                                        _submitError = '';
                                      });

                                      final success = await appModel
                                          .startSession(
                                            cwd: trimmedCwd,
                                            prompt: trimmedPrompt,
                                            agentId:
                                                appModel.selectedStartAgentId,
                                          );

                                      if (!mounted) {
                                        return;
                                      }

                                      if (success) {
                                        navigator.pop();
                                      } else {
                                        setState(() {
                                          _isCreating = false;
                                          final connectionError =
                                              appModel.connectionError;
                                          _submitError = connectionError.isEmpty
                                              ? '创建会话失败，请检查 Agent 状态和输入内容。'
                                              : connectionError;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
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
      },
    );
  }
}
