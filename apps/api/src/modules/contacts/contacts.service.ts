import type { Contact, Prisma } from '@prisma/client';
import type { z } from 'zod';
import type { contactCreateSchema, contactUpdateSchema } from '../../contracts';
import { addDaysISO } from '../../domain/recurrence';
import { parseDate, todayISO } from '../../lib/dates';
import { notFound } from '../../lib/errors';
import { toCents } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { audit } from '../audit/audit.service';
import { invoicesDueUntil } from '../cards/cards.service';
import { serializeTransaction, transactionInclude } from '../transactions/transactions.service';

type Ctx = { userId: string; entityId: string; ip?: string };

const OPEN = ['PLANNED', 'PENDING', 'PARTIAL'] as const;

export interface ContactSummary {
  /** Faturado ao cliente (receitas lançadas, exceto canceladas). */
  billedCents: number;
  /** Efetivamente recebido do cliente. */
  receivedCents: number;
  receivableOpenCents: number;
  receivableOverdueCents: number;
  /** Comprado do fornecedor (despesas lançadas, exceto canceladas). */
  purchasedCents: number;
  paidCents: number;
  payableOpenCents: number;
  payableOverdueCents: number;
}

const emptySummary = (): ContactSummary => ({
  billedCents: 0,
  receivedCents: 0,
  receivableOpenCents: 0,
  receivableOverdueCents: 0,
  purchasedCents: 0,
  paidCents: 0,
  payableOpenCents: 0,
  payableOverdueCents: 0,
});

function overdueWhere(today: string): Prisma.TransactionWhereInput {
  const t = parseDate(today);
  return {
    status: { in: [...OPEN] },
    OR: [{ dueDate: { lt: t } }, { dueDate: null, competenceDate: { lt: t } }],
  };
}

/** Faturado × recebido e em aberto/atrasado por contato — base de inadimplência e histórico. */
export async function summaries(contactIds: string[], today = todayISO()): Promise<Map<string, ContactSummary>> {
  const out = new Map(contactIds.map((id) => [id, emptySummary()]));
  if (contactIds.length === 0) return out;
  const base: Prisma.TransactionWhereInput = {
    contactId: { in: contactIds },
    deletedAt: null,
    status: { not: 'CANCELED' },
    type: { in: ['INCOME', 'EXPENSE'] },
  };
  const [totals, overdue] = await Promise.all([
    prisma.transaction.groupBy({ by: ['contactId', 'type'], where: base, _sum: { amountCents: true, settledAmountCents: true } }),
    prisma.transaction.groupBy({
      by: ['contactId', 'type'],
      where: { ...base, ...overdueWhere(today) },
      _sum: { amountCents: true, settledAmountCents: true },
    }),
  ]);
  for (const g of totals) {
    const s = out.get(g.contactId!)!;
    const amount = toCents(g._sum.amountCents ?? 0n);
    const settled = toCents(g._sum.settledAmountCents ?? 0n);
    if (g.type === 'INCOME') {
      s.billedCents = amount;
      s.receivedCents = settled;
      s.receivableOpenCents = amount - settled;
    } else {
      s.purchasedCents = amount;
      s.paidCents = settled;
      s.payableOpenCents = amount - settled;
    }
  }
  for (const g of overdue) {
    const s = out.get(g.contactId!)!;
    const remaining = toCents(g._sum.amountCents ?? 0n) - toCents(g._sum.settledAmountCents ?? 0n);
    if (g.type === 'INCOME') s.receivableOverdueCents = remaining;
    else s.payableOverdueCents = remaining;
  }
  return out;
}

function serializeContact(c: Contact, summary: ContactSummary) {
  return {
    id: c.id,
    entityId: c.entityId,
    kind: c.kind,
    name: c.name,
    document: c.document,
    email: c.email,
    phone: c.phone,
    notes: c.notes,
    archived: c.archivedAt !== null,
    summary,
  };
}

async function getContactOrThrow(entityId: string, id: string) {
  const c = await prisma.contact.findFirst({ where: { id, entityId } });
  if (!c) throw notFound('Contato não encontrado');
  return c;
}

export async function listContacts(entityId: string, opts: { kind?: 'CLIENT' | 'SUPPLIER'; q?: string; includeArchived?: boolean }) {
  const contacts = await prisma.contact.findMany({
    where: {
      entityId,
      ...(opts.includeArchived ? {} : { archivedAt: null }),
      ...(opts.kind ? { kind: { in: [opts.kind, 'BOTH'] } } : {}),
      ...(opts.q ? { OR: [{ name: { contains: opts.q, mode: 'insensitive' } }, { document: { contains: opts.q.replace(/\D/g, '') || opts.q } }] } : {}),
    },
    orderBy: { name: 'asc' },
  });
  const sums = await summaries(contacts.map((c) => c.id));
  return contacts.map((c) => serializeContact(c, sums.get(c.id)!));
}

