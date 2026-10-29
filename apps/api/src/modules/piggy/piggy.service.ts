import type { Account, PiggyBank } from '@prisma/client';
import type { z } from 'zod';
import type {
  piggyAchieveSchema,
  piggyCreateSchema,
  piggyMoveSchema,
  piggyUpdateSchema,
  piggyYieldSchema,
} from '../../contracts';
import { ACHIEVEMENTS, goalMilestones, levelFor, weeklyStreak } from '../../domain/gamification';
import { accrue, estimateTax, monthsToGoal, openLots, simulateGrowth, type Flow } from '../../domain/yields';
import { formatDate, parseDate, todayISO } from '../../lib/dates';
import { notFound, unprocessable } from '../../lib/errors';
import { recordEvent } from '../../lib/events';
import { toCents } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { accountBalances } from '../accounts/balances';
import { audit } from '../audit/audit.service';
import { currentAnnualPct, loadSeries } from '../market/market.service';
import { addSettlement } from '../settlements/settlements';
import { createTransaction } from '../transactions/transactions.service';
import { createTransfer } from '../transfers/transfers.service';

type Ctx = { userId: string; entityId: string; ip?: string };
type Row = PiggyBank & { account: Account };

const LEDGER_REFERENCE_DATE = '2000-01-01';
const YIELD_CATEGORY = 'Rendimentos';

async function getRow(entityId: string, id: string, db: Tx | typeof prisma = prisma): Promise<Row> {
  const p = await db.piggyBank.findFirst({ where: { id, entityId }, include: { account: true } });
  if (!p) throw notFound('Cofrinho não encontrado');
  return p;
}

/** Movimentos liquidados do cofrinho: guardar (+), retirar (−), rendimentos e ajustes. */
async function ledger(piggyId: string, until?: string) {
  const rows = await prisma.settlement.findMany({
    where: {
      transaction: { accountId: piggyId, deletedAt: null, status: { in: ['SETTLED', 'PARTIAL'] } },
      ...(until ? { date: { lte: parseDate(until) } } : {}),
    },
    include: { transaction: { select: { id: true, type: true, direction: true, description: true, transferId: true } } },
    orderBy: [{ date: 'asc' }, { createdAt: 'asc' }],
  });
  return rows.map((s) => {
    const t = s.transaction;
    const cents = toCents(s.amountCents) * (t.direction === 'IN' ? 1 : -1);
    const kind = t.type === 'TRANSFER' ? (cents > 0 ? 'DEPOSIT' : 'WITHDRAWAL') : t.type === 'INCOME' ? 'YIELD' : 'ADJUSTMENT';
    return { id: s.id, transactionId: t.id, date: formatDate(s.date), cents, kind, description: t.description };
  });
}

/** Rendimento estimado desde o último rendimento confirmado, conforme a regra do cofrinho (RN07). */
async function estimate(p: Row, moves: Awaited<ReturnType<typeof ledger>>, today: string) {
  if (p.yieldKind === 'NONE' || p.yieldKind === 'MANUAL' || moves.length === 0) return null;
  const lastYield = moves.filter((m) => m.kind === 'YIELD' || m.kind === 'ADJUSTMENT').at(-1)?.date;
  const from = lastYield ?? moves[0]!.date;
  const startBalance = moves.filter((m) => m.date <= from).reduce((s, m) => s + m.cents, 0);
  const flows: Flow[] = moves.filter((m) => m.date > from).map((m) => ({ date: m.date, cents: m.cents }));
  const engine = p.yieldKind === 'PREFIXED' ? 'PREFIXED' : p.yieldKind;
  const series =
    engine === 'PREFIXED' ? { daily: new Map<string, number>() } : await loadSeries(engine === 'CDI_PERCENT' ? 'CDI' : 'SELIC', from, today);
  const r = accrue(startBalance, from, today, flows, { engine, rateBps: p.yieldRateBps }, series);
  return r ? { ...r, since: from } : { unavailable: true as const, since: from };
}

const YIELD_LABEL: Record<PiggyBank['yieldKind'], (bps: number) => string> = {
  CDI_PERCENT: (b) => `${(b / 100).toLocaleString('pt-BR')}% do CDI`,
  SELIC_PERCENT: (b) => `${(b / 100).toLocaleString('pt-BR')}% da Selic`,
  PREFIXED: (b) => `${(b / 100).toLocaleString('pt-BR')}% a.a. prefixado`,
  MANUAL: () => 'Rendimento informado manualmente',
  NONE: () => 'Sem rendimento',
};

