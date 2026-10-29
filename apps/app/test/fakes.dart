import 'package:hoink/core/api_client.dart';
import 'package:hoink/core/token_storage.dart';
import 'package:hoink/data/models.dart';
import 'package:hoink/data/repository.dart';

class MemoryTokenStorage extends TokenStorage {
  MemoryTokenStorage([this.value]);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async => value = token;
  @override
  Future<void> clear() async => value = null;
}

final testUser = User(id: 'u1', email: 'miguel@hoink.dev', name: 'Miguel Santos');
final personal = FinancialEntity(id: 'e1', name: 'Pessoal', kind: 'PERSONAL', role: 'OWNER', ownershipShareBps: 10000);
final business = FinancialEntity(
  id: 'e2',
  name: 'Profissional',
  kind: 'BUSINESS',
  role: 'OWNER',
  ownershipShareBps: 10000,
);

Json txnJson({
  String id = 't1',
  String type = 'EXPENSE',
  String direction = 'OUT',
  int amount = 35000,
  String status = 'SETTLED',
  String? effective,
}) => {
  'id': id,
  'entityId': 'e1',
  'type': type,
  'direction': direction,
  'description': 'Supermercado Pão de Açúcar',
  'amountCents': amount,
  'settledAmountCents': status == 'SETTLED' ? amount : 0,
  'status': status,
  'effectiveStatus': effective ?? status,
  'competenceDate': '2025-06-09',
  'dueDate': null,
  'settledDate': status == 'SETTLED' ? '2025-06-09' : null,
  'counterparty': null,
  'notes': null,
  'tags': <String>[],
  'account': {'id': 'a1', 'name': 'Nubank Ultravioleta', 'institution': 'Nubank'},
  'category': {'id': 'c1', 'name': 'Mercado', 'icon': 'shopping_cart'},
  'transfer': null,
};

Dashboard fakeDashboard() => Dashboard.fromJson({
  'scope': 'entity',
  'month': '2025-06',
  'today': '2025-06-20',
  'accounts': [
    {
      'id': 'a1',
      'entityId': 'e1',
      'name': 'Nubank Ultravioleta',
      'institution': 'Nubank',
      'type': 'CHECKING',
      'initialBalanceCents': 100000,
      'referenceDate': '2025-01-01',
      'balanceCents': 1248000,
      'archived': false,
    },
  ],
  'totalBalanceCents': 1248000,
  'realized': {'incomeCents': 780000, 'expenseCents': 490000, 'netCents': 290000},
  'forecast': {'incomeCents': 0, 'expenseCents': 28750, 'count': 1},
  'overdue': {'incomeCents': 0, 'expenseCents': 0, 'count': 0},
  'series': [
    for (final m in ['01', '02', '03', '04', '05', '06'])
      {'month': '2025-$m', 'incomeCents': 700000, 'expenseCents': 450000, 'netCents': 250000},
  ],
  'expensesByCategory': [
    {'name': 'Moradia', 'icon': 'home', 'cents': 185000, 'shareBps': 6250},
    {'name': 'Mercado', 'icon': 'shopping_cart', 'cents': 111000, 'shareBps': 3750},
  ],
  'recent': [txnJson()],
  'upcoming': <Json>[],
});

/// Repositório falso: nenhuma chamada de rede; registra as operações de escrita.
class FakeRepository extends HoinkRepository {
  FakeRepository() : super(ApiClient(baseUrl: 'http://fake'));
  final created = <Map<String, Object?>>[];
  final createdRecurring = <Map<String, Object?>>[];
  final savedContacts = <Map<String, Object?>>[];
  final purchases = <Map<String, Object?>>[];
  final simulated = <Map<String, Object?>>[];
  final budgetsSaved = <(String, int, int)>[];
  List<CreditCard> cardList = [];
  String? loginError;
  bool withBusiness = true;

