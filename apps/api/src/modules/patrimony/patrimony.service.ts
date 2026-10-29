import { Prisma } from '@prisma/client';
import type { z } from 'zod';
import type { patrimonyItemSchema, patrimonyItemUpdateSchema } from '../../contracts';
import { applyShare } from '../../domain/consolidation';
import { formatDate, monthRange, parseDate, shiftMonth, todayISO } from '../../lib/dates';
import { notFound } from '../../lib/errors';
import { cashAccountType } from '../../lib/ledgers';
import { toCents } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { accountBalances } from '../accounts/balances';
import { audit } from '../audit/audit.service';
import { portfolioValueAt } from '../investments/investments.service';

type Ctx = { userId: string; entityId: string; ip?: string };

export interface NetWorth {
  date: string;
  assets: { cashCents: number; piggyBanksCents: number; investmentsCents: number; otherCents: number; totalCents: number };
  liabilities: { debtsCents: number; cardsCents: number; otherCents: number; totalCents: number };
  netWorthCents: number;
}

/** Saldo devedor (principal) das dívidas numa data: principal − amortizações pagas até a data. */
async function debtsOutstanding(entityId: string, date: string) {
  const debts = await prisma.debt.findMany({
    where: { entityId, status: { not: 'CANCELED' }, startDate: { lte: parseDate(date) } },
    include: { installments: { include: { transaction: true } } },
  });
  let total = 0;
  for (const d of debts) {
    let paid = 0;
    for (const i of d.installments) {
      const t = i.transaction;
      const paidByDate = i.paidBeforeApp
        ? formatDate(i.dueDate) <= date
        : !!t && !t.deletedAt && t.status === 'SETTLED' && !!t.settledDate && formatDate(t.settledDate) <= date;
      if (paidByDate) paid += toCents(i.principalCents);
    }
    total += Math.max(0, toCents(d.principalCents) - paid);
  }
  return total;
}

/**
 * Fatura comprometida dos cartões numa data: compras feitas até a data (todas as parcelas, inclusive
 * futuras — o limite já está comprometido) menos pagamentos feitos até a data.
 */
async function cardsOwed(entityId: string, date: string) {
  const cards = await prisma.creditCard.findMany({ where: { entityId }, select: { id: true } });
  let total = 0;
  for (const c of cards) {
    const purchases = await prisma.cardPurchase.aggregate({
      where: { cardId: c.id, deletedAt: null, purchaseDate: { lte: parseDate(date) } },
      _sum: { totalCents: true },
    });
    const payments = await prisma.transaction.aggregate({
      where: { accountId: c.id, type: 'TRANSFER', direction: 'IN', deletedAt: null, competenceDate: { lte: parseDate(date) } },
      _sum: { amountCents: true },
    });
    total += Math.max(0, toCents(purchases._sum.totalCents ?? 0n) - toCents(payments._sum.amountCents ?? 0n));
  }
  return total;
}

/**
 * Patrimônio líquido de um ambiente numa data. Sem dupla contagem: dinheiro guardado em cofrinho ou
 * aplicado em investimento já saiu das contas (transferência / aporte), e a compra no cartão é
 * passivo até a fatura ser paga.
 */
