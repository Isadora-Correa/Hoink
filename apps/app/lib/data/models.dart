// Modelos espelhando os contratos da API. Valores monetários sempre em centavos (int).

typedef Json = Map<String, dynamic>;

class User {
  User({required this.id, required this.email, required this.name, this.avatarUpdatedAt});
  final String id;
  final String email;
  final String name;

  /// Data da última foto de perfil; null quando o usuário não tem foto.
  final String? avatarUpdatedAt;

  bool get hasAvatar => avatarUpdatedAt != null;

  String get firstName => name.split(' ').first;
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  factory User.fromJson(Json j) =>
      User(id: j['id'], email: j['email'], name: j['name'], avatarUpdatedAt: j['avatarUpdatedAt'] as String?);
}

class FinancialEntity {
  FinancialEntity({
    required this.id,
    required this.name,
    required this.kind,
    required this.role,
    required this.ownershipShareBps,
  });
  final String id;
  final String name;
  final String kind; // PERSONAL | BUSINESS
  final String role;
  final int ownershipShareBps;

  bool get isPersonal => kind == 'PERSONAL';
  bool get canWrite => role != 'VIEWER';

  factory FinancialEntity.fromJson(Json j) => FinancialEntity(
    id: j['id'],
    name: j['name'],
    kind: j['kind'],
    role: j['role'],
    ownershipShareBps: j['ownershipShareBps'] as int,
  );
}

const accountTypeLabels = {
  'CHECKING': 'Conta corrente',
  'PAYMENT': 'Conta de pagamento',
  'SAVINGS': 'Poupança',
  'WALLET': 'Carteira',
  'BROKERAGE': 'Corretora',
  'OTHER': 'Outros',
};

class Account {
  Account({
    required this.id,
    required this.entityId,
    required this.name,
    this.institution,
    required this.type,
    required this.initialBalanceCents,
    required this.referenceDate,
    required this.balanceCents,
    required this.archived,
  });
  final String id;
  final String entityId;
  final String name;
  final String? institution;
  final String type;
  final int initialBalanceCents;
  final String referenceDate;
  final int balanceCents;
  final bool archived;

  factory Account.fromJson(Json j) => Account(
    id: j['id'],
    entityId: j['entityId'],
    name: j['name'],
    institution: j['institution'],
    type: j['type'],
    initialBalanceCents: j['initialBalanceCents'] as int,
    referenceDate: j['referenceDate'],
    balanceCents: j['balanceCents'] as int,
    archived: j['archived'] as bool,
  );
}

class Category {
  Category({required this.id, required this.name, required this.kind, required this.icon, this.color});
  final String id;
  final String name;
  final String kind;
  final String icon;
  final String? color;

  factory Category.fromJson(Json j) =>
      Category(id: j['id'], name: j['name'], kind: j['kind'], icon: j['icon'] ?? 'category', color: j['color']);
}

const transactionTypeLabels = {
  'INCOME': 'Receita',
  'EXPENSE': 'Despesa',
  'TRANSFER': 'Transferência',
  'CONTRIBUTION': 'Aporte',
  'REDEMPTION': 'Resgate',
  'REFUND': 'Reembolso',
  'ADJUSTMENT': 'Ajuste',
  'WITHDRAWAL': 'Retirada',
};

const statusLabels = {
  'PLANNED': 'Previsto',
  'PENDING': 'Pendente',
  'PARTIAL': 'Parcial',
  'SETTLED': 'Liquidado',
  'OVERDUE': 'Atrasado',
  'CANCELED': 'Cancelado',
};

const transferClassificationLabels = {
  'INTERNAL': 'Entre contas próprias',
  'OWNER_CONTRIBUTION': 'Aporte de capital do sócio',
  'OWNER_WITHDRAWAL': 'Retirada do sócio',
  'PRO_LABORE': 'Pró-labore',
  'PROFIT_DISTRIBUTION': 'Distribuição de lucros',
  'LOAN_TO_ENTITY': 'Empréstimo entre ambientes',
  'LOAN_REPAYMENT': 'Devolução de empréstimo',
  'EXPENSE_REIMBURSEMENT': 'Reembolso de despesa',
};

class TxnRef {
  TxnRef(this.id, this.name, [this.icon, this.extra]);
  final String id;
  final String name;
  final String? icon;
  final String? extra;
}

