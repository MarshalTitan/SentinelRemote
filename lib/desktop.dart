import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'protocol.dart';
import 'gamepad.dart';

class DesktopController extends ChangeNotifier {
  final RemoteClient client;
  DesktopController(this.client);
  final ready = ValueNotifier<bool>(false);
  final Stopwatch clock = Stopwatch()..start();
  WebSocket? socket;
  Timer? timer, retry;
  final List<Completer<Map<String, dynamic>>> pending = [];
  Uint8List? jpeg;
  String? frameId;
  int width = 1, height = 1, sequence = 0, generation = 0, received = 0, attempts = 0;
  bool connecting = false, framePending = false, actionPending = false, disposed = false, wanted = false;
  String message = 'Connecting to your trusted PC…';
  bool get fresh => ready.value && clock.elapsedMilliseconds - received < 1800;
  void changed() { if (!disposed) notifyListeners(); }
  void clearImage() {
    final old = jpeg;
    jpeg = null; frameId = null; ready.value = false;
    if (old != null) { MemoryImage(old).evict(); }
  }
  void disconnect(String text, {bool reconnect = false}) {
    generation++; timer?.cancel(); timer = null;
    retry?.cancel(); retry = null;
    socket?.close(); socket = null;
    for (final request in pending.toList()) { if (!request.isCompleted) request.completeError(const RemoteFailure('connection_lost')); }
    pending.clear(); connecting = framePending = actionPending = false;
    clearImage(); message = text; changed();
    if (reconnect && wanted && !disposed) {
      attempts = (attempts + 1).clamp(1, 6);
      final seconds = [1, 2, 4, 8, 16, 30][attempts - 1];
      retry = Timer(Duration(seconds: seconds), () { if (wanted) connect(resetAttempts: false); });
    }
  }
  void stop([String text = 'Desktop stopped. Tap Connect to resume.']) { wanted = false; attempts = 0; disconnect(text); }
  Future<void> connect({bool resetAttempts = true}) async {
    if (connecting || disposed) { return; }
    disconnect('Connecting to your PC…');
    wanted = true;
    if (resetAttempts) { attempts = 0; }
    connecting = true; changed();
    final epoch = generation;
    try {
      final opened = await client.openDesktop();
      if (disposed || epoch != generation || !wanted) { opened.close(); return; }
      socket = opened; sequence = 0;
      final hello = Completer<Map<String, dynamic>>();
      pending.add(hello);
      opened.listen((data) {
        if (epoch != generation || disposed) { return; }
        try {
          if (data is! String || data.length > 450000 || pending.isEmpty) { throw const RemoteFailure('invalid_response'); }
          final reply = jsonDecode(data) as Map<String, dynamic>;
          if (reply['success'] is! bool || reply['code'] is! String) { throw const RemoteFailure('invalid_response'); }
          final request = pending.removeAt(0);
          if (reply['success'] == true) { request.complete(reply); }
          else { request.completeError(RemoteFailure(reply['code'] as String)); }
        } catch (_) { disconnect('Desktop response was invalid.', reconnect: true); }
      }, onDone: () {
        if (epoch == generation) { disconnect('Desktop disconnected. Reconnecting view…', reconnect: true); }
      }, onError: (Object _) {
        if (epoch == generation) { disconnect('Desktop connection lost.', reconnect: true); }
      }, cancelOnError: true);
      final greeting = await hello.future.timeout(const Duration(seconds: 8));
      if (greeting['code'] != 'desktop_ready') { throw const RemoteFailure('invalid_response'); }
      if (epoch != generation) { return; }
      connecting = false; message = 'Loading desktop…'; changed();
      await capture();
      if (epoch != generation) { return; }
      timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        if (jpeg != null && !fresh) { disconnect('View became stale. Reconnecting view…', reconnect: true); return; }
        if (!framePending) { capture(); }
      });
    } catch (error) {
      if (epoch == generation && !disposed) {
        final denied = error is RemoteFailure && (error.code == 'desktop_not_permitted' || error.code == 'unauthorized');
        disconnect(denied ? 'In the PC app, select this phone and choose Trust selected phone once.' : 'Desktop unavailable. Check the PC and tap Connect.',
          reconnect: !denied);
      }
    }
  }
  Future<Map<String, dynamic>> request(String kind, Map<String, dynamic> fields) {
    if (socket == null || pending.length >= 2) { return Future.error(const RemoteFailure('connection_lost')); }
    final completion = Completer<Map<String, dynamic>>();
    pending.add(completion);
    socket!.add(jsonEncode({'version': 1, 'sequence': ++sequence, 'kind': kind, ...fields}));
    return completion.future.timeout(const Duration(seconds: 3));
  }
  Future<void> capture() async {
    if (framePending || socket == null || disposed) { return; }
    final epoch = generation; framePending = true;
    try {
      final reply = await request('frame', {});
      if (epoch != generation || disposed) { return; }
      final data = reply['data'] as Map<String, dynamic>;
      final w = data['width'], h = data['height'], id = data['frameId'], encoded = data['jpegBase64'];
      if (w is! int || h is! int || w < 1 || w > 1280 || h < 1 || h > 720 || id is! String ||
          !RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(id) || encoded is! String || encoded.length > 440000) {
        throw const RemoteFailure('invalid_response');
      }
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty || bytes.length > 327680) { throw const RemoteFailure('invalid_response'); }
      final old = jpeg; jpeg = bytes; width = w; height = h; frameId = id;
      received = clock.elapsedMilliseconds; ready.value = true; attempts = 0;
      message = 'Desktop live · tap to click · double-tap to open · hold for right-click';
      if (old != null) { MemoryImage(old).evict(); }
      changed();
    } catch (_) {
      if (epoch == generation && !disposed) { disconnect('Desktop capture unavailable. Reconnecting view…', reconnect: true); }
    } finally { if (epoch == generation) { framePending = false; } }
  }
  Future<void> act(String kind, {double? x, double? y, String? key, String? text}) async {
    if (!fresh || actionPending || socket == null) { return; }
    final epoch = generation; actionPending = true;
    try {
      await request(kind, {'frameId': frameId, 'x': ?x, 'y': ?y, 'key': ?key, 'text': ?text});
    } catch (_) {
      if (epoch == generation && !disposed) { disconnect('Input could not be confirmed. It was not retried. Reconnect and check the screen.'); }
    } finally { if (epoch == generation) { actionPending = false; } }
  }
  @override
  void dispose() { wanted = false; disconnect(''); disposed = true; ready.dispose(); clock.stop(); super.dispose(); }
}