export async function netWorthAt(entityId: string, date: string): Promise<NetWorth> {
  const [cashAccounts, piggies, investmentsCents, debtsCents, cardsCents, items] = await Promise.all([
    prisma.account.findMany({ where: { entityId, type: cashAccountType, referenceDate: { lte: parseDate(date) } } }),
    prisma.account.findMany({ where: { entityId, type: 'PIGGY_BANK' } }),
    portfolioValueAt(entityId, date),
    debtsOutstanding(entityId, date),
    cardsOwed(entityId, date),
    prisma.patrimonyItem.findMany({ where: { entityId, deletedAt: null, valuedAt: { lte: parseDate(date) } } }),
  ]);
  const sum = (m: Map<string, number>) => [...m.values()].reduce((s, v) => s + v, 0);
  const cashCents = sum(await accountBalances(cashAccounts, { until: date }));
  const piggyBanksCents = sum(await accountBalances(piggies, { until: date }));
  const otherAssets = items.filter((i) => i.side === 'ASSET').reduce((s, i) => s + toCents(i.valueCents), 0);
  const otherLiabilities = items.filter((i) => i.side === 'LIABILITY').reduce((s, i) => s + toCents(i.valueCents), 0);
  const assetsTotal = cashCents + piggyBanksCents + investmentsCents + otherAssets;
  const liabilitiesTotal = debtsCents + cardsCents + otherLiabilities;
  return {
    date,
    assets: { cashCents, piggyBanksCents, investmentsCents, otherCents: otherAssets, totalCents: assetsTotal },
    liabilities: { debtsCents, cardsCents, otherCents: otherLiabilities, totalCents: liabilitiesTotal },
    netWorthCents: assetsTotal - liabilitiesTotal,
  };
}

async function saveSnapshot(entityId: string, month: string, nw: NetWorth) {
  const data = {
    assetsCents: BigInt(nw.assets.totalCents),
    liabilitiesCents: BigInt(nw.liabilities.totalCents),
    breakdown: nw as unknown as Prisma.InputJsonValue,
  };
  await prisma.netWorthSnapshot.upsert({
    where: { entityId_month: { entityId, month: parseDate(`${month}-01`) } },
    create: { entityId, month: parseDate(`${month}-01`), ...data },
    update: data,
  });
}

/**
 * Histórico mensal (fim de cada mês). Meses encerrados são lidos do snapshot gravado (ou calculados
 * e gravados na primeira consulta); o mês corrente é sempre recalculado e atualizado.
 */
export async function history(entityId: string, months = 12) {
  const today = todayISO();
  const current = today.slice(0, 7);
  const snapshots = await prisma.netWorthSnapshot.findMany({
    where: { entityId, month: { gte: parseDate(`${shiftMonth(current, -(months - 1))}-01`) } },
  });
  const byMonth = new Map(snapshots.map((s) => [formatDate(s.month).slice(0, 7), s.breakdown as unknown as NetWorth]));
  const out: { month: string; netWorth: NetWorth }[] = [];
  for (let k = months - 1; k >= 0; k--) {
    const month = shiftMonth(current, -k);
    let nw = k > 0 ? byMonth.get(month) : undefined;
    if (!nw) {
      nw = await netWorthAt(entityId, k === 0 ? today : monthRange(month).to);
      await saveSnapshot(entityId, month, nw);
    }
    out.push({ month, netWorth: nw });
  }
  return out;
}

export async function patrimony(entityId: string) {
  const today = todayISO();
  const [nw, items, hist] = await Promise.all([
    netWorthAt(entityId, today),
    prisma.patrimonyItem.findMany({ where: { entityId, deletedAt: null }, orderBy: [{ side: 'asc' }, { name: 'asc' }] }),
    history(entityId),
  ]);
  const firstWithData = hist.findIndex((h) => h.netWorth.assets.totalCents !== 0 || h.netWorth.liabilities.totalCents !== 0);
  return {
    ...nw,
    items: items.map((i) => ({
      id: i.id,
      side: i.side,
      category: i.category,
      name: i.name,
      valueCents: toCents(i.valueCents),
      valuedAt: formatDate(i.valuedAt),
      notes: i.notes,
    })),
    history: (firstWithData < 0 ? [] : hist.slice(firstWithData)).map((h) => ({
      month: h.month,
      assetsCents: h.netWorth.assets.totalCents,
      liabilitiesCents: h.netWorth.liabilities.totalCents,
      netWorthCents: h.netWorth.netWorthCents,
    })),
  };
}

