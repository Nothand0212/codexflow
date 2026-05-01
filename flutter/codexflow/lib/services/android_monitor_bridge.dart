import 'dart:async';

import 'package:flutter/services.dart';

import '../navigation/notification_target.dart';

typedef NotificationRouteHandler = void Function(NotificationTarget target);

abstract class AndroidMonitorBridgeApi {
  Future<void> start();
  Future<void> stop();
  Future<void> setVisible(bool visible);
  Future<void> agentUrlChanged(String url);
  Future<bool> requestNotificationPermission();
  Future<AndroidMonitorStatus> getStatus();
  void setNotificationRouteHandler(NotificationRouteHandler? handler);
  Future<NotificationTarget?> takeInitialNotificationRoute();
}

class AndroidMonitorStatus {
  const AndroidMonitorStatus({
    required this.supported,
    required this.running,
    required this.notificationPermissionGranted,
    required this.versionName,
    required this.buildNumber,
  });

  factory AndroidMonitorStatus.fromMap(Map<Object?, Object?>? value) {
    return AndroidMonitorStatus(
      supported: _asBool(value?['supported'], defaultValue: false),
      running: _asBool(value?['running'], defaultValue: false),
      notificationPermissionGranted: _asBool(
        value?['notificationPermissionGranted'],
        defaultValue: false,
      ),
      versionName: _asString(value?['versionName']),
      buildNumber: _asInt(value?['buildNumber']),
    );
  }

  static const unsupported = AndroidMonitorStatus(
    supported: false,
    running: false,
    notificationPermissionGranted: false,
    versionName: '',
    buildNumber: 0,
  );

  final bool supported;
  final bool running;
  final bool notificationPermissionGranted;
  final String versionName;
  final int buildNumber;

  static bool _asBool(Object? value, {required bool defaultValue}) {
    return value is bool ? value : defaultValue;
  }

  static String _asString(Object? value) {
    return value == null ? '' : value.toString();
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

class AndroidMonitorBridge implements AndroidMonitorBridgeApi {
  AndroidMonitorBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('codexflow/monitor');

  final MethodChannel _channel;
  NotificationRouteHandler? _notificationRouteHandler;

  @override
  Future<void> start() async {
    await _ignoreMissingPlugin(_channel.invokeMethod<void>('startMonitor'));
  }

  @override
  Future<void> stop() async {
    await _ignoreMissingPlugin(_channel.invokeMethod<void>('stopMonitor'));
  }

  @override
  Future<void> setVisible(bool visible) async {
    await _ignoreMissingPlugin(
      _channel.invokeMethod<void>('setAppVisible', <String, Object?>{
        'visible': visible,
      }),
    );
  }

  @override
  Future<void> agentUrlChanged(String url) async {
    await _ignoreMissingPlugin(
      _channel.invokeMethod<void>('agentUrlChanged', <String, Object?>{
        'url': url,
      }),
    );
  }

  @override
  Future<bool> requestNotificationPermission() async {
    final granted = await _withMissingPluginDefault<bool?>(
      _channel.invokeMethod<bool>('requestNotificationPermission'),
      false,
    );
    return granted ?? false;
  }

  @override
  Future<AndroidMonitorStatus> getStatus() async {
    final status = await _withMissingPluginDefault<Map<dynamic, dynamic>?>(
      _channel.invokeMapMethod<dynamic, dynamic>('getMonitorStatus'),
      null,
    );
    return AndroidMonitorStatus.fromMap(status);
  }

  @override
  void setNotificationRouteHandler(NotificationRouteHandler? handler) {
    _notificationRouteHandler = handler;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  Future<NotificationTarget?> takeInitialNotificationRoute() async {
    final route = await _withMissingPluginDefault<String?>(
      _channel.invokeMethod<String>('takeInitialNotificationRoute'),
      null,
    );
    if (route == null || route.isEmpty) {
      return null;
    }
    return NotificationTarget.fromJsonString(route);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'notificationRoute':
        final route = call.arguments?.toString();
        if (route != null && route.isNotEmpty) {
          _notificationRouteHandler?.call(
            NotificationTarget.fromJsonString(route),
          );
        }
        return;
      default:
        throw MissingPluginException('No handler for ${call.method}');
    }
  }

  Future<void> _ignoreMissingPlugin(Future<void> future) async {
    try {
      await future;
    } on MissingPluginException {
      return;
    }
  }

  Future<T> _withMissingPluginDefault<T>(
    Future<T> future,
    T defaultValue,
  ) async {
    try {
      return await future;
    } on MissingPluginException {
      return defaultValue;
    }
  }
}