async function serialize(p: Row, today = todayISO(), withMovements = false) {
  const moves = await ledger(p.id);
  const balance = moves.reduce((s, m) => s + m.cents, 0);
  const principal = moves.filter((m) => m.kind === 'DEPOSIT' || m.kind === 'WITHDRAWAL').reduce((s, m) => s + m.cents, 0);
  const effectiveYield = balance - principal;
  const est = await estimate(p, moves, today);
  const estimatedYield = est && 'yieldCents' in est ? est.yieldCents : 0;
  const gross = balance + estimatedYield;
  const lots = openLots(moves.filter((m) => m.kind === 'DEPOSIT' || m.kind === 'WITHDRAWAL').map((m) => ({ date: m.date, cents: m.cents })));
  const tax = estimateTax(p.taxation, lots, effectiveYield + estimatedYield, today);
  const goal = p.goalCents ? toCents(p.goalCents) : null;
  const monthsLeft = p.targetDate
    ? Math.max(1, (Number(formatDate(p.targetDate).slice(0, 4)) - Number(today.slice(0, 4))) * 12 + Number(formatDate(p.targetDate).slice(5, 7)) - Number(today.slice(5, 7)))
    : null;
  const missing = goal ? Math.max(0, goal - balance) : null;
  return {
    id: p.id,
    entityId: p.entityId,
    kind: p.kind,
    name: p.account.name,
    institution: p.account.institution,
    icon: p.icon,
    color: p.account.color,
    link: p.link,
    priority: p.priority,
    goalCents: goal,
    targetDate: p.targetDate ? formatDate(p.targetDate) : null,
    achievedAt: p.achievedAt ? formatDate(p.achievedAt) : null,
    archived: p.account.archivedAt !== null,
    yieldKind: p.yieldKind,
    yieldRateBps: p.yieldRateBps,
    yieldLabel: YIELD_LABEL[p.yieldKind](p.yieldRateBps),
    liquidity: p.liquidity,
    liquidityDays: p.liquidityDays,
    taxation: p.taxation,
    /** Saldo confirmado (guardado − retirado + rendimentos lançados). */
    balanceCents: balance,
    /** Principal aportado líquido (guardado − retirado). */
    principalCents: principal,
    effectiveYieldCents: effectiveYield,
    /** Estimativa desde o último rendimento confirmado; não é garantia (RN07). */
    estimatedYieldCents: estimatedYield,
    grossEstimatedCents: gross,
    taxEstimatedCents: tax.iofCents + tax.irCents,
    netEstimatedCents: gross - tax.iofCents - tax.irCents,
    estimate: est
      ? 'unavailable' in est
        ? { available: false, since: est.since, ratesUpTo: null, missingRates: 0 }
        : { available: true, since: est.since, ratesUpTo: est.ratesUpTo, missingRates: est.missingRates }
      : null,
    progressBps: goal ? Math.min(10000, Math.round((Math.max(0, balance) * 10000) / goal)) : null,
    missingCents: missing,
    /** Quanto guardar por mês para chegar na data-alvo (sem contar rendimentos). */
    monthlyNeededCents: missing !== null && monthsLeft ? Math.ceil(missing / monthsLeft) : null,
    ...(withMovements ? { movements: [...moves].reverse() } : {}),
  };
}

export async function listPiggies(entityId: string, includeArchived = false) {
  const rows = await prisma.piggyBank.findMany({
    where: { entityId, ...(includeArchived ? {} : { account: { archivedAt: null } }) },
    include: { account: true },
    orderBy: [{ achievedAt: { sort: 'asc', nulls: 'first' } }, { priority: 'asc' }, { createdAt: 'asc' }],
  });
  const today = todayISO();
  return Promise.all(rows.map((p) => serialize(p, today)));
}

export async function getPiggy(entityId: string, id: string) {
  return serialize(await getRow(entityId, id), todayISO(), true);
}

export async function createPiggy(ctx: Ctx, input: z.infer<typeof piggyCreateSchema>) {
  const id = await prisma.$transaction(async (tx) => {
    const account = await tx.account.create({
      data: {
        entityId: ctx.entityId,
        name: input.name,
        institution: input.institution ?? null,
        type: 'PIGGY_BANK',
        color: input.color ?? null,
        initialBalanceCents: 0n,
        referenceDate: parseDate(LEDGER_REFERENCE_DATE),
      },
    });
    const p = await tx.piggyBank.create({
      data: {
        id: account.id,
        entityId: ctx.entityId,
        kind: input.kind,
        link: input.link ?? null,
        priority: input.priority,
        icon: input.icon,
        goalCents: input.goalCents ? BigInt(input.goalCents) : null,
        targetDate: input.targetDate ? parseDate(input.targetDate) : null,
        yieldKind: input.yieldKind,
        yieldRateBps: input.yieldRateBps,
        liquidity: input.liquidity,
        liquidityDays: input.liquidityDays,
        taxation: input.taxation,
      },
    });
    await audit(tx, { ...ctx, action: 'create', resourceType: 'piggy_bank', resourceId: p.id, after: { ...p, name: input.name } });
    return p.id;
  });
  const unlocked = await evaluateAchievements(ctx.userId);
  return { piggy: await getPiggy(ctx.entityId, id), unlocked };
}