class Txn {
  Txn({
    required this.id,
    required this.entityId,
    required this.type,
    required this.direction,
    required this.description,
    required this.amountCents,
    required this.settledAmountCents,
    required this.status,
    required this.effectiveStatus,
    required this.competenceDate,
    this.dueDate,
    this.settledDate,
    this.counterparty,
    this.notes,
    required this.tags,
    required this.account,
    this.category,
    this.transferId,
    this.transferClassification,
    this.recurring,
    this.contactId,
    this.contactName,
    this.settlements = const [],
  });

  final String id;
  final String entityId;
  final String type;
  final String direction;
  final String description;
  final int amountCents;
  final int settledAmountCents;
  final String status;
  final String effectiveStatus;
  final String competenceDate;
  final String? dueDate;
  final String? settledDate;
  final String? counterparty;
  final String? notes;
  final List<String> tags;
  final TxnRef account;
  final TxnRef? category;
  final String? transferId;
  final String? transferClassification;
  final RecurringInfo? recurring;
  final String? contactId;
  final String? contactName;

  /// Histórico de pagamentos/recebimentos (somente no detalhe do lançamento).
  final List<SettlementEntry> settlements;

  bool get isRecurring => recurring != null;
  bool get isIn => direction == 'IN';
  bool get isOpen => status == 'PLANNED' || status == 'PENDING' || status == 'PARTIAL';
  bool get isTransfer => type == 'TRANSFER';
  int get signedAmount => isIn ? amountCents : -amountCents;
  int get remainingCents => amountCents - settledAmountCents;
  String get displayDate => dueDate != null && isOpen ? dueDate! : (settledDate ?? competenceDate);

  factory Txn.fromJson(Json j) {
    final acc = j['account'] as Json;
    final cat = j['category'] as Json?;
    final tr = j['transfer'] as Json?;
    return Txn(
      id: j['id'],
      entityId: j['entityId'],
      type: j['type'],
      direction: j['direction'],
      description: j['description'],
      amountCents: j['amountCents'] as int,
      settledAmountCents: j['settledAmountCents'] as int,
      status: j['status'],
      effectiveStatus: j['effectiveStatus'],
      competenceDate: j['competenceDate'],
      dueDate: j['dueDate'],
      settledDate: j['settledDate'],
      counterparty: j['counterparty'],
      notes: j['notes'],
      tags: List<String>.from(j['tags'] ?? const []),
      account: TxnRef(acc['id'], acc['name'], null, acc['institution']),
      category: cat == null ? null : TxnRef(cat['id'], cat['name'], cat['icon']),
      transferId: tr?['id'],
      transferClassification: tr?['classification'],
      recurring: j['recurring'] == null ? null : RecurringInfo.fromJson(j['recurring']),
      contactId: (j['contact'] as Json?)?['id'],
      contactName: (j['contact'] as Json?)?['name'],
      settlements: ((j['settlements'] as List?) ?? const [])
          .map((s) => SettlementEntry(s['id'], s['date'], s['amountCents']))
          .toList(),
    );
  }
}

class PageResult<T> {
  PageResult(this.items, this.page, this.pageSize, this.total, this.totalPages);
  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
}

class FlowTotals {
  FlowTotals(this.incomeCents, this.expenseCents, this.netCents, this.transfersInCents, this.transfersOutCents);
  final int incomeCents;
  final int expenseCents;
  final int netCents;
  final int transfersInCents;
  final int transfersOutCents;
  factory FlowTotals.fromJson(Json j) => FlowTotals(
    j['incomeCents'],
    j['expenseCents'],
    j['netCents'],
    j['transfersInCents'] ?? 0,
    j['transfersOutCents'] ?? 0,
  );
}

class OpenTotals {
  OpenTotals(this.incomeCents, this.expenseCents, this.count);
  final int incomeCents;
  final int expenseCents;
  final int count;
  factory OpenTotals.fromJson(Json j) => OpenTotals(j['incomeCents'], j['expenseCents'], j['count']);
}

class SeriesPoint {
  SeriesPoint(this.month, this.incomeCents, this.expenseCents, this.netCents);
  final String month;
  final int incomeCents;
  final int expenseCents;
  final int netCents;
}

class CategorySlice {
  CategorySlice(this.name, this.icon, this.cents, this.shareBps);
  final String name;
  final String icon;
  final int cents;
  final int shareBps;
}

