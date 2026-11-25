import type { Account, DebitCard } from '@prisma/client';
import type { z } from 'zod';
import type { debitCardCreateSchema, debitCardUpdateSchema } from '../../contracts';
import { notFound, unprocessable } from '../../lib/errors';
import { cashAccountType } from '../../lib/ledgers';
import { prisma, type Tx } from '../../lib/prisma';
import { audit } from '../audit/audit.service';

type Ctx = { userId: string; entityId: string; ip?: string };

function serialize(card: DebitCard & { account: Account }) {
  return {
    id: card.id,
    entityId: card.entityId,
    name: card.name,
    institution: card.institution,
    brand: card.brand,
    account: { id: card.account.id, name: card.account.name },
    archived: card.archivedAt !== null,
  };
}

async function getOrThrow(entityId: string, id: string) {
  const card = await prisma.debitCard.findFirst({ where: { id, entityId }, include: { account: true } });
  if (!card) throw notFound('Cartão não encontrado');
  return card;
}

/** A conta vinculada precisa ser uma conta de dinheiro (não cartão de crédito nem cofrinho) deste ambiente. */
async function validateAccount(db: Tx, entityId: string, accountId: string | undefined) {
  if (!accountId) return;
  const a = await db.account.findFirst({ where: { id: accountId, entityId, archivedAt: null, type: cashAccountType } });
  if (!a) throw unprocessable('INVALID_ACCOUNT', 'A conta vinculada não pertence a este ambiente');
}

export async function listDebitCards(entityId: string, includeArchived = false) {
  const cards = await prisma.debitCard.findMany({
    where: { entityId, ...(includeArchived ? {} : { archivedAt: null }) },
    include: { account: true },
    orderBy: { createdAt: 'asc' },
  });
  return cards.map(serialize);
}

export async function createDebitCard(ctx: Ctx, input: z.infer<typeof debitCardCreateSchema>) {
  const card = await prisma.$transaction(async (tx) => {
    await validateAccount(tx, ctx.entityId, input.accountId);
    const created = await tx.debitCard.create({
      data: {
        entityId: ctx.entityId,
        accountId: input.accountId,
        name: input.name,
        institution: input.institution ?? null,
        brand: input.brand ?? null,
      },
      include: { account: true },
    });
    await audit(tx, { ...ctx, action: 'create', resourceType: 'debit_card', resourceId: created.id, after: created });
    return created;
  });
  return serialize(card);
}

export async function updateDebitCard(ctx: Ctx, id: string, input: z.infer<typeof debitCardUpdateSchema>) {
  const before = await getOrThrow(ctx.entityId, id);
  const card = await prisma.$transaction(async (tx) => {
    await validateAccount(tx, ctx.entityId, input.accountId);
    const after = await tx.debitCard.update({
      where: { id },
      data: { name: input.name, institution: input.institution, brand: input.brand, accountId: input.accountId },
      include: { account: true },
    });
    await audit(tx, { ...ctx, action: 'update', resourceType: 'debit_card', resourceId: id, before, after });
    return after;
  });
  return serialize(card);
}

export async function setDebitCardArchived(ctx: Ctx, id: string, archived: boolean) {
  await getOrThrow(ctx.entityId, id);
  const card = await prisma.$transaction(async (tx) => {
    const after = await tx.debitCard.update({
      where: { id },
      data: { archivedAt: archived ? new Date() : null },
      include: { account: true },
    });
    await audit(tx, { ...ctx, action: archived ? 'archive' : 'unarchive', resourceType: 'debit_card', resourceId: id });
    return after;
  });
  return serialize(card);
}
