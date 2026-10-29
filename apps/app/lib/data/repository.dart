import 'dart:typed_data';

import '../core/api_client.dart';
import '../core/ids.dart';
import 'models.dart';

/// Acesso tipado à API hoink. Nenhum cálculo financeiro é feito no app: os números vêm do backend (RN13).
class HoinkRepository {
  HoinkRepository(this.api);
  final ApiClient api;

  // ── Autenticação ──
  Future<(User, String)> login(String email, String password) async {
    final r = await api.post('/auth/login', {'email': email, 'password': password});
    return (User.fromJson(r['data']['user']), r['data']['token'] as String);
  }

  Future<(User, String)> signup(String name, String email, String password, {bool withBusiness = false}) async {
    final r = await api.post('/auth/signup', {
      'name': name,
      'email': email,
      'password': password,
      'withBusiness': withBusiness,
    });
    return (User.fromJson(r['data']['user']), r['data']['token'] as String);
  }

  Future<User> me() async => User.fromJson((await api.get('/auth/me'))['data']);
  Future<void> logout() => api.post('/auth/logout');
  Future<void> forgotPassword(String email) => api.post('/auth/forgot-password', {'email': email});
  Future<void> resetPassword(String token, String password) =>
      api.post('/auth/reset-password', {'token': token, 'password': password});
  Future<void> changePassword(String current, String next) =>
      api.post('/auth/change-password', {'currentPassword': current, 'newPassword': next});
  Future<User> updateProfile(String name) async => User.fromJson((await api.patch('/auth/me', {'name': name}))['data']);

  Future<User> uploadAvatar(List<int> bytes, String contentType) async =>
      User.fromJson((await api.putBytes('/auth/me/avatar', bytes, contentType))['data']);
  Future<Uint8List?> avatar() => api.getBytes('/auth/me/avatar');
  Future<User> removeAvatar() async => User.fromJson((await api.delete('/auth/me/avatar'))['data']);

  Future<List<SessionInfo>> sessions() async {
    final r = await api.get('/auth/sessions');
    return (r['data'] as List)
        .map(
          (s) => SessionInfo(
            s['id'],
            s['userAgent'],
            DateTime.parse(s['lastUsedAt']),
            DateTime.parse(s['createdAt']),
            s['current'] as bool,
          ),
        )
        .toList();
  }

  Future<void> revokeSession(String id) => api.delete('/auth/sessions/$id');

  // ── Ambientes ──
  Future<List<FinancialEntity>> entities() async =>
      ((await api.get('/entities'))['data'] as List).map((e) => FinancialEntity.fromJson(e)).toList();
  Future<void> updateEntity(String id, Map<String, Object?> body) => api.patch('/entities/$id', body);

  /// Ativa (ou reativa, com os dados preservados) a conta profissional.
  Future<void> enableBusiness() => api.post('/entities/business');

  /// Desativa um ambiente profissional sem apagar os dados.
  Future<void> archiveEntity(String id) => api.post('/entities/$id/archive');

  // ── Dashboard ──
  Future<Dashboard> dashboard({String? entityId, required String month}) async {
    final path = entityId == null ? '/consolidated/dashboard' : '/entities/$entityId/dashboard';
    return Dashboard.fromJson((await api.get(path, query: {'month': month}))['data']);
  }

  // ── Contas ──
  Future<List<Account>> accounts(String entityId, {bool includeArchived = false}) async {
    final r = await api.get('/entities/$entityId/accounts', query: {'includeArchived': includeArchived});
    return (r['data'] as List).map((a) => Account.fromJson(a)).toList();
  }

  Future<Account> saveAccount(String entityId, Map<String, Object?> body, {String? id}) async {
    final r = id == null
        ? await api.post('/entities/$entityId/accounts', body)
        : await api.patch('/entities/$entityId/accounts/$id', body);
    return Account.fromJson(r['data']);
  }

  Future<void> setAccountArchived(String entityId, String id, bool archived) =>
      api.post('/entities/$entityId/accounts/$id/${archived ? 'archive' : 'unarchive'}');

  Future<Statement> statement(String entityId, String id, String from, String to) async => Statement.fromJson(
    (await api.get('/entities/$entityId/accounts/$id/statement', query: {'from': from, 'to': to}))['data'],
  );

