import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'protocol.dart';

/// Local touch state only. It is never retried, persisted or automatically reacquired.
class PadState {
  double lx = 0, ly = 0, rx = 0, ry = 0;
  final Map<int, int> held = {};
  int get buttons => held.values.where((bit) => bit > 0).fold(0, (a, b) => a | b) & 0xF3FF;
  void clear() { lx = ly = rx = ry = 0; held.clear(); }
  Map<String, dynamic> reply(Map<String, dynamic> poll) {
    if (poll.length != 3 || poll['version'] != 1 || poll['sequence'] is! int ||
        (poll['sequence'] as int) <= 0 || poll['challenge'] is! String ||
        !RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(poll['challenge'] as String)) {
      throw const RemoteFailure('invalid_response');
    }
    return {...poll, 'leftX': lx, 'leftY': ly, 'rightX': rx, 'rightY': ry,
      'leftTrigger': held.values.contains(-1) ? 1.0 : 0.0,
      'rightTrigger': held.values.contains(-2) ? 1.0 : 0.0,
      'buttons': buttons};
  }
}

class GamepadPage extends StatefulWidget {
  final RemoteClient client;
  final String instance;
  final String character;
  final Widget? liveView;
  final ValueListenable<bool>? viewReady;
  const GamepadPage({super.key, required this.client, required this.instance, required this.character, this.liveView, this.viewReady});
  @override
  State<GamepadPage> createState() => _GamepadPageState();
}
class _GamepadPageState extends State<GamepadPage> with WidgetsBindingObserver {
  final pad = PadState();
  WebSocket? socket;
  Timer? watchdog;
  bool active = false, connecting = false, foreground = true, closing = false;
  int generation = 0, lastSequence = 0;
  final Stopwatch elapsed = Stopwatch()..start();
  int lastPollMs = 0;
  String message = 'Trust this phone once in the PC app, then start here. For minimized control, enable FFXIV’s inactive-client gamepad setting.';
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this); widget.viewReady?.addListener(viewChanged);
    if (widget.liveView != null) { message = 'Start gamepad after your enrolled character connects.'; }
  }
  void viewChanged() {
    if (widget.viewReady?.value == false && (active || connecting)) { stop('Desktop view stopped. Controls released.'); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) stop('Controls released · tap Start again when ready.');
  }
  @override
  void didChangeMetrics() {
    if (active || connecting) stop('Screen changed. Controls released; tap Start when ready.');
  }
  void stop(String text) {
    generation++; watchdog?.cancel(); watchdog = null;
    pad.clear(); final current = socket; socket = null;
    current?.close(WebSocketStatus.normalClosure);
    if (mounted && !closing) setState(() { active = connecting = false; message = text; });
  }
  Future<void> start() async {
    if (active || connecting || !foreground || widget.viewReady?.value == false) return;
    final epoch = ++generation;
    pad.clear(); lastSequence = 0;
    setState(() { connecting = true; message = 'Connecting the controller to your approved character…'; });
    try {
      final opened = await widget.client.openGamepad();
      if (!mounted || epoch != generation || !foreground) { opened.close(); return; }
      socket = opened;
      opened.add(jsonEncode({'version': 1, 'instanceId': widget.instance}));
      lastPollMs = elapsed.elapsedMilliseconds;
      watchdog = Timer.periodic(const Duration(milliseconds: 100), (_) {
        final limit = connecting ? 12000 : 500;
        if (elapsed.elapsedMilliseconds - lastPollMs >= limit) stop('Connection paused. Controls released; tap Start to reconnect.');
      });
      opened.listen((data) {
        if (!mounted || epoch != generation || !foreground) return;
        try {
          if (data is! String || data.length > 512) throw const RemoteFailure('invalid_response');
          final poll = jsonDecode(data) as Map<String, dynamic>;
          final reply = pad.reply(poll);
          if ((poll['sequence'] as int) != lastSequence + 1) throw const RemoteFailure('invalid_response');
          lastSequence = poll['sequence'] as int;
          lastPollMs = elapsed.elapsedMilliseconds;
          opened.add(jsonEncode(reply)); // Only respond to a fresh server poll; no frame timer/backlog.
          if (!active) setState(() { active = true; connecting = false; message = 'Gamepad active · Stop releases all controls'; });
        } catch (_) { stop('Controls released. Reopen controls and try again.'); }
      }, onDone: () {
        if (epoch == generation) stop('Controls released. Check trusted phone access, one running game, unlocked Windows, and Tailscale; tap Start to try again.');
      }, onError: (Object _) {
        if (epoch == generation) stop('Connection lost. Controls released; tap Start to reconnect.');
      }, cancelOnError: true);
    } catch (_) {
      if (mounted && epoch == generation) stop('Could not start. Check that the PC is connected and this phone is trusted.');
    }
  }
  @override
  void dispose() {
    closing = true; widget.viewReady?.removeListener(viewChanged); stop(''); elapsed.stop();
    WidgetsBinding.instance.removeObserver(this); super.dispose();
  }
  Widget hold(String label, int bit) => GestureDetector(onPanUpdate: (_) {}, child: Listener(
    onPointerDown: active ? (event) { setState(() { pad.held[event.pointer] = bit; }); } : null,
    onPointerUp: (event) { if (mounted) setState(() { pad.held.remove(event.pointer); }); },
    onPointerCancel: (event) { if (mounted) setState(() { pad.held.remove(event.pointer); }); },
    child: Semantics(label: label, button: true, enabled: active, child: Container(
      width: 64, height: 54, alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10), margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: !active ? Colors.white10 : pad.held.values.contains(bit) ? const Color(0xFF8862B8) : const Color(0xFF352743),
        borderRadius: BorderRadius.circular(14)), child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white38))))));
  Widget controls() => SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      TouchStick(label: 'Move', enabled: active, onChanged: (x, y) { pad.lx = x; pad.ly = y; }),
      TouchStick(label: 'Camera', enabled: active, onChanged: (x, y) { pad.rx = x; pad.ry = y; }),
    ]),
    const SizedBox(height: 12),
    Wrap(alignment: WrapAlignment.center, children: [
      hold('↑', 1), hold('↓', 2), hold('←', 4), hold('→', 8),
      hold('A', 0x1000), hold('B', 0x2000), hold('X', 0x4000), hold('Y', 0x8000),
      hold('LB', 0x100), hold('RB', 0x200), hold('LT', -1), hold('RT', -2),
      hold('L3', 0x40), hold('R3', 0x80), hold('View', 0x20), hold('Menu', 0x10),
    ]),
    const SizedBox(height: 12),
    const Text('Leaving controls, locking the phone or losing the connection releases the gamepad.',
      textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
  ])));
  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, result) { if (didPop) stop('Controls released.'); },
    child: Scaffold(
      appBar: AppBar(title: Text(widget.character, overflow: TextOverflow.ellipsis)),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: Text(message, maxLines: 3, textAlign: TextAlign.center)),
        Wrap(spacing: 12, children: [
          FilledButton(onPressed: active || connecting ? null : start, child: const Text('Start gamepad')),
          OutlinedButton(onPressed: () => stop('Controls released · tap Start to begin a new session.'), child: const Text('Stop gamepad')),
        ]),
        Expanded(child: widget.liveView == null ? controls() : LayoutBuilder(builder: (context, area) {
          final view = Expanded(child: widget.liveView!);
          final pad = Expanded(child: controls());
          return area.maxWidth > area.maxHeight * 1.5
            ? Row(children: [view, pad]) : Column(children: [view, pad]);
        })),
      ])),
    ));

}

