import type { Account, CardInvoice, CreditCard } from '@prisma/client';
import type { z } from 'zod';
import type { cardCreateSchema, cardPurchaseSchema, cardUpdateSchema, invoicePaymentSchema } from '../../contracts';
import { invoiceDates, invoiceForPurchase, invoiceStatus, splitInstallments, type InvoiceDates } from '../../domain/cards';
import { formatDate, parseDate, todayISO } from '../../lib/dates';
import { notFound, unprocessable } from '../../lib/errors';
import { recordEvent } from '../../lib/events';
import { toCents } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { accountBalances } from '../accounts/balances';
import { audit } from '../audit/audit.service';
import { addSettlement } from '../settlements/settlements';
import { serializeTransaction, transactionInclude } from '../transactions/transactions.service';
import { createTransfer } from '../transfers/transfers.service';
import { cashAccountType } from '../../lib/ledgers';

type Ctx = { userId: string; entityId: string; ip?: string };
type CardRow = CreditCard & { account: Account; paymentAccount: Account | null };

/** A conta-razão do cartão aceita compras antigas (cadastro de faturas já em andamento). */
const LEDGER_REFERENCE_DATE = '2000-01-01';

const monthDate = (month: string) => parseDate(`${month}-01`);

async function getCardOrThrow(entityId: string, cardId: string, db: Tx | typeof prisma = prisma): Promise<CardRow> {
  const card = await db.creditCard.findFirst({
    where: { id: cardId, entityId },
    include: { account: true, paymentAccount: true },
  });
  if (!card) throw notFound('Cartão não encontrado');
  return card;
}

/** Totais por fatura: soma das parcelas (despesas) e dos pagamentos (entradas na conta-razão). */
async function invoiceTotals(invoiceIds: string[]) {
  const out = new Map<string, { totalCents: number; paidCents: number; count: number }>();
  for (const id of invoiceIds) out.set(id, { totalCents: 0, paidCents: 0, count: 0 });
  if (invoiceIds.length === 0) return out;
  const groups = await prisma.transaction.groupBy({
    by: ['invoiceId', 'type', 'direction'],
    where: { invoiceId: { in: invoiceIds }, deletedAt: null, status: { not: 'CANCELED' } },
    _sum: { amountCents: true },
    _count: true,
  });
  for (const g of groups) {
    const t = out.get(g.invoiceId!)!;
    const v = toCents(g._sum.amountCents ?? 0n);
    if (g.type === 'EXPENSE') {
      t.totalCents += v;
      t.count += g._count;
    } else if (g.type === 'TRANSFER' && g.direction === 'IN') t.paidCents += v;
  }
  return out;
}

function serializeInvoice(inv: CardInvoice, totals: { totalCents: number; paidCents: number; count: number }, today: string) {
  const closingDate = formatDate(inv.closingDate);
  const dueDate = formatDate(inv.dueDate);
  return {
    id: inv.id,
    month: formatDate(inv.month).slice(0, 7),
    closingDate,
    dueDate,
    totalCents: totals.totalCents,
    paidCents: totals.paidCents,
    remainingCents: Math.max(0, totals.totalCents - totals.paidCents),
    itemsCount: totals.count,
    status: invoiceStatus({ closingDate, dueDate, ...totals }, today),
  };
}

async function serializeCard(card: CardRow, today = todayISO()) {
  const balance = (await accountBalances([card.account])).get(card.id) ?? 0;
  const usedCents = Math.max(0, -balance);
  const limitCents = toCents(card.limitCents);
  // Fatura atual = a que recebe as compras de hoje. Pendentes = já fechadas e ainda não quitadas.
  const current = invoiceForPurchase(today, card.closingDay, card.dueDay);
  const invoices = await prisma.cardInvoice.findMany({
    where: { cardId: card.id, OR: [{ closingDate: { lte: parseDate(today) } }, { month: monthDate(current.month) }] },
    orderBy: { month: 'asc' },
  });
  const totals = await invoiceTotals(invoices.map((i) => i.id));
  const serialized = invoices.map((i) => serializeInvoice(i, totals.get(i.id)!, today));
  const pending = serialized.filter((i) => i.status === 'CLOSED' || i.status === 'PARTIAL' || i.status === 'OVERDUE');
  const open = serialized.find((i) => i.month === current.month);
  return {
    id: card.id,
    entityId: card.entityId,
    name: card.account.name,
    institution: card.account.institution,
    brand: card.brand,
    color: card.account.color,
    limitCents,
    usedCents,
    availableCents: limitCents - usedCents,
    closingDay: card.closingDay,
    dueDay: card.dueDay,
    paymentAccount: card.paymentAccount ? { id: card.paymentAccount.id, name: card.paymentAccount.name } : null,
    archived: card.account.archivedAt !== null,
    currentInvoice: open ?? { ...current, totalCents: 0, paidCents: 0, remainingCents: 0, itemsCount: 0, status: 'OPEN' as const, id: null },
    /** Faturas fechadas aguardando pagamento (a pagar). */
    pendingInvoices: pending,
  };
}

