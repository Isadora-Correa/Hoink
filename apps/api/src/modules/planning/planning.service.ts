import type { z } from 'zod';
import type { budgetUpsertSchema, reserveSettingsSchema } from '../../contracts';
import { applyShare } from '../../domain/consolidation';
import { budgetState, projectCashflow, type CashItem } from '../../domain/planning';
import { addDaysISO } from '../../domain/recurrence';
import { formatDate, monthRange, parseDate, shiftMonth, todayISO } from '../../lib/dates';
import { notFound, unprocessable } from '../../lib/errors';
import { toCents } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { accountBalances } from '../accounts/balances';
import { audit } from '../audit/audit.service';
import { invoicesDueUntil } from '../cards/cards.service';
import { realizedFlows } from '../dashboard/dashboard.service';
import { ensureGenerated } from '../recurring/recurring.service';
import { settledAggregate } from '../settlements/settlements';

type Ctx = { userId: string; entityId: string; ip?: string };

const OPEN = ['PLANNED', 'PENDING', 'PARTIAL'] as const;
const DEFAULT_RESERVE_MONTHS = 6;
/** Meses completos usados na média de despesas da reserva de emergência. */
const AVERAGE_MONTHS = 6;

// ───────────── Orçamentos ─────────────

/**
 * Orçamentos do mês: gasto realizado por categoria (pela data de cada pagamento, inclusive
 * parcelas de cartão do mês, líquido de reembolsos) e compromissos em aberto que vencem no mês.
 */
export async function listBudgets(entityId: string, month: string) {
  await ensureGenerated([entityId]);
  const { from, to } = monthRange(month);
  const [budgets, settled, open] = await Promise.all([
    prisma.budget.findMany({
      where: { entityId },
      include: { category: { select: { id: true, name: true, icon: true, color: true } } },
      orderBy: { category: { name: 'asc' } },
    }),
    settledAggregate({ entityIds: [entityId], types: ['EXPENSE', 'REFUND'], from, to }),
    prisma.transaction.groupBy({
      by: ['categoryId'],
      where: {
        entityId,
        deletedAt: null,
        type: 'EXPENSE',
        status: { in: [...OPEN] },
        OR: [
          { dueDate: { gte: parseDate(from), lte: parseDate(to) } },
          { dueDate: null, competenceDate: { gte: parseDate(from), lte: parseDate(to) } },
        ],
      },
      _sum: { amountCents: true, settledAmountCents: true },
    }),
  ]);
  const spentBy = new Map<string, number>();
  for (const r of settled) {
    if (!r.categoryId) continue;
    const signed = r.type === 'REFUND' && r.direction === 'IN' ? -r.cents : r.cents;
    spentBy.set(r.categoryId, (spentBy.get(r.categoryId) ?? 0) + signed);
  }
  const committedBy = new Map<string, number>();
  for (const g of open) {
    if (!g.categoryId) continue;
    committedBy.set(g.categoryId, toCents(g._sum.amountCents ?? 0n) - toCents(g._sum.settledAmountCents ?? 0n));
  }
  const items = budgets.map((b) => {
    const spentCents = Math.max(0, spentBy.get(b.categoryId) ?? 0);
    const committedCents = committedBy.get(b.categoryId) ?? 0;
    const limitCents = toCents(b.limitCents);
    return {
      id: b.id,
      category: b.category,
      limitCents,
      alertThresholdBps: b.alertThresholdBps,
      spentCents,
      committedCents,
      ...budgetState({ limitCents, alertThresholdBps: b.alertThresholdBps }, spentCents, committedCents),
    };
  });
  const totals = {
    limitCents: items.reduce((s, b) => s + b.limitCents, 0),
    spentCents: items.reduce((s, b) => s + b.spentCents, 0),
    committedCents: items.reduce((s, b) => s + b.committedCents, 0),
  };
  const alerts = items
    .filter((b) => b.state !== 'OK')
    .map((b) => ({
      budgetId: b.id,
      category: b.category.name,
      state: b.state,
      message:
        b.state === 'EXCEEDED'
          ? `${b.category.name}: orçamento estourado`
          : b.usedBps >= b.alertThresholdBps
            ? `${b.category.name}: ${Math.floor(b.usedBps / 100)}% do orçamento usado`
            : `${b.category.name}: as contas em aberto vão ultrapassar o orçamento`,
    }));
  return { month, items, totals, alerts };
}

