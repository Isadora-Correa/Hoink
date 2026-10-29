import type { Prisma, Transaction } from '@prisma/client';
import type { z } from 'zod';
import type {
  StoredTransactionStatus,
  TransactionCreateInput,
  TransactionListQuery,
  transactionUpdateSchema,
} from '../../contracts';
import {
  DomainError,
  effectiveStatus,
  expectedCategoryKind,
  normalizeSettlement,
  resolveDirection,
} from '../../domain/transactionRules';
import { formatDate, parseDate, todayISO } from '../../lib/dates';
import { AppError, notFound, unprocessable } from '../../lib/errors';
import { toCents } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { recordEvent } from '../../lib/events';
import { audit } from '../audit/audit.service';
import { addSettlement, replaceSettlements } from '../settlements/settlements';

type Ctx = { userId: string; entityId: string; ip?: string };

export const transactionInclude = {
  category: { select: { id: true, name: true, icon: true, color: true } },
  account: { select: { id: true, name: true, institution: true } },
  transfer: { select: { id: true, classification: true, fromEntityId: true, toEntityId: true } },
  recurringRule: { select: { id: true, amountKind: true, frequency: true, status: true } },
  contact: { select: { id: true, name: true, kind: true } },
} satisfies Prisma.TransactionInclude;
const include = transactionInclude;

type Row = Prisma.TransactionGetPayload<{ include: typeof transactionInclude }>;

export function serializeTransaction(t: Row, today = todayISO()) {
  const dueDate = t.dueDate ? formatDate(t.dueDate) : null;
  const competenceDate = formatDate(t.competenceDate);
  return {
    id: t.id,
    entityId: t.entityId,
    type: t.type,
    direction: t.direction,
    description: t.description,
    amountCents: toCents(t.amountCents),
    settledAmountCents: toCents(t.settledAmountCents),
    status: t.status,
    effectiveStatus: effectiveStatus(t.status, dueDate, competenceDate, today),
    competenceDate,
    dueDate,
    settledDate: t.settledDate ? formatDate(t.settledDate) : null,
    counterparty: t.counterparty,
    contact: t.contact,
    notes: t.notes,
    tags: t.tags,
    account: t.account,
    category: t.category,
    transfer: t.transfer,
    recurring: t.recurringRule
      ? {
          ruleId: t.recurringRule.id,
          occurrenceDate: t.occurrenceDate ? formatDate(t.occurrenceDate) : null,
          isOverride: t.isOverride,
          amountKind: t.recurringRule.amountKind,
          frequency: t.recurringRule.frequency,
          ruleStatus: t.recurringRule.status,
        }
      : null,
    receiptKey: t.receiptKey,
    installment: t.purchaseId ? { purchaseId: t.purchaseId, number: t.installmentNumber, invoiceId: t.invoiceId } : null,
    invoiceId: t.invoiceId,
    createdAt: t.createdAt,
    updatedAt: t.updatedAt,
  };
}

function wrapDomain<T>(fn: () => T): T {
  try {
    return fn();
  } catch (e) {
    if (e instanceof DomainError) throw unprocessable(e.code, e.message);
    throw e;
  }
}

/** Cliente/fornecedor precisa ser do mesmo ambiente; devolve o nome para preencher a contraparte. */
export async function resolveContact(db: Tx, entityId: string, contactId: string | null | undefined) {
  if (!contactId) return null;
  const contact = await db.contact.findFirst({ where: { id: contactId, entityId } });
  if (!contact) throw unprocessable('INVALID_CONTACT', 'Cliente/fornecedor não pertence a este ambiente');
  return contact;
}

