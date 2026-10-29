import { describe, expect, it } from 'vitest';
import { applyShare, consolidate } from './consolidation';
import { flowTotals } from './flows';
import { effectiveStatus, normalizeSettlement, resolveDirection } from './transactionRules';

describe('resolveDirection', () => {
  it('fixa o sentido de receitas e despesas', () => {
    expect(resolveDirection('INCOME')).toBe('IN');
    expect(resolveDirection('EXPENSE')).toBe('OUT');
    expect(() => resolveDirection('EXPENSE', 'IN')).toThrow();
  });
  it('exige sentido em ajustes', () => {
    expect(() => resolveDirection('ADJUSTMENT')).toThrow();
    expect(resolveDirection('ADJUSTMENT', 'IN')).toBe('IN');
  });
});

describe('normalizeSettlement (RN06)', () => {
  const base = { amountCents: 10000, competenceDate: '2025-06-10' };
  it('liquidado usa o valor total', () => {
    expect(normalizeSettlement({ ...base, status: 'SETTLED' })).toEqual({
      settledAmountCents: 10000,
      settledDate: '2025-06-10',
    });
  });
  it('pendente e previsto não liquidam nada', () => {
    expect(normalizeSettlement({ ...base, status: 'PENDING', settledAmountCents: 500 }).settledAmountCents).toBe(0);
    expect(normalizeSettlement({ ...base, status: 'PLANNED' }).settledDate).toBeNull();
  });
  it('parcial exige valor intermediário', () => {
    expect(normalizeSettlement({ ...base, status: 'PARTIAL', settledAmountCents: 4000 }).settledAmountCents).toBe(4000);
    expect(() => normalizeSettlement({ ...base, status: 'PARTIAL', settledAmountCents: 10000 })).toThrow();
  });
});

describe('effectiveStatus', () => {
  it('marca em aberto vencido como atrasado', () => {
    expect(effectiveStatus('PENDING', '2025-06-01', '2025-05-20', '2025-06-02')).toBe('OVERDUE');
    expect(effectiveStatus('PENDING', '2025-06-02', '2025-05-20', '2025-06-02')).toBe('PENDING');
    expect(effectiveStatus('SETTLED', '2025-06-01', '2025-05-20', '2025-06-10')).toBe('SETTLED');
  });
});

describe('flowTotals', () => {
  it('transferências, aportes e resgates não são receita nem despesa (RN01–RN03)', () => {
    const t = flowTotals([
      { type: 'INCOME', direction: 'IN', cents: 780000 },
      { type: 'EXPENSE', direction: 'OUT', cents: 490000 },
      { type: 'REFUND', direction: 'IN', cents: 10000 },
      { type: 'TRANSFER', direction: 'OUT', cents: 50000 },
      { type: 'TRANSFER', direction: 'IN', cents: 50000 },
      { type: 'CONTRIBUTION', direction: 'OUT', cents: 100000 },
      { type: 'REDEMPTION', direction: 'IN', cents: 20000 },
    ]);
    expect(t.incomeCents).toBe(780000);
    expect(t.expenseCents).toBe(480000);
    expect(t.netCents).toBe(300000);
    expect(t.cashChangeCents).toBe(780000 - 490000 + 10000 - 100000 + 20000);
  });
});

describe('consolidação', () => {
  it('pondera pela participação', () => {
    expect(applyShare(10001, 5000)).toBe(5001);
    expect(applyShare(-10001, 5000)).toBe(-5001);
    expect(
      consolidate([
        { entityId: 'a', shareBps: 10000, values: { balance: 1000 } },
        { entityId: 'b', shareBps: 5000, values: { balance: 3000 } },
      ]),
    ).toEqual({ balance: 2500 });
  });
});
