import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sentinel_remote/protocol.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sentinel_remote/main.dart';

void main() {
  testWidgets('unpaired app has no sample characters or active game actions', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const SentinelRemoteApp());
    await tester.pumpAndSettle();
    expect(find.text('Sentinel Remote'), findsOneWidget);
    expect(find.text('Pair a PC to get started.'), findsOneWidget);
    expect(find.textContaining('Wrothy'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('launcher remains available with FFXIV exited and no connected Relay', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'sentinel.hosts.v1': jsonEncode([{
      'label': 'Test PC', 'origin': 'https://pc.tail.ts.net', 'deviceId': 'device',
      'deviceToken': 'test-secret', 'hostId': 'pc'
    }])});
    final transport = RecoveryTransport();
    await tester.pumpWidget(MaterialApp(home: RemoteHome(transport: transport)));
    await tester.pumpAndSettle();
    expect(transport.operations.where((v) => v['operation'] == 'launcher.open'), isEmpty);
    final launch = find.widgetWithText(FilledButton, 'Open XIVLauncher');
    expect(tester.widget<FilledButton>(launch).onPressed, isNotNull);
    final gamepad = find.widgetWithText(FilledButton, 'Gamepad');
    await tester.ensureVisible(gamepad);
    expect(tester.widget<FilledButton>(gamepad).onPressed, isNull);
    await tester.ensureVisible(launch);
    await tester.tap(launch);
    await tester.pumpAndSettle();
    final requests = transport.operations.where((v) => v['operation'] == 'launcher.open').toList();
    expect(requests, hasLength(1));
    expect(requests.single['instanceId'], isNull);
    expect(requests.single.keys, isNot(contains('path')));
    final restore = find.widgetWithText(OutlinedButton, 'Restore game window');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(transport.operations.where((v) => v['operation'] == 'game.restore').single['instanceId'], 'saved');
    await tester.pumpWidget(const SizedBox.shrink());
  });

}

class RecoveryTransport implements JsonTransport {
  final operations = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> post(Uri origin, String path, Map<String, dynamic> body, String? credential) async {
    if (path.endsWith('/session')) return {'success': true, 'code': 'session_opened', 'data': {'sessionToken': 'session', 'protocolVersion': 1}};
    operations.add(body);
    final dynamic data = switch (body['operation']) {
      'session.ping' => {'hostId': 'pc'},
      'instances.list' => [{'instanceId': 'saved', 'label': 'Saved character'}],
      'srank.status' => {'processStatus': 'exited', 'relayStatus': 'unavailable'},
      _ => null,
    };
    return {'success': true, 'code': 'ok', 'data': data};
  }
  @override
  void cancel() {}
}