  Future<Map<String, dynamic>> reconcile(
    String entityId,
    String id,
    int statementCents,
    String date,
    bool adjust,
  ) async => (await api.post('/entities/$entityId/accounts/$id/reconcile', {
    'statementBalanceCents': statementCents,
    'date': date,
    'createAdjustment': adjust,
  }))['data'];

  // ── Categorias ──
  Future<List<Category>> categories(String entityId) async =>
      ((await api.get('/entities/$entityId/categories'))['data'] as List).map((c) => Category.fromJson(c)).toList();

  Future<void> createCategory(String entityId, Map<String, Object?> body) =>
      api.post('/entities/$entityId/categories', body);
  Future<void> archiveCategory(String entityId, String id) => api.delete('/entities/$entityId/categories/$id');

  // ── Lançamentos ──
  Future<PageResult<Txn>> transactions({String? entityId, required Map<String, Object?> query}) async {
    final path = entityId == null ? '/consolidated/transactions' : '/entities/$entityId/transactions';
    final r = await api.get(path, query: query);
    final m = r['meta'];
    return PageResult(
      (r['data'] as List).map((t) => Txn.fromJson(t)).toList(),
      m['page'],
      m['pageSize'],
      m['total'],
      m['totalPages'],
    );
  }

  Future<Txn> transaction(String entityId, String id) async =>
      Txn.fromJson((await api.get('/entities/$entityId/transactions/$id'))['data']);

  Future<Txn> createTransaction(String entityId, Map<String, Object?> body, {String? idempotencyKey}) async =>
      Txn.fromJson(
        (await api.post('/entities/$entityId/transactions', body, idempotencyKey ?? newIdempotencyKey()))['data'],
      );

  Future<Txn> updateTransaction(String entityId, String id, Map<String, Object?> body) async =>
      Txn.fromJson((await api.patch('/entities/$entityId/transactions/$id', body))['data']);

  Future<Txn> settle(String entityId, String id, String date, {int? amountCents, int? finalAmountCents}) async =>
      Txn.fromJson(
        (await api.post('/entities/$entityId/transactions/$id/settle', {
          'date': date,
          'amountCents': ?amountCents,
          'finalAmountCents': ?finalAmountCents,
        }, newIdempotencyKey()))['data'],
      );

  // ── Clientes e fornecedores ──
  Future<List<Contact>> contacts(String entityId, {String? kind, String? q}) async =>
      ((await api.get('/entities/$entityId/contacts', query: {'kind': kind, 'q': q}))['data'] as List)
          .map((c) => Contact.fromJson(c))
          .toList();
  Future<Contact> contact(String entityId, String id) async =>
      Contact.fromJson((await api.get('/entities/$entityId/contacts/$id'))['data']);
  Future<Contact> saveContact(String entityId, Map<String, Object?> body, {String? id}) async => Contact.fromJson(
    (id == null
        ? await api.post('/entities/$entityId/contacts', body)
        : await api.patch('/entities/$entityId/contacts/$id', body))['data'],
  );
  Future<void> setContactArchived(String entityId, String id, bool archived) =>
      api.post('/entities/$entityId/contacts/$id/${archived ? 'archive' : 'unarchive'}');

  /// [kind]: `receivable` (a receber) ou `payable` (a pagar). [status]: `open` ou `overdue`.
  Future<PayablesPage> payables(String entityId, {required String kind, String status = 'open'}) async {
    final r = await api.get('/entities/$entityId/payables', query: {'kind': kind, 'status': status});
    final t = r['totals'];
    return PayablesPage(
      (r['data'] as List).map((x) => Txn.fromJson(x)).toList(),
      t['openCents'],
      t['overdueCents'],
      t['next7DaysCents'],
      ((r['cardInvoices'] as List?) ?? const []).map((i) => PendingInvoice.fromJson(i)).toList(),
    );
  }