class EntityShare {
  EntityShare(
    this.id,
    this.name,
    this.kind,
    this.ownershipShareBps,
    this.totalBalanceCents,
    this.attributableBalanceCents,
  );
  final String id;
  final String name;
  final String kind;
  final int ownershipShareBps;
  final int totalBalanceCents;
  final int attributableBalanceCents;
}

class Dashboard {
  Dashboard({
    required this.scope,
    required this.month,
    required this.today,
    required this.accounts,
    required this.totalBalanceCents,
    required this.realized,
    required this.forecast,
    required this.overdue,
    required this.series,
    required this.expensesByCategory,
    required this.recent,
    required this.upcoming,
    required this.entities,
  });

  final String scope;
  final String month;
  final String today;
  final List<Account> accounts;
  final int totalBalanceCents;
  final FlowTotals realized;
  final OpenTotals forecast;
  final OpenTotals overdue;
  final List<SeriesPoint> series;
  final List<CategorySlice> expensesByCategory;
  final List<Txn> recent;
  final List<Txn> upcoming;
  final List<EntityShare> entities;

  factory Dashboard.fromJson(Json j) => Dashboard(
    scope: j['scope'],
    month: j['month'],
    today: j['today'],
    accounts: (j['accounts'] as List).map((a) => Account.fromJson(a)).toList(),
    totalBalanceCents: j['totalBalanceCents'],
    realized: FlowTotals.fromJson(j['realized']),
    forecast: OpenTotals.fromJson(j['forecast']),
    overdue: OpenTotals.fromJson(j['overdue']),
    series: (j['series'] as List)
        .map((s) => SeriesPoint(s['month'], s['incomeCents'], s['expenseCents'], s['netCents']))
        .toList(),
    expensesByCategory: (j['expensesByCategory'] as List)
        .map((c) => CategorySlice(c['name'], c['icon'] ?? 'category', c['cents'], c['shareBps']))
        .toList(),
    recent: (j['recent'] as List).map((t) => Txn.fromJson(t)).toList(),
    upcoming: (j['upcoming'] as List).map((t) => Txn.fromJson(t)).toList(),
    entities: ((j['entities'] as List?) ?? const [])
        .map(
          (e) => EntityShare(
            e['id'],
            e['name'],
            e['kind'],
            e['ownershipShareBps'],
            e['totalBalanceCents'],
            e['attributableBalanceCents'],
          ),
        )
        .toList(),
  );
}

class StatementEntry {
  StatementEntry(
    this.id,
    this.date,
    this.description,
    this.type,
    this.direction,
    this.amountCents,
    this.balanceAfterCents,
    this.categoryName,
  );
  final String id;
  final String date;
  final String description;
  final String type;
  final String direction;
  final int amountCents;
  final int balanceAfterCents;
  final String? categoryName;
}

class Statement {
  Statement(this.account, this.from, this.to, this.openingBalanceCents, this.closingBalanceCents, this.entries);
  final Account account;
  final String from;
  final String to;
  final int openingBalanceCents;
  final int closingBalanceCents;
  final List<StatementEntry> entries;

  factory Statement.fromJson(Json j) => Statement(
    Account.fromJson(j['account']),
    j['from'],
    j['to'],
    j['openingBalanceCents'],
    j['closingBalanceCents'],
    (j['entries'] as List)
        .map(
          (e) => StatementEntry(
            e['id'],
            e['date'],
            e['description'],
            e['type'],
            e['direction'],
            e['amountCents'],
            e['balanceAfterCents'],
            (e['category'] as Json?)?['name'],
          ),
        )
        .toList(),
  );
}

class SessionInfo {
  SessionInfo(this.id, this.userAgent, this.lastUsedAt, this.createdAt, this.current);
  final String id;
  final String? userAgent;
  final DateTime lastUsedAt;
  final DateTime createdAt;
  final bool current;
}

// ───────────── Recorrências ─────────────

const frequencyLabels = {
  'DAILY': 'Diária',
  'WEEKLY': 'Semanal',
  'BIWEEKLY': 'Quinzenal',
  'MONTHLY': 'Mensal',
  'YEARLY': 'Anual',
  'CUSTOM': 'Personalizada',
};

const intervalUnitLabels = {'DAY': 'dia(s)', 'WEEK': 'semana(s)', 'MONTH': 'mês(es)', 'YEAR': 'ano(s)'};

const amountKindLabels = {'FIXED': 'Fixo', 'VARIABLE': 'Variável', 'ESTIMATED': 'Estimado'};

