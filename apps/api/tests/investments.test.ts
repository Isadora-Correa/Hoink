import { Prisma } from '@prisma/client';
import { beforeEach, describe, expect, it } from 'vitest';
import { addDaysISO } from '../src/domain/recurrence';
import { parseDate, todayISO } from '../src/lib/dates';
import { prisma } from '../src/lib/prisma';
import { balanceOf, createAccount, createUser, resetDb, type TestUser } from './helpers';

let u: TestUser;
let base: string;
let acc: { id: string };
const today = todayISO();

beforeEach(async () => {
  await resetDb();
  u = await createUser();
  base = `/api/entities/${u.personalId}`;
  acc = await createAccount(u, u.personalId, 5_000_000);
});

async function seedCdi(daysBack: number, rate = '0.05') {
  const data = [];
  for (let d = addDaysISO(today, -daysBack); d <= today; d = addDaysISO(d, 1)) {
    data.push({ index: 'CDI' as const, date: parseDate(d), ratePct: new Prisma.Decimal(rate), source: 'BCB' as const });
  }
  await prisma.marketRate.createMany({ data });
}

describe('investimentos — motores por produto', () => {
  it('CDB % do CDI: aporte sai do caixa sem ser despesa e o valor é estimado pelo índice', async () => {
    await seedCdi(20);
    const start = addDaysISO(today, -20);
    const res = await u.api.post(`${base}/investments`, {
      kind: 'CDB',
      name: 'CDB Banco X 110% CDI',
      indexer: 'CDI_PERCENT',
      rateBps: 11000,
      maturityDate: addDaysISO(today, 700),
      initial: { date: start, amountCents: 1_000_000, accountId: acc.id },
    });
    expect(res.status).toBe(201);
    const inv = res.body.data;
    expect(inv).toMatchObject({ principalCents: 1_000_000, valueSource: 'ESTIMATED', taxation: 'REGRESSIVE' });
    expect(inv.valueCents).toBe(Math.round(1_000_000 * Math.pow(1 + 0.0005 * 1.1, 20)));
    expect(inv.gainCents).toBe(inv.valueCents - 1_000_000);
    expect(inv.taxEstimatedCents).toBeGreaterThan(0);
    expect(await balanceOf(u, u.personalId, acc.id)).toBe(4_000_000);
    const dash = (await u.api.get(`${base}/dashboard`)).body.data;
    expect(dash.realized).toMatchObject({ expenseCents: 0, incomeCents: 0, contributionsCents: 1_000_000 });

    // Valor do extrato vira o ponto de partida (efetivo).
    const informed = (await u.api.post(`${base}/investments/${inv.id}/value`, { date: today, valueCents: 1_011_500 })).body.data;
    expect(informed).toMatchObject({ valueCents: 1_011_500, valueSource: 'INFORMED' });

    const red = (await u.api.post(`${base}/investments/${inv.id}/redemptions`, { date: today, amountCents: 500_000, accountId: acc.id })).body.data;
    expect(red.valueCents).toBe(511_500);
    expect(await balanceOf(u, u.personalId, acc.id)).toBe(4_500_000);
    const tooMuch = await u.api.post(`${base}/investments/${inv.id}/redemptions`, { date: today, amountCents: 9_000_000, accountId: acc.id });
    expect(tooMuch.body.error.code).toBe('INSUFFICIENT_POSITION');
    expect(red.history.length).toBeGreaterThan(0);
  });

  it('LCI é isenta e prefixado não depende de série', async () => {
    const inv = (
      await u.api.post(`${base}/investments`, {
        kind: 'LCI',
        name: 'LCI 12% a.a.',
        indexer: 'PREFIXED',
        rateBps: 1200,
        initial: { date: addDaysISO(today, -30), amountCents: 100_000 },
      })
    ).body.data;
    expect(inv.taxation).toBe('EXEMPT');
    expect(inv.taxEstimatedCents).toBe(0);
    expect(inv.valueCents).toBeGreaterThan(100_000);
    expect(await balanceOf(u, u.personalId, acc.id)).toBe(5_000_000); // posição anterior ao app: sem perna de caixa
  });

  it('ações: cotas × preço informado, sem inventar cotação, com aviso de desatualizado', async () => {
    const bad = await u.api.post(`${base}/investments`, { kind: 'STOCK', name: 'Petrobras', indexer: 'CDI_PERCENT' });
    expect(bad.status).toBe(400);
    const inv = (
      await u.api.post(`${base}/investments`, {
        kind: 'STOCK',
        name: 'Itaúsa',
        ticker: 'itsa4',
        indexer: 'MARKET',
        initial: { date: addDaysISO(today, -30), amountCents: 100_000, quantity: 100, accountId: acc.id },
      })
    ).body.data;
    expect(inv).toMatchObject({ ticker: 'ITSA4', quantity: 100, unitPrice: 1000, valueCents: 100_000, valueSource: 'MARKET_PRICE', stale: true, taxation: 'STOCKS' });
    const updated = (await u.api.post(`${base}/investments/${inv.id}/value`, { date: today, unitPriceCents: 1150 })).body.data;
    expect(updated).toMatchObject({ valueCents: 115_000, gainCents: 15_000, stale: false, taxEstimatedCents: 2_250 });
    const div = (await u.api.post(`${base}/investments/${inv.id}/income`, { date: today, amountCents: 800, accountId: acc.id })).body.data;
    expect(div.incomeReceivedCents).toBe(800);
    expect(div.returnBps).toBe(1580);
    const sell = await u.api.post(`${base}/investments/${inv.id}/redemptions`, { date: today, amountCents: 57_500, quantity: 50, accountId: acc.id });
    expect(sell.body.data).toMatchObject({ quantity: 50, valueCents: 57_500 });
    const del = await u.api.delete(`${base}/investments/${inv.id}/movements/${sell.body.data.movements[0].id}`);
    expect(del.body.data.quantity).toBe(100);
  });

  it('isola investimentos entre usuários', async () => {
    const inv = (await u.api.post(`${base}/investments`, { kind: 'OTHER', name: 'Consórcio', indexer: 'MANUAL' })).body.data;
    const other = await createUser('Outra');
    expect((await other.api.get(`${base}/investments/${inv.id}`)).status).toBe(404);
  });
});