class DesktopSurface extends StatefulWidget {
  final DesktopController controller;
  const DesktopSurface({super.key, required this.controller});
  @override
  State<DesktopSurface> createState() => _DesktopSurfaceState();
}
class _DesktopSurfaceState extends State<DesktopSurface> {
  Offset? doublePoint;
  DesktopController get controller => widget.controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: controller, builder: (context, _) {
    final bytes = controller.jpeg;
    if (bytes == null) { return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(controller.message, textAlign: TextAlign.center))); }
    return InteractiveViewer(minScale: 1, maxScale: 5, child: Center(child: AspectRatio(
      aspectRatio: controller.width / controller.height,
      child: LayoutBuilder(builder: (context, area) {
        void click(String kind, Offset point) {
          controller.act(kind, x: (point.dx / area.maxWidth).clamp(0.0, 1.0).toDouble(),
            y: (point.dy / area.maxHeight).clamp(0.0, 1.0));
        }
        return GestureDetector(
          onTapUp: (event) => click('tap', event.localPosition),
          onDoubleTapDown: (event) { doublePoint = event.localPosition; },
          onDoubleTap: () { if (doublePoint != null) { click('doubleTap', doublePoint!); } },
          onLongPressStart: (event) => click('rightClick', event.localPosition),
          child: Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Center(child: Text('Desktop image could not be displayed.'))),
        );
      }),
    )));
  });
}