const recurrenceStatusLabels = {'ACTIVE': 'Ativa', 'PAUSED': 'Pausada', 'CANCELED': 'Cancelada'};

/// Dados de recorrência de um lançamento que é ocorrência de uma série.
class RecurringInfo {
  RecurringInfo(this.ruleId, this.occurrenceDate, this.isOverride, this.amountKind, this.frequency, this.ruleStatus);
  final String ruleId;
  final String? occurrenceDate;
  final bool isOverride;
  final String amountKind;
  final String frequency;
  final String ruleStatus;

  bool get isVariable => amountKind != 'FIXED';

  factory RecurringInfo.fromJson(Json j) => RecurringInfo(
    j['ruleId'],
    j['occurrenceDate'],
    j['isOverride'] as bool,
    j['amountKind'],
    j['frequency'],
    j['ruleStatus'],
  );
}

class RecurringRule {
  RecurringRule({
    required this.id,
    required this.entityId,
    required this.type,
    required this.description,
    required this.amountCents,
    required this.amountKind,
    required this.accountName,
    this.accountId,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    this.counterparty,
    required this.frequency,
    required this.intervalCount,
    this.intervalUnit,
    required this.startDate,
    this.endDate,
    this.maxOccurrences,
    required this.status,
    this.nextDate,
    this.nextAmountCents,
    required this.settledCount,
    required this.openCount,
    required this.overdueCount,
    this.occurrences = const [],
  });

  final String id;
  final String entityId;
  final String type;
  final String description;
  final int amountCents;
  final String amountKind;
  final String? accountId;
  final String accountName;
  final String? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final String? counterparty;
  final String frequency;
  final int intervalCount;
  final String? intervalUnit;
  final String startDate;
  final String? endDate;
  final int? maxOccurrences;
  final String status;
  final String? nextDate;
  final int? nextAmountCents;
  final int settledCount;
  final int openCount;
  final int overdueCount;
  final List<Txn> occurrences;

  bool get isActive => status == 'ACTIVE';
  bool get isIncome => type == 'INCOME';

  String get frequencyLabel => frequency == 'CUSTOM'
      ? 'A cada $intervalCount ${intervalUnitLabels[intervalUnit] ?? ''}'
      : frequencyLabels[frequency] ?? frequency;

  factory RecurringRule.fromJson(Json j) {
    final account = j['account'] as Json?;
    final category = j['category'] as Json?;
    final next = j['nextOccurrence'] as Json?;
    final stats = j['stats'] as Json;
    return RecurringRule(
      id: j['id'],
      entityId: j['entityId'],
      type: j['type'],
      description: j['description'],
      amountCents: j['amountCents'],
      amountKind: j['amountKind'],
      accountId: account?['id'],
      accountName: account?['name'] ?? '',
      categoryId: category?['id'],
      categoryName: category?['name'],
      categoryIcon: category?['icon'],
      counterparty: j['counterparty'],
      frequency: j['frequency'],
      intervalCount: j['intervalCount'],
      intervalUnit: j['intervalUnit'],
      startDate: j['startDate'],
      endDate: j['endDate'],
      maxOccurrences: j['maxOccurrences'],
      status: j['status'],
      nextDate: next?['date'],
      nextAmountCents: next?['amountCents'],
      settledCount: stats['settled'],
      openCount: stats['open'],
      overdueCount: stats['overdue'],
      occurrences: ((j['occurrences'] as List?) ?? const []).map((t) => Txn.fromJson(t)).toList(),
    );
  }
}

class SettlementEntry {
  SettlementEntry(this.id, this.date, this.amountCents);
  final String id;
  final String date;
  final int amountCents;
}

// ───────────── Clientes e fornecedores ─────────────

const contactKindLabels = {'CLIENT': 'Cliente', 'SUPPLIER': 'Fornecedor', 'BOTH': 'Cliente e fornecedor'};

class ContactSummary {
  ContactSummary(Json j)
    : billedCents = j['billedCents'],
      receivedCents = j['receivedCents'],
      receivableOpenCents = j['receivableOpenCents'],
      receivableOverdueCents = j['receivableOverdueCents'],
      purchasedCents = j['purchasedCents'],
      paidCents = j['paidCents'],
      payableOpenCents = j['payableOpenCents'],
      payableOverdueCents = j['payableOverdueCents'];
  final int billedCents;
  final int receivedCents;
  final int receivableOpenCents;
  final int receivableOverdueCents;
  final int purchasedCents;
  final int paidCents;
  final int payableOpenCents;
  final int payableOverdueCents;
}

