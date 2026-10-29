import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../core/dates.dart';
import '../core/token_storage.dart';
import '../data/models.dart';
import '../data/repository.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(baseUrl: apiBaseUrl));

final repositoryProvider = Provider<HoinkRepository>((ref) => HoinkRepository(ref.watch(apiClientProvider)));

// ───────────── Autenticação ─────────────

class AuthController extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    final api = ref.read(apiClientProvider);
    api.onUnauthorized = () {
      // Sessão expirada/revogada: limpa o token e volta ao login.
      ref.read(tokenStorageProvider).clear();
      api.token = null;
      state = const AsyncData(null);
    };
    final token = await ref.read(tokenStorageProvider).read();
    if (token == null) return null;
    api.token = token;
    try {
      return await ref.read(repositoryProvider).me();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await ref.read(tokenStorageProvider).clear();
        api.token = null;
        return null;
      }
      rethrow;
    }
  }

  Future<void> _start((User, String) result) async {
    final (user, token) = result;
    ref.read(apiClientProvider).token = token;
    await ref.read(tokenStorageProvider).write(token);
    ref.invalidate(entitiesProvider);
    state = AsyncData(user);
  }

  Future<void> login(String email, String password) async =>
      _start(await ref.read(repositoryProvider).login(email, password));

  Future<void> signup(String name, String email, String password, {bool withBusiness = false}) async =>
      _start(await ref.read(repositoryProvider).signup(name, email, password, withBusiness: withBusiness));

  void updateUser(User user) => state = AsyncData(user);

  Future<void> logout() async {
    try {
      await ref.read(repositoryProvider).logout();
    } catch (_) {
      // Mesmo sem rede, encerra localmente.
    }
    await ref.read(tokenStorageProvider).clear();
    ref.read(apiClientProvider).token = null;
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthController, User?>(AuthController.new);

// ───────────── Escopo (Pessoal / Pro / Total) e mês ─────────────

enum Scope { personal, business, total }

class ScopeController extends Notifier<Scope> {
  @override
  Scope build() => Scope.personal;
  void set(Scope s) => state = s;
}

final scopeProvider = NotifierProvider<ScopeController, Scope>(ScopeController.new);

class MonthController extends Notifier<String> {
  @override
  String build() => isoMonth(DateTime.now());
  void set(String m) => state = m;
}

final monthProvider = NotifierProvider<MonthController, String>(MonthController.new);

/// Incrementado após qualquer alteração de dados para recarregar as consultas dependentes.
class DataVersion extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final dataVersionProvider = NotifierProvider<DataVersion, int>(DataVersion.new);

final entitiesProvider = FutureProvider<List<FinancialEntity>>((ref) async {
  final user = await ref.watch(authProvider.future);
  if (user == null) return [];
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).entities();
});

/// O usuário ativou a conta profissional?
final hasBusinessProvider = Provider<bool>(
  (ref) => (ref.watch(entitiesProvider).value ?? const []).any((e) => e.kind == 'BUSINESS'),
);

/// Escopo efetivo: sem conta profissional, tudo é Pessoal (Pro e Total deixam de existir).
final effectiveScopeProvider = Provider<Scope>((ref) {
  final scope = ref.watch(scopeProvider);
  return ref.watch(hasBusinessProvider) ? scope : Scope.personal;
});

/// Foto de perfil do usuário logado (recarrega quando a foto muda).
final avatarProvider = FutureProvider<Uint8List?>((ref) async {
  final user = ref.watch(authProvider).value;
  if (user == null || !user.hasAvatar) return null;
  return ref.read(repositoryProvider).avatar();
});

/// Ambiente atual; null quando o escopo é o Consolidado.
final currentEntityProvider = Provider<FinancialEntity?>((ref) {
  final scope = ref.watch(effectiveScopeProvider);
  final entities = ref.watch(entitiesProvider).value ?? const [];
  if (scope == Scope.total || entities.isEmpty) return null;
  final want = scope == Scope.personal ? 'PERSONAL' : 'BUSINESS';
  return entities.where((e) => e.kind == want).firstOrNull;
});

final dashboardProvider = FutureProvider<Dashboard>((ref) async {
  ref.watch(dataVersionProvider);
  await ref.watch(entitiesProvider.future);
  final scope = ref.watch(effectiveScopeProvider);
  final month = ref.watch(monthProvider);
  final entity = ref.watch(currentEntityProvider);
  if (scope != Scope.total && entity == null) throw StateError('Ambiente indisponível');
  return ref.read(repositoryProvider).dashboard(entityId: entity?.id, month: month);
});

final accountsProvider = FutureProvider.family<List<Account>, String>((ref, entityId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).accounts(entityId, includeArchived: true);
});

final categoriesProvider = FutureProvider.family<List<Category>, String>((ref, entityId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).categories(entityId);
});
