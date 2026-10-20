import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel_remote/gamepad.dart';
import 'package:sentinel_remote/protocol.dart';

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
}
