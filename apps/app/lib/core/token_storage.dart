import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda o token de sessão no armazenamento seguro da plataforma (Keychain/Keystore; no Web, armazenamento cifrado do navegador).
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'hoink_session_token';

  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  Future<void> clear() => _storage.delete(key: _key);
}
