import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.fieldErrors = const {}]);
  final int status;
  final String code;
  final String message;
  final Map<String, List<String>> fieldErrors;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Cliente HTTP da API hoink. Envia o token de sessão como Bearer e converte erros em [ApiException].
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client, this.onUnauthorized}) : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  String? token;
  void Function()? onUnauthorized;

  Uri _uri(String path, [Map<String, Object?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    return Uri.parse('$baseUrl/api$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> _headers({String? idempotencyKey}) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': ?(token == null ? null : 'Bearer $token'),
    'Idempotency-Key': ?idempotencyKey,
  };

  Future<dynamic> get(String path, {Map<String, Object?>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, [Object? body, String? idempotencyKey]) => _send(
    () => _http.post(
      _uri(path),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode(body ?? {}),
    ),
  );

  Future<dynamic> patch(String path, Object body) =>
      _send(() => _http.patch(_uri(path), headers: _headers(), body: jsonEncode(body)));

  Future<dynamic> put(String path, Object body) =>
      _send(() => _http.put(_uri(path), headers: _headers(), body: jsonEncode(body)));

  Future<dynamic> delete(String path) => _send(() => _http.delete(_uri(path), headers: _headers()));

  /// Envia um corpo binário (ex.: foto de perfil).
  Future<dynamic> putBytes(String path, List<int> bytes, String contentType) =>
      _send(() => _http.put(_uri(path), headers: {..._headers(), 'Content-Type': contentType}, body: bytes));

  /// Baixa um conteúdo binário; retorna null em 404.
  Future<Uint8List?> getBytes(String path, {Map<String, Object?>? query}) async {
    http.Response res;
    try {
      res = await _http.get(_uri(path, query), headers: _headers());
    } catch (_) {
      throw ApiException(0, 'NETWORK', 'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) throw ApiException(res.statusCode, 'ERROR', 'Falha ao baixar arquivo');
    return res.bodyBytes;
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call();
    } catch (_) {
      throw ApiException(0, 'NETWORK', 'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
    if (res.statusCode == 204 || res.bodyBytes.isEmpty) return null;
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw ApiException(res.statusCode, 'BAD_RESPONSE', 'Resposta inesperada do servidor (${res.statusCode}).');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    final err = (decoded is Map ? decoded['error'] : null) as Map<String, dynamic>? ?? {};
    final fields = <String, List<String>>{};
    final details = err['details'];
    if (details is Map && details['fieldErrors'] is Map) {
      (details['fieldErrors'] as Map).forEach((k, v) => fields[k as String] = List<String>.from(v as List));
    }
    final e = ApiException(
      res.statusCode,
      err['code'] as String? ?? 'ERROR',
      err['message'] as String? ?? 'Erro inesperado',
      fields,
    );
    if (e.isUnauthorized && token != null) onUnauthorized?.call();
    throw e;
  }
}
