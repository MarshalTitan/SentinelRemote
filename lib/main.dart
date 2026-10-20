import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'protocol.dart';
import 'vault.dart';
import 'gamepad.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const SentinelRemoteApp()); }

class SentinelRemoteApp extends StatelessWidget {
  const SentinelRemoteApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sentinel Remote', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, colorSchemeSeed: const Color(0xFFAC8CF2),
      scaffoldBackgroundColor: const Color(0xFF11101C), useMaterial3: true,
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 6))),
    home: const RemoteHome());
}

class RemoteHome extends StatefulWidget {
  const RemoteHome({super.key});
  @override
  State<RemoteHome> createState() => _RemoteHomeState();
}
class _RemoteHomeState extends State<RemoteHome> with WidgetsBindingObserver {
  final _vault = const HostVault();
  final _transport = PrivateHttpsTransport();
  List<PairedHost> _hosts = [];
  RemoteClient? _client;
  List<Map<String, dynamic>> _instances = [];
  String? _selected;
  Map<String, dynamic>? _detail;
  Uint8List? _image;
  String _message = 'Loading paired PCs…';
  bool _busy = false;
  bool _active = true;
  bool _controlling = false;
  Timer? _timer;
  int _viewEpoch = 0;
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) { if (_active && !_busy && !_controlling && _client != null) { _refresh(); } });
  }
  Future<void> _load() async {
    try {
      final hosts = await _vault.load();
      if (!mounted) return;
      setState(() { _hosts = hosts; _message = hosts.isEmpty ? 'Pair a PC to get started.' : 'Choose a paired PC.'; });
      if (hosts.isNotEmpty) _chooseHost(hosts.first);
    } catch (_) { if (mounted) setState(() { _message = 'Secure storage is unavailable. Unlock the phone and reopen the app.'; }); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _viewEpoch++; _client?.disconnect();
      if (mounted) setState(() { _image = null; _detail = null; _message = 'Paused · reconnect when you return'; });
    } else if (!_busy && !_controlling && _client != null) { _refresh(); }
  }
  @override
  void dispose() { _timer?.cancel(); _client?.disconnect(); _transport.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  void _chooseHost(PairedHost host) {
    _viewEpoch++; _client?.disconnect();
    setState(() { _client = RemoteClient(host, _transport); _selected = null; _instances = []; _detail = null; _image = null; });
    _refresh();
  }
  Future<void> _run(Future<void> Function(RemoteClient, int) action) async {
    if (_busy || _client == null || !_active) return;
    final client = _client!; final epoch = _viewEpoch;
    setState(() { _busy = true; });
    try { await action(client, epoch); }
    catch (e) {
      if (mounted && epoch == _viewEpoch) setState(() { _detail = null; _message = _friendly(e); });
    } finally { if (mounted) setState(() { _busy = false; }); }
  }
  bool _current(int epoch) => mounted && _active && epoch == _viewEpoch;
  Future<void> _refresh() => _run((client, epoch) async {
    await client.request('session.ping');
    final rows = ((await client.request('instances.list')) as List).cast<Map<String, dynamic>>();
    if (!_current(epoch)) return;
    setState(() { _instances = rows; _selected ??= rows.isEmpty ? null : rows.first['instanceId'] as String; _message = 'PC connected · updated ${TimeOfDay.now().format(context)}'; });
    if (_selected != null) await _status(client, epoch, _selected!);
  });
  Future<void> _status(RemoteClient client, int epoch, String instance) async {
    final detail = await client.request('srank.status', instance: instance) as Map<String, dynamic>;
    if (_current(epoch) && _selected == instance) setState(() { _detail = detail; });
  }
  Future<void> _gamepad() async {
    final client = _client; final instance = _selected;
    if (client == null || instance == null || _busy || !_active) return;
    setState(() { _controlling = true; });
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => GamepadPage(
      client: client, instance: instance, character: _detail?['character'] as String? ?? 'Gamepad')));
    if (mounted) { setState(() { _controlling = false; }); if (_active) _refresh(); }
  }
  Future<void> _command(String operation) => _run((client, epoch) async {
    final instance = _selected; if (instance == null) return;
    final data = await client.request(operation, instance: instance);
    if (!_current(epoch) || _selected != instance) return;
    if (operation == 'screenshot') {
      final png = (data as Map<String, dynamic>)['pngBase64'] as String;
      if (png.length > 10000000) throw const RemoteFailure('response_too_large');
      setState(() { _image = base64Decode(png); _message = 'Screenshot received · ${TimeOfDay.now().format(context)}'; });
    } else { setState(() { _message = 'Request completed. Refreshing status…'; }); await _status(client, epoch, instance); }
  });
  Future<void> _reset() => _run((client, epoch) async {
    final instance = _selected; if (instance == null) return;
    final pending = await client.request('srank.reset.request', instance: instance) as Map<String, dynamic>;
    if (!mounted || !_current(epoch)) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Reset this character?'), content: const Text('Stop the current hunt and reset through Ul’dah. Confirm within 30 seconds.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop + reset'))]));
    if (confirmed != true || !_current(epoch) || _selected != instance) return;
    await client.request('srank.reset.confirm', instance: instance, confirmation: pending['confirmation'] as String);
    if (_current(epoch)) { setState(() { _message = 'Reset requested. Refreshing status…'; }); await _status(client, epoch, instance); }
  });
  Future<void> _pair() async {
    final host = await showDialog<PairedHost>(context: context, builder: (_) => PairDialog(transport: _transport));
    if (host == null || !mounted) return;
    final hosts = [..._hosts.where((h) => h.hostId != host.hostId), host];
    try { await _vault.save(hosts); if (!mounted) return; setState(() { _hosts = hosts; }); _chooseHost(host); }
    catch (_) { if (mounted) setState(() { _message = 'Could not save pairing securely. Revoke this phone on the PC and pair again.'; }); }
  }
  Future<void> _forget() async {
    final host = _client?.host; if (host == null) return;
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Forget this PC?'),
      content: const Text('This removes the saved phone credential. Revoke the device on the PC as well.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Forget'))]));
    if (yes != true) return;
    final hosts = _hosts.where((h) => h != host).toList();
    try { await _vault.save(hosts); }
    catch (_) { if (mounted) setState(() { _message = 'Secure storage is unavailable. The pairing was retained.'; }); return; }
    _viewEpoch++; _client?.disconnect();
    if (!mounted) return;
    setState(() { _hosts = hosts; _client = null; _instances = []; _detail = null; _selected = null; _image = null; _message = 'Pairing removed.'; });
  }
  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final srank = detail?['srank'] as Map<String, dynamic>?;
    final ready = detail?['relayStatus'] == 'connected';
    return Scaffold(appBar: AppBar(title: const Text('Sentinel Remote'), actions: [
      IconButton(onPressed: _busy ? null : _pair, icon: const Icon(Icons.add_link), tooltip: 'Pair a PC'),
      IconButton(onPressed: _busy || _client == null ? null : _forget, icon: const Icon(Icons.link_off), tooltip: 'Forget PC')]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Text('YOUR CHARACTERS', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: const Color(0xFFC7B1F6))),
        const SizedBox(height: 12),
        if (_hosts.isNotEmpty) DropdownButtonFormField<PairedHost>(initialValue: _client?.host, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Paired PC', border: OutlineInputBorder()),
          items: _hosts.map((h) => DropdownMenuItem(value: h, child: Text(h.label, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: _busy ? null : (host) { if (host != null) _chooseHost(host); }),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: Text(_message)), IconButton(onPressed: _busy || _client == null ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh')]),
        if (_busy) const LinearProgressIndicator(),
        if (_instances.isEmpty && !_busy) Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(_client == null ? 'Pair your PC with a one-time invitation created locally.' : 'No authorized game clients. Check the device grants on your PC.'))),
        for (final instance in _instances) Card(clipBehavior: Clip.antiAlias, color: _selected == instance['instanceId'] ? const Color(0xFF302641) : null,
          child: ListTile(leading: Icon(Icons.shield_outlined, color: _selected == instance['instanceId'] ? const Color(0xFFC9ABFF) : null),
            title: Text(instance['label'] as String), subtitle: Text(_selected == instance['instanceId'] && ready ? 'Relay connected' : 'Select to check status'),
            selected: _selected == instance['instanceId'], onTap: _busy ? null : () {
              _viewEpoch++; setState(() { _selected = instance['instanceId'] as String; _detail = null; _image = null; }); _refresh();
            })),
        if (detail != null) Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(detail['character'] as String? ?? 'Character unavailable', style: Theme.of(context).textTheme.titleLarge),
          if (!ready) const Text('Last known values · Relay unavailable', style: TextStyle(color: Colors.orangeAccent)),
          const SizedBox(height: 12),
          _line('FFXIV', detail['processStatus']), _line('Relay', detail['relayStatus']),
          _line('World', detail['world']), _line('Map', detail['map']),
          _line('Territory', detail['territory']), _line('Profile', detail['profile']),
          _line('S Rank', srank?['state']), _line('vnavmesh', detail['vnavmesh']),
          _line('Heartbeat', detail['heartbeatUtc']),
        ]))),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.tonalIcon(onPressed: _busy || !ready ? null : _gamepad, icon: const Icon(Icons.sports_esports), label: const Text('Gamepad')),
          FilledButton.tonalIcon(onPressed: _busy || !ready ? null : () => _command('screenshot'), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Screenshot')),
          FilledButton.tonal(onPressed: _busy || !ready ? null : () => _command('srank.skip'), child: const Text('Skip + keep queue')),
          OutlinedButton(onPressed: _busy || !ready ? null : _reset, child: const Text('Stop + reset'))]),
        if (_image != null) Padding(padding: const EdgeInsets.only(top: 18), child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(_image!, gaplessPlayback: false,
          errorBuilder: (_, _, _) => const Text('Screenshot could not be displayed.')))),
        const SizedBox(height: 24), const Text('Gamepad controls are a preview requiring local PC permission. Live game view and launcher recovery follow later.', style: TextStyle(color: Colors.white54)),
      ])));
  }
  Widget _line(String label, dynamic value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start,
    children: [SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.white60))), Expanded(child: Text(value?.toString() ?? 'Unknown'))]));
}