/** Consolidado: soma os ambientes ponderando pela participação do usuário (RN10). */
export async function consolidatedPatrimony(userId: string) {
  const memberships = await prisma.entityMember.findMany({ where: { userId, entity: { archivedAt: null } }, include: { entity: true } });
  const parts = await Promise.all(memberships.map(async (m) => ({ m, p: await patrimony(m.entityId) })));
  const share = (v: number, bps: number) => applyShare(v, bps);
  const zero = (): NetWorth => ({
    date: todayISO(),
    assets: { cashCents: 0, piggyBanksCents: 0, investmentsCents: 0, otherCents: 0, totalCents: 0 },
    liabilities: { debtsCents: 0, cardsCents: 0, otherCents: 0, totalCents: 0 },
    netWorthCents: 0,
  });
  const out = zero();
  const hist = new Map<string, { month: string; assetsCents: number; liabilitiesCents: number; netWorthCents: number }>();
  for (const { m, p } of parts) {
    const bps = m.ownershipShareBps;
    for (const k of Object.keys(out.assets) as (keyof NetWorth['assets'])[]) out.assets[k] += share(p.assets[k], bps);
    for (const k of Object.keys(out.liabilities) as (keyof NetWorth['liabilities'])[]) out.liabilities[k] += share(p.liabilities[k], bps);
    for (const h of p.history) {
      const cur = hist.get(h.month) ?? { month: h.month, assetsCents: 0, liabilitiesCents: 0, netWorthCents: 0 };
      cur.assetsCents += share(h.assetsCents, bps);
      cur.liabilitiesCents += share(h.liabilitiesCents, bps);
      cur.netWorthCents = cur.assetsCents - cur.liabilitiesCents;
      hist.set(h.month, cur);
    }
  }
  out.netWorthCents = out.assets.totalCents - out.liabilities.totalCents;
  return {
    ...out,
    entities: parts.map(({ m, p }) => ({ id: m.entityId, name: m.entity.name, kind: m.entity.kind, netWorthCents: share(p.netWorthCents, m.ownershipShareBps) })),
    items: [],
    history: [...hist.values()].sort((a, b) => a.month.localeCompare(b.month)),
  };
}

export async function createItem(ctx: Ctx, input: z.infer<typeof patrimonyItemSchema>) {
  return prisma.$transaction(async (tx) => {
    const i = await tx.patrimonyItem.create({
      data: {
        entityId: ctx.entityId,
        side: input.side,
        category: input.category,
        name: input.name,
        valueCents: BigInt(input.valueCents),
        valuedAt: parseDate(input.valuedAt),
        notes: input.notes ?? null,
      },
    });
    await audit(tx, { ...ctx, action: 'create', resourceType: 'patrimony_item', resourceId: i.id, after: i });
    return { id: i.id };
  });
}

export async function updateItem(ctx: Ctx, id: string, input: z.infer<typeof patrimonyItemUpdateSchema>) {
  const before = await prisma.patrimonyItem.findFirst({ where: { id, entityId: ctx.entityId, deletedAt: null } });
  if (!before) throw notFound('Item não encontrado');
  await prisma.$transaction(async (tx) => {
    const after = await tx.patrimonyItem.update({
      where: { id },
      data: {
        side: input.side,
        category: input.category,
        name: input.name,
        valueCents: input.valueCents === undefined ? undefined : BigInt(input.valueCents),
        valuedAt: input.valuedAt ? parseDate(input.valuedAt) : undefined,
        notes: input.notes,
      },
    });
    await audit(tx, { ...ctx, action: 'update', resourceType: 'patrimony_item', resourceId: id, before, after });
  });
  return { id };
}

export async function deleteItem(ctx: Ctx, id: string) {
  const before = await prisma.patrimonyItem.findFirst({ where: { id, entityId: ctx.entityId, deletedAt: null } });
  if (!before) throw notFound('Item não encontrado');
  await prisma.$transaction(async (tx) => {
    await tx.patrimonyItem.update({ where: { id }, data: { deletedAt: new Date() } });
    await audit(tx, { ...ctx, action: 'delete', resourceType: 'patrimony_item', resourceId: id, before });
  });
}
