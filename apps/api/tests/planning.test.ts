import { beforeEach, describe, expect, it } from 'vitest';
import { addDaysISO } from '../src/domain/recurrence';
import { monthRange, shiftMonth, todayISO } from '../src/lib/dates';
import { categoryId, createAccount, createUser, resetDb, type TestUser } from './helpers';

let u: TestUser;
let base: string;
const today = todayISO();
const month = today.slice(0, 7);

beforeEach(async () => {
  await resetDb();
  u = await createUser();
  base = `/api/entities/${u.personalId}`;
});

describe('planejamento — orçamentos', () => {
  it('soma gasto realizado (inclusive cartão) e compromissos, com alertas', async () => {
    const acc = await createAccount(u, u.personalId, 1_000_000);
    const mercado = await categoryId(u, u.personalId, 'Mercado');
    const lazer = await categoryId(u, u.personalId, 'Lazer');
    expect((await u.api.put(`${base}/planning/budgets`, { categoryId: mercado, limitCents: 100_000 })).status).toBe(200);
    await u.api.put(`${base}/planning/budgets`, { categoryId: lazer, limitCents: 50_000, alertThresholdBps: 5000 });

    await u.api.post(`${base}/transactions`, { type: 'EXPENSE', description: 'Feira', amountCents: 30_000, accountId: acc.id, categoryId: mercado, competenceDate: today });
    await u.api.post(`${base}/transactions`, {
      type: 'EXPENSE',
      description: 'Atacadão',
      amountCents: 80_000,
      accountId: acc.id,
      categoryId: mercado,
      status: 'PENDING',
      competenceDate: monthRange(month).to,
      dueDate: monthRange(month).to,
    });
    const card = (await u.api.post(`${base}/cards`, { name: 'Cartão', limitCents: 100_000, closingDay: 3, dueDay: 10 })).body.data;
    await u.api.post(`${base}/cards/${card.id}/purchases`, { description: 'Cinema', totalCents: 30_000, purchaseDate: today, categoryId: lazer });

    const res = (await u.api.get(`${base}/planning/budgets?month=${month}`)).body.data;
    const m = res.items.find((b: { category: { id: string } }) => b.category.id === mercado);
    const l = res.items.find((b: { category: { id: string } }) => b.category.id === lazer);
    expect(m).toMatchObject({ spentCents: 30_000, committedCents: 80_000, state: 'WARNING', remainingCents: 70_000 });
    expect(l).toMatchObject({ spentCents: 30_000, usedBps: 6000, state: 'WARNING' });
    expect(res.alerts).toHaveLength(2);

    // Atualizar o limite não duplica o orçamento.
    await u.api.put(`${base}/planning/budgets`, { categoryId: mercado, limitCents: 200_000 });
    const again = (await u.api.get(`${base}/planning/budgets`)).body.data;
    expect(again.items).toHaveLength(2);
    expect((await u.api.delete(`${base}/planning/budgets/${m.id}`)).status).toBe(204);

    const income = await categoryId(u, u.personalId, 'Salário');
    expect((await u.api.put(`${base}/planning/budgets`, { categoryId: income, limitCents: 1 })).body.error.code).toBe('INVALID_CATEGORY');
  });
});

describe('planejamento — fluxo de caixa projetado', () => {
  it('separa confirmado (pendentes, faturas, parcelas) de previsto (recorrências)', async () => {
    const acc = await createAccount(u, u.personalId, 500_000);
    const in10 = addDaysISO(today, 10);
    await u.api.post(`${base}/transactions`, {
      type: 'INCOME',
      description: 'Cliente',
      amountCents: 200_000,
      accountId: acc.id,
      status: 'PENDING',
      competenceDate: in10,
      dueDate: in10,
    });
    await u.api.post(`${base}/recurring`, {
      type: 'EXPENSE',
      description: 'Aluguel',
      amountCents: 150_000,
      accountId: acc.id,
      frequency: 'MONTHLY',
      startDate: addDaysISO(today, 5),
    });
    const card = (await u.api.post(`${base}/cards`, { name: 'Cartão', limitCents: 100_000, closingDay: 3, dueDay: 10 })).body.data;
    await u.api.post(`${base}/cards/${card.id}/purchases`, { description: 'Compra', totalCents: 40_000, purchaseDate: today });

    const cf = (await u.api.get(`${base}/planning/cashflow`)).body.data;
    expect(cf.startBalanceCents).toBe(500_000);
    const h90 = cf.horizons[2];
    expect(h90.days).toBe(90);
    expect(h90.incomeConfirmedCents).toBe(200_000);
    expect(h90.expensePlannedCents).toBeGreaterThanOrEqual(300_000);
    expect(h90.expenseConfirmedCents).toBe(40_000);
    expect(h90.endBalanceConfirmedCents).toBe(500_000 + 200_000 - 40_000);
    expect(h90.endBalanceProjectedCents).toBe(h90.endBalanceConfirmedCents - h90.expensePlannedCents);
    expect(cf.points).toHaveLength(91);

    const consolidated = (await u.api.get('/api/consolidated/planning/cashflow')).body.data;
    expect(consolidated.startBalanceCents).toBe(500_000);
  });

  it('alerta quando o saldo projetado fica negativo', async () => {
    const acc = await createAccount(u, u.personalId, 10_000);
    const in3 = addDaysISO(today, 3);
    await u.api.post(`${base}/transactions`, {
      type: 'EXPENSE',
      description: 'Boleto',
      amountCents: 50_000,
      accountId: acc.id,
      status: 'PENDING',
      competenceDate: in3,
      dueDate: in3,
    });
    const cf = (await u.api.get(`${base}/planning/cashflow`)).body.data;
    expect(cf.lowest).toMatchObject({ date: in3, projectedCents: -40_000 });
    expect(cf.alerts).toHaveLength(1);
  });
});

describe('planejamento — reserva de emergência', () => {
  it('meta pela média de despesas e saldo das contas da reserva', async () => {
    const acc = await createAccount(u, u.personalId, 1_000_000);
    const poupanca = (await u.api.post(`${base}/accounts`, {
      name: 'Poupança',
      type: 'SAVINGS',
      initialBalanceCents: 300_000,
      referenceDate: '2025-01-01',
    })).body.data;
    const lastMonth = monthRange(shiftMonth(month, -1)).from;
    await u.api.post(`${base}/transactions`, { type: 'EXPENSE', description: 'Gastos', amountCents: 600_000, accountId: acc.id, competenceDate: lastMonth });

    const r = (await u.api.get(`${base}/planning/reserve`)).body.data;
    expect(r).toMatchObject({ targetMonths: 6, avgMonthlyExpenseCents: 100_000, targetCents: 600_000, currentCents: 300_000, missingCents: 300_000 });
    expect(r).toMatchObject({ progressBps: 5000, monthsCovered: 3, customAccounts: false });

    const updated = (await u.api.put(`${base}/planning/reserve`, { targetMonths: 3, accountIds: [acc.id, poupanca.id] })).body.data;
    expect(updated).toMatchObject({ targetMonths: 3, targetCents: 300_000, customAccounts: true, progressBps: 10000 });
  });
});