class Contact {
  Contact({
    required this.id,
    required this.entityId,
    required this.kind,
    required this.name,
    this.document,
    this.email,
    this.phone,
    this.notes,
    required this.archived,
    required this.summary,
    this.transactions = const [],
  });
  final String id;
  final String entityId;
  final String kind;
  final String name;
  final String? document;
  final String? email;
  final String? phone;
  final String? notes;
  final bool archived;
  final ContactSummary summary;
  final List<Txn> transactions;

  bool get isClient => kind != 'SUPPLIER';
  bool get isSupplier => kind != 'CLIENT';

  String? get formattedDocument {
    final d = document;
    if (d == null || d.isEmpty) return null;
    if (d.length == 11) return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
    if (d.length == 14) {
      return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12)}';
    }
    return d;
  }

  factory Contact.fromJson(Json j) => Contact(
    id: j['id'],
    entityId: j['entityId'],
    kind: j['kind'],
    name: j['name'],
    document: j['document'],
    email: j['email'],
    phone: j['phone'],
    notes: j['notes'],
    archived: j['archived'] as bool,
    summary: ContactSummary(j['summary']),
    transactions: ((j['transactions'] as List?) ?? const []).map((t) => Txn.fromJson(t)).toList(),
  );
}

class PayablesPage {
  PayablesPage(this.items, this.openCents, this.overdueCents, this.next7DaysCents, [this.cardInvoices = const []]);
  final List<Txn> items;
  final List<PendingInvoice> cardInvoices;
  final int openCents;
  final int overdueCents;
  final int next7DaysCents;
}

// ───────────── Cartões de crédito ─────────────

class InvoiceSummary {
  InvoiceSummary({
    required this.id,
    required this.month,
    required this.closingDate,
    required this.dueDate,
    required this.totalCents,
    required this.paidCents,
    required this.remainingCents,
    required this.itemsCount,
    required this.status,
  });
  final String? id;
  final String month;
  final String closingDate;
  final String dueDate;
  final int totalCents;
  final int paidCents;
  final int remainingCents;
  final int itemsCount;

  /// OPEN, CLOSED, PARTIAL, PAID ou OVERDUE.
  final String status;

  factory InvoiceSummary.fromJson(Json j) => InvoiceSummary(
    id: j['id'],
    month: j['month'],
    closingDate: j['closingDate'],
    dueDate: j['dueDate'],
    totalCents: j['totalCents'] as int,
    paidCents: j['paidCents'] as int,
    remainingCents: j['remainingCents'] as int,
    itemsCount: j['itemsCount'] as int,
    status: j['status'],
  );
}

const invoiceStatusLabels = {
  'OPEN': 'Aberta',
  'CLOSED': 'Fechada',
  'PARTIAL': 'Paga em parte',
  'PAID': 'Paga',
  'OVERDUE': 'Atrasada',
};

class CreditCard {
  CreditCard({
    required this.id,
    required this.entityId,
    required this.name,
    this.institution,
    this.brand,
    this.color,
    required this.limitCents,
    required this.usedCents,
    required this.availableCents,
    required this.closingDay,
    required this.dueDay,
    this.paymentAccountId,
    this.paymentAccountName,
    required this.archived,
    required this.currentInvoice,
    required this.pendingInvoices,
  });
  final String id;
  final String entityId;
  final String name;
  final String? institution;
  final String? brand;
  final String? color;
  final int limitCents;
  final int usedCents;
  final int availableCents;
  final int closingDay;
  final int dueDay;
  final String? paymentAccountId;
  final String? paymentAccountName;
  final bool archived;
  final InvoiceSummary currentInvoice;
  final List<InvoiceSummary> pendingInvoices;

  factory CreditCard.fromJson(Json j) => CreditCard(
    id: j['id'],
    entityId: j['entityId'],
    name: j['name'],
    institution: j['institution'],
    brand: j['brand'],
    color: j['color'],
    limitCents: j['limitCents'] as int,
    usedCents: j['usedCents'] as int,
    availableCents: j['availableCents'] as int,
    closingDay: j['closingDay'] as int,
    dueDay: j['dueDay'] as int,
    paymentAccountId: (j['paymentAccount'] as Json?)?['id'],
    paymentAccountName: (j['paymentAccount'] as Json?)?['name'],
    archived: j['archived'] as bool,
    currentInvoice: InvoiceSummary.fromJson(j['currentInvoice']),
    pendingInvoices: (j['pendingInvoices'] as List).map((i) => InvoiceSummary.fromJson(i)).toList(),
  );
}