String _friendly(Object error) {
  if (error is! RemoteFailure) return 'The request could not be completed.';
  return switch (error.code) {
    'connection_lost' => 'PC unreachable. Check Tailscale and the Remote host. Commands are not retried.',
    'unauthorized' => 'Session expired or this phone was revoked. Refresh or pair again locally.',
    'remote_disabled' => 'Remote access is disabled on this PC.',
    'bridge_unavailable' => 'PC connected · game bridge unavailable. Check the game and per-character mobile opt-in.',
    'process_exited' => 'FFXIV has exited. Launcher recovery is not available in this build.',
    'ambiguous_client' => 'More than one game matched. Rebind the installation locally.',
    'control_not_authorized' => 'This phone has view permission. Enable control locally on the PC to use this action.',
    'screenshot_disabled' => 'Enable mobile screenshots for this character in Relay.',
    'confirmation_rejected' || 'character_changed' => 'Confirmation expired or the character changed. Refresh status and try again.',
    'pairing_rejected' => 'Invitation expired or already used. Create a fresh invitation on the PC.',
    'rate_limited' || 'cooldown' => 'Please wait before sending another request.',
    'invalid_private_https_url' => 'Enter the PC’s HTTPS Tailscale address ending in .ts.net.',
    'invalid_pairing' => 'Enter a PC label and the complete 64-character invitation.',
    'protocol_mismatch' => 'Update the app and PC host to compatible versions.',
    'host_identity_changed' => 'PC identity changed. Revoke the old pairing and pair locally again.',
    _ => 'Request failed safely. Check the PC and refresh status.',
  };
}