  // ── Recorrências ──
  Future<List<RecurringRule>> recurringRules(String entityId) async =>
      ((await api.get('/entities/$entityId/recurring'))['data'] as List).map((r) => RecurringRule.fromJson(r)).toList();
  Future<RecurringRule> recurringRule(String entityId, String id) async =>
      RecurringRule.fromJson((await api.get('/entities/$entityId/recurring/$id'))['data']);
  Future<RecurringRule> createRecurring(String entityId, Map<String, Object?> body) async =>
      RecurringRule.fromJson((await api.post('/entities/$entityId/recurring', body))['data']);

  /// [scope]: `SERIES` (toda a série) ou `FROM` (desta ocorrência em diante, a partir de [fromDate]).
  Future<RecurringRule> updateRecurring(
    String entityId,
    String id, {
    required String scope,
    String? fromDate,
    required Map<String, Object?> changes,
  }) async => RecurringRule.fromJson(
    (await api.patch('/entities/$entityId/recurring/$id', {
      'scope': scope,
      'fromDate': ?fromDate,
      'changes': changes,
    }))['data'],
  );
  Future<void> recurringAction(String entityId, String id, String action) =>
      api.post('/entities/$entityId/recurring/$id/$action');

  Future<void> deleteTransaction(String entityId, String id) => api.delete('/entities/$entityId/transactions/$id');

  // ── Transferências ──
  Future<void> createTransfer(Map<String, Object?> body, {String? idempotencyKey}) =>
      api.post('/transfers', body, idempotencyKey ?? newIdempotencyKey());
  Future<void> deleteTransfer(String id) => api.delete('/transfers/$id');

  // ── Cartões de crédito ──
  Future<List<CreditCard>> cards(String entityId) async =>
      ((await api.get('/entities/$entityId/cards'))['data'] as List).map((c) => CreditCard.fromJson(c)).toList();
  Future<CreditCard> card(String entityId, String id) async =>
      CreditCard.fromJson((await api.get('/entities/$entityId/cards/$id'))['data']);
  Future<CreditCard> saveCard(String entityId, Map<String, Object?> body, {String? id}) async => CreditCard.fromJson(
    (id == null
        ? await api.post('/entities/$entityId/cards', body)
        : await api.patch('/entities/$entityId/cards/$id', body))['data'],
  );
  Future<void> archiveCard(String entityId, String id) => api.post('/entities/$entityId/cards/$id/archive');

  /// Fatura do mês [month] (AAAA-MM). Sem mês: a fatura que recebe as compras de hoje.
  Future<Invoice> invoice(String entityId, String cardId, {String? month}) async =>
      Invoice.fromJson((await api.get('/entities/$entityId/cards/$cardId/invoice', query: {'month': month}))['data']);
  Future<void> createPurchase(String entityId, String cardId, Map<String, Object?> body) =>
      api.post('/entities/$entityId/cards/$cardId/purchases', body, newIdempotencyKey());
  Future<void> deletePurchase(String entityId, String cardId, String purchaseId) =>
      api.delete('/entities/$entityId/cards/$cardId/purchases/$purchaseId');

  /// Paga a fatura com uma transferência da conta escolhida (não cria nova despesa).
  Future<void> payInvoice(
    String entityId,
    String cardId,
    String invoiceId, {
    required String fromAccountId,
    required String date,
    int? amountCents,
    String? classification,
  }) => api.post('/entities/$entityId/cards/$cardId/invoices/$invoiceId/pay', {
    'fromAccountId': fromAccountId,
    'date': date,
    'amountCents': ?amountCents,
    'classification': ?classification,
  }, newIdempotencyKey());