describe('patrimônio', () => {
  it('ativos − passivos sem dupla contagem, com histórico mensal', async () => {
    const piggy = (await u.api.post(`${base}/piggy-banks`, { name: 'Viagem' })).body.data.piggy.id;
    await u.api.post(`${base}/piggy-banks/${piggy}/deposit`, { accountId: acc.id, amountCents: 200_000, date: today });
    await u.api.post(`${base}/investments`, {
      kind: 'OTHER',
      name: 'Previdência',
      indexer: 'MANUAL',
      initial: { date: today, amountCents: 300_000, accountId: acc.id },
    });
    const card = (await u.api.post(`${base}/cards`, { name: 'Cartão', limitCents: 500_000, closingDay: 3, dueDay: 10 })).body.data;
    await u.api.post(`${base}/cards/${card.id}/purchases`, { description: 'TV', totalCents: 120_000, installments: 3, purchaseDate: today });
    await u.api.post(`${base}/debts`, {
      kind: 'LOAN',
      name: 'Empréstimo',
      principalCents: 1_000_000,
      monthlyRatePpm: 10_000,
      installmentCount: 10,
      startDate: today,
      firstDueDate: addDaysISO(today, 30),
      accountId: acc.id,
    });
    const item = await u.api.post(`${base}/patrimony/items`, { side: 'ASSET', category: 'Veículo', name: 'Moto', valueCents: 1_500_000, valuedAt: today });
    expect(item.status).toBe(201);

    const p = (await u.api.get(`${base}/patrimony`)).body.data;
    expect(p.assets).toMatchObject({ cashCents: 4_500_000, piggyBanksCents: 200_000, investmentsCents: 300_000, otherCents: 1_500_000, totalCents: 6_500_000 });
    expect(p.liabilities).toMatchObject({ cardsCents: 120_000, debtsCents: 1_000_000, totalCents: 1_120_000 });
    expect(p.netWorthCents).toBe(5_380_000);
    expect(p.history.at(-1)).toMatchObject({ month: today.slice(0, 7), netWorthCents: 5_380_000 });
    expect(await prisma.netWorthSnapshot.count()).toBeGreaterThan(0);

    const consolidated = (await u.api.get('/api/consolidated/patrimony')).body.data;
    expect(consolidated.netWorthCents).toBe(5_380_000);

    expect((await u.api.delete(`${base}/patrimony/items/${item.body.data.id}`)).status).toBe(204);
    expect((await u.api.get(`${base}/patrimony`)).body.data.netWorthCents).toBe(3_880_000);
  });
});
