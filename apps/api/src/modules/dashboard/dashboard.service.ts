import type { Prisma } from '@prisma/client';
import { applyShare } from '../../domain/consolidation';
import { flowTotals, type FlowGroup, type FlowTotals } from '../../domain/flows';
import { formatDate, monthRange, parseDate, shiftMonth, todayISO } from '../../lib/dates';
import { toCents } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { listAccounts } from '../accounts/accounts.service';
import { settledAggregate } from '../settlements/settlements';
import { ensureGenerated } from '../recurring/recurring.service';
import { serializeTransaction, transactionInclude } from '../transactions/transactions.service';

const OPEN = ['PLANNED', 'PENDING', 'PARTIAL'] as const;
const SERIES_MONTHS = 6;

/** Receitas/despesas realizadas (pela data de cada liquidação) num intervalo. Mesma regra dos relatórios (RN13). */
export async function realizedFlows(entityIds: string[], from: string, to: string): Promise<FlowTotals> {
  const rows = await settledAggregate({ entityIds, from, to });
  return flowTotals(rows.map((r): FlowGroup => ({ type: r.type, direction: r.direction, cents: r.cents })));
}

/** Valores ainda em aberto (previstos/pendentes) com vencimento no intervalo — nunca misturados ao realizado (RN06). */
async function openItems(entityId: string, where: Prisma.TransactionWhereInput) {
  const rows = await prisma.transaction.findMany({
    where: { entityId, deletedAt: null, status: { in: [...OPEN] }, type: { in: ['INCOME', 'EXPENSE'] }, ...where },
    select: { type: true, amountCents: true, settledAmountCents: true },
  });
  let incomeCents = 0;
  let expenseCents = 0;
  for (const r of rows) {
    const remaining = toCents(r.amountCents) - toCents(r.settledAmountCents);
    if (r.type === 'INCOME') incomeCents += remaining;
    else expenseCents += remaining;
  }
  return { incomeCents, expenseCents, count: rows.length };
}

function dueBetween(from: string, to: string): Prisma.TransactionWhereInput {
  return {
    OR: [
      { dueDate: { gte: parseDate(from), lte: parseDate(to) } },
      { dueDate: null, competenceDate: { gte: parseDate(from), lte: parseDate(to) } },
    ],
  };
}

function dueBefore(date: string): Prisma.TransactionWhereInput {
  return { OR: [{ dueDate: { lt: parseDate(date) } }, { dueDate: null, competenceDate: { lt: parseDate(date) } }] };
}

async function entityDashboard(entityId: string, month: string, today: string) {
  await ensureGenerated([entityId]);
  const { from, to } = monthRange(month);
  const seriesStart = monthRange(shiftMonth(month, -(SERIES_MONTHS - 1))).from;
  const in7 = formatDate(new Date(parseDate(today).getTime() + 7 * 86400000));

  const [accounts, realized, forecast, overdue, seriesRows, catGroups, recent, upcoming] = await Promise.all([
    listAccounts(entityId),
    realizedFlows([entityId], from, to),
    openItems(entityId, dueBetween(from, to)),
    openItems(entityId, dueBefore(today)),
    settledAggregate({ entityIds: [entityId], types: ['INCOME', 'EXPENSE', 'REFUND'], from: seriesStart, to }),
    settledAggregate({ entityIds: [entityId], types: ['EXPENSE', 'REFUND'], from, to }),
    prisma.transaction.findMany({
      where: { entityId, deletedAt: null, competenceDate: { lte: parseDate(today) } },
      orderBy: [{ competenceDate: 'desc' }, { createdAt: 'desc' }],
      take: 5,
      include: transactionInclude,
    }),
    prisma.transaction.findMany({
      where: { entityId, deletedAt: null, status: { in: [...OPEN] }, ...dueBetween(today, in7) },
      orderBy: [{ dueDate: 'asc' }],
      take: 10,
      include: transactionInclude,
    }),
  ]);

  // Série mensal de receitas/despesas realizadas, com a mesma regra de flowTotals.
  const buckets = new Map<string, FlowGroup[]>();
  for (let i = SERIES_MONTHS - 1; i >= 0; i--) buckets.set(shiftMonth(month, -i), []);
  for (const r of seriesRows) {
    buckets.get(r.month)?.push({ type: r.type, direction: r.direction, cents: r.cents });
  }
  const series = [...buckets.entries()].map(([m, groups]) => {
    const t = flowTotals(groups);
    return { month: m, incomeCents: t.incomeCents, expenseCents: t.expenseCents, netCents: t.netCents };
  });

  const categoryIds = [...new Set(catGroups.map((g) => g.categoryId).filter((v): v is string => !!v))];
  const categories = await prisma.category.findMany({ where: { id: { in: categoryIds } } });
  const byCat = new Map<string, { categoryId: string | null; name: string; icon: string; color: string | null; cents: number }>();
  for (const g of catGroups) {
    const c = categories.find((x) => x.id === g.categoryId);
    const key = c?.name ?? 'Sem categoria';
    const v = g.cents;
    const signed = g.type === 'REFUND' && g.direction === 'IN' ? -v : v;
    const cur = byCat.get(key) ?? { categoryId: c?.id ?? null, name: key, icon: c?.icon ?? 'category', color: c?.color ?? null, cents: 0 };
    cur.cents += signed;
    byCat.set(key, cur);
  }

  return {
    accounts,
    totalBalanceCents: accounts.reduce((s, a) => s + a.balanceCents, 0),
    realized,
    forecast,
    overdue,
    series,
    expensesByCategory: [...byCat.values()].filter((c) => c.cents > 0),
    recent: recent.map((t) => serializeTransaction(t, today)),
    upcoming: upcoming.map((t) => serializeTransaction(t, today)),
  };
}

