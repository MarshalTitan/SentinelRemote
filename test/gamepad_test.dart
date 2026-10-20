import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel_remote/gamepad.dart';
import 'package:sentinel_remote/protocol.dart';

class FakeSocket extends Stream<dynamic> implements WebSocket {
  final events = StreamController<dynamic>();
  final sent = <dynamic>[];
  bool closed = false;
  @override
  StreamSubscription<dynamic> listen(void Function(dynamic)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
    events.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  void add(dynamic data) { sent.add(jsonDecode(data as String)); }
  @override
  Future<void> close([int? code, String? reason]) async { closed = true; await events.close(); }
  void poll(int sequence) { if (!closed) events.add(jsonEncode({'version': 1, 'sequence': sequence, 'challenge': 'A' * 64})); }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class FakeClient extends RemoteClient {
  final FakeSocket socket = FakeSocket();
  int opened = 0;
  FakeClient() : super(PairedHost('PC', Uri.parse('https://pc.tail.ts.net'), 'device', 'token', 'host'), UnusedTransport());
  @override
  Future<WebSocket> openGamepad() async { opened++; return socket; }
}
class UnusedTransport implements JsonTransport {
  @override
  Future<Map<String, dynamic>> post(Uri origin, String path, Map<String, dynamic> body, String? credential) async => {};
  @override
  void cancel() {}
}

void main() {
  final poll = {'version': 1, 'sequence': 1, 'challenge': 'A' * 64};
  test('complete state contains independent triggers and no reserved buttons', () {
    final pad = PadState()..lx = 0.5..ry = -0.5;
    pad.held[1] = 0x1000; pad.held[2] = -1; pad.held[3] = -2;
    final frame = pad.reply(poll);
    expect(frame['leftX'], 0.5); expect(frame['rightY'], -0.5);
    expect(frame['buttons'], 0x1000);
    expect(frame['leftTrigger'], 1); expect(frame['rightTrigger'], 1);
    pad.held.remove(2);
    expect(pad.reply(poll)['leftTrigger'], 0); expect(pad.reply(poll)['rightTrigger'], 1);
    pad.clear();
    expect(pad.reply(poll)['buttons'], 0);
    expect(pad.reply(poll)['leftX'], 0); expect(pad.reply(poll)['rightY'], 0);
  });
  test('touch state cannot reply to malformed freshness polls', () {
    for (final bad in [
      {...poll, 'sequence': 0}, {...poll, 'challenge': 'bad'},
      {...poll, 'version': 2}, {...poll, 'unknown': 'field'},
    ]) {
      expect(() => PadState().reply(bad), throwsA(isA<RemoteFailure>()));
    }
  });
  testWidgets('stick pointer cancellation and disable release both axes', (tester) async {
    var enabled = true; var x = 0.0, y = 0.0;
    Widget build() => MaterialApp(home: Scaffold(body: TouchStick(label: 'Move', enabled: enabled,
      onChanged: (a, b) { x = a; y = b; })));
    await tester.pumpWidget(build());
    final stick = find.byType(TouchStick);
    final gesture = await tester.startGesture(tester.getCenter(stick));
    await gesture.moveBy(const Offset(30, -20)); await tester.pump();
    expect(x, greaterThan(0)); expect(y, greaterThan(0));
    await gesture.cancel(); await tester.pump(); expect(x, 0); expect(y, 0);
    final second = await tester.startGesture(tester.getCenter(stick));
    await second.moveBy(const Offset(25, 25)); await tester.pump();
    enabled = false; await tester.pumpWidget(build()); expect(x, 0); expect(y, 0);
    await second.up();
  });
  testWidgets('background releases held touches, closes socket and never automatically reacquires', (tester) async {
    final client = FakeClient();
    await tester.pumpWidget(MaterialApp(home: GamepadPage(client: client, instance: 'one', character: 'Character')));
    await tester.tap(find.text('Start gamepad')); await tester.pump();
    client.socket.poll(1); await tester.pump();
    final stick = find.byType(TouchStick).first;
    final finger = await tester.startGesture(tester.getCenter(stick));
    await finger.moveBy(const Offset(30, -20)); await tester.pump();
    client.socket.poll(2); await tester.pump();
    expect((client.socket.sent.last as Map)['leftX'], greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await tester.pump();
    expect(client.socket.closed, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pump();
    expect(client.opened, 1);
    expect(find.text('Start gamepad'), findsOneWidget);
    await finger.up(); await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('preview fits narrow portrait and landscape with stop always reachable', (tester) async {
    for (final size in [const Size(320, 640), const Size(740, 360)]) {
      tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(home: GamepadPage(client: FakeClient(), instance: 'one', character: 'Character')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Stop gamepad').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
  });

}
