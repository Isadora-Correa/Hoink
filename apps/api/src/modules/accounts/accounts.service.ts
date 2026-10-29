import type { Account } from '@prisma/client';
import { accountCreateSchema, accountUpdateSchema, type TransactionType } from '../../contracts';
import type { z } from 'zod';
import { formatDate, parseDate, todayISO } from '../../lib/dates';
import { notFound, unprocessable } from '../../lib/errors';
import { toCents } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { audit } from '../audit/audit.service';
import { addSettlement } from '../settlements/settlements';
import { accountBalances, settledMovementWhere, settledNetByAccount } from './balances';
import { cashAccountType } from '../../lib/ledgers';

type Ctx = { userId: string; entityId: string; ip?: string };

export function serializeAccount(a: Account, balanceCents: number) {
  return {
    id: a.id,
    entityId: a.entityId,
    name: a.name,
    institution: a.institution,
    type: a.type,
    color: a.color,
    isEmergencyReserve: a.isEmergencyReserve,
    initialBalanceCents: toCents(a.initialBalanceCents),
    referenceDate: formatDate(a.referenceDate),
    balanceCents,
    archived: a.archivedAt !== null,
    createdAt: a.createdAt,
  };
}

export async function getAccountOrThrow(entityId: string, accountId: string) {
  const a = await prisma.account.findFirst({ where: { id: accountId, entityId, type: cashAccountType } });
  if (!a) throw notFound('Conta não encontrada');
  return a;
}

export async function listAccounts(entityId: string, includeArchived = false) {
  const accounts = await prisma.account.findMany({
    // Cartões têm conta-razão própria (limite comprometido), mas não são dinheiro disponível.
    where: { entityId, type: cashAccountType, ...(includeArchived ? {} : { archivedAt: null }) },
    orderBy: [{ archivedAt: { sort: 'asc', nulls: 'first' } }, { createdAt: 'asc' }],
  });
  const balances = await accountBalances(accounts);
  return accounts.map((a) => serializeAccount(a, balances.get(a.id) ?? 0));
}

export async function getAccount(entityId: string, accountId: string) {
  const a = await getAccountOrThrow(entityId, accountId);
  const balances = await accountBalances([a]);
  return serializeAccount(a, balances.get(a.id) ?? 0);
}

export async function createAccount(ctx: Ctx, input: z.infer<typeof accountCreateSchema>) {
  return prisma.$transaction(async (tx) => {
    const a = await tx.account.create({
      data: {
        entityId: ctx.entityId,
        name: input.name,
        institution: input.institution ?? null,
        type: input.type,
        color: input.color ?? null,
        initialBalanceCents: BigInt(input.initialBalanceCents),
        referenceDate: parseDate(input.referenceDate),
      },
    });
    await audit(tx, { ...ctx, action: 'create', resourceType: 'account', resourceId: a.id, after: a });
    return serializeAccount(a, input.initialBalanceCents);
  });
}

export async function updateAccount(ctx: Ctx, accountId: string, input: z.infer<typeof accountUpdateSchema>) {
  const before = await getAccountOrThrow(ctx.entityId, accountId);
  if (input.referenceDate && input.referenceDate > formatDate(before.referenceDate)) {
    // Mover a data de referência para frente esconderia movimentações já liquidadas (RN15).
    const earlier = await prisma.settlement.count({
      where: { date: { lt: parseDate(input.referenceDate) }, transaction: { ...settledMovementWhere, accountId } },
    });
    if (earlier > 0) {
      throw unprocessable(
        'MOVEMENTS_BEFORE_REFERENCE',
        'Há movimentações liquidadas antes da nova data de referência. Ajuste-as ou escolha uma data anterior.',
      );
    }
  }
  return prisma.$transaction(async (tx) => {
    const a = await tx.account.update({
      where: { id: accountId },
      data: {
        name: input.name,
        institution: input.institution,
        type: input.type,
        color: input.color,
        initialBalanceCents: input.initialBalanceCents === undefined ? undefined : BigInt(input.initialBalanceCents),
        referenceDate: input.referenceDate ? parseDate(input.referenceDate) : undefined,
      },
    });
    await audit(tx, { ...ctx, action: 'update', resourceType: 'account', resourceId: a.id, before, after: a });
    const balances = await accountBalances([a], { db: tx });
    return serializeAccount(a, balances.get(a.id) ?? 0);
  });
}