async function validateRefs(
  db: Tx,
  entityId: string,
  type: Transaction['type'],
  accountId: string,
  categoryId: string | null | undefined,
  settledDate: string | null,
) {
  const account = await db.account.findFirst({ where: { id: accountId, entityId } });
  if (!account) throw unprocessable('INVALID_ACCOUNT', 'Conta não pertence a este ambiente');
  if (account.type === 'CREDIT_CARD') {
    throw unprocessable('USE_CARD_PURCHASE', 'Gastos no cartão são lançados como compras do cartão');
  }
  if (account.type === 'PIGGY_BANK') {
    throw unprocessable('USE_PIGGY_BANK', 'Use guardar/retirar do cofrinho para movimentá-lo');
  }
  if (account.archivedAt) throw unprocessable('ACCOUNT_ARCHIVED', 'Conta arquivada não aceita novos lançamentos');
  if (settledDate && settledDate < formatDate(account.referenceDate)) {
    throw unprocessable(
      'SETTLED_BEFORE_REFERENCE',
      `A liquidação não pode ser anterior à data de referência do saldo inicial da conta (${formatDate(account.referenceDate)})`,
    );
  }
  if (categoryId) {
    const category = await db.category.findFirst({ where: { id: categoryId, entityId } });
    if (!category) throw unprocessable('INVALID_CATEGORY', 'Categoria não pertence a este ambiente');
    const expected = expectedCategoryKind(type);
    if (expected && category.kind !== expected) {
      throw unprocessable('CATEGORY_KIND_MISMATCH', 'Categoria incompatível com o tipo de lançamento');
    }
  }
}

export async function createTransaction(ctx: Ctx, input: TransactionCreateInput) {
  const direction = wrapDomain(() => resolveDirection(input.type, input.direction));
  const settlement = wrapDomain(() => normalizeSettlement(input));
  return prisma.$transaction(async (tx) => {
    await validateRefs(tx, ctx.entityId, input.type, input.accountId, input.categoryId, settlement.settledDate);
    const contact = await resolveContact(tx, ctx.entityId, input.contactId);
    if (input.receiptKey) {
      const dup = await tx.transaction.findFirst({ where: { entityId: ctx.entityId, receiptKey: input.receiptKey, deletedAt: null } });
      if (dup) throw new AppError(409, 'RECEIPT_ALREADY_USED', 'Esta nota fiscal já foi lançada');
    }
    const t = await tx.transaction.create({
      data: {
        entityId: ctx.entityId,
        accountId: input.accountId,
        categoryId: input.categoryId ?? null,
        type: input.type,
        direction,
        amountCents: BigInt(input.amountCents),
        settledAmountCents: BigInt(settlement.settledAmountCents),
        status: input.status,
        competenceDate: parseDate(input.competenceDate),
        dueDate: input.dueDate ? parseDate(input.dueDate) : null,
        settledDate: settlement.settledDate ? parseDate(settlement.settledDate) : null,
        description: input.description,
        counterparty: input.counterparty ?? contact?.name ?? null,
        contactId: contact?.id ?? null,
        notes: input.notes ?? null,
        tags: input.tags,
        receiptKey: input.receiptKey ?? null,
        createdById: ctx.userId,
      },
      include,
    });
    if (settlement.settledDate) {
      await addSettlement(tx, t.id, settlement.settledAmountCents, settlement.settledDate, ctx.userId);
    }
    await audit(tx, { ...ctx, action: 'create', resourceType: 'transaction', resourceId: t.id, after: t });
    recordEvent('transaction.created', { entityId: ctx.entityId, transactionId: t.id, type: t.type });
    return serializeTransaction(t);
  });
}

async function getRow(entityId: string, id: string, db: Tx | typeof prisma = prisma) {
  const t = await db.transaction.findFirst({ where: { id, entityId, deletedAt: null }, include });
  if (!t) throw notFound('Lançamento não encontrado');
  return t;
}

/** Parcelas de cartão e de dívidas pertencem aos seus módulos; aqui só podem ser liquidadas. */
async function assertFreeForEdit(db: Tx, t: Row) {
  if (t.purchaseId) throw unprocessable('CARD_INSTALLMENT', 'Parcelas de cartão são alteradas pela compra no cartão');
  if (await db.debtInstallment.count({ where: { transactionId: t.id } })) {
    throw unprocessable('DEBT_INSTALLMENT', 'Parcelas de dívida são alteradas pela própria dívida');
  }
}

/** Detalhe do lançamento com o histórico de liquidações (pagamentos/recebimentos parciais). */
export async function getTransaction(entityId: string, id: string) {
  const t = await getRow(entityId, id);
  const settlements = await prisma.settlement.findMany({ where: { transactionId: id }, orderBy: { date: 'asc' } });
  return {
    ...serializeTransaction(t),
    settlements: settlements.map((s) => ({ id: s.id, date: formatDate(s.date), amountCents: toCents(s.amountCents) })),
  };
}