export async function getContact(entityId: string, id: string) {
  const c = await getContactOrThrow(entityId, id);
  const [sums, transactions] = await Promise.all([
    summaries([id]),
    prisma.transaction.findMany({
      where: { contactId: id, deletedAt: null },
      include: transactionInclude,
      orderBy: [{ competenceDate: 'desc' }, { createdAt: 'desc' }],
      take: 100,
    }),
  ]);
  const today = todayISO();
  return { ...serializeContact(c, sums.get(id)!), transactions: transactions.map((t) => serializeTransaction(t, today)) };
}

const clean = (v: string | null | undefined) => (v === undefined ? undefined : v || null);

export async function createContact(ctx: Ctx, input: z.infer<typeof contactCreateSchema>) {
  return prisma.$transaction(async (tx) => {
    const c = await tx.contact.create({
      data: {
        entityId: ctx.entityId,
        kind: input.kind,
        name: input.name,
        document: clean(input.document) ?? null,
        email: clean(input.email) ?? null,
        phone: clean(input.phone) ?? null,
        notes: clean(input.notes) ?? null,
      },
    });
    await audit(tx, { ...ctx, action: 'create', resourceType: 'contact', resourceId: c.id, after: c });
    return serializeContact(c, emptySummary());
  });
}

export async function updateContact(ctx: Ctx, id: string, input: z.infer<typeof contactUpdateSchema>) {
  const before = await getContactOrThrow(ctx.entityId, id);
  await prisma.$transaction(async (tx) => {
    const c = await tx.contact.update({
      where: { id },
      data: {
        kind: input.kind,
        name: input.name,
        document: clean(input.document),
        email: clean(input.email),
        phone: clean(input.phone),
        notes: clean(input.notes),
      },
    });
    await audit(tx, { ...ctx, action: 'update', resourceType: 'contact', resourceId: id, before, after: c });
  });
  return getContact(ctx.entityId, id);
}

/** Arquiva (não exclui) para preservar o histórico financeiro do contato. */
export async function setContactArchived(ctx: Ctx, id: string, archived: boolean) {
  await getContactOrThrow(ctx.entityId, id);
  await prisma.$transaction(async (tx) => {
    await tx.contact.update({ where: { id }, data: { archivedAt: archived ? new Date() : null } });
    await audit(tx, { ...ctx, action: archived ? 'archive' : 'unarchive', resourceType: 'contact', resourceId: id });
  });
  return getContact(ctx.entityId, id);
}

/**
 * Contas a receber (receitas) ou a pagar (despesas) em aberto — previstas, pendentes,
 * parcialmente liquidadas — com totais de atraso e dos próximos 7 dias.
 */
export async function payables(
  entityIds: string[],
  q: { kind: 'receivable' | 'payable'; status: 'open' | 'overdue'; contactId?: string },
) {
  const today = todayISO();
  const where: Prisma.TransactionWhereInput = {
    entityId: { in: entityIds },
    deletedAt: null,
    type: q.kind === 'receivable' ? 'INCOME' : 'EXPENSE',
    status: { in: [...OPEN] },
    ...(q.contactId ? { contactId: q.contactId } : {}),
    ...(q.status === 'overdue' ? overdueWhere(today) : {}),
  };
  const rows = await prisma.transaction.findMany({
    where,
    include: transactionInclude,
    orderBy: [{ dueDate: { sort: 'asc', nulls: 'last' } }, { competenceDate: 'asc' }],
    take: 500,
  });
  const items = rows.map((t) => serializeTransaction(t, today));
  const in7 = addDaysISO(today, 7);
  const remaining = (t: (typeof items)[number]) => t.amountCents - t.settledAmountCents;
  const due = (t: (typeof items)[number]) => t.dueDate ?? t.competenceDate;
  // Faturas de cartão fechadas e não quitadas também são contas a pagar.
  const cardInvoices =
    q.kind === 'payable' && !q.contactId
      ? (await invoicesDueUntil(entityIds, '9999-12-31')).filter(
          (i) => i.closingDate <= today && (q.status === 'open' || i.dueDate < today),
        )
      : [];
  const sum = <T>(xs: T[], f: (x: T) => number) => xs.reduce((s, x) => s + f(x), 0);
  return {
    data: items,
    cardInvoices,
    totals: {
      openCents: sum(items, remaining) + sum(cardInvoices, (i) => i.remainingCents),
      overdueCents:
        sum(items.filter((t) => t.effectiveStatus === 'OVERDUE'), remaining) +
        sum(cardInvoices.filter((i) => i.dueDate < today), (i) => i.remainingCents),
      next7DaysCents:
        sum(items.filter((t) => due(t) >= today && due(t) <= in7), remaining) +
        sum(cardInvoices.filter((i) => i.dueDate >= today && i.dueDate <= in7), (i) => i.remainingCents),
      count: items.length + cardInvoices.length,
    },
  };
}
