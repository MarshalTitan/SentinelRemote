import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel_remote/desktop.dart';
import 'package:sentinel_remote/gamepad.dart';
import 'package:sentinel_remote/protocol.dart';
import 'gamepad_test.dart' show FakeClient;

class DesktopSocket extends Stream<dynamic> implements WebSocket {
  final events = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;
  int frames = 0;
  DesktopSocket() {
    scheduleMicrotask(() => events.add(jsonEncode({'success': true, 'code': 'desktop_ready', 'data': null})));
  }
  @override
  StreamSubscription<dynamic> listen(void Function(dynamic)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
    events.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  void add(dynamic data) {
    final request = jsonDecode(data as String) as Map<String, dynamic>;
    sent.add(request);
    final frame = request['kind'] == 'frame';
    events.add(jsonEncode({'success': true, 'code': frame ? 'desktop_frame' : 'desktop_applied', 'data': frame ? {
      'frameId': (++frames).toRadixString(16).padLeft(64, 'A'), 'width': 640, 'height': 360,
      'jpegBase64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      'capturedUtc': DateTime.now().toUtc().toIso8601String()
    } : null}));
  }
  @override
  Future<void> close([int? code, String? reason]) async { if (closed) return; closed = true; await events.close(); }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class DesktopClient extends RemoteClient {
  final sockets = <DesktopSocket>[];
  DesktopClient() : super(PairedHost('PC', Uri.parse('https://pc.tail.ts.net'), 'device', 'token', 'host'), UnusedDesktopTransport());
  @override
  Future<WebSocket> openDesktop() async { final socket = DesktopSocket(); sockets.add(socket); return socket; }
}
class UnusedDesktopTransport implements JsonTransport {
  @override
  Future<Map<String, dynamic>> post(Uri origin, String path, Map<String, dynamic> body, String? credential) async => {};
  @override
  void cancel() {}
}

void main() {
  test('desktop starts without game state and sends a displayed-frame click exactly once', () async {
    final client = DesktopClient(); final desktop = DesktopController(client);
    await desktop.connect();
    expect(desktop.fresh, isTrue);
    expect(client.sockets.single.sent.single['kind'], 'frame');
    final frame = desktop.frameId;
    await desktop.act('tap', x: .25, y: .75);
    final actions = client.sockets.single.sent.where((r) => r['kind'] != 'frame').toList();
    expect(actions, hasLength(1));
    expect(actions.single['frameId'], frame);
    expect(actions.single['x'], .25);
    desktop.stop();
    expect(desktop.jpeg, isNull);
    expect(desktop.ready.value, isFalse);
    await desktop.act('tap', x: .5, y: .5);
    expect(client.sockets.single.sent.where((r) => r['kind'] != 'frame'), hasLength(1));
    desktop.dispose();
  });
  testWidgets('desktop view and gamepad fit portrait and landscape with reachable Stop', (tester) async {
    for (final size in [const Size(320, 640), const Size(740, 360)]) {
      tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
      final ready = ValueNotifier(true); final client = FakeClient();
      await tester.pumpWidget(MaterialApp(home: GamepadPage(client: client, instance: 'one', character: 'Character',
        liveView: const ColoredBox(key: Key('mirror'), color: Colors.black), viewReady: ready)));
      await tester.pump();
      expect(find.byKey(const Key('mirror')), findsOneWidget);
      expect(tester.getRect(find.text('Stop gamepad')).bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink()); ready.dispose();
    }
    tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
  });
  testWidgets('losing desktop view releases active gamepad without automatic reacquisition', (tester) async {
    final client = FakeClient(); final ready = ValueNotifier(true);
    await tester.pumpWidget(MaterialApp(home: GamepadPage(client: client, instance: 'one', character: 'Character',
      liveView: const ColoredBox(color: Colors.black), viewReady: ready)));
    await tester.tap(find.text('Start gamepad')); await tester.pump();
    client.socket.poll(1); await tester.pump();
    expect(client.opened, 1);
    ready.value = false; await tester.pump();
    expect(client.socket.closed, isTrue);
    ready.value = true; await tester.pump();
    expect(client.opened, 1);
    await tester.pumpWidget(const SizedBox.shrink()); ready.dispose();
  });
  testWidgets('desktop taps map to the actual image rectangle', (tester) async {
    final client = DesktopClient(); final desktop = DesktopController(client);
    await desktop.connect();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 640, height: 360, child: DesktopSurface(controller: desktop)))));
    await tester.pumpAndSettle();
    final image = find.byType(Image);
    final rectangle = tester.getRect(image);
    await tester.tapAt(Offset(rectangle.left + rectangle.width * .25, rectangle.top + rectangle.height * .75));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    final tap = client.sockets.single.sent.where((r) => r['kind'] == 'tap').single;
    expect(tap['x'], closeTo(.25, .01)); expect(tap['y'], closeTo(.75, .01));
    await tester.pumpWidget(const SizedBox.shrink()); desktop.dispose();
  });
  testWidgets('typing dialog clears on phone background', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showDialog<void>(context: context, builder: (_) => const DesktopTyping()), child: const Text('Type'))))));
    await tester.tap(find.text('Type')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test-only-secret');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