export async function updateTransaction(ctx: Ctx, id: string, input: z.infer<typeof transactionUpdateSchema>) {
  return prisma.$transaction(async (tx) => {
    const before = await getRow(ctx.entityId, id, tx);
    if (before.transferId) {
      throw unprocessable('TRANSFER_LEG', 'Pernas de transferência são alteradas pela própria transferência');
    }
    await assertFreeForEdit(tx, before);
    const merged = {
      status: (input.status ?? before.status) as StoredTransactionStatus,
      amountCents: input.amountCents ?? toCents(before.amountCents),
      competenceDate: input.competenceDate ?? formatDate(before.competenceDate),
      settledAmountCents: input.settledAmountCents ?? toCents(before.settledAmountCents),
      settledDate:
        input.settledDate !== undefined ? input.settledDate : before.settledDate ? formatDate(before.settledDate) : null,
    };
    const settlement = wrapDomain(() => normalizeSettlement(merged));
    const accountId = input.accountId ?? before.accountId;
    const categoryId = input.categoryId !== undefined ? input.categoryId : before.categoryId;
    await validateRefs(tx, ctx.entityId, before.type, accountId, categoryId, settlement.settledDate);
    const contact = input.contactId !== undefined ? await resolveContact(tx, ctx.entityId, input.contactId) : undefined;

    const t = await tx.transaction.update({
      where: { id },
      data: {
        accountId,
        categoryId,
        description: input.description,
        amountCents: BigInt(merged.amountCents),
        status: merged.status,
        settledAmountCents: BigInt(settlement.settledAmountCents),
        settledDate: settlement.settledDate ? parseDate(settlement.settledDate) : null,
        competenceDate: parseDate(merged.competenceDate),
        dueDate: input.dueDate !== undefined ? (input.dueDate ? parseDate(input.dueDate) : null) : undefined,
        counterparty: input.counterparty ?? (contact ? contact.name : undefined),
        contactId: contact === undefined ? undefined : (contact?.id ?? null),
        notes: input.notes,
        tags: input.tags,
        // Editar uma ocorrência isolada protege seus valores contra edições futuras da série.
        isOverride: before.recurringRuleId ? true : undefined,
      },
      include,
    });
    const beforeSettledDate = before.settledDate ? formatDate(before.settledDate) : null;
    if (toCents(before.settledAmountCents) !== settlement.settledAmountCents || beforeSettledDate !== settlement.settledDate) {
      // Edição do valor/data liquidados: o histórico de liquidações passa a refletir o novo estado.
      await replaceSettlements(tx, id, settlement.settledAmountCents, settlement.settledDate, ctx.userId);
    }
    await audit(tx, { ...ctx, action: 'update', resourceType: 'transaction', resourceId: id, before, after: t });
    return serializeTransaction(t);
  });
}

/** Liquida (total ou parcialmente) um lançamento em aberto. `amountCents` é o valor pago agora. */
/**
 * Liquida (total ou parcialmente) um lançamento em aberto. `amountCents` é o valor pago agora.
 * `finalAmountCents` corrige o valor total antes de liquidar — útil para contas variáveis
 * (ex.: energia prevista em R$ 250,00 que veio R$ 287,50); só esta ocorrência é alterada.
 */
export async function settleTransaction(
  ctx: Ctx,
  id: string,
  input: { date: string; amountCents?: number; finalAmountCents?: number },
) {
  return prisma.$transaction(async (tx) => {
    const before = await getRow(ctx.entityId, id, tx);
    if (before.status === 'SETTLED' || before.status === 'CANCELED') {
      throw unprocessable('NOT_OPEN', 'Lançamento não está em aberto');
    }
    const already = toCents(before.settledAmountCents);
    if (input.finalAmountCents !== undefined && input.finalAmountCents < already) {
      throw unprocessable('INVALID_AMOUNT', 'O valor final não pode ser menor que o já liquidado');
    }
    const total = input.finalAmountCents ?? toCents(before.amountCents);
    const paying = input.amountCents ?? total - already;
    if (paying <= 0 || already + paying > total) {
      throw unprocessable('INVALID_AMOUNT', 'Valor de liquidação inválido');
    }
    const settled = already + paying;
    await validateRefs(tx, ctx.entityId, before.type, before.accountId, before.categoryId, input.date);
    const t = await tx.transaction.update({
      where: { id },
      data: {
        amountCents: BigInt(total),
        isOverride: before.recurringRuleId && total !== toCents(before.amountCents) ? true : undefined,
        settledAmountCents: BigInt(settled),
        status: settled === total ? 'SETTLED' : 'PARTIAL',
        settledDate: parseDate(input.date),
      },
      include,
    });
    await addSettlement(tx, id, paying, input.date, ctx.userId);
    await audit(tx, { ...ctx, action: 'settle', resourceType: 'transaction', resourceId: id, before, after: t });
    return serializeTransaction(t);
  });
}

