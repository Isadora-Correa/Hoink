import type { MemberRole, TransferClassification } from '@prisma/client';
import type { z } from 'zod';
import type { transferCreateSchema } from '../../contracts';
import { formatDate, parseDate } from '../../lib/dates';
import { notFound, unprocessable } from '../../lib/errors';
import { toCents } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { recordEvent } from '../../lib/events';
import { audit } from '../audit/audit.service';
import { addSettlement } from '../settlements/settlements';

const WRITE: MemberRole[] = ['OWNER', 'ADMIN', 'MEMBER'];

async function writableAccount(userId: string, accountId: string, allowCard = false) {
  const account = await prisma.account.findFirst({
    where: { id: accountId, archivedAt: null, entity: { archivedAt: null, members: { some: { userId, role: { in: WRITE } } } } },
    include: { entity: { select: { id: true, kind: true, name: true } } },
  });
  // Contas de ambientes sem permissão são tratadas como inexistentes (RN11).
  if (!account) throw notFound('Conta não encontrada');
  if (account.type === 'CREDIT_CARD' && !allowCard) {
    throw unprocessable('USE_INVOICE_PAYMENT', 'Para pagar o cartão, use o pagamento da fatura');
  }
  return account;
}

/**
 * Transferência = duas pernas atômicas (saída na origem e entrada no destino) sob um registro `transfers`.
 * Nunca é receita/despesa (RN01). Entre ambientes distintos exige classificação gerencial (RN09).
 */
export async function createTransfer(
  userId: string,
  input: z.infer<typeof transferCreateSchema>,
  ip?: string,
  /** Pagamento de fatura: a perna de entrada vai para a conta-razão do cartão, ligada à fatura. */
  invoice?: { invoiceId: string; cardAccountId: string },
) {
  const from = await writableAccount(userId, input.fromAccountId);
  const to = await writableAccount(userId, input.toAccountId, invoice?.cardAccountId === input.toAccountId);
  const crossEntity = from.entityId !== to.entityId;

  let classification: TransferClassification = input.classification ?? 'INTERNAL';
  if (crossEntity && classification === 'INTERNAL') {
    throw unprocessable(
      'CLASSIFICATION_REQUIRED',
      'Transferências entre ambientes precisam de classificação (ex.: pró-labore, aporte de capital, retirada)',
    );
  }
  if (!crossEntity && classification !== 'INTERNAL') classification = 'INTERNAL';

  for (const acc of [from, to]) {
    if (input.date < formatDate(acc.referenceDate)) {
      throw unprocessable(
        'SETTLED_BEFORE_REFERENCE',
        `A data não pode ser anterior à data de referência da conta ${acc.name} (${formatDate(acc.referenceDate)})`,
      );
    }
  }

  const amount = BigInt(input.amountCents);
  const date = parseDate(input.date);
  const description = input.description || `Transferência ${from.name} → ${to.name}`;

  return prisma.$transaction(async (tx) => {
    const transfer = await tx.transfer.create({
      data: {
        fromEntityId: from.entityId,
        toEntityId: to.entityId,
        classification,
        amountCents: amount,
        date,
        createdById: userId,
      },
    });
    const common = {
      type: 'TRANSFER' as const,
      amountCents: amount,
      settledAmountCents: amount,
      status: 'SETTLED' as const,
      competenceDate: date,
      settledDate: date,
      description,
      notes: input.notes ?? null,
      transferId: transfer.id,
      invoiceId: invoice?.invoiceId ?? null,
      createdById: userId,
    };
    const out = await tx.transaction.create({
      data: { ...common, entityId: from.entityId, accountId: from.id, direction: 'OUT', counterparty: to.name },
    });
    const inn = await tx.transaction.create({
      data: { ...common, entityId: to.entityId, accountId: to.id, direction: 'IN', counterparty: from.name },
    });
    await addSettlement(tx, out.id, input.amountCents, input.date, userId);
    await addSettlement(tx, inn.id, input.amountCents, input.date, userId);
    for (const entityId of new Set([from.entityId, to.entityId])) {
      await audit(tx, { userId, entityId, ip, action: 'create', resourceType: 'transfer', resourceId: transfer.id, after: transfer });
    }
    recordEvent('transfer.created', { transferId: transfer.id, classification, crossEntity });
    return {
      id: transfer.id,
      classification,
      amountCents: toCents(amount),
      date: input.date,
      fromAccountId: from.id,
      toAccountId: to.id,
      fromEntityId: from.entityId,
      toEntityId: to.entityId,
      outTransactionId: out.id,
      inTransactionId: inn.id,
    };
  });
}

export async function deleteTransfer(userId: string, transferId: string, ip?: string) {
  const transfer = await prisma.transfer.findFirst({ where: { id: transferId, deletedAt: null } });
  if (!transfer) throw notFound('Transferência não encontrada');
  // É preciso ter permissão de escrita nos dois ambientes envolvidos.
  const count = await prisma.entityMember.count({
    where: { userId, role: { in: WRITE }, entityId: { in: [transfer.fromEntityId, transfer.toEntityId] } },
  });
  const needed = transfer.fromEntityId === transfer.toEntityId ? 1 : 2;
  if (count < needed) throw notFound('Transferência não encontrada');

  await prisma.$transaction(async (tx) => {
    const now = new Date();
    await tx.transfer.update({ where: { id: transferId }, data: { deletedAt: now } });
    await tx.transaction.updateMany({ where: { transferId }, data: { deletedAt: now } });
    for (const entityId of new Set([transfer.fromEntityId, transfer.toEntityId])) {
      await audit(tx, { userId, entityId, ip, action: 'delete', resourceType: 'transfer', resourceId: transferId, before: transfer });
    }
  });
}