export async function listCards(entityId: string, includeArchived = false) {
  const cards = await prisma.creditCard.findMany({
    where: { entityId, ...(includeArchived ? {} : { account: { archivedAt: null } }) },
    include: { account: true, paymentAccount: true },
    orderBy: { createdAt: 'asc' },
  });
  const today = todayISO();
  return Promise.all(cards.map((c) => serializeCard(c, today)));
}

export async function getCard(entityId: string, cardId: string) {
  return serializeCard(await getCardOrThrow(entityId, cardId));
}

async function validatePaymentAccount(db: Tx, entityId: string, id: string | null | undefined) {
  if (!id) return;
  const a = await db.account.findFirst({ where: { id, entityId, archivedAt: null, type: cashAccountType } });
  if (!a) throw unprocessable('INVALID_ACCOUNT', 'Conta de pagamento não pertence a este ambiente');
}

export async function createCard(ctx: Ctx, input: z.infer<typeof cardCreateSchema>) {
  const id = await prisma.$transaction(async (tx) => {
    await validatePaymentAccount(tx, ctx.entityId, input.paymentAccountId);
    const account = await tx.account.create({
      data: {
        entityId: ctx.entityId,
        name: input.name,
        institution: input.institution ?? null,
        type: 'CREDIT_CARD',
        color: input.color ?? null,
        initialBalanceCents: 0n,
        referenceDate: parseDate(LEDGER_REFERENCE_DATE),
      },
    });
    const card = await tx.creditCard.create({
      data: {
        id: account.id,
        entityId: ctx.entityId,
        brand: input.brand ?? null,
        limitCents: BigInt(input.limitCents),
        closingDay: input.closingDay,
        dueDay: input.dueDay,
        paymentAccountId: input.paymentAccountId ?? null,
      },
    });
    await audit(tx, { ...ctx, action: 'create', resourceType: 'credit_card', resourceId: card.id, after: { ...card, name: input.name } });
    return card.id;
  });
  return getCard(ctx.entityId, id);
}

export async function updateCard(ctx: Ctx, cardId: string, input: z.infer<typeof cardUpdateSchema>) {
  const before = await getCardOrThrow(ctx.entityId, cardId);
  await prisma.$transaction(async (tx) => {
    await validatePaymentAccount(tx, ctx.entityId, input.paymentAccountId);
    await tx.account.update({
      where: { id: cardId },
      data: { name: input.name, institution: input.institution, color: input.color },
    });
    const after = await tx.creditCard.update({
      where: { id: cardId },
      data: {
        brand: input.brand,
        limitCents: input.limitCents === undefined ? undefined : BigInt(input.limitCents),
        paymentAccountId: input.paymentAccountId,
      },
    });
    await audit(tx, { ...ctx, action: 'update', resourceType: 'credit_card', resourceId: cardId, before, after });
  });
  return getCard(ctx.entityId, cardId);
}

/** Arquiva o cartão. Só com todas as faturas quitadas (sem limite comprometido). */
export async function setCardArchived(ctx: Ctx, cardId: string, archived: boolean) {
  const card = await getCardOrThrow(ctx.entityId, cardId);
  if (archived) {
    const balance = (await accountBalances([card.account])).get(cardId) ?? 0;
    if (balance < 0) throw unprocessable('CARD_HAS_BALANCE', 'Pague as faturas (inclusive parcelas futuras) antes de arquivar o cartão');
  }
  await prisma.$transaction(async (tx) => {
    await tx.account.update({ where: { id: cardId }, data: { archivedAt: archived ? new Date() : null } });
    await audit(tx, { ...ctx, action: archived ? 'archive' : 'unarchive', resourceType: 'credit_card', resourceId: cardId });
  });
  return getCard(ctx.entityId, cardId);
}

async function ensureInvoice(db: Tx, cardId: string, d: InvoiceDates) {
  return db.cardInvoice.upsert({
    where: { cardId_month: { cardId, month: monthDate(d.month) } },
    create: { cardId, month: monthDate(d.month), closingDate: parseDate(d.closingDate), dueDate: parseDate(d.dueDate) },
    update: {},
  });
}

/**
 * Compra no cartão. Cada parcela vira uma DESPESA liquidada na conta-razão do cartão, na fatura
 * do seu mês: a 1ª na data da compra, as demais no fechamento das faturas seguintes. A despesa é
 * reconhecida aqui e só aqui; pagar a fatura não cria nova despesa (RN08).
 */
