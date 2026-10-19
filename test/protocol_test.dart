import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel_remote/protocol.dart';

class StubTransport implements JsonTransport {
  final calls = <Map<String, dynamic>>[];
  bool failNextMutation = false;
  @override
  Future<Map<String, dynamic>> post(Uri origin, String path, Map<String, dynamic> body, String? credential) async {
    calls.add({'path': path, ...body, 'credential': credential});
    if (path.endsWith('/pair')) return {'success': true, 'code': 'paired', 'data': {'deviceId': 'device', 'deviceToken': 'device-secret'}};
    if (path.endsWith('/session')) return {'success': true, 'code': 'session_opened', 'data': {'sessionToken': 'session-${calls.length}', 'protocolVersion': 1}};
    if (failNextMutation && body['operation'] == 'srank.skip') { failNextMutation = false; throw const RemoteFailure('connection_lost'); }
    return {'success': true, 'code': 'ok', 'data': {'hostId': 'pc'}};
  }
  @override
  void cancel() {}
}

void main() {
  final host = PairedHost('PC', Uri.parse('https://pc.tail.ts.net'), 'device', 'device-secret', 'pc');
  test('private HTTPS origin only, no URL secrets or alternate ports', () {
    for (final bad in ['http://pc.tail.ts.net', 'https://example.com', 'https://u:p@pc.tail.ts.net',
      'https://pc.tail.ts.net?token=x', 'https://pc.tail.ts.net#x', 'https://pc.tail.ts.net/path', 'https://pc.tail.ts.net:8443']) {
      expect(() => remoteOrigin(bad), throwsA(isA<RemoteFailure>()));
    }
    expect(remoteOrigin('https://pc.tail.ts.net/').toString(), 'https://pc.tail.ts.net');
  });
  test('session credentials are separated and requests are monotonically serialized', () async {
    final transport = StubTransport(); final client = RemoteClient(host, transport);
    await Future.wait([client.request('session.ping'), client.request('instances.list')]);
    expect(transport.calls.first['credential'], 'device-secret');
    final requests = transport.calls.where((v) => v['path'] == '/remote/v1/request').toList();
    expect(requests.map((v) => v['sequence']), [1, 2]);
    expect(requests.every((v) => v['credential'] != 'device-secret'), isTrue);
  });
  test('lost mutation is never retried and next explicit request opens a fresh session', () async {
    final transport = StubTransport()..failNextMutation = true; final client = RemoteClient(host, transport);
    await expectLater(client.request('srank.skip', instance: 'one'), throwsA(isA<RemoteFailure>()));
    await client.request('session.ping');
    expect(transport.calls.where((v) => v['operation'] == 'srank.skip').length, 1);
    expect(transport.calls.where((v) => v['path'] == '/remote/v1/session').length, 2);
  });
  test('disconnect cancels queued requests before they can send', () async {
    final transport = StubTransport(); final client = RemoteClient(host, transport);
    final pending = client.request('srank.skip', instance: 'one'); client.disconnect();
    await expectLater(pending, throwsA(isA<RemoteFailure>()));
    expect(transport.calls, isEmpty);
  });
  test('host identity mismatch is rejected', () async {
    final transport = StubTransport(); final client = RemoteClient(PairedHost('Other', host.origin, 'device', 'device-secret', 'different'), transport);
    await expectLater(client.request('session.ping'), throwsA(isA<RemoteFailure>()));
  });
  test('pairing validates invitation locally and never saves it in host data', () async {
    final transport = StubTransport();
    await expectLater(RemoteClient.pair(transport, host.origin.toString(), 'PC', 'bad'), throwsA(isA<RemoteFailure>()));
    expect(transport.calls, isEmpty);
    final invitation = 'A' * 64;
    final paired = await RemoteClient.pair(transport, host.origin.toString(), 'PC', invitation);
    expect(paired.hostId, 'pc');
    expect(paired.toJson().values.contains(invitation), isFalse);
    expect(paired.toJson().containsKey('sessionToken'), isFalse);
  });
}
