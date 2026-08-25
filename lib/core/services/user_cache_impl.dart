import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'user_cache.dart';

class UserCacheImpl implements UserCache {
  final FlutterSecureStorage secureStorage;
  UserCacheImpl({required this.secureStorage});

  static const _kUserKey = 'sc_cached_user';

  @override
  Future<void> saveJson(Map<String, dynamic> json) async {
    await secureStorage.write(key: _kUserKey, value: jsonEncode(json));
  }

  @override
  Future<Map<String, dynamic>?> readJson() async {
    final raw = await secureStorage.read(key: _kUserKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    await secureStorage.delete(key: _kUserKey);
  }
}