  // ── Dívidas ──
  Future<List<Debt>> debts(String entityId, {bool includeClosed = false}) async =>
      ((await api.get('/entities/$entityId/debts', query: {'includeClosed': includeClosed}))['data'] as List)
          .map((d) => Debt.fromJson(d))
          .toList();
  Future<Debt> debt(String entityId, String id) async =>
      Debt.fromJson((await api.get('/entities/$entityId/debts/$id'))['data']);
  Future<DebtSimulation> simulateDebt(String entityId, Map<String, Object?> body) async =>
      DebtSimulation((await api.post('/entities/$entityId/debts/simulate', body))['data']);
  Future<Debt> createDebt(String entityId, Map<String, Object?> body) async =>
      Debt.fromJson((await api.post('/entities/$entityId/debts', body, newIdempotencyKey()))['data']);
  Future<Debt> prepayDebt(String entityId, String id, Map<String, Object?> body) async =>
      Debt.fromJson((await api.post('/entities/$entityId/debts/$id/prepay', body, newIdempotencyKey()))['data']);
  Future<PayoffQuote> payoffQuote(String entityId, String id, String date) async =>
      PayoffQuote((await api.get('/entities/$entityId/debts/$id/payoff', query: {'date': date}))['data']);
  Future<Debt> payoffDebt(String entityId, String id, String date) async => Debt.fromJson(
    (await api.post('/entities/$entityId/debts/$id/payoff', {'date': date}, newIdempotencyKey()))['data'],
  );
  Future<void> cancelDebt(String entityId, String id) => api.post('/entities/$entityId/debts/$id/cancel');

  // ── Planejamento ──
  Future<BudgetsPage> budgets(String entityId, String month) async =>
      BudgetsPage((await api.get('/entities/$entityId/planning/budgets', query: {'month': month}))['data']);
  Future<void> saveBudget(String entityId, String categoryId, int limitCents, int alertThresholdBps) => api.put(
    '/entities/$entityId/planning/budgets',
    {'categoryId': categoryId, 'limitCents': limitCents, 'alertThresholdBps': alertThresholdBps},
  );
  Future<void> deleteBudget(String entityId, String id) => api.delete('/entities/$entityId/planning/budgets/$id');

  /// Projeção de 30/60/90 dias de um ambiente, ou consolidada quando [entityId] é nulo.
  Future<Cashflow> cashflow({String? entityId}) async => Cashflow(
    (await api.get(
      entityId == null ? '/consolidated/planning/cashflow' : '/entities/$entityId/planning/cashflow',
    ))['data'],
  );
  Future<EmergencyReserve> reserve(String entityId) async =>
      EmergencyReserve((await api.get('/entities/$entityId/planning/reserve'))['data']);
  Future<EmergencyReserve> saveReserve(String entityId, int targetMonths, List<String> accountIds) async =>
      EmergencyReserve(
        (await api.put('/entities/$entityId/planning/reserve', {
          'targetMonths': targetMonths,
          'accountIds': accountIds,
        }))['data'],
      );

  // ── Cofrinhos e gamificação ──
  Future<List<PiggyBank>> piggyBanks(String entityId) async =>
      ((await api.get('/entities/$entityId/piggy-banks'))['data'] as List).map((p) => PiggyBank(p)).toList();
  Future<PiggyBank> piggyBank(String entityId, String id) async =>
      PiggyBank((await api.get('/entities/$entityId/piggy-banks/$id'))['data']);
  Future<PiggyResult> savePiggy(String entityId, Map<String, Object?> body, {String? id}) async => PiggyResult(
    (id == null
        ? await api.post('/entities/$entityId/piggy-banks', body)
        : await api.patch('/entities/$entityId/piggy-banks/$id', body))['data'],
  );

  /// [action]: `deposit`, `withdraw`, `yield` ou `achieve`.
  Future<PiggyResult> piggyAction(String entityId, String id, String action, Map<String, Object?> body) async =>
      PiggyResult((await api.post('/entities/$entityId/piggy-banks/$id/$action', body, newIdempotencyKey()))['data']);
  Future<void> archivePiggy(String entityId, String id) => api.post('/entities/$entityId/piggy-banks/$id/archive');
  Future<PiggySimulation> simulatePiggy(String entityId, String id, int monthlyCents, int months) async =>
      PiggySimulation(
        (await api.get(
          '/entities/$entityId/piggy-banks/$id/simulate',
          query: {'monthlyCents': monthlyCents, 'months': months},
        ))['data'],
      );
  Future<GamificationProfile> gamification() async => GamificationProfile((await api.get('/gamification'))['data']);
  Future<List<MarketRateStatus>> marketRates() async =>
      ((await api.get('/market-rates'))['data'] as List).map((m) => MarketRateStatus(m)).toList();