export async function updatePiggy(ctx: Ctx, id: string, input: z.infer<typeof piggyUpdateSchema>) {
  const before = await getRow(ctx.entityId, id);
  await prisma.$transaction(async (tx) => {
    await tx.account.update({ where: { id }, data: { name: input.name, institution: input.institution, color: input.color } });
    const after = await tx.piggyBank.update({
      where: { id },
      data: {
        kind: input.kind,
        link: input.link,
        priority: input.priority,
        icon: input.icon,
        goalCents: input.goalCents === undefined ? undefined : input.goalCents ? BigInt(input.goalCents) : null,
        targetDate: input.targetDate === undefined ? undefined : input.targetDate ? parseDate(input.targetDate) : null,
        yieldKind: input.yieldKind,
        yieldRateBps: input.yieldRateBps,
        liquidity: input.liquidity,
        liquidityDays: input.liquidityDays,
        taxation: input.taxation,
      },
    });
    await audit(tx, { ...ctx, action: 'update', resourceType: 'piggy_bank', resourceId: id, before, after });
  });
  const unlocked = await evaluateAchievements(ctx.userId);
  return { piggy: await getPiggy(ctx.entityId, id), unlocked };
}

/** Guardar: transferência da conta para o cofrinho (o dinheiro sai do saldo disponível; não é despesa). */
export async function deposit(ctx: Ctx, id: string, input: z.infer<typeof piggyMoveSchema>) {
  const p = await getRow(ctx.entityId, id);
  if (p.account.archivedAt) throw unprocessable('PIGGY_ARCHIVED', 'Cofrinho arquivado');
  if (p.achievedAt) throw unprocessable('PIGGY_ACHIEVED', 'Este desejo já foi realizado');
  await createTransfer(
    ctx.userId,
    {
      fromAccountId: input.accountId,
      toAccountId: id,
      amountCents: input.amountCents!,
      date: input.date,
      description: `Guardado no cofrinho ${p.account.name}`,
      classification: input.classification,
    },
    ctx.ip,
  );
  recordEvent('piggy.deposit', { entityId: ctx.entityId, piggyId: id });
  const unlocked = await evaluateAchievements(ctx.userId);
  return { piggy: await getPiggy(ctx.entityId, id), unlocked };
}

/** Retirar: transferência do cofrinho de volta para uma conta. Não permite saldo negativo. */
export async function withdraw(ctx: Ctx, id: string, input: z.infer<typeof piggyMoveSchema>) {
  const p = await getRow(ctx.entityId, id);
  const balance = (await accountBalances([p.account])).get(id) ?? 0;
  const amount = input.amountCents ?? balance;
  if (amount <= 0 || amount > balance) throw unprocessable('INSUFFICIENT_BALANCE', 'Saldo do cofrinho insuficiente');
  await createTransfer(
    ctx.userId,
    {
      fromAccountId: id,
      toAccountId: input.accountId,
      amountCents: amount,
      date: input.date,
      description: `Retirado do cofrinho ${p.account.name}`,
      classification: input.classification,
    },
    ctx.ip,
  );
  recordEvent('piggy.withdrawal', { entityId: ctx.entityId, piggyId: id });
  return { piggy: await getPiggy(ctx.entityId, id), unlocked: [] };
}

async function incomeCategory(db: Tx, entityId: string) {
  const c = await db.category.upsert({
    where: { entityId_kind_name: { entityId, kind: 'INCOME', name: YIELD_CATEGORY } },
    create: { entityId, kind: 'INCOME', name: YIELD_CATEGORY, icon: 'trending_up', color: '#B9E9CF', isSystem: true },
    update: {},
  });
  return c.id;
}

/**
 * Confirma o saldo informado pelo banco: a diferença para o saldo da hoink. vira rendimento
 * efetivo (receita) — ou ajuste negativo, se o banco mostrar menos. Estimativas nunca são gravadas.
 */