export async function createPurchase(ctx: Ctx, cardId: string, input: z.infer<typeof cardPurchaseSchema>) {
  const card = await getCardOrThrow(ctx.entityId, cardId);
  if (card.account.archivedAt) throw unprocessable('CARD_ARCHIVED', 'Cartão arquivado não aceita compras');
  const balance = (await accountBalances([card.account])).get(cardId) ?? 0;
  const available = toCents(card.limitCents) + balance;
  if (input.totalCents > available) {
    throw unprocessable('LIMIT_EXCEEDED', 'Compra acima do limite disponível do cartão');
  }
  if (input.categoryId) {
    const cat = await prisma.category.findFirst({ where: { id: input.categoryId, entityId: ctx.entityId, kind: 'EXPENSE' } });
    if (!cat) throw unprocessable('INVALID_CATEGORY', 'Categoria de despesa não pertence a este ambiente');
  }
  const amounts = splitInstallments(input.totalCents, input.installments);
  const first = invoiceForPurchase(input.purchaseDate, card.closingDay, card.dueDay);
  const n = input.installments;

  const purchaseId = await prisma.$transaction(async (tx) => {
    const purchase = await tx.cardPurchase.create({
      data: {
        entityId: ctx.entityId,
        cardId,
        description: input.description,
        categoryId: input.categoryId ?? null,
        totalCents: BigInt(input.totalCents),
        installmentCount: n,
        purchaseDate: parseDate(input.purchaseDate),
        createdById: ctx.userId,
      },
    });
    for (let k = 0; k < n; k++) {
      const [y, m] = first.month.split('-').map(Number) as [number, number];
      const monthK = new Date(Date.UTC(y, m - 1 + k, 1)).toISOString().slice(0, 7);
      const dates = invoiceDates(monthK, card.closingDay, card.dueDay);
      const invoice = await ensureInvoice(tx, cardId, dates);
      const date = k === 0 ? input.purchaseDate : dates.closingDate;
      const amount = amounts[k]!;
      const t = await tx.transaction.create({
        data: {
          entityId: ctx.entityId,
          accountId: cardId,
          categoryId: input.categoryId ?? null,
          type: 'EXPENSE',
          direction: 'OUT',
          amountCents: BigInt(amount),
          settledAmountCents: BigInt(amount),
          status: 'SETTLED',
          competenceDate: parseDate(date),
          settledDate: parseDate(date),
          description: n > 1 ? `${input.description} (${k + 1}/${n})` : input.description,
          counterparty: card.account.name,
          invoiceId: invoice.id,
          purchaseId: purchase.id,
          installmentNumber: k + 1,
          createdById: ctx.userId,
        },
      });
      await addSettlement(tx, t.id, amount, date, ctx.userId);
    }
    await audit(tx, { ...ctx, action: 'create', resourceType: 'card_purchase', resourceId: purchase.id, after: purchase });
    return purchase.id;
  });
  recordEvent('card.purchase_created', { entityId: ctx.entityId, cardId, installments: n });
  return getPurchase(ctx.entityId, cardId, purchaseId);
}

export async function getPurchase(entityId: string, cardId: string, purchaseId: string) {
  const p = await prisma.cardPurchase.findFirst({
    where: { id: purchaseId, cardId, entityId, deletedAt: null },
    include: {
      category: { select: { id: true, name: true, icon: true, color: true } },
      transactions: { where: { deletedAt: null }, include: { invoice: true }, orderBy: { installmentNumber: 'asc' } },
    },
  });
  if (!p) throw notFound('Compra não encontrada');
  return {
    id: p.id,
    cardId: p.cardId,
    description: p.description,
    category: p.category,
    totalCents: toCents(p.totalCents),
    installmentCount: p.installmentCount,
    purchaseDate: formatDate(p.purchaseDate),
    installments: p.transactions.map((t) => ({
      transactionId: t.id,
      number: t.installmentNumber,
      amountCents: toCents(t.amountCents),
      date: formatDate(t.competenceDate),
      invoiceMonth: t.invoice ? formatDate(t.invoice.month).slice(0, 7) : null,
    })),
  };
}

/** Exclui (logicamente) a compra e todas as suas parcelas, devolvendo o limite. */
export async function deletePurchase(ctx: Ctx, cardId: string, purchaseId: string) {
  const before = await getPurchase(ctx.entityId, cardId, purchaseId);
  await prisma.$transaction(async (tx) => {
    const now = new Date();
    await tx.cardPurchase.update({ where: { id: purchaseId }, data: { deletedAt: now } });
    await tx.transaction.updateMany({ where: { purchaseId }, data: { deletedAt: now } });
    await audit(tx, { ...ctx, action: 'delete', resourceType: 'card_purchase', resourceId: purchaseId, before });
  });
}

