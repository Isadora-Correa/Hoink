/**
 * Planejamento (funções puras): projeção de caixa e situação de orçamentos.
 */

export interface CashItem {
  /** Data esperada (vencimento). Itens atrasados devem vir com a data de hoje. */
  date: string;
  /** Valor com sinal: positivo entra, negativo sai. */
  cents: number;
  /** Confirmado (pendente, fatura, parcela de dívida) × apenas previsto (recorrência, estimativa). */
  confirmed: boolean;
}

export interface HorizonSummary {
  days: number;
  until: string;
  incomeConfirmedCents: number;
  incomePlannedCents: number;
  expenseConfirmedCents: number;
  expensePlannedCents: number;
  /** Saldo final considerando só o que está confirmado. */
  endBalanceConfirmedCents: number;
  /** Saldo final considerando confirmado + previsto. */
  endBalanceProjectedCents: number;
}

export interface CashPoint {
  date: string;
  confirmedCents: number;
  projectedCents: number;
}

export interface CashflowProjection {
  today: string;
  startBalanceCents: number;
  horizons: HorizonSummary[];
  points: CashPoint[];
  /** Menor saldo projetado no maior horizonte (alerta de caixa negativo). */
  lowest: CashPoint;
}

const addDays = (iso: string, days: number) => {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
};

/**
 * Projeta o saldo dia a dia a partir do saldo atual, separando receitas/despesas confirmadas das
 * previstas (Seção 14: "Separar receitas previstas de receitas confirmadas").
 */
export function projectCashflow(
  startBalanceCents: number,
  today: string,
  items: CashItem[],
  horizons: number[] = [30, 60, 90],
): CashflowProjection {
  const maxDays = Math.max(...horizons);
  const byDay = new Map<string, { confirmed: number; planned: number }>();
  for (const it of items) {
    const date = it.date < today ? today : it.date;
    const cur = byDay.get(date) ?? { confirmed: 0, planned: 0 };
    if (it.confirmed) cur.confirmed += it.cents;
    else cur.planned += it.cents;
    byDay.set(date, cur);
  }
  const points: CashPoint[] = [];
  let confirmed = startBalanceCents;
  let projected = startBalanceCents;
  for (let d = 0; d <= maxDays; d++) {
    const date = addDays(today, d);
    const day = byDay.get(date);
    if (day) {
      confirmed += day.confirmed;
      projected += day.confirmed + day.planned;
    }
    points.push({ date, confirmedCents: confirmed, projectedCents: projected });
  }
  const summaries = horizons.map((days): HorizonSummary => {
    const until = addDays(today, days);
    const s = {
      days,
      until,
      incomeConfirmedCents: 0,
      incomePlannedCents: 0,
      expenseConfirmedCents: 0,
      expensePlannedCents: 0,
      endBalanceConfirmedCents: points[days]!.confirmedCents,
      endBalanceProjectedCents: points[days]!.projectedCents,
    };
    for (const it of items) {
      if (it.date > until) continue;
      if (it.cents >= 0) {
        if (it.confirmed) s.incomeConfirmedCents += it.cents;
        else s.incomePlannedCents += it.cents;
      } else if (it.confirmed) s.expenseConfirmedCents -= it.cents;
      else s.expensePlannedCents -= it.cents;
    }
    return s;
  });
  const lowest = points.reduce((min, p) => (p.projectedCents < min.projectedCents ? p : min), points[0]!);
  return { today, startBalanceCents, horizons: summaries, points, lowest };
}

export type BudgetState = 'OK' | 'WARNING' | 'EXCEEDED';

/**
 * Situação de um orçamento no mês: estourado se o gasto realizado passou do limite; em alerta se
 * atingiu o limiar (ex.: 80%) ou se gasto + compromissos em aberto vão passar do limite.
 */
export function budgetState(
  b: { limitCents: number; alertThresholdBps: number },
  spentCents: number,
  committedCents: number,
): { state: BudgetState; usedBps: number; remainingCents: number } {
  const usedBps = b.limitCents > 0 ? Math.round((spentCents * 10000) / b.limitCents) : 0;
  let state: BudgetState = 'OK';
  if (spentCents > b.limitCents) state = 'EXCEEDED';
  else if (usedBps >= b.alertThresholdBps || spentCents + committedCents > b.limitCents) state = 'WARNING';
  return { state, usedBps, remainingCents: b.limitCents - spentCents };
}