function withShares(list: { name: string; icon: string; color: string | null; cents: number }[]) {
  const total = list.reduce((s, c) => s + c.cents, 0);
  return list
    .sort((a, b) => b.cents - a.cents)
    .map((c) => ({ ...c, shareBps: total > 0 ? Math.round((c.cents * 10000) / total) : 0 }));
}

export async function getEntityDashboard(entityId: string, month: string) {
  const today = todayISO();
  const d = await entityDashboard(entityId, month, today);
  return { scope: 'entity' as const, entityId, month, today, ...d, expensesByCategory: withShares(d.expensesByCategory) };
}

/**
 * Consolidado: soma os ambientes do usuário ponderando pela participação (RN10).
 * Transferências entre ambientes não entram em receitas/despesas, então não há duplicação.
 */
export async function getConsolidatedDashboard(userId: string, month: string) {
  const today = todayISO();
  const memberships = await prisma.entityMember.findMany({
    where: { userId, entity: { archivedAt: null } },
    include: { entity: true },
  });
  const parts = await Promise.all(
    memberships.map(async (m) => ({ m, d: await entityDashboard(m.entityId, month, today) })),
  );
  const share = (v: number, bps: number) => applyShare(v, bps);
  const sumFlows = (pick: (d: Awaited<ReturnType<typeof entityDashboard>>) => FlowTotals) => {
    const out = flowTotals([]);
    for (const { m, d } of parts) {
      const f = pick(d);
      for (const k of Object.keys(out) as (keyof FlowTotals)[]) out[k] += share(f[k], m.ownershipShareBps);
    }
    return out;
  };
  const realized = sumFlows((d) => d.realized);
  // Transferências entre ambientes do próprio usuário se anulam no consolidado.
  realized.transfersInCents = 0;
  realized.transfersOutCents = 0;

  const sumOpen = (pick: (d: Awaited<ReturnType<typeof entityDashboard>>) => { incomeCents: number; expenseCents: number; count: number }) =>
    parts.reduce(
      (acc, { m, d }) => {
        const v = pick(d);
        acc.incomeCents += share(v.incomeCents, m.ownershipShareBps);
        acc.expenseCents += share(v.expenseCents, m.ownershipShareBps);
        acc.count += v.count;
        return acc;
      },
      { incomeCents: 0, expenseCents: 0, count: 0 },
    );

  const series = parts[0]?.d.series.map((s, i) => {
    const r = { month: s.month, incomeCents: 0, expenseCents: 0, netCents: 0 };
    for (const { m, d } of parts) {
      const x = d.series[i]!;
      r.incomeCents += share(x.incomeCents, m.ownershipShareBps);
      r.expenseCents += share(x.expenseCents, m.ownershipShareBps);
    }
    r.netCents = r.incomeCents - r.expenseCents;
    return r;
  }) ?? [];

  const cats = new Map<string, { name: string; icon: string; color: string | null; cents: number }>();
  for (const { m, d } of parts) {
    for (const c of d.expensesByCategory) {
      const cur = cats.get(c.name) ?? { name: c.name, icon: c.icon, color: c.color, cents: 0 };
      cur.cents += share(c.cents, m.ownershipShareBps);
      cats.set(c.name, cur);
    }
  }

  const entities = parts.map(({ m, d }) => ({
    id: m.entityId,
    name: m.entity.name,
    kind: m.entity.kind,
    ownershipShareBps: m.ownershipShareBps,
    totalBalanceCents: d.totalBalanceCents,
    attributableBalanceCents: share(d.totalBalanceCents, m.ownershipShareBps),
  }));

  const byDateDesc = (a: { competenceDate: string }, b: { competenceDate: string }) => b.competenceDate.localeCompare(a.competenceDate);
  return {
    scope: 'consolidated' as const,
    month,
    today,
    entities,
    accounts: parts.flatMap(({ d }) => d.accounts),
    totalBalanceCents: entities.reduce((s, e) => s + e.attributableBalanceCents, 0),
    realized,
    forecast: sumOpen((d) => d.forecast),
    overdue: sumOpen((d) => d.overdue),
    series,
    expensesByCategory: withShares([...cats.values()]),
    // Pernas de transferência entre os próprios ambientes são omitidas da lista consolidada.
    recent: parts.flatMap(({ d }) => d.recent).filter((t) => !(t.transfer && t.direction === 'IN')).sort(byDateDesc).slice(0, 5),
    upcoming: parts.flatMap(({ d }) => d.upcoming).sort((a, b) => (a.dueDate ?? a.competenceDate).localeCompare(b.dueDate ?? b.competenceDate)).slice(0, 10),
  };
}
