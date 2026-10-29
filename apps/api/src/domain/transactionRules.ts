import type { Direction, StoredTransactionStatus, TransactionStatus, TransactionType } from '../contracts';

export class DomainError extends Error {
  constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

/** Sentido fixo por tipo; ADJUSTMENT exige sentido explícito; REFUND é entrada por padrão. */
const FIXED_DIRECTION: Partial<Record<TransactionType, Direction>> = {
  INCOME: 'IN',
  EXPENSE: 'OUT',
  CONTRIBUTION: 'OUT',
  REDEMPTION: 'IN',
  WITHDRAWAL: 'OUT',
};

export function resolveDirection(type: TransactionType, requested?: Direction): Direction {
  const fixed = FIXED_DIRECTION[type];
  if (fixed) {
    if (requested && requested !== fixed) {
      throw new DomainError('INVALID_DIRECTION', `Lançamentos do tipo ${type} sempre têm sentido ${fixed}`);
    }
    return fixed;
  }
  if (type === 'REFUND') return requested ?? 'IN';
  if (type === 'ADJUSTMENT') {
    if (!requested) throw new DomainError('DIRECTION_REQUIRED', 'Ajustes exigem o sentido (entrada ou saída)');
    return requested;
  }
  if (type === 'TRANSFER') throw new DomainError('USE_TRANSFER', 'Transferências possuem fluxo próprio');
  return requested ?? 'OUT';
}

/** Categoria compatível com o tipo do lançamento. */
export function expectedCategoryKind(type: TransactionType): 'INCOME' | 'EXPENSE' | null {
  if (type === 'INCOME') return 'INCOME';
  if (type === 'EXPENSE' || type === 'REFUND') return 'EXPENSE';
  return null;
}

export interface SettlementInput {
  status: StoredTransactionStatus;
  amountCents: number;
  settledAmountCents?: number;
  settledDate?: string | null;
  competenceDate: string;
}

/**
 * Normaliza a parte liquidada de um lançamento (RN06: previsto ≠ realizado).
 * Somente `settledAmountCents` afeta o saldo das contas.
 */
export function normalizeSettlement(input: SettlementInput): { settledAmountCents: number; settledDate: string | null } {
  switch (input.status) {
    case 'SETTLED':
      return { settledAmountCents: input.amountCents, settledDate: input.settledDate ?? input.competenceDate };
    case 'PARTIAL': {
      const s = input.settledAmountCents ?? 0;
      if (s <= 0 || s >= input.amountCents) {
        throw new DomainError('INVALID_PARTIAL', 'Valor liquidado parcial deve ser maior que zero e menor que o total');
      }
      return { settledAmountCents: s, settledDate: input.settledDate ?? input.competenceDate };
    }
    default:
      return { settledAmountCents: 0, settledDate: null };
  }
}

/** Status exibido: lançamentos em aberto com vencimento passado aparecem como Atrasado. */
export function effectiveStatus(
  status: StoredTransactionStatus,
  dueDate: string | null,
  competenceDate: string,
  today: string,
): TransactionStatus {
  if (status === 'PLANNED' || status === 'PENDING' || status === 'PARTIAL') {
    if ((dueDate ?? competenceDate) < today) return 'OVERDUE';
  }
  return status;
}

export function signed(direction: Direction, cents: number): number {
  return direction === 'IN' ? cents : -cents;
}