class InvoiceItem {
  InvoiceItem(this.txn, this.purchaseId, this.installmentNumber, this.installmentCount, this.purchaseDate);
  final Txn txn;
  final String? purchaseId;
  final int installmentNumber;
  final int installmentCount;
  final String? purchaseDate;
}

class InvoicePayment {
  InvoicePayment(this.date, this.amountCents, this.transferId);
  final String date;
  final int amountCents;
  final String? transferId;
}

class Invoice {
  Invoice(this.summary, this.items, this.payments);
  final InvoiceSummary summary;
  final List<InvoiceItem> items;
  final List<InvoicePayment> payments;

  factory Invoice.fromJson(Json j) => Invoice(
    InvoiceSummary.fromJson(j),
    (j['items'] as List).map((t) {
      final inst = t['installment'] as Json?;
      return InvoiceItem(
        Txn.fromJson(t),
        inst?['purchaseId'],
        (inst?['number'] as int?) ?? 1,
        (t['installmentCount'] as int?) ?? 1,
        t['purchaseDate'],
      );
    }).toList(),
    (j['payments'] as List).map((p) => InvoicePayment(p['date'], p['amountCents'] as int, p['transferId'])).toList(),
  );
}

/// Fatura fechada e não quitada, listada em Contas a pagar.
class PendingInvoice {
  PendingInvoice({
    required this.id,
    required this.entityId,
    required this.cardId,
    required this.cardName,
    required this.month,
    required this.dueDate,
    required this.remainingCents,
  });
  final String id;
  final String entityId;
  final String cardId;
  final String cardName;
  final String month;
  final String dueDate;
  final int remainingCents;

  factory PendingInvoice.fromJson(Json j) => PendingInvoice(
    id: j['id'],
    entityId: j['entityId'],
    cardId: j['cardId'],
    cardName: j['cardName'],
    month: j['month'],
    dueDate: j['dueDate'],
    remainingCents: j['remainingCents'] as int,
  );
}

// ───────────── Dívidas ─────────────

const debtKindLabels = {
  'FINANCING': 'Financiamento',
  'LOAN': 'Empréstimo',
  'OVERDRAFT': 'Cheque especial',
  'OTHER': 'Outra dívida',
};

class DebtInstallment {
  DebtInstallment({
    required this.id,
    required this.kind,
    this.number,
    required this.dueDate,
    required this.principalCents,
    required this.interestCents,
    required this.feesCents,
    required this.totalCents,
    required this.balanceAfterCents,
    required this.state,
    required this.paidBeforeApp,
    required this.paidCents,
    this.paidDate,
    required this.penaltyCents,
    this.transactionId,
  });
  final String id;

  /// REGULAR, EXTRA (amortização extraordinária) ou PAYOFF (quitação).
  final String kind;
  final int? number;
  final String dueDate;
  final int principalCents;
  final int interestCents;
  final int feesCents;
  final int totalCents;
  final int balanceAfterCents;

  /// PAID, PARTIAL, OPEN ou OVERDUE.
  final String state;
  final bool paidBeforeApp;
  final int paidCents;
  final String? paidDate;
  final int penaltyCents;
  final String? transactionId;

  factory DebtInstallment.fromJson(Json j) => DebtInstallment(
    id: j['id'],
    kind: j['kind'],
    number: j['number'],
    dueDate: j['dueDate'],
    principalCents: j['principalCents'] as int,
    interestCents: j['interestCents'] as int,
    feesCents: j['feesCents'] as int,
    totalCents: j['totalCents'] as int,
    balanceAfterCents: j['balanceAfterCents'] as int,
    state: j['state'],
    paidBeforeApp: j['paidBeforeApp'] as bool,
    paidCents: j['paidCents'] as int,
    paidDate: j['paidDate'],
    penaltyCents: j['penaltyCents'] as int,
    transactionId: j['transactionId'],
  );
}

