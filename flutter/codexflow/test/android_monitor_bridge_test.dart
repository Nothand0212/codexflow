import 'package:codexflow_flutter/services/android_monitor_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('codexflow/monitor');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          if (call.method == 'getMonitorStatus') {
            return <String, Object?>{};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('setVisible sends visibility payload to Android', () async {
    final bridge = AndroidMonitorBridge(channel: channel);

    await bridge.setVisible(true);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setAppVisible');
    expect(calls.single.arguments, <String, Object?>{'visible': true});
  });

  test('agentUrlChanged sends updated agent URL to Android', () async {
    final bridge = AndroidMonitorBridge(channel: channel);

    await bridge.agentUrlChanged('http://100.91.5.116:4318');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'agentUrlChanged');
    expect(calls.single.arguments, <String, Object?>{
      'url': 'http://100.91.5.116:4318',
    });
  });

  test('getStatus maps missing fields to safe defaults', () async {
    final bridge = AndroidMonitorBridge(channel: channel);

    final status = await bridge.getStatus();

    expect(calls.single.method, 'getMonitorStatus');
    expect(status.supported, isFalse);
    expect(status.running, isFalse);
    expect(status.notificationPermissionGranted, isFalse);
    expect(status.versionName, isEmpty);
    expect(status.buildNumber, 0);
  });
}