export async function upsertBudget(ctx: Ctx, input: z.infer<typeof budgetUpsertSchema>) {
  const cat = await prisma.category.findFirst({ where: { id: input.categoryId, entityId: ctx.entityId, kind: 'EXPENSE' } });
  if (!cat) throw unprocessable('INVALID_CATEGORY', 'Escolha uma categoria de despesa deste ambiente');
  return prisma.$transaction(async (tx) => {
    const b = await tx.budget.upsert({
      where: { entityId_categoryId: { entityId: ctx.entityId, categoryId: input.categoryId } },
      create: {
        entityId: ctx.entityId,
        categoryId: input.categoryId,
        limitCents: BigInt(input.limitCents),
        alertThresholdBps: input.alertThresholdBps,
      },
      update: { limitCents: BigInt(input.limitCents), alertThresholdBps: input.alertThresholdBps },
    });
    await audit(tx, { ...ctx, action: 'upsert', resourceType: 'budget', resourceId: b.id, after: b });
    return { id: b.id, categoryId: b.categoryId, limitCents: toCents(b.limitCents), alertThresholdBps: b.alertThresholdBps };
  });
}

export async function deleteBudget(ctx: Ctx, id: string) {
  const b = await prisma.budget.findFirst({ where: { id, entityId: ctx.entityId } });
  if (!b) throw notFound('Orçamento não encontrado');
  await prisma.$transaction(async (tx) => {
    await tx.budget.delete({ where: { id } });
    await audit(tx, { ...ctx, action: 'delete', resourceType: 'budget', resourceId: id, before: b });
  });
}

// ───────────── Fluxo de caixa projetado ─────────────

/** Saldo disponível hoje: contas de dinheiro (sem cartões), até hoje. */
async function cashBalance(entityId: string, today: string) {
  const accounts = await prisma.account.findMany({
    where: { entityId, archivedAt: null, type: { not: 'CREDIT_CARD' } },
  });
  const balances = await accountBalances(accounts, { until: today });
  return [...balances.values()].reduce((s, v) => s + v, 0);
}

/**
 * Itens futuros de caixa de um ambiente: lançamentos em aberto de contas de dinheiro e faturas
 * de cartão a pagar. Confirmado = pendente/parcial (já lançado), faturas e parcelas de dívida;
 * previsto = ocorrências de recorrências e estimativas (status Previsto).
 */
async function cashItems(entityId: string, until: string): Promise<CashItem[]> {
  const rows = await prisma.transaction.findMany({
    where: {
      entityId,
      deletedAt: null,
      type: { in: ['INCOME', 'EXPENSE'] },
      status: { in: [...OPEN] },
      account: { type: { not: 'CREDIT_CARD' } },
      OR: [{ dueDate: { lte: parseDate(until) } }, { dueDate: null, competenceDate: { lte: parseDate(until) } }],
    },
    select: { type: true, status: true, amountCents: true, settledAmountCents: true, dueDate: true, competenceDate: true },
  });
  const items: CashItem[] = rows.map((r) => {
    const remaining = toCents(r.amountCents) - toCents(r.settledAmountCents);
    return {
      date: formatDate(r.dueDate ?? r.competenceDate),
      cents: r.type === 'INCOME' ? remaining : -remaining,
      confirmed: r.status !== 'PLANNED',
    };
  });
  for (const inv of await invoicesDueUntil([entityId], until)) {
    items.push({ date: inv.dueDate, cents: -inv.remainingCents, confirmed: true });
  }
  return items;
}