class PairDialog extends StatefulWidget {
  final JsonTransport transport;
  const PairDialog({super.key, required this.transport});
  @override
  State<PairDialog> createState() => _PairDialogState();
}
class _PairDialogState extends State<PairDialog> {
  final _url = TextEditingController(); final _label = TextEditingController(); final _invite = TextEditingController();
  bool _busy = false; String? _error;
  @override
  void dispose() { _url.dispose(); _label.dispose(); _invite.clear(); _invite.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: AlertDialog(title: const Text('Pair your PC'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Use the private HTTPS address and one-time invitation shown on your PC.'), const SizedBox(height: 16),
      TextField(controller: _label, enabled: !_busy, maxLength: 64, decoration: const InputDecoration(labelText: 'PC label')),
      TextField(controller: _url, enabled: !_busy, autocorrect: false, enableSuggestions: false, keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'https://your-pc.tailnet.ts.net')),
      TextField(controller: _invite, enabled: !_busy, obscureText: true, autocorrect: false, enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'One-time invitation')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent))),
      if (_busy) const LinearProgressIndicator(),
    ])), actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : () async {
        setState(() { _busy = true; _error = null; });
        try {
          final host = await RemoteClient.pair(widget.transport, _url.text, _label.text, _invite.text);
          if (context.mounted) Navigator.pop(context, host);
        } catch (e) { if (mounted) setState(() { _busy = false; _invite.clear(); _error = _friendly(e); }); }
      }, child: const Text('Pair'))]));
}