/** Arquiva a conta. Só é permitido com saldo zero e sem lançamentos em aberto, para não "sumir" com dinheiro. */
export async function setArchived(ctx: Ctx, accountId: string, archived: boolean) {
  const a = await getAccountOrThrow(ctx.entityId, accountId);
  if (archived) {
    const balance = (await accountBalances([a])).get(a.id) ?? 0;
    if (balance !== 0) {
      throw unprocessable('ACCOUNT_HAS_BALANCE', 'Transfira ou ajuste o saldo para zero antes de arquivar a conta');
    }
    const open = await prisma.transaction.count({
      where: { accountId, deletedAt: null, status: { in: ['PLANNED', 'PENDING', 'PARTIAL'] } },
    });
    if (open > 0) throw unprocessable('ACCOUNT_HAS_OPEN_ITEMS', 'A conta possui lançamentos em aberto');
  }
  return prisma.$transaction(async (tx) => {
    const updated = await tx.account.update({
      where: { id: accountId },
      data: { archivedAt: archived ? new Date() : null },
    });
    await audit(tx, { ...ctx, action: archived ? 'archive' : 'unarchive', resourceType: 'account', resourceId: a.id });
    return serializeAccount(updated, (await accountBalances([updated], { db: tx })).get(a.id) ?? 0);
  });
}

/**
 * Extrato: saldo de abertura + cada liquidação no período (um recebimento parcial é uma linha)
 * com saldo acumulado.
 */
export async function statement(entityId: string, accountId: string, from: string, to: string) {
  const a = await getAccountOrThrow(entityId, accountId);
  const opening = toCents(a.initialBalanceCents) + ((await settledNetByAccount([a.id], { before: from })).get(a.id) ?? 0);
  const rows = await prisma.settlement.findMany({
    where: {
      date: { gte: parseDate(from), lte: parseDate(to) },
      transaction: { ...settledMovementWhere, accountId },
    },
    orderBy: [{ date: 'asc' }, { createdAt: 'asc' }],
    include: { transaction: { include: { category: { select: { id: true, name: true, icon: true } } } } },
  });
  let running = opening;
  const entries = rows.map((s) => {
    const t = s.transaction;
    const amount = toCents(s.amountCents);
    running += t.direction === 'IN' ? amount : -amount;
    return {
      id: s.id,
      transactionId: t.id,
      date: formatDate(s.date),
      description: t.description,
      type: t.type as TransactionType,
      direction: t.direction,
      amountCents: amount,
      partial: amount !== toCents(t.amountCents),
      category: t.category,
      transferId: t.transferId,
      balanceAfterCents: running,
    };
  });
  return {
    account: serializeAccount(a, (await accountBalances([a])).get(a.id) ?? 0),
    from,
    to,
    openingBalanceCents: opening,
    closingBalanceCents: running,
    entries,
  };
}

/**
 * Conciliação: compara o saldo calculado na data com o saldo informado pelo banco.
 * Opcionalmente cria um lançamento de AJUSTE para a diferença (rastreável, nunca altera o histórico).
 */
export async function reconcile(
  ctx: Ctx,
  accountId: string,
  input: { statementBalanceCents: number; date: string; createAdjustment: boolean },
) {
  const a = await getAccountOrThrow(ctx.entityId, accountId);
  if (input.date < formatDate(a.referenceDate)) {
    throw unprocessable('DATE_BEFORE_REFERENCE', 'Data anterior à data de referência do saldo inicial');
  }
  if (input.date > todayISO()) throw unprocessable('FUTURE_DATE', 'Não é possível conciliar uma data futura');
  const computed = (await accountBalances([a], { until: input.date })).get(a.id) ?? 0;
  const difference = input.statementBalanceCents - computed;
  let adjustmentId: string | null = null;
  if (input.createAdjustment && difference !== 0) {
    adjustmentId = await prisma.$transaction(async (tx) => {
      const amount = BigInt(Math.abs(difference));
      const t = await tx.transaction.create({
        data: {
          entityId: ctx.entityId,
          accountId,
          type: 'ADJUSTMENT',
          direction: difference > 0 ? 'IN' : 'OUT',
          amountCents: amount,
          settledAmountCents: amount,
          status: 'SETTLED',
          competenceDate: parseDate(input.date),
          settledDate: parseDate(input.date),
          description: 'Ajuste de conciliação',
          createdById: ctx.userId,
        },
      });
      await addSettlement(tx, t.id, Math.abs(difference), input.date, ctx.userId);
      await audit(tx, {
        ...ctx,
        action: 'reconcile',
        resourceType: 'account',
        resourceId: accountId,
        after: { computed, statement: input.statementBalanceCents, difference, adjustmentId: t.id },
      });
      return t.id;
    });
  }
  return { computedBalanceCents: computed, statementBalanceCents: input.statementBalanceCents, differenceCents: difference, adjustmentId };
}
