import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'protocol.dart';

class HostVault {
  final FlutterSecureStorage storage;
  const HostVault([this.storage = const FlutterSecureStorage()]);
  Future<List<PairedHost>> load() async {
    final value = await storage.read(key: 'sentinel.hosts.v1');
    if (value == null) return [];
    return (jsonDecode(value) as List).map((v) => PairedHost.fromJson(v as Map<String, dynamic>)).toList();
  }
  Future<void> save(List<PairedHost> hosts) => storage.write(key: 'sentinel.hosts.v1',
    value: jsonEncode(hosts.map((h) => h.toJson()).toList()));
}
