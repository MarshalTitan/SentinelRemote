import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RemoteFailure implements Exception {
  final String code;
  const RemoteFailure(this.code);
}

Uri remoteOrigin(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || uri.scheme != 'https' ||
      !uri.host.endsWith('.ts.net') || uri.userInfo.isNotEmpty ||
      uri.hasQuery || uri.hasFragment || (uri.path != '' && uri.path != '/') ||
      (uri.hasPort && uri.port != 443)) {
    throw const RemoteFailure('invalid_private_https_url');
  }
  return Uri(scheme: 'https', host: uri.host);
}

abstract interface class JsonTransport {
  Future<Map<String, dynamic>> post(Uri origin, String path,
      Map<String, dynamic> body, String? credential);
  void cancel();
}

class PrivateHttpsTransport implements JsonTransport {
  final Set<HttpClient> _active = {};
  @override
  Future<Map<String, dynamic>> post(Uri origin, String path,
      Map<String, dynamic> body, String? credential) async {
    remoteOrigin(origin.toString());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    _active.add(client);
    try {
      return await (() async {
        final request = await client.postUrl(origin.resolve(path));
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        if (credential != null) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $credential');
        }
        request.add(utf8.encode(jsonEncode(body)));
        final response = await request.close();
        if (response.isRedirect) throw const RemoteFailure('redirect_rejected');
        if (response.contentLength > 11000000) {
          throw const RemoteFailure('response_too_large');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 11000000) {
            throw const RemoteFailure('response_too_large');
          }
          bytes.addAll(chunk);
        }
        if (response.statusCode == 429) throw const RemoteFailure('rate_limited');
        final value = jsonDecode(utf8.decode(bytes));
        if (value is! Map<String, dynamic> || value['success'] is! bool || value['code'] is! String) {
          throw const RemoteFailure('invalid_response');
        }
        if (value['success'] != true) {
          const safeCodes = {'unauthorized', 'remote_disabled', 'pairing_rejected',
            'protocol_mismatch', 'instance_not_authorized', 'control_not_authorized',
            'replay_rejected', 'confirmation_rejected', 'bridge_unavailable',
            'state_unavailable', 'character_changed', 'plugin_disabled', 'operation_failed',
            'screenshot_disabled', 'capture_failed', 'cooldown', 'ambiguous_client', 'process_exited'};
          throw RemoteFailure(safeCodes.contains(value['code']) ? value['code'] as String : 'operation_failed');
        }
        return value;
      })().timeout(const Duration(seconds: 12));
    } on RemoteFailure {
      rethrow;
    } catch (_) {
      throw const RemoteFailure('connection_lost');
    } finally {
      _active.remove(client);
      client.close(force: true);
    }
  }
  @override
  void cancel() { for (final client in _active.toList()) { client.close(force: true); } }
}

class PairedHost {
  final String label;
  final Uri origin;
  final String deviceId;
  final String deviceToken;
  final String hostId;
  const PairedHost(this.label, this.origin, this.deviceId, this.deviceToken, this.hostId);
  Map<String, dynamic> toJson() => {'label': label, 'origin': origin.toString(),
    'deviceId': deviceId, 'deviceToken': deviceToken, 'hostId': hostId};
  factory PairedHost.fromJson(Map<String, dynamic> json) => PairedHost(
    json['label'] as String, remoteOrigin(json['origin'] as String),
    json['deviceId'] as String, json['deviceToken'] as String, json['hostId'] as String);
  // Intentionally no credential-bearing toString/diagnostic implementation.
}

class RemoteClient {
  final PairedHost host;
  final JsonTransport transport;
  String? _session;
  int _sequence = 0;
  int _generation = 0;
  Future<void> _tail = Future.value();
  RemoteClient(this.host, this.transport);

  static Future<PairedHost> pair(JsonTransport transport, String url, String label, String invitation) async {
    final origin = remoteOrigin(url);
    if (label.trim().isEmpty || label.length > 64 || !RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(invitation.trim())) {
      throw const RemoteFailure('invalid_pairing');
    }
    final reply = await transport.post(origin, '/remote/v1/pair',
      {'version': 1, 'invitation': invitation.trim()}, null);
    final data = reply['data'] as Map<String, dynamic>;
    final provisional = PairedHost(label.trim(), origin, data['deviceId'] as String, data['deviceToken'] as String, '');
    final client = RemoteClient(provisional, transport);
    final ping = await client.request('session.ping');
    client.disconnect();
    return PairedHost(provisional.label, origin, provisional.deviceId, provisional.deviceToken, ping['hostId'] as String);
  }

  Future<dynamic> request(String operation, {String? instance, String? confirmation}) {
    final generation = _generation;
    final result = Completer<dynamic>();
    _tail = _tail.then((_) async {
      try {
        if (generation != _generation) throw const RemoteFailure('connection_lost');
        if (_session == null) {
          final reply = await transport.post(host.origin, '/remote/v1/session',
            {'version': 1, 'deviceId': host.deviceId}, host.deviceToken);
          if (generation != _generation) throw const RemoteFailure('connection_lost');
          final data = reply['data'] as Map<String, dynamic>;
          if (data['protocolVersion'] != 1) throw const RemoteFailure('protocol_mismatch');
          _session = data['sessionToken'] as String;
          _sequence = 0;
        }
        final reply = await transport.post(host.origin, '/remote/v1/request',
          {'version': 1, 'sequence': ++_sequence, 'operation': operation,
            'instanceId': instance, 'confirmation': confirmation}, _session);
        if (generation != _generation) throw const RemoteFailure('connection_lost');
        if (operation == 'session.ping' && host.hostId.isNotEmpty && reply['data']['hostId'] != host.hostId) {
          throw const RemoteFailure('host_identity_changed');
        }
        result.complete(reply['data']);
      } catch (error) {
        // Never retry an uncertain command. Clear session so the next explicit action authenticates anew.
        _session = null;
        _sequence = 0;
        result.completeError(error is RemoteFailure ? error : const RemoteFailure('invalid_response'));
      }
    });
    return result.future;
  }
  void disconnect() { _generation++; _session = null; _sequence = 0; transport.cancel(); }
}