  @override
  Future<(User, String)> login(String email, String password) async {
    if (loginError != null) throw ApiException(401, 'UNAUTHORIZED', loginError!);
    return (testUser, 'token-123456789012345678901');
  }

  @override
  Future<User> me() async => testUser;
  @override
  Future<List<FinancialEntity>> entities() async => [personal, if (withBusiness) business];
  @override
  Future<Dashboard> dashboard({String? entityId, required String month}) async => fakeDashboard();
  @override
  Future<List<Account>> accounts(String entityId, {bool includeArchived = false}) async => fakeDashboard().accounts;
  @override
  Future<List<Category>> categories(String entityId) async => [
    Category(id: 'c1', name: 'Mercado', kind: 'EXPENSE', icon: 'shopping_cart'),
    Category(id: 'c2', name: 'Salário', kind: 'INCOME', icon: 'payments'),
  ];
  @override
  Future<Txn> createTransaction(String entityId, Map<String, Object?> body, {String? idempotencyKey}) async {
    created.add(body);
    return Txn.fromJson(txnJson());
  }

  @override
  Future<RecurringRule> createRecurring(String entityId, Map<String, Object?> body) async {
    createdRecurring.add(body);
    return RecurringRule.fromJson({
      'id': 'r1',
      'entityId': entityId,
      'type': body['type'],
      'description': body['description'],
      'amountCents': body['amountCents'],
      'amountKind': body['amountKind'],
      'account': {'id': 'a1', 'name': 'Nubank Ultravioleta'},
      'category': null,
      'counterparty': null,
      'frequency': body['frequency'],
      'intervalCount': 1,
      'intervalUnit': null,
      'startDate': body['startDate'],
      'endDate': null,
      'maxOccurrences': null,
      'status': 'ACTIVE',
      'nextOccurrence': null,
      'stats': {'settled': 0, 'open': 3, 'overdue': 0, 'canceled': 0},
      'occurrences': <Json>[],
    });
  }

  @override
  Future<List<RecurringRule>> recurringRules(String entityId) async => [];

  @override
  Future<List<Contact>> contacts(String entityId, {String? kind, String? q}) async => [];

  @override
  Future<Contact> saveContact(String entityId, Map<String, Object?> body, {String? id}) async {
    savedContacts.add(body);
    return Contact.fromJson({
      'id': 'c9',
      'entityId': entityId,
      'kind': body['kind'],
      'name': body['name'],
      'archived': false,
      'summary': {
        'billedCents': 0,
        'receivedCents': 0,
        'receivableOpenCents': 0,
        'receivableOverdueCents': 0,
        'purchasedCents': 0,
        'paidCents': 0,
        'payableOpenCents': 0,
        'payableOverdueCents': 0,
      },
    });
  }

  @override
  Future<PayablesPage> payables(String entityId, {required String kind, String status = 'open'}) async =>
      PayablesPage([Txn.fromJson(txnJson(id: 'p1', status: 'PENDING', effective: 'OVERDUE'))], 35000, 35000, 0);

  @override
  Future<List<CreditCard>> cards(String entityId) async => cardList;
  @override
  Future<CreditCard> card(String entityId, String id) async => cardList.firstWhere((c) => c.id == id);
  @override
  Future<Invoice> invoice(String entityId, String cardId, {String? month}) async => Invoice.fromJson({
    ...invoiceJson(month ?? '2025-07'),
    'items': [
      {
        ...txnJson(id: 'i1', amount: 42000),
        'description': 'Notebook (2/10)',
        'installment': {'purchaseId': 'p1', 'number': 2, 'invoiceId': 'inv1'},
        'installmentCount': 10,
        'purchaseDate': '2025-05-18',
      },
    ],
    'payments': <Json>[],
  });
  @override
  Future<void> createPurchase(String entityId, String cardId, Map<String, Object?> body) async => purchases.add(body);