class TouchStick extends StatefulWidget {
  final String label;
  final bool enabled;
  final void Function(double, double) onChanged;
  const TouchStick({super.key, required this.label, required this.enabled, required this.onChanged});
  @override
  State<TouchStick> createState() => _TouchStickState();
}
class _TouchStickState extends State<TouchStick> {
  int? pointer;
  Offset position = Offset.zero;
  void release() { pointer = null; position = Offset.zero; widget.onChanged(0, 0); }
  @override
  void didUpdateWidget(TouchStick oldWidget) { super.didUpdateWidget(oldWidget); if (!widget.enabled) release(); }
  void update(Offset point) {
    var delta = (point - const Offset(65, 65)) / 45;
    if (delta.distance > 1) delta /= delta.distance;
    setState(() { position = delta; });
    widget.onChanged(delta.dx, -delta.dy);
  }
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(widget.label), const SizedBox(height: 8),
    GestureDetector(onPanUpdate: (_) {}, child: Listener(behavior: HitTestBehavior.opaque,
      onPointerDown: (event) { if (!widget.enabled || pointer != null) return; pointer = event.pointer; update(event.localPosition); },
      onPointerMove: (event) { if (widget.enabled && pointer == event.pointer) update(event.localPosition); },
      onPointerUp: (event) { if (pointer == event.pointer) setState(release); },
      onPointerCancel: (event) { if (pointer == event.pointer) setState(release); },
      child: Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle,
        color: widget.enabled ? const Color(0xFF352743) : Colors.white10),
        child: Center(child: Transform.translate(offset: position * 45,
          child: Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle,
            color: widget.enabled ? const Color(0xFFAC8CF2) : Colors.white24))))))),
  ]);
}
