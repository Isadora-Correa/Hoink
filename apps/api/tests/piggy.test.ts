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
  acc = await createAccount(u, u.personalId, 1_000_000);
});

const ps5 = { kind: 'WISH', name: 'PS5 para o namorado', goalCents: 400_000, link: 'https://loja.exemplo/ps5', priority: 1 };

describe('cofrinhos e lista de desejos', () => {
  it('guardar e retirar são transferências: o dinheiro não existe nos dois lugares', async () => {
    const created = await u.api.post(`${base}/piggy-banks`, ps5);
    expect(created.status).toBe(201);
    const id = created.body.data.piggy.id;
    expect(created.body.data.unlocked.map((a: { code: string }) => a.code)).toEqual(expect.arrayContaining(['FIRST_PIGGY', 'FIRST_WISH']));

    const dep = await u.api.post(`${base}/piggy-banks/${id}/deposit`, { accountId: acc.id, amountCents: 100_000, date: today });
    expect(dep.status).toBe(200);
    expect(dep.body.data.piggy).toMatchObject({ balanceCents: 100_000, principalCents: 100_000, progressBps: 2500, missingCents: 300_000 });
    expect(dep.body.data.unlocked.map((a: { code: string }) => a.code)).toEqual(expect.arrayContaining(['FIRST_DEPOSIT', 'GOAL_25', 'SAVED_1K']));
    expect(await balanceOf(u, u.personalId, acc.id)).toBe(900_000);

    // Saldo disponível não inclui o cofrinho; receitas/despesas não mudam.
    const dash = (await u.api.get(`${base}/dashboard`)).body.data;
    expect(dash.totalBalanceCents).toBe(900_000);
    expect(dash.realized.expenseCents).toBe(0);

    const tooMuch = await u.api.post(`${base}/piggy-banks/${id}/withdraw`, { accountId: acc.id, amountCents: 200_000, date: today });
    expect(tooMuch.body.error.code).toBe('INSUFFICIENT_BALANCE');
    await u.api.post(`${base}/piggy-banks/${id}/withdraw`, { accountId: acc.id, amountCents: 30_000, date: today });
    expect(await balanceOf(u, u.personalId, acc.id)).toBe(930_000);
    const got = (await u.api.get(`${base}/piggy-banks/${id}`)).body.data;
    expect(got.balanceCents).toBe(70_000);
    expect(got.movements.map((m: { kind: string }) => m.kind)).toEqual(['WITHDRAWAL', 'DEPOSIT']);

    // Lançamento direto no cofrinho é recusado.
    const direct = await u.api.post(`${base}/transactions`, { type: 'EXPENSE', description: 'x', amountCents: 1, accountId: id, competenceDate: today });
    expect(direct.body.error.code).toBe('USE_PIGGY_BANK');
  });

  it('desejo realizado: retira o saldo, lança a compra uma única vez e dá conquista', async () => {
    const id = (await u.api.post(`${base}/piggy-banks`, ps5)).body.data.piggy.id;
    await u.api.post(`${base}/piggy-banks/${id}/deposit`, { accountId: acc.id, amountCents: 400_000, date: today });
    const done = await u.api.post(`${base}/piggy-banks/${id}/achieve`, { accountId: acc.id, date: today, purchaseCents: 389_900, description: 'PS5' });
    expect(done.status).toBe(200);
    expect(done.body.data.piggy).toMatchObject({ achievedAt: today, balanceCents: 0 });
    expect(done.body.data.unlocked.map((a: { code: string }) => a.code)).toContain('WISH_ACHIEVED');
    expect(await balanceOf(u, u.personalId, acc.id)).toBe(1_000_000 - 389_900);
    const dash = (await u.api.get(`${base}/dashboard`)).body.data;
    expect(dash.realized.expenseCents).toBe(389_900);

    const profile = (await u.api.get('/api/gamification')).body.data;
    expect(profile.points).toBeGreaterThanOrEqual(100);
    expect(profile.unlocked.find((a: { code: string }) => a.code === 'GOAL_100')).toBeTruthy();
    expect(profile.streak).toMatchObject({ current: 1, depositedThisWeek: true });
  });

  it('rendimento: estimado pelo CDI guardado (não gravado) e efetivo ao confirmar o saldo do banco', async () => {
    const days: string[] = [];
    for (let d = addDaysISO(today, -10); d <= today; d = addDaysISO(d, 1)) days.push(d);
    await prisma.marketRate.createMany({ data: days.map((d) => ({ index: 'CDI' as const, date: parseDate(d), ratePct: new Prisma.Decimal('0.05'), source: 'BCB' as const })) });
    const id = (
      await u.api.post(`${base}/piggy-banks`, { kind: 'RESERVE', name: 'Reserva', goalCents: 2_000_000, yieldKind: 'CDI_PERCENT', yieldRateBps: 11500 })
    ).body.data.piggy.id;
    await u.api.post(`${base}/piggy-banks/${id}/deposit`, { accountId: acc.id, amountCents: 500_000, date: addDaysISO(today, -10) });

    const p = (await u.api.get(`${base}/piggy-banks/${id}`)).body.data;
    expect(p.yieldLabel).toBe('115% do CDI');
    expect(p.balanceCents).toBe(500_000);
    expect(p.estimatedYieldCents).toBe(Math.round(500_000 * Math.pow(1 + 0.0005 * 1.15, 10)) - 500_000);
    expect(p.grossEstimatedCents).toBe(500_000 + p.estimatedYieldCents);
    expect(p.taxEstimatedCents).toBeGreaterThan(0);
    expect(p.netEstimatedCents).toBeLessThan(p.grossEstimatedCents);

    const conf = await u.api.post(`${base}/piggy-banks/${id}/yield`, { date: today, balanceCents: 502_800 });
    expect(conf.body.data.differenceCents).toBe(2_800);
    expect(conf.body.data.piggy).toMatchObject({ balanceCents: 502_800, effectiveYieldCents: 2_800, estimatedYieldCents: 0 });
    // Rendimento é receita (categoria Rendimentos).
    expect((await u.api.get(`${base}/dashboard`)).body.data.realized.incomeCents).toBe(2_800);

    const sim = (await u.api.get(`${base}/piggy-banks/${id}/simulate?monthlyCents=50000&months=12`)).body.data;
    expect(sim).toMatchObject({ estimate: true, rateAvailable: true });
    expect(sim.points).toHaveLength(12);
    expect(sim.monthsToGoal).toBeGreaterThan(12);

    // A reserva de emergência considera cofrinhos do tipo Reserva.
    const reserve = (await u.api.get(`${base}/planning/reserve`)).body.data;
    expect(reserve.currentCents).toBe(502_800);
  });

  it('sem taxa do índice, não estima rendimento', async () => {
    const id = (await u.api.post(`${base}/piggy-banks`, { name: 'Viagem', yieldKind: 'CDI_PERCENT', yieldRateBps: 10000 })).body.data.piggy.id;
    await u.api.post(`${base}/piggy-banks/${id}/deposit`, { accountId: acc.id, amountCents: 10_000, date: today });
    const p = (await u.api.get(`${base}/piggy-banks/${id}`)).body.data;
    expect(p.estimate.available).toBe(false);
    expect(p.estimatedYieldCents).toBe(0);
  });

  it('isola cofrinhos entre usuários e valida link', async () => {
    const id = (await u.api.post(`${base}/piggy-banks`, ps5)).body.data.piggy.id;
    const other = await createUser('Outra');
    expect((await other.api.get(`${base}/piggy-banks/${id}`)).status).toBe(404);
    expect((await u.api.post(`${base}/piggy-banks`, { ...ps5, link: 'javascript:alert(1)' })).status).toBe(400);
    const archive = await u.api.post(`${base}/piggy-banks/${id}/archive`);
    expect(archive.status).toBe(204);
  });
});

describe('índices de mercado', () => {
  it('lista a situação e só a administração lança taxa manual', async () => {
    const status = (await u.api.get('/api/market-rates')).body.data;
    expect(status.map((s: { index: string }) => s.index)).toEqual(['CDI', 'SELIC', 'IPCA']);
    expect(status[0]).toMatchObject({ lastDate: null, stale: true });
    const denied = await u.api.put('/api/market-rates', { index: 'CDI', date: today, annualPct: 13.65 });
    expect(denied.status).toBe(403);
    const ok = await u.api.put('/api/market-rates', { index: 'CDI', date: today, annualPct: 13.65 }).set('X-Admin-Token', 'admin-token-para-testes-123');
    expect(ok.status).toBe(200);
    expect(ok.body.data[0]).toMatchObject({ lastDate: today, source: 'MANUAL', stale: false });
    expect(ok.body.data[0].annualPct).toBeCloseTo(13.65, 2);
  });
});
