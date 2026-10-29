import type { Direction, TransactionType } from '../contracts';

export interface FlowGroup {
  type: TransactionType;
  direction: Direction;
  cents: number;
}

export interface FlowTotals {
  /** Receitas (somente INCOME). */
  incomeCents: number;
  /** Despesas de consumo/operação (EXPENSE), líquidas de reembolsos recebidos (REFUND IN). */
  expenseCents: number;
  /** Resultado = receitas − despesas. */
  netCents: number;
  /** Movimentações patrimoniais que não são receita nem despesa (RN01–RN03). */
  transfersInCents: number;
  transfersOutCents: number;
  contributionsCents: number;
  redemptionsCents: number;
  withdrawalsCents: number;
  adjustmentsCents: number;
  /** Variação total de caixa (todas as movimentações com sinal). */
  cashChangeCents: number;
}

/**
 * Regra única de classificação de fluxos, compartilhada por dashboard e relatórios (RN13).
 */
export function flowTotals(groups: FlowGroup[]): FlowTotals {
  const t: FlowTotals = {
    incomeCents: 0,
    expenseCents: 0,
    netCents: 0,
    transfersInCents: 0,
    transfersOutCents: 0,
    contributionsCents: 0,
    redemptionsCents: 0,
    withdrawalsCents: 0,
    adjustmentsCents: 0,
    cashChangeCents: 0,
  };
  for (const g of groups) {
    const s = g.direction === 'IN' ? g.cents : -g.cents;
    t.cashChangeCents += s;
    switch (g.type) {
      case 'INCOME':
        t.incomeCents += g.cents;
        break;
      case 'EXPENSE':
        t.expenseCents += g.cents;
        break;
      case 'REFUND':
        // Reembolso recebido abate despesas; reembolso pago (OUT) é tratado como despesa.
        t.expenseCents -= s;
        break;
      case 'TRANSFER':
        if (g.direction === 'IN') t.transfersInCents += g.cents;
        else t.transfersOutCents += g.cents;
        break;
      case 'CONTRIBUTION':
        t.contributionsCents += g.cents;
        break;
      case 'REDEMPTION':
        t.redemptionsCents += g.cents;
        break;
      case 'WITHDRAWAL':
        t.withdrawalsCents += g.cents;
        break;
      case 'ADJUSTMENT':
        t.adjustmentsCents += s;
        break;
    }
  }
  t.netCents = t.incomeCents - t.expenseCents;
  return t;
}