  // ── Investimentos ──
  Future<List<Investment>> investments(String entityId) async =>
      ((await api.get('/entities/$entityId/investments'))['data'] as List).map((i) => Investment(i)).toList();
  Future<Investment> investment(String entityId, String id) async =>
      Investment((await api.get('/entities/$entityId/investments/$id'))['data']);
  Future<Investment> createInvestment(String entityId, Map<String, Object?> body) async =>
      Investment((await api.post('/entities/$entityId/investments', body, newIdempotencyKey()))['data']);

  /// [path]: `contributions`, `redemptions`, `income` ou `value`.
  Future<Investment> investmentAction(String entityId, String id, String path, Map<String, Object?> body) async =>
      Investment((await api.post('/entities/$entityId/investments/$id/$path', body, newIdempotencyKey()))['data']);
  Future<Investment> deleteInvestmentMovement(String entityId, String id, String movementId) async =>
      Investment((await api.delete('/entities/$entityId/investments/$id/movements/$movementId'))['data']);
  Future<void> updateInvestment(String entityId, String id, Map<String, Object?> body) =>
      api.patch('/entities/$entityId/investments/$id', body);

  // ── Patrimônio ──
  Future<Patrimony> patrimony({String? entityId}) async => Patrimony(
    (await api.get(entityId == null ? '/consolidated/patrimony' : '/entities/$entityId/patrimony'))['data'],
  );
  Future<void> savePatrimonyItem(String entityId, Map<String, Object?> body, {String? id}) => id == null
      ? api.post('/entities/$entityId/patrimony/items', body)
      : api.patch('/entities/$entityId/patrimony/items/$id', body);
  Future<void> deletePatrimonyItem(String entityId, String id) => api.delete('/entities/$entityId/patrimony/items/$id');

  // ── Nota fiscal ──
  /// Lê o QR Code (link) ou a chave de acesso de uma NFC-e e devolve a prévia do gasto.
  Future<ReceiptPreview> receiptPreview(String entityId, String qr) async =>
      ReceiptPreview((await api.post('/entities/$entityId/receipts/preview', {'qr': qr}))['data']);

  // ── Relatórios ──
  Future<List<({String type, String title})>> reportTypes() async => ((await api.get('/reports'))['data'] as List)
      .map((t) => (type: t['type'] as String, title: t['title'] as String))
      .toList();

  String _reportPath(String? entityId, String type) =>
      entityId == null ? '/consolidated/reports/$type' : '/entities/$entityId/reports/$type';

  /// Prévia (JSON) do relatório; [query]: period, ref, from, to, categoryId.
  Future<Report> report(String? entityId, String type, Map<String, Object?> query) async =>
      Report((await api.get(_reportPath(entityId, type), query: query))['data']);

  /// Arquivo do relatório em `pdf`, `xlsx` ou `csv`, com os mesmos números da prévia.
  Future<Uint8List?> reportFile(String? entityId, String type, String format, Map<String, Object?> query) =>
      api.getBytes(_reportPath(entityId, type), query: {...query, 'format': format});

  // ── Costelinha ──
  /// Perguntas sugeridas da Costelinha.
  Future<List<String>> assistantSuggestions() async =>
      List<String>.from((await api.get('/assistant'))['data']['suggestions'] as List);

  Future<AssistantAnswer> ask(String? entityId, String question) async => AssistantAnswer(
    (await api.post(entityId == null ? '/assistant/ask' : '/entities/$entityId/assistant/ask', {
      'question': question,
    }))['data'],
  );

  Future<({List<CompareResult> results, List<String> missing})> compareInvestments(Map<String, Object?> body) async {
    final d = (await api.post('/assistant/compare-investments', body))['data'];
    return (
      results: (d['results'] as List).map((r) => CompareResult(r)).toList(),
      missing: List<String>.from(d['missingRates'] as List),
    );
  }

  // ── Notificações ──
  Future<({int unread, List<AppNotification> items})> notifications() async {
    final d = (await api.get('/notifications'))['data'];
    return (unread: d['unread'] as int, items: (d['items'] as List).map((n) => AppNotification(n)).toList());
  }

  Future<void> markNotificationRead(String id) => api.post('/notifications/$id/read');
  Future<void> markAllNotificationsRead() => api.post('/notifications/read-all');
}