class DebtSummary {
  DebtSummary(Json j)
    : outstandingPrincipalCents = j['outstandingPrincipalCents'] as int,
      remainingTotalCents = j['remainingTotalCents'] as int,
      paidPrincipalCents = j['paidPrincipalCents'] as int,
      paidInterestCents = j['paidInterestCents'] as int,
      paidFeesCents = j['paidFeesCents'] as int,
      paidPenaltiesCents = j['paidPenaltiesCents'] as int,
      paidInstallments = j['paidInstallments'] as int,
      remainingInstallments = j['remainingInstallments'] as int,
      overdueInstallments = j['overdueInstallments'] as int,
      progressBps = j['progressBps'] as int,
      nextInstallment = j['nextInstallment'] == null ? null : DebtInstallment.fromJson(j['nextInstallment']);
  final int outstandingPrincipalCents;
  final int remainingTotalCents;
  final int paidPrincipalCents;
  final int paidInterestCents;
  final int paidFeesCents;
  final int paidPenaltiesCents;
  final int paidInstallments;
  final int remainingInstallments;
  final int overdueInstallments;
  final int progressBps;
  final DebtInstallment? nextInstallment;
}

class Debt {
  Debt({
    required this.id,
    required this.entityId,
    required this.kind,
    required this.name,
    this.creditor,
    required this.principalCents,
    required this.monthlyRatePpm,
    required this.system,
    required this.installmentCount,
    required this.startDate,
    required this.firstDueDate,
    required this.feesCents,
    required this.accountId,
    required this.accountName,
    required this.status,
    this.notes,
    required this.summary,
    required this.installments,
  });
  final String id;
  final String entityId;
  final String kind;
  final String name;
  final String? creditor;
  final int principalCents;
  final int monthlyRatePpm;
  final String system;
  final int installmentCount;
  final String startDate;
  final String firstDueDate;
  final int feesCents;
  final String accountId;
  final String accountName;

  /// ACTIVE, PAID_OFF ou CANCELED.
  final String status;
  final String? notes;
  final DebtSummary summary;
  final List<DebtInstallment> installments;

  factory Debt.fromJson(Json j) => Debt(
    id: j['id'],
    entityId: j['entityId'],
    kind: j['kind'],
    name: j['name'],
    creditor: j['creditor'],
    principalCents: j['principalCents'] as int,
    monthlyRatePpm: j['monthlyRatePpm'] as int,
    system: j['system'],
    installmentCount: j['installmentCount'] as int,
    startDate: j['startDate'],
    firstDueDate: j['firstDueDate'],
    feesCents: j['feesCents'] as int,
    accountId: (j['account'] as Json)['id'],
    accountName: (j['account'] as Json)['name'],
    status: j['status'],
    notes: j['notes'],
    summary: DebtSummary(j['summary']),
    installments: ((j['installments'] as List?) ?? const []).map((i) => DebtInstallment.fromJson(i)).toList(),
  );
}

class ScheduleRow {
  ScheduleRow(Json j)
    : number = j['number'] as int,
      dueDate = j['dueDate'],
      principalCents = j['principalCents'] as int,
      interestCents = j['interestCents'] as int,
      feesCents = j['feesCents'] as int,
      totalCents = j['totalCents'] as int,
      balanceAfterCents = j['balanceAfterCents'] as int;
  final int number;
  final String dueDate;
  final int principalCents;
  final int interestCents;
  final int feesCents;
  final int totalCents;
  final int balanceAfterCents;
}

class DebtSimulation {
  DebtSimulation(Json j)
    : rows = (j['installments'] as List).map((r) => ScheduleRow(r)).toList(),
      totalCents = j['totalCents'] as int,
      totalInterestCents = j['totalInterestCents'] as int,
      totalFeesCents = j['totalFeesCents'] as int,
      firstPaymentCents = j['firstPaymentCents'] as int,
      lastPaymentCents = j['lastPaymentCents'] as int;
  final List<ScheduleRow> rows;
  final int totalCents;
  final int totalInterestCents;
  final int totalFeesCents;
  final int firstPaymentCents;
  final int lastPaymentCents;
}

class PayoffQuote {
  PayoffQuote(Json j)
    : date = j['date'],
      overdueCents = j['overdueCents'] as int,
      outstandingPrincipalCents = j['outstandingPrincipalCents'] as int,
      accruedInterestCents = j['accruedInterestCents'] as int,
      payoffCents = j['payoffCents'] as int,
      remainingTotalCents = j['remainingTotalCents'] as int,
      savingsCents = j['savingsCents'] as int;
  final String date;
  final int overdueCents;
  final int outstandingPrincipalCents;
  final int accruedInterestCents;
  final int payoffCents;
  final int remainingTotalCents;
  final int savingsCents;
}