  @override
  Future<List<Debt>> debts(String entityId, {bool includeClosed = false}) async => [];
  @override
  Future<DebtSimulation> simulateDebt(String entityId, Map<String, Object?> body) async {
    simulated.add(body);
    return DebtSimulation({
      'installments': [
        {
          'number': 1,
          'dueDate': '2025-08-10',
          'principalCents': 78849,
          'interestCents': 10000,
          'feesCents': 0,
          'totalCents': 88849,
          'balanceAfterCents': 921151,
        },
      ],
      'totalCents': 1066188,
      'totalInterestCents': 66188,
      'totalFeesCents': 0,
      'firstPaymentCents': 88849,
      'lastPaymentCents': 88849,
    });
  }

  @override
  Future<BudgetsPage> budgets(String entityId, String month) async => BudgetsPage({
    'month': month,
    'items': [
      {
        'id': 'b1',
        'category': {'id': 'c1', 'name': 'Mercado', 'icon': 'shopping_cart'},
        'limitCents': 60000,
        'alertThresholdBps': 8000,
        'spentCents': 51000,
        'committedCents': 0,
        'state': 'WARNING',
        'usedBps': 8500,
        'remainingCents': 9000,
      },
    ],
    'totals': {'limitCents': 60000, 'spentCents': 51000, 'committedCents': 0},
    'alerts': [
      {'message': 'Mercado: 85% do orçamento usado'},
    ],
  });
  @override
  Future<void> saveBudget(String entityId, String categoryId, int limitCents, int alertThresholdBps) async =>
      budgetsSaved.add((categoryId, limitCents, alertThresholdBps));

  @override
  Future<Cashflow> cashflow({String? entityId}) async => Cashflow({
    'today': '2025-07-01',
    'startBalanceCents': 500000,
    'horizons': [
      for (final d in [30, 60, 90])
        {
          'days': d,
          'until': '2025-09-29',
          'incomeConfirmedCents': 200000,
          'incomePlannedCents': 780000 * d ~/ 30,
          'expenseConfirmedCents': 120000,
          'expensePlannedCents': 400000 * d ~/ 30,
          'endBalanceConfirmedCents': 580000,
          'endBalanceProjectedCents': 580000 + 380000 * d ~/ 30,
        },
    ],
    'points': [
      for (var i = 0; i <= 90; i++)
        {'date': '2025-07-01', 'confirmedCents': 500000 + i * 100, 'projectedCents': 500000 + i * 500},
    ],
    'lowest': {'date': '2025-07-01', 'confirmedCents': 500000, 'projectedCents': 500000},
    'alerts': <String>[],
  });

  @override
  Future<EmergencyReserve> reserve(String entityId) async => EmergencyReserve({
    'targetMonths': 6,
    'avgMonthlyExpenseCents': 400000,
    'targetCents': 2400000,
    'currentCents': 1450000,
    'missingCents': 950000,
    'progressBps': 6042,
    'monthsCovered': 3.6,
    'customAccounts': true,
    'accounts': [
      {'id': 'a2', 'name': 'Reserva Nubank', 'balanceCents': 1450000},
    ],
  });
}

Json invoiceJson(String month) => {
  'id': 'inv1',
  'month': month,
  'closingDate': '$month-03',
  'dueDate': '$month-10',
  'totalCents': 42000,
  'paidCents': 0,
  'remainingCents': 42000,
  'itemsCount': 1,
  'status': 'CLOSED',
};

CreditCard fakeCard() => CreditCard.fromJson({
  'id': 'card1',
  'entityId': 'e1',
  'name': 'Nubank Roxinho',
  'institution': 'Nubank',
  'brand': 'Mastercard',
  'color': null,
  'limitCents': 1200000,
  'usedCents': 420000,
  'availableCents': 780000,
  'closingDay': 3,
  'dueDay': 10,
  'paymentAccount': {'id': 'a1', 'name': 'Nubank Ultravioleta'},
  'archived': false,
  'currentInvoice': invoiceJson('2025-07'),
  'pendingInvoices': [invoiceJson('2025-06')],
});