export async function confirmYield(ctx: Ctx, id: string, input: z.infer<typeof piggyYieldSchema>) {
  const p = await getRow(ctx.entityId, id);
  const current = (await accountBalances([p.account], { until: input.date })).get(id) ?? 0;
  const diff = input.balanceCents - current;
  if (diff !== 0) {
    await prisma.$transaction(async (tx) => {
      const amount = BigInt(Math.abs(diff));
      const t = await tx.transaction.create({
        data: {
          entityId: ctx.entityId,
          accountId: id,
          categoryId: diff > 0 ? await incomeCategory(tx, ctx.entityId) : null,
          type: diff > 0 ? 'INCOME' : 'ADJUSTMENT',
          direction: diff > 0 ? 'IN' : 'OUT',
          amountCents: amount,
          settledAmountCents: amount,
          status: 'SETTLED',
          competenceDate: parseDate(input.date),
          settledDate: parseDate(input.date),
          description: diff > 0 ? `Rendimento ${p.account.name}` : `Ajuste ${p.account.name}`,
          createdById: ctx.userId,
        },
      });
      await addSettlement(tx, t.id, Math.abs(diff), input.date, ctx.userId);
      await audit(tx, {
        ...ctx,
        action: 'confirm_yield',
        resourceType: 'piggy_bank',
        resourceId: id,
        after: { computed: current, informed: input.balanceCents, difference: diff },
      });
    });
  }
  const unlocked = await evaluateAchievements(ctx.userId);
  return { piggy: await getPiggy(ctx.entityId, id), unlocked, differenceCents: diff };
}

/**
 * "Comprei!": retira o saldo para a conta e, opcionalmente, já lança a despesa da compra
 * (que é a única despesa — guardar não foi despesa).
 */
export async function achieve(ctx: Ctx, id: string, input: z.infer<typeof piggyAchieveSchema>) {
  const p = await getRow(ctx.entityId, id);
  if (p.achievedAt) throw unprocessable('PIGGY_ACHIEVED', 'Este desejo já foi realizado');
  const balance = (await accountBalances([p.account])).get(id) ?? 0;
  if (balance > 0) await withdraw(ctx, id, { accountId: input.accountId, date: input.date });
  if (input.purchaseCents) {
    const account = await prisma.account.findFirst({ where: { id: input.accountId } });
    await createTransaction(
      { ...ctx, entityId: account!.entityId },
      {
        type: 'EXPENSE',
        description: input.description ?? p.account.name,
        amountCents: input.purchaseCents,
        accountId: input.accountId,
        categoryId: input.categoryId ?? null,
        status: 'SETTLED',
        competenceDate: input.date,
        tags: ['desejo-realizado'],
      },
    );
  }
  await prisma.$transaction(async (tx) => {
    await tx.piggyBank.update({ where: { id }, data: { achievedAt: parseDate(input.date) } });
    await audit(tx, { ...ctx, action: 'achieve', resourceType: 'piggy_bank', resourceId: id, after: input });
  });
  recordEvent('piggy.achieved', { entityId: ctx.entityId, piggyId: id });
  const unlocked = await evaluateAchievements(ctx.userId);
  return { piggy: await getPiggy(ctx.entityId, id), unlocked };
}

/** Arquiva o cofrinho (somente com saldo zero). */
export async function archivePiggy(ctx: Ctx, id: string) {
  const p = await getRow(ctx.entityId, id);
  const balance = (await accountBalances([p.account])).get(id) ?? 0;
  if (balance !== 0) throw unprocessable('PIGGY_HAS_BALANCE', 'Retire o saldo antes de arquivar o cofrinho');
  await prisma.$transaction(async (tx) => {
    await tx.account.update({ where: { id }, data: { archivedAt: new Date() } });
    await audit(tx, { ...ctx, action: 'archive', resourceType: 'piggy_bank', resourceId: id });
  });
}

/**
 * Simulação (estimativa): evolução com aporte mensal na taxa anual atual da regra do cofrinho.
 * A taxa é a última conhecida do índice e não é garantia de rentabilidade.
 */
export async function simulatePiggy(entityId: string, id: string, q: { monthlyCents: number; months: number }) {
  const p = await getPiggy(entityId, id);
  const annual =
    p.yieldKind === 'NONE' || p.yieldKind === 'MANUAL' ? 0 : await currentAnnualPct(p.yieldKind, p.yieldRateBps);
  const today = todayISO();
  return {
    estimate: true,
    annualRatePct: annual,
    rateAvailable: annual !== null,
    points: simulateGrowth(p.balanceCents, q.monthlyCents, q.months, annual ?? 0, today),
    monthsToGoal: p.goalCents ? monthsToGoal(p.balanceCents, q.monthlyCents, p.goalCents, annual ?? 0) : null,
  };
}