// ───────────── Planejamento ─────────────

class BudgetItem {
  BudgetItem(Json j)
    : id = j['id'],
      categoryId = (j['category'] as Json)['id'],
      categoryName = (j['category'] as Json)['name'],
      categoryIcon = (j['category'] as Json)['icon'] ?? 'category',
      limitCents = j['limitCents'] as int,
      alertThresholdBps = j['alertThresholdBps'] as int,
      spentCents = j['spentCents'] as int,
      committedCents = j['committedCents'] as int,
      state = j['state'],
      usedBps = j['usedBps'] as int,
      remainingCents = j['remainingCents'] as int;
  final String id;
  final String categoryId;
  final String categoryName;
  final String categoryIcon;
  final int limitCents;
  final int alertThresholdBps;
  final int spentCents;
  final int committedCents;

  /// OK, WARNING ou EXCEEDED.
  final String state;
  final int usedBps;
  final int remainingCents;
}

class BudgetsPage {
  BudgetsPage(Json j)
    : month = j['month'],
      items = (j['items'] as List).map((b) => BudgetItem(b)).toList(),
      limitCents = (j['totals'] as Json)['limitCents'] as int,
      spentCents = (j['totals'] as Json)['spentCents'] as int,
      committedCents = (j['totals'] as Json)['committedCents'] as int,
      alerts = (j['alerts'] as List).map((a) => (a as Json)['message'] as String).toList();
  final String month;
  final List<BudgetItem> items;
  final int limitCents;
  final int spentCents;
  final int committedCents;
  final List<String> alerts;
}

class CashHorizon {
  CashHorizon(Json j)
    : days = j['days'] as int,
      until = j['until'],
      incomeConfirmedCents = j['incomeConfirmedCents'] as int,
      incomePlannedCents = j['incomePlannedCents'] as int,
      expenseConfirmedCents = j['expenseConfirmedCents'] as int,
      expensePlannedCents = j['expensePlannedCents'] as int,
      endBalanceConfirmedCents = j['endBalanceConfirmedCents'] as int,
      endBalanceProjectedCents = j['endBalanceProjectedCents'] as int;
  final int days;
  final String until;
  final int incomeConfirmedCents;
  final int incomePlannedCents;
  final int expenseConfirmedCents;
  final int expensePlannedCents;
  final int endBalanceConfirmedCents;
  final int endBalanceProjectedCents;
}

class CashPoint {
  CashPoint(Json j)
    : date = j['date'],
      confirmedCents = j['confirmedCents'] as int,
      projectedCents = j['projectedCents'] as int;
  final String date;
  final int confirmedCents;
  final int projectedCents;
}

class Cashflow {
  Cashflow(Json j)
    : today = j['today'],
      startBalanceCents = j['startBalanceCents'] as int,
      horizons = (j['horizons'] as List).map((h) => CashHorizon(h)).toList(),
      points = (j['points'] as List).map((p) => CashPoint(p)).toList(),
      lowest = CashPoint(j['lowest']),
      alerts = List<String>.from(j['alerts'] as List);
  final String today;
  final int startBalanceCents;
  final List<CashHorizon> horizons;
  final List<CashPoint> points;
  final CashPoint lowest;
  final List<String> alerts;
}

class EmergencyReserve {
  EmergencyReserve(Json j)
    : targetMonths = j['targetMonths'] as int,
      avgMonthlyExpenseCents = j['avgMonthlyExpenseCents'] as int,
      targetCents = j['targetCents'] as int,
      currentCents = j['currentCents'] as int,
      missingCents = j['missingCents'] as int,
      progressBps = j['progressBps'] as int,
      monthsCovered = (j['monthsCovered'] as num?)?.toDouble(),
      customAccounts = j['customAccounts'] as bool,
      accounts = (j['accounts'] as List)
          .map((a) => (id: a['id'] as String, name: a['name'] as String, balanceCents: a['balanceCents'] as int))
          .toList();
  final int targetMonths;
  final int avgMonthlyExpenseCents;
  final int targetCents;
  final int currentCents;
  final int missingCents;
  final int progressBps;
  final double? monthsCovered;
  final bool customAccounts;
  final List<({String id, String name, int balanceCents})> accounts;
}
