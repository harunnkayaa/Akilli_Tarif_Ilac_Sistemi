import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  static const _key = 'access_token';
  final FlutterSecureStorage _storage;

  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveToken(String token) =>
      _storage.write(key: _key, value: token);

  Future<String?> readToken() => _storage.read(key: _key);

  Future<void> deleteToken() => _storage.delete(key: _key);
}
/*
class TokenStore {
  static String? _token;

  Future<void> saveToken(String token) async {
    _token = token;
  }

  Future<String?> readToken() async {
    return _token;
  }

  Future<void> deleteToken() async {
    _token = null;
  }
}*/