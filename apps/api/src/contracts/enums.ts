export const ENTITY_KINDS = ['PERSONAL', 'BUSINESS'] as const;
export type EntityKind = (typeof ENTITY_KINDS)[number];

export const MEMBER_ROLES = ['OWNER', 'ADMIN', 'MEMBER', 'VIEWER'] as const;
export type MemberRole = (typeof MEMBER_ROLES)[number];

export const ACCOUNT_TYPES = ['CHECKING', 'PAYMENT', 'SAVINGS', 'WALLET', 'BROKERAGE', 'OTHER'] as const;
export type AccountType = (typeof ACCOUNT_TYPES)[number];

export const ACCOUNT_TYPE_LABELS: Record<AccountType, string> = {
  CHECKING: 'Conta corrente',
  PAYMENT: 'Conta de pagamento',
  SAVINGS: 'Poupança',
  WALLET: 'Carteira',
  BROKERAGE: 'Corretora',
  OTHER: 'Outros',
};

export const CATEGORY_KINDS = ['INCOME', 'EXPENSE'] as const;
export type CategoryKind = (typeof CATEGORY_KINDS)[number];

/**
 * Tipos de lançamento. Apenas INCOME e EXPENSE entram em receitas/despesas
 * (RN01, RN02, RN03). Os demais movimentam caixa sem representar consumo/renda.
 */
export const TRANSACTION_TYPES = [
  'INCOME',
  'EXPENSE',
  'TRANSFER',
  'CONTRIBUTION',
  'REDEMPTION',
  'REFUND',
  'ADJUSTMENT',
  'WITHDRAWAL',
] as const;
export type TransactionType = (typeof TRANSACTION_TYPES)[number];

export const TRANSACTION_TYPE_LABELS: Record<TransactionType, string> = {
  INCOME: 'Receita',
  EXPENSE: 'Despesa',
  TRANSFER: 'Transferência',
  CONTRIBUTION: 'Aporte',
  REDEMPTION: 'Resgate',
  REFUND: 'Reembolso',
  ADJUSTMENT: 'Ajuste',
  WITHDRAWAL: 'Retirada',
};

export const DIRECTIONS = ['IN', 'OUT'] as const;
export type Direction = (typeof DIRECTIONS)[number];

/** Status persistidos. OVERDUE é derivado (pendente/previsto com vencimento passado). */
export const STORED_TRANSACTION_STATUSES = ['PLANNED', 'PENDING', 'PARTIAL', 'SETTLED', 'CANCELED'] as const;
export type StoredTransactionStatus = (typeof STORED_TRANSACTION_STATUSES)[number];

export const TRANSACTION_STATUSES = [...STORED_TRANSACTION_STATUSES, 'OVERDUE'] as const;
export type TransactionStatus = (typeof TRANSACTION_STATUSES)[number];

export const TRANSACTION_STATUS_LABELS: Record<TransactionStatus, string> = {
  PLANNED: 'Previsto',
  PENDING: 'Pendente',
  PARTIAL: 'Parcialmente liquidado',
  SETTLED: 'Concluído',
  OVERDUE: 'Atrasado',
  CANCELED: 'Cancelado',
};

/** Classificação gerencial de transferências (RN09). */
export const TRANSFER_CLASSIFICATIONS = [
  'INTERNAL',
  'OWNER_CONTRIBUTION',
  'OWNER_WITHDRAWAL',
  'PRO_LABORE',
  'PROFIT_DISTRIBUTION',
  'LOAN_TO_ENTITY',
  'LOAN_REPAYMENT',
  'EXPENSE_REIMBURSEMENT',
] as const;
export type TransferClassification = (typeof TRANSFER_CLASSIFICATIONS)[number];

export const TRANSFER_CLASSIFICATION_LABELS: Record<TransferClassification, string> = {
  INTERNAL: 'Entre contas próprias',
  OWNER_CONTRIBUTION: 'Aporte de capital do sócio',
  OWNER_WITHDRAWAL: 'Retirada do sócio',
  PRO_LABORE: 'Pró-labore',
  PROFIT_DISTRIBUTION: 'Distribuição de lucros',
  LOAN_TO_ENTITY: 'Empréstimo entre ambientes',
  LOAN_REPAYMENT: 'Devolução de empréstimo',
  EXPENSE_REIMBURSEMENT: 'Reembolso de despesa',
};
