import { describe, expect, it } from 'vitest';
import { invoiceDates, invoiceForPurchase, invoiceStatus, splitInstallments } from './cards';
import { amortizationSchedule, payoffQuote, remainingTerm } from './debts';
import { budgetState, projectCashflow } from './planning';

describe('cartões — faturas', () => {
  it('fechamento antes do vencimento no mesmo mês', () => {
    expect(invoiceDates('2026-04', 3, 10)).toEqual({ month: '2026-04', closingDate: '2026-04-03', dueDate: '2026-04-10' });
  });

  it('vencimento antes do fechamento: fecha no mês anterior', () => {
    expect(invoiceDates('2026-04', 28, 5)).toEqual({ month: '2026-04', closingDate: '2026-03-28', dueDate: '2026-04-05' });
  });

  it('dias inexistentes no mês são ajustados para o último dia', () => {
    expect(invoiceDates('2026-03', 31, 10).closingDate).toBe('2026-02-28');
  });

  it('compra antes do fechamento entra na fatura atual; no dia do fechamento ou depois, na seguinte', () => {
    expect(invoiceForPurchase('2026-04-02', 3, 10).month).toBe('2026-04');
    expect(invoiceForPurchase('2026-04-03', 3, 10).month).toBe('2026-05');
    expect(invoiceForPurchase('2026-03-27', 28, 5).month).toBe('2026-04');
    expect(invoiceForPurchase('2026-03-28', 28, 5).month).toBe('2026-05');
    expect(invoiceForPurchase('2026-12-30', 28, 5).month).toBe('2027-02');
  });

  it('parcelas somam exatamente o total, com o resto na primeira', () => {
    expect(splitInstallments(10000, 3)).toEqual([3334, 3333, 3333]);
    expect(splitInstallments(99, 1)).toEqual([99]);
    const p = splitInstallments(123457, 10);
    expect(p.reduce((a, b) => a + b, 0)).toBe(123457);
    expect(() => splitInstallments(100, 0)).toThrow();
  });

  it('situação da fatura', () => {
    const inv = { closingDate: '2026-04-03', dueDate: '2026-04-10', totalCents: 1000, paidCents: 0 };
    expect(invoiceStatus(inv, '2026-04-02')).toBe('OPEN');
    expect(invoiceStatus(inv, '2026-04-05')).toBe('CLOSED');
    expect(invoiceStatus({ ...inv, paidCents: 400 }, '2026-04-05')).toBe('PARTIAL');
    expect(invoiceStatus({ ...inv, paidCents: 1000 }, '2026-04-05')).toBe('PAID');
    expect(invoiceStatus(inv, '2026-04-11')).toBe('OVERDUE');
  });
});

