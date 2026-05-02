import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/app_models.dart';
import 'navigation/mobile_notification_route_coordinator.dart';
import 'navigation/notification_target.dart';
import 'screens/approval_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/session_detail_screen.dart';
import 'state/app_model.dart';
import 'theme/palette.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(CodexFlowApp(prefs: prefs));
}

class CodexFlowApp extends StatelessWidget {
  const CodexFlowApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppModel>(
      create: (_) => AppModel(prefs)..bootstrap(),
      child: MaterialApp(
        title: 'CodexFlow',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Palette.canvas,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Palette.softBlue,
            primary: Palette.softBlue,
            secondary: Palette.accent,
            surface: Palette.canvas,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Palette.canvas,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            iconTheme: const IconThemeData(color: Palette.mutedInk),
            titleTextStyle: roundedTextStyle(size: 17, weight: FontWeight.w600),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          dividerColor: Colors.transparent,
        ),
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _timer;
  AppModel? _model;
  int _handledNotificationRouteVersion = 0;
  final MobileNotificationRouteCoordinator _notificationRoutes =
      MobileNotificationRouteCoordinator();

  static const _pages = <Widget>[
    DashboardScreen(),
    ApprovalScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = context.read<AppModel>();
      model.setNotificationRouteHandler(model.applyNotificationTarget);
      unawaited(model.startMonitorIfAllowed());
      unawaited(_takeInitialNotificationRoute(model));
      _timer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (!mounted) {
          return;
        }
        unawaited(context.read<AppModel>().refreshDashboard());
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextModel = context.read<AppModel>();
    if (_model == nextModel) {
      return;
    }
    _model?.removeListener(_handleAppModelChanged);
    _model = nextModel;
    nextModel.addListener(_handleAppModelChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _model?.removeListener(_handleAppModelChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    unawaited(context.read<AppModel>().setMonitorVisible(visible));
  }

  Future<void> _takeInitialNotificationRoute(AppModel model) async {
    final target = await model.takeInitialNotificationRoute();
    if (!mounted || target == null) {
      return;
    }
    model.applyNotificationTarget(target);
  }

  void _handleAppModelChanged() {
    final model = _model;
    if (model == null ||
        model.notificationRouteVersion == _handledNotificationRouteVersion) {
      return;
    }
    _handledNotificationRouteVersion = model.notificationRouteVersion;
    unawaited(_applyNotificationTarget(model.pendingNotificationTarget));
  }

  Future<void> _applyNotificationTarget(NotificationTarget target) async {
    final decision = _notificationRoutes.begin(target);
    switch (decision.action) {
      case MobileNotificationRouteAction.showDashboard:
        _showTab(0);
      case MobileNotificationRouteAction.showApprovals:
        await _openApprovalsTarget(decision);
      case MobileNotificationRouteAction.showSessionDetail:
        await _openSessionDetailTarget(decision);
      case MobileNotificationRouteAction.showNotice:
        _showTab(0);
        context.read<AppModel>().showNotice(
          decision.notice,
          isError: decision.noticeIsError,
        );
      case MobileNotificationRouteAction.ignore:
        return;
    }
  }

  void _showTab(int index) {
    if (!mounted) {
      return;
    }
    setState(() {
      _index = index;
    });
  }

  Future<void> _openApprovalsTarget(
    MobileNotificationRouteDecision decision,
  ) async {
    _showTab(1);
    final model = context.read<AppModel>();
    await model.refreshDashboard();
    if (!mounted) {
      return;
    }
    final session = _findSession(model, decision.sessionId);
    if (session != null) {
      model.setSelectedStartAgent(session.agentId);
    }
    if (decision.approvalId.isNotEmpty) {
      final exists = model.dashboard.approvals.any(
        (approval) => approval.id == decision.approvalId,
      );
      if (!exists) {
        model.showNotice('这条审批可能已经处理。');
      }
    }
  }

  Future<void> _openSessionDetailTarget(
    MobileNotificationRouteDecision decision,
  ) async {
    _showTab(0);
    final sessionId = decision.sessionId;
    final model = context.read<AppModel>();
    var opened = false;
    try {
      await model.refreshDashboard();
      if (!mounted) {
        return;
      }
      final session = _findSession(model, sessionId);
      if (session == null) {
        model.showNotice('这个会话当前不可用，可能已经被清理。', isError: true);
        return;
      }
      model.setSelectedStartAgent(session.agentId);
      await model.loadSession(sessionId);
      if (!mounted) {
        return;
      }
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      _notificationRoutes.markSessionOpened(sessionId);
      opened = true;
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: 'session-detail:$sessionId'),
          builder: (_) => SessionDetailScreen(sessionId: sessionId),
        ),
      );
    } finally {
      if (opened) {
        _notificationRoutes.markSessionClosed(sessionId);
      } else {
        _notificationRoutes.markSessionOpenFailed(sessionId);
      }
    }
  }

  SessionSummary? _findSession(AppModel model, String sessionId) {
    if (sessionId.isEmpty) {
      return null;
    }
    return model.dashboard.sessions.cast<SessionSummary?>().firstWhere(
      (session) => session?.id == sessionId,
      orElse: () => null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.canvas,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Palette.panelStrong,
        indicatorColor: Palette.softBlue.appOpacity(0.12),
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: '会话',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rounded),
            label: '审批',
          ),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: '设置'),
        ],
      ),
    );
  }
}