export async function cashflow(entityIds: { entityId: string; shareBps: number }[], days: number[] = [30, 60, 90]) {
  const today = todayISO();
  const until = addDaysISO(today, Math.max(...days));
  await ensureGenerated(entityIds.map((e) => e.entityId));
  let start = 0;
  const items: CashItem[] = [];
  for (const { entityId, shareBps } of entityIds) {
    start += applyShare(await cashBalance(entityId, today), shareBps);
    for (const it of await cashItems(entityId, until)) items.push({ ...it, cents: applyShare(it.cents, shareBps) });
  }
  const projection = projectCashflow(start, today, items, days);
  const alerts: string[] = [];
  if (projection.lowest.projectedCents < 0) {
    alerts.push(`O saldo projetado fica negativo em ${projection.lowest.date.split('-').reverse().join('/')}`);
  }
  return { ...projection, alerts };
}

// ───────────── Reserva de emergência ─────────────

/**
 * Reserva de emergência: meta = média mensal de despesas dos últimos 6 meses completos × meses
 * desejados; atual = saldo das contas marcadas como reserva (ou das poupanças, se nenhuma marcada).
 */
export async function reserve(entityId: string) {
  const today = todayISO();
  const thisMonth = today.slice(0, 7);
  const from = monthRange(shiftMonth(thisMonth, -AVERAGE_MONTHS)).from;
  const to = monthRange(shiftMonth(thisMonth, -1)).to;
  const [settings, accounts, flows] = await Promise.all([
    prisma.planningSettings.findUnique({ where: { entityId } }),
    prisma.account.findMany({ where: { entityId, archivedAt: null, type: { not: 'CREDIT_CARD' } }, orderBy: { createdAt: 'asc' } }),
    realizedFlows([entityId], from, to),
  ]);
  const flagged = accounts.filter((a) => a.isEmergencyReserve);
  const reserveAccounts = flagged.length > 0 ? flagged : accounts.filter((a) => a.type === 'SAVINGS');
  const balances = await accountBalances(reserveAccounts, { until: today });
  const currentCents = [...balances.values()].reduce((s, v) => s + v, 0);
  const avgMonthlyExpenseCents = Math.round(Math.max(0, flows.expenseCents) / AVERAGE_MONTHS);
  const targetMonths = settings?.emergencyTargetMonths ?? DEFAULT_RESERVE_MONTHS;
  const targetCents = avgMonthlyExpenseCents * targetMonths;
  return {
    targetMonths,
    avgMonthlyExpenseCents,
    targetCents,
    currentCents,
    missingCents: Math.max(0, targetCents - currentCents),
    progressBps: targetCents > 0 ? Math.min(10000, Math.round((currentCents * 10000) / targetCents)) : 0,
    monthsCovered: avgMonthlyExpenseCents > 0 ? Math.floor((currentCents * 10) / avgMonthlyExpenseCents) / 10 : null,
    /** true quando as contas foram escolhidas pelo usuário; false quando usamos as poupanças por padrão. */
    customAccounts: flagged.length > 0,
    accounts: reserveAccounts.map((a) => ({ id: a.id, name: a.name, balanceCents: balances.get(a.id) ?? 0 })),
    basedOn: { from, to },
  };
}

export async function updateReserve(ctx: Ctx, input: z.infer<typeof reserveSettingsSchema>) {
  const valid = await prisma.account.count({
    where: { id: { in: input.accountIds }, entityId: ctx.entityId, type: { not: 'CREDIT_CARD' } },
  });
  if (valid !== new Set(input.accountIds).size) throw unprocessable('INVALID_ACCOUNT', 'Conta não pertence a este ambiente');
  await prisma.$transaction(async (tx) => {
    await tx.planningSettings.upsert({
      where: { entityId: ctx.entityId },
      create: { entityId: ctx.entityId, emergencyTargetMonths: input.targetMonths },
      update: { emergencyTargetMonths: input.targetMonths },
    });
    await tx.account.updateMany({ where: { entityId: ctx.entityId }, data: { isEmergencyReserve: false } });
    if (input.accountIds.length) {
      await tx.account.updateMany({ where: { id: { in: input.accountIds } }, data: { isEmergencyReserve: true } });
    }
    await audit(tx, { ...ctx, action: 'update', resourceType: 'planning_settings', resourceId: ctx.entityId, after: input });
  });
  return reserve(ctx.entityId);
}