describe('dívidas — amortização', () => {
  const base = { principalCents: 1_000_000, monthlyRatePpm: 10_000, installments: 12, firstDueDate: '2026-01-31' };

  it('PRICE: parcelas iguais, juros decrescentes e principal exato', () => {
    const rows = amortizationSchedule({ ...base, system: 'PRICE' });
    expect(rows[0]).toMatchObject({ number: 1, interestCents: 10_000, principalCents: 78_849, totalCents: 88_849 });
    expect(rows.slice(0, 11).every((r) => r.totalCents === 88_849)).toBe(true);
    expect(rows.reduce((s, r) => s + r.principalCents, 0)).toBe(1_000_000);
    expect(rows.at(-1)!.balanceAfterCents).toBe(0);
    expect(rows.map((r) => r.dueDate).slice(0, 3)).toEqual(['2026-01-31', '2026-02-28', '2026-03-31']);
  });

  it('SAC: amortização constante e parcelas decrescentes', () => {
    const rows = amortizationSchedule({ ...base, system: 'SAC', feesCents: 500 });
    expect(rows[0]).toMatchObject({ principalCents: 83_333, interestCents: 10_000, feesCents: 500, totalCents: 93_833 });
    expect(rows[1]!.totalCents).toBeLessThan(rows[0]!.totalCents);
    expect(rows.reduce((s, r) => s + r.principalCents, 0)).toBe(1_000_000);
  });

  it('juros zero divide o principal igualmente', () => {
    const rows = amortizationSchedule({ ...base, monthlyRatePpm: 0, installments: 3, system: 'PRICE' });
    expect(rows.map((r) => r.totalCents)).toEqual([333_333, 333_333, 333_334]);
  });

  it('prazo restante mantendo a parcela', () => {
    expect(remainingTerm(500_000, 10_000, 'PRICE', { paymentCents: 88_849, amortizationCents: 0 })).toBe(6);
    expect(remainingTerm(500_000, 0, 'SAC', { paymentCents: 0, amortizationCents: 83_333 })).toBe(7);
    expect(remainingTerm(0, 10_000, 'PRICE', { paymentCents: 1, amortizationCents: 0 })).toBe(0);
  });

  it('quitação antecipada desconta juros futuros e cobra juros pro rata', () => {
    const rows = amortizationSchedule({ ...base, system: 'PRICE' });
    const open = rows.slice(6);
    const q = payoffQuote(open, 10_000, '2026-07-15', '2026-06-30');
    const outstanding = open.reduce((s, r) => s + r.principalCents, 0);
    expect(q.outstandingPrincipalCents).toBe(outstanding);
    expect(q.accruedInterestCents).toBe(Math.round(outstanding * (Math.pow(1.01, 15 / 30) - 1)));
    expect(q.payoffCents).toBe(outstanding + q.accruedInterestCents);
    expect(q.savingsCents).toBeGreaterThan(0);
    expect(q.remainingTotalCents).toBe(open.reduce((s, r) => s + r.totalCents, 0));
  });

  it('parcelas vencidas entram pelo valor integral na quitação', () => {
    const open = [
      { dueDate: '2026-01-10', principalCents: 1000, interestCents: 100, feesCents: 0 },
      { dueDate: '2026-02-10', principalCents: 1000, interestCents: 50, feesCents: 0 },
    ];
    const q = payoffQuote(open, 0, '2026-01-20', '2026-01-10');
    expect(q).toMatchObject({ overdueCents: 1100, outstandingPrincipalCents: 1000, accruedInterestCents: 0, payoffCents: 2100 });
  });
});

describe('planejamento', () => {
  it('projeção separa confirmado de previsto e acumula por dia', () => {
    const p = projectCashflow(100_000, '2026-04-01', [
      { date: '2026-03-20', cents: -10_000, confirmed: true }, // atrasado: conta hoje
      { date: '2026-04-05', cents: 50_000, confirmed: false },
      { date: '2026-04-10', cents: -30_000, confirmed: true },
      { date: '2026-05-20', cents: -200_000, confirmed: false },
    ]);
    const h30 = p.horizons[0]!;
    expect(h30).toMatchObject({
      days: 30,
      incomePlannedCents: 50_000,
      expenseConfirmedCents: 40_000,
      endBalanceConfirmedCents: 60_000,
      endBalanceProjectedCents: 110_000,
    });
    expect(p.points[0]).toEqual({ date: '2026-04-01', confirmedCents: 90_000, projectedCents: 90_000 });
    expect(p.horizons[2]!.endBalanceProjectedCents).toBe(-90_000);
    expect(p.lowest).toMatchObject({ date: '2026-05-20', projectedCents: -90_000 });
    expect(p.points).toHaveLength(91);
  });

  it('orçamento: ok, alerta pelo limiar, alerta por compromissos e estourado', () => {
    const b = { limitCents: 100_000, alertThresholdBps: 8000 };
    expect(budgetState(b, 50_000, 0)).toEqual({ state: 'OK', usedBps: 5000, remainingCents: 50_000 });
    expect(budgetState(b, 80_000, 0).state).toBe('WARNING');
    expect(budgetState(b, 50_000, 60_000).state).toBe('WARNING');
    expect(budgetState(b, 120_000, 0)).toMatchObject({ state: 'EXCEEDED', remainingCents: -20_000 });
  });
});