class DesktopPage extends StatefulWidget {
  final RemoteClient client;
  final String? instance;
  final String character;
  const DesktopPage({super.key, required this.client, this.instance, required this.character});
  @override
  State<DesktopPage> createState() => _DesktopPageState();
}
class _DesktopPageState extends State<DesktopPage> with WidgetsBindingObserver {
  late final DesktopController desktop;
  Timer? gameTimer;
  String? instance;
  late String character;
  bool gameReady = false, checkingGame = false, inGamepad = false, active = true, resumeView = false;
  int gameEpoch = 0;
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    instance = widget.instance; character = widget.character;
    desktop = DesktopController(widget.client); desktop.connect();
    checkGame();
    gameTimer = Timer.periodic(const Duration(seconds: 5), (_) { checkGame(); });
  }
  Future<void> checkGame() async {
    if (!active || checkingGame || inGamepad || !mounted) { return; }
    final epoch = gameEpoch;
    setState(() { checkingGame = true; });
    try {
      final rows = ((await widget.client.read('instances.list')) as List).cast<Map<String, dynamic>>();
      final next = rows.where((r) => r['instanceId'] == instance).firstOrNull ?? rows.firstOrNull;
      final id = next?['instanceId'] as String?;
      final detail = id == null ? null : await widget.client.read('srank.status', instance: id) as Map<String, dynamic>;
      if (!mounted || !active || epoch != gameEpoch) { return; }
      setState(() {
        instance = id;
        character = detail?['character'] as String? ?? next?['label'] as String? ?? widget.character;
        gameReady = detail?['relayStatus'] == 'connected';
      });
    } catch (_) {
      if (mounted && epoch == gameEpoch) { setState(() { gameReady = false; }); }
    } finally {
      if (mounted && epoch == gameEpoch) { setState(() { checkingGame = false; }); }
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (!active) {
      if (desktop.wanted) { resumeView = true; }
      gameEpoch++; checkingGame = false;
      desktop.stop('Desktop paused while the phone is in the background.');
    } else {
      if (resumeView) { resumeView = false; desktop.connect(); }
      checkGame();
    }
  }
  @override
  void dispose() { gameEpoch++; gameTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); desktop.dispose(); super.dispose(); }
  Future<void> keyboard() async {
    if (!desktop.fresh) { return; }
    final text = await showDialog<String>(context: context, builder: (_) => const DesktopTyping());
    if (text != null && text.isNotEmpty && mounted) { await desktop.act('text', text: text); }
  }
  Future<void> gamepad() async {
    if (checkingGame || !desktop.fresh) { return; }
    await checkGame();
    if (!mounted || !active || !gameReady || instance == null || !desktop.fresh) { return; }
    inGamepad = true;
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => GamepadPage(
      client: widget.client, instance: instance!, character: character,
      liveView: DesktopSurface(controller: desktop), viewReady: desktop.ready)));
    inGamepad = false;
    if (mounted && active) { checkGame(); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Desktop'), actions: [
      IconButton(onPressed: keyboard, icon: const Icon(Icons.keyboard), tooltip: 'Type on PC'),
      IconButton(onPressed: !gameReady || checkingGame ? null : gamepad, icon: const Icon(Icons.sports_esports), tooltip: 'Gamepad with live view'),
    ]),
    body: SafeArea(child: Column(children: [
      Expanded(child: DesktopSurface(controller: desktop)),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final key in ['Start', 'Tab', 'Enter', 'Escape', 'Backspace', 'ScrollUp', 'ScrollDown'])
          TextButton(onPressed: () => desktop.act('key', key: key), child: Text(key)),
      ])),
      ListenableBuilder(listenable: desktop, builder: (context, _) => Padding(padding: const EdgeInsets.all(8), child: Text(desktop.message, maxLines: 3, textAlign: TextAlign.center))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(
        gameReady ? 'Gamepad ready · $character' : 'Gamepad appears when an approved character connects.',
        textAlign: TextAlign.center)),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        FilledButton(onPressed: () => desktop.connect(), child: const Text('Connect')),
        OutlinedButton(onPressed: desktop.stop, child: const Text('Stop desktop')),
      ]),
      const SizedBox(height: 8),
    ])),
  );
}

class DesktopTyping extends StatefulWidget {
  const DesktopTyping({super.key});
  @override
  State<DesktopTyping> createState() => _DesktopTypingState();
}
class _DesktopTypingState extends State<DesktopTyping> with WidgetsBindingObserver {
  final text = TextEditingController();
  bool hidden = true;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      text.clear();
      if (mounted && ModalRoute.of(context)?.isCurrent == true) { Navigator.pop(context); }
    }
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); text.clear(); text.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Type into the selected PC field'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: text, autofocus: true, obscureText: hidden, maxLength: 256,
        autocorrect: false, enableSuggestions: false, autofillHints: const []),
      CheckboxListTile(value: hidden, onChanged: (value) => setState(() { hidden = value ?? true; }), title: const Text('Hide typing')),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Send once')),
    ],
  );
}
