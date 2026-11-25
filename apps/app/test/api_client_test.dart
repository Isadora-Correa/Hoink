import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoink/core/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response utf8Json(Object body, int status) =>
    http.Response.bytes(utf8.encode(body is String ? body : jsonEncode(body)), status);

void main() {
  test('envia Bearer e Idempotency-Key e decodifica a resposta', () async {
    late http.Request captured;
    final api = ApiClient(
      baseUrl: 'http://api',
      client: MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'data': {'ok': true},
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    )..token = 'tok_1234567890123456789012';
    final r = await api.post('/entities/x/transactions', {'a': 1}, 'key-1');
    expect(r['data']['ok'], true);
    expect(captured.url.toString(), 'http://api/api/entities/x/transactions');
    expect(captured.headers['Authorization'], 'Bearer tok_1234567890123456789012');
    expect(captured.headers['Idempotency-Key'], 'key-1');
  });

  test('omite query params vazios', () async {
    late Uri url;
    final api = ApiClient(
      baseUrl: 'http://api',
      client: MockClient((req) async {
        url = req.url;
        return http.Response('{"data":[]}', 200);
      }),
    );
    await api.get('/x', query: {'q': '', 'kind': null, 'page': 2});
    expect(url.query, 'page=2');
  });

  test('converte erros da API em ApiException com erros de campo', () async {
    final api = ApiClient(
      baseUrl: 'http://api',
      client: MockClient(
        (_) async => utf8Json(({
          'error': {
            'code': 'VALIDATION_ERROR',
            'message': 'Dados inválidos',
            'details': {
              'fieldErrors': {
                'amountCents': ['Valor deve ser maior que zero'],
              },
            },
          },
        }), 400),
      ),
    );
    expect(
      () => api.post('/x'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'VALIDATION_ERROR')
            .having((e) => e.fieldErrors['amountCents']!.first, 'field', 'Valor deve ser maior que zero'),
      ),
    );
  });

  test('401 com token dispara onUnauthorized', () async {
    var called = false;
    final api =
        ApiClient(
            baseUrl: 'http://api',
            client: MockClient(
              (_) async => utf8Json('{"error":{"code":"UNAUTHORIZED","message":"Sessão expirada"}}', 401),
            ),
          )
          ..token = 'tok'
          ..onUnauthorized = () => called = true;
    await expectLater(api.get('/auth/me'), throwsA(isA<ApiException>()));
    expect(called, isTrue);
  });

  test('falha de rede vira mensagem amigável', () async {
    final api = ApiClient(baseUrl: 'http://api', client: MockClient((_) async => throw Exception('offline')));
    expect(() => api.get('/x'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')));
  });

  test('resposta não-JSON vira ApiException', () async {
    final api = ApiClient(
      baseUrl: 'http://api',
      client: MockClient((_) async => http.Response('<html>502</html>', 502)),
    );
    expect(() => api.get('/x'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'BAD_RESPONSE')));
  });

  test('cliques repetidos enquanto envia viram um único envio (sem transferência duplicada)', () async {
    var calls = 0;
    final release = Completer<void>();
    final api = ApiClient(
      baseUrl: 'http://api',
      client: MockClient((req) async {
        calls++;
        await release.future;
        return http.Response(
          jsonEncode({
            'data': {'id': 't$calls'},
          }),
          201,
        );
      }),
    );
    final body = {'fromAccountId': 'a', 'toAccountId': 'b', 'amountCents': 10000};
    // Três cliques em "Transferir" antes da resposta chegar: só o primeiro envia.
    final first = api.post('/transfers', body, 'k-0');
    final repeats = [for (var i = 1; i < 3; i++) api.post('/transfers', body, 'k-$i')];
    for (final r in repeats) {
      await expectLater(r, throwsA(isA<ApiException>().having((e) => e.isDuplicate, 'isDuplicate', isTrue)));
    }
    release.complete();
    expect((await first)['data']['id'], 't1');
    expect(calls, 1);

    // Depois que termina, um novo envio (outra transferência de verdade) segue normalmente.
    await api.post('/transfers', body, 'k-novo');
    expect(calls, 2);

    // Envios diferentes ao mesmo tempo não se misturam.
    final a = api.post('/transfers', {...body, 'amountCents': 1});
    final b = api.post('/transfers', {...body, 'amountCents': 2});
    await Future.wait([a, b]);
    expect(calls, 4);
  });
}