export async function deleteTransaction(ctx: Ctx, id: string) {
  await prisma.$transaction(async (tx) => {
    const before = await getRow(ctx.entityId, id, tx);
    if (before.transferId) {
      throw unprocessable('TRANSFER_LEG', 'Exclua a transferência para remover suas duas pernas');
    }
    await assertFreeForEdit(tx, before);
    if (before.recurringRuleId) {
      // Ocorrência de recorrência: cancela em vez de excluir, para não ser gerada de novo.
      await tx.transaction.update({
        where: { id },
        data: { status: 'CANCELED', settledAmountCents: 0n, settledDate: null, isOverride: true },
      });
      await replaceSettlements(tx, id, 0, null, ctx.userId);
      await audit(tx, { ...ctx, action: 'cancel_occurrence', resourceType: 'transaction', resourceId: id, before });
      return;
    }
    await tx.transaction.update({ where: { id }, data: { deletedAt: new Date() } });
    await audit(tx, { ...ctx, action: 'delete', resourceType: 'transaction', resourceId: id, before });
  });
}

export function buildWhere(entityIds: string[], q: TransactionListQuery, today = todayISO()): Prisma.TransactionWhereInput {
  const and: Prisma.TransactionWhereInput[] = [{ entityId: { in: entityIds }, deletedAt: null }];
  if (q.type) and.push({ type: q.type });
  if (q.kind === 'income') and.push({ type: 'INCOME' });
  if (q.kind === 'expense') and.push({ type: 'EXPENSE' });
  if (q.kind === 'transfer') and.push({ type: 'TRANSFER' });
  if (q.kind === 'recurring') and.push({ recurringRuleId: { not: null } });
  if (q.accountId) and.push({ accountId: q.accountId });
  if (q.categoryId) and.push({ categoryId: q.categoryId });
  if (q.contactId) and.push({ contactId: q.contactId });
  if (q.from) and.push({ competenceDate: { gte: parseDate(q.from) } });
  if (q.to) and.push({ competenceDate: { lte: parseDate(q.to) } });
  if (q.q) {
    and.push({
      OR: [
        { description: { contains: q.q, mode: 'insensitive' } },
        { counterparty: { contains: q.q, mode: 'insensitive' } },
        { notes: { contains: q.q, mode: 'insensitive' } },
        { tags: { has: q.q.toLowerCase() } },
      ],
    });
  }
  const t = parseDate(today);
  const overdue: Prisma.TransactionWhereInput = {
    status: { in: ['PLANNED', 'PENDING', 'PARTIAL'] },
    OR: [{ dueDate: { lt: t } }, { dueDate: null, competenceDate: { lt: t } }],
  };
  if (q.status === 'OVERDUE') and.push(overdue);
  else if (q.status) {
    and.push({ status: q.status });
    if (q.status !== 'SETTLED' && q.status !== 'CANCELED') and.push({ NOT: overdue });
  }
  return { AND: and };
}

const ORDER: Record<TransactionListQuery['sort'], Prisma.TransactionOrderByWithRelationInput[]> = {
  date_desc: [{ competenceDate: 'desc' }, { createdAt: 'desc' }],
  date_asc: [{ competenceDate: 'asc' }, { createdAt: 'asc' }],
  amount_desc: [{ amountCents: 'desc' }, { createdAt: 'desc' }],
  amount_asc: [{ amountCents: 'asc' }, { createdAt: 'desc' }],
};

export async function listTransactions(entityIds: string[], q: TransactionListQuery) {
  const where = buildWhere(entityIds, q);
  const [total, rows] = await prisma.$transaction([
    prisma.transaction.count({ where }),
    prisma.transaction.findMany({
      where,
      include,
      orderBy: ORDER[q.sort],
      skip: (q.page - 1) * q.pageSize,
      take: q.pageSize,
    }),
  ]);
  const today = todayISO();
  return {
    data: rows.map((r) => serializeTransaction(r, today)),
    meta: { page: q.page, pageSize: q.pageSize, total, totalPages: Math.max(1, Math.ceil(total / q.pageSize)) },
  };
}