/** Fatura de um mês (AAAA-MM) com seus itens e pagamentos. Meses sem compras retornam a fatura vazia. */
export async function getInvoice(entityId: string, cardId: string, month?: string) {
  const card = await getCardOrThrow(entityId, cardId);
  const today = todayISO();
  const m = month ?? invoiceForPurchase(today, card.closingDay, card.dueDay).month;
  const dates = invoiceDates(m, card.closingDay, card.dueDay);
  const inv = await prisma.cardInvoice.findUnique({ where: { cardId_month: { cardId, month: monthDate(m) } } });
  if (!inv) {
    return {
      id: null,
      ...dates,
      totalCents: 0,
      paidCents: 0,
      remainingCents: 0,
      itemsCount: 0,
      status: invoiceStatus({ ...dates, totalCents: 0, paidCents: 0 }, today),
      items: [],
      payments: [],
    };
  }
  const totals = (await invoiceTotals([inv.id])).get(inv.id)!;
  const rows = await prisma.transaction.findMany({
    where: { invoiceId: inv.id, deletedAt: null },
    include: { ...transactionInclude, purchase: { select: { installmentCount: true, purchaseDate: true } } },
    orderBy: [{ competenceDate: 'asc' }, { createdAt: 'asc' }],
  });
  const items = rows
    .filter((t) => t.type === 'EXPENSE')
    .map((t) => ({
      ...serializeTransaction(t, today),
      installmentCount: t.purchase?.installmentCount ?? 1,
      purchaseDate: t.purchase ? formatDate(t.purchase.purchaseDate) : null,
    }));
  const payments = rows
    .filter((t) => t.type === 'TRANSFER' && t.direction === 'IN')
    .map((t) => ({ id: t.id, transferId: t.transferId, date: formatDate(t.competenceDate), amountCents: toCents(t.amountCents) }));
  return { ...serializeInvoice(inv, totals, today), items, payments };
}

/**
 * Paga a fatura (total ou parcialmente) com uma TRANSFERÊNCIA da conta escolhida para a
 * conta-razão do cartão. Não é despesa: as despesas já foram reconhecidas nas compras (RN08).
 */
export async function payInvoice(ctx: Ctx, cardId: string, invoiceId: string, input: z.infer<typeof invoicePaymentSchema>) {
  const card = await getCardOrThrow(ctx.entityId, cardId);
  const inv = await prisma.cardInvoice.findFirst({ where: { id: invoiceId, cardId } });
  if (!inv) throw notFound('Fatura não encontrada');
  const totals = (await invoiceTotals([inv.id])).get(inv.id)!;
  const remaining = totals.totalCents - totals.paidCents;
  if (remaining <= 0) throw unprocessable('INVOICE_PAID', 'Esta fatura já está paga');
  const amount = input.amountCents ?? remaining;
  if (amount > remaining) throw unprocessable('INVALID_AMOUNT', 'Valor maior que o saldo da fatura');
  const month = formatDate(inv.month).slice(0, 7);
  const transfer = await createTransfer(
    ctx.userId,
    {
      fromAccountId: input.fromAccountId,
      toAccountId: cardId,
      amountCents: amount,
      date: input.date,
      description: `Pagamento fatura ${card.account.name} ${month.slice(5)}/${month.slice(0, 4)}`,
      classification: input.classification,
    },
    ctx.ip,
    { invoiceId: inv.id, cardAccountId: cardId },
  );
  recordEvent('card.invoice_paid', { entityId: ctx.entityId, cardId, invoiceId, full: amount === remaining });
  return { transferId: transfer.id, invoice: await getInvoice(ctx.entityId, cardId, month) };
}

/** Faturas com saldo a pagar e vencimento até a data — usadas na projeção de caixa. */
export async function invoicesDueUntil(entityIds: string[], until: string) {
  const invoices = await prisma.cardInvoice.findMany({
    where: { card: { entityId: { in: entityIds }, account: { archivedAt: null } }, dueDate: { lte: parseDate(until) } },
    include: { card: { select: { entityId: true, account: { select: { name: true } } } } },
  });
  const totals = await invoiceTotals(invoices.map((i) => i.id));
  return invoices
    .map((i) => {
      const t = totals.get(i.id)!;
      return {
        id: i.id,
        entityId: i.card.entityId,
        cardId: i.cardId,
        cardName: i.card.account.name,
        month: formatDate(i.month).slice(0, 7),
        closingDate: formatDate(i.closingDate),
        dueDate: formatDate(i.dueDate),
        remainingCents: t.totalCents - t.paidCents,
      };
    })
    .filter((i) => i.remainingCents > 0);
}