// ───────────── Gamificação ─────────────

async function userPiggies(userId: string) {
  return prisma.piggyBank.findMany({
    where: { account: { entity: { members: { some: { userId } }, archivedAt: null } } },
    include: { account: true },
  });
}

/** Datas de depósito em cofrinhos (pernas de entrada das transferências). */
async function depositDates(piggyIds: string[]) {
  if (piggyIds.length === 0) return [];
  const rows = await prisma.transaction.findMany({
    where: { accountId: { in: piggyIds }, type: 'TRANSFER', direction: 'IN', deletedAt: null },
    select: { competenceDate: true },
  });
  return rows.map((r) => formatDate(r.competenceDate));
}

/** Reavalia as conquistas e devolve as recém-desbloqueadas (para a comemoração no app). */
export async function evaluateAchievements(userId: string) {
  const piggies = await userPiggies(userId);
  const balances = await accountBalances(piggies.map((p) => p.account));
  const dates = await depositDates(piggies.map((p) => p.id));
  const total = [...balances.values()].reduce((s, v) => s + Math.max(0, v), 0);
  const streak = weeklyStreak(dates, todayISO());
  const earned: { code: string; piggyId: string | null }[] = [];
  if (piggies.length > 0) earned.push({ code: 'FIRST_PIGGY', piggyId: null });
  if (piggies.some((p) => p.kind === 'WISH')) earned.push({ code: 'FIRST_WISH', piggyId: null });
  if (dates.length > 0) earned.push({ code: 'FIRST_DEPOSIT', piggyId: null });
  if (total >= 100_000) earned.push({ code: 'SAVED_1K', piggyId: null });
  if (total >= 1_000_000) earned.push({ code: 'SAVED_10K', piggyId: null });
  if (streak.best >= 4) earned.push({ code: 'STREAK_4', piggyId: null });
  if (streak.best >= 12) earned.push({ code: 'STREAK_12', piggyId: null });
  for (const p of piggies) {
    const goal = p.goalCents ? toCents(p.goalCents) : null;
    for (const code of goalMilestones(balances.get(p.id) ?? 0, goal)) earned.push({ code, piggyId: p.id });
    if (p.achievedAt) earned.push({ code: 'WISH_ACHIEVED', piggyId: p.id });
  }
  const existing = await prisma.achievement.findMany({ where: { userId } });
  const key = (c: string, pid: string | null) => `${c}:${pid ?? ''}`;
  const have = new Set(existing.map((a) => key(a.code, a.piggyId)));
  const fresh = earned.filter((e) => !have.has(key(e.code, e.piggyId)));
  if (fresh.length) {
    await prisma.achievement.createMany({ skipDuplicates: true, data: fresh.map((e) => ({ userId, ...e })) });
  }
  const names = new Map(piggies.map((p) => [p.id, p.account.name]));
  return fresh.map((e) => {
    const def = ACHIEVEMENTS.find((a) => a.code === e.code)!;
    return { ...def, piggyId: e.piggyId, piggyName: e.piggyId ? (names.get(e.piggyId) ?? null) : null };
  });
}

export async function gamificationProfile(userId: string) {
  const piggies = await userPiggies(userId);
  const [achievements, dates] = await Promise.all([
    prisma.achievement.findMany({ where: { userId }, orderBy: { unlockedAt: 'desc' } }),
    depositDates(piggies.map((p) => p.id)),
  ]);
  const names = new Map(piggies.map((p) => [p.id, p.account.name]));
  const points = achievements.reduce((s, a) => s + (ACHIEVEMENTS.find((d) => d.code === a.code)?.points ?? 0), 0);
  const unlockedCodes = new Set(achievements.map((a) => a.code));
  return {
    ...levelFor(points),
    streak: weeklyStreak(dates, todayISO()),
    unlocked: achievements.map((a) => ({
      ...ACHIEVEMENTS.find((d) => d.code === a.code)!,
      piggyId: a.piggyId,
      piggyName: a.piggyId ? (names.get(a.piggyId) ?? null) : null,
      unlockedAt: a.unlockedAt,
    })),
    /** Conquistas globais ainda bloqueadas (as de meta aparecem em cada cofrinho). */
    locked: ACHIEVEMENTS.filter((d) => !d.perPiggy && !unlockedCodes.has(d.code)),
  };
}

