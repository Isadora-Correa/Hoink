import 'package:flutter_test/flutter_test.dart';
import 'package:hoink/app/router.dart';

String? r(String uri, {bool loading = false, bool loggedIn = false}) {
  final u = Uri.parse(uri);
  return resolveRedirect(loading: loading, loggedIn: loggedIn, location: u.path, uri: u);
}

void main() {
  test('deep link sobrevive ao carregamento da sessão', () {
    expect(r('/contas', loading: true), '/carregando?from=%2Fcontas');
    expect(r('/carregando?from=%2Fcontas', loading: true), isNull);
    expect(r('/carregando?from=%2Fcontas', loggedIn: true), '/contas');
  });

  test('sem sessão, vai ao login e volta ao destino depois', () {
    expect(r('/carregando?from=%2Fcontas'), '/login?from=%2Fcontas');
    expect(r('/lancamentos'), '/login?from=%2Flancamentos');
    expect(r('/login?from=%2Flancamentos', loggedIn: true), '/lancamentos');
    expect(r('/login', loggedIn: true), '/');
  });

  test('ignora destinos externos (open redirect)', () {
    expect(r('/login?from=%2F%2Fevil.com', loggedIn: true), '/');
    expect(r('/login?from=https%3A%2F%2Fevil.com', loggedIn: true), '/');
  });

  test('rotas públicas e privadas', () {
    expect(r('/cadastro'), isNull);
    expect(r('/', loggedIn: true), isNull);
    expect(r('/'), '/login');
  });
}
