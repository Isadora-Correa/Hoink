import type { EntityKind } from '@prisma/client';
import { forbidden, notFound, unprocessable } from '../../lib/errors';
import { prisma, type Tx } from '../../lib/prisma';
import { defaultCategories } from '../categories/defaults';

export async function createEntity(tx: Tx, userId: string, name: string, kind: EntityKind) {
  const entity = await tx.financialEntity.create({
    data: {
      name,
      kind,
      members: { create: { userId, role: 'OWNER' } },
      categories: { create: defaultCategories(kind).map((c) => ({ ...c, isSystem: true })) },
    },
  });
  return entity;
}

/** Todo usuário tem o ambiente Pessoal; o Profissional é opcional. */
export async function createDefaultEntities(tx: Tx, userId: string, withBusiness: boolean) {
  await createEntity(tx, userId, 'Pessoal', 'PERSONAL');
  if (withBusiness) await createEntity(tx, userId, 'Profissional', 'BUSINESS');
}

/**
 * Ativa a conta profissional: reativa o ambiente PJ arquivado mais recente (com todos os dados)
 * ou cria um novo. Idempotente — se já houver um ambiente PJ ativo, retorna-o.
 */
export async function enableBusiness(userId: string) {
  return prisma.$transaction(async (tx) => {
    const owned = await tx.entityMember.findMany({
      where: { userId, role: 'OWNER', entity: { kind: 'BUSINESS' } },
      include: { entity: true },
      orderBy: { entity: { archivedAt: { sort: 'desc', nulls: 'first' } } },
    });
    const active = owned.find((m) => !m.entity.archivedAt);
    if (active) return active.entity;
    const archived = owned[0];
    if (archived) return tx.financialEntity.update({ where: { id: archived.entityId }, data: { archivedAt: null } });
    return createEntity(tx, userId, 'Profissional', 'BUSINESS');
  });
}

/**
 * Desativa um ambiente profissional. Os dados são preservados (arquivamento lógico) e voltam ao reativar.
 * O ambiente Pessoal não pode ser desativado.
 */
export async function archiveEntity(userId: string, entityId: string) {
  const m = await prisma.entityMember.findUnique({
    where: { entityId_userId: { entityId, userId } },
    include: { entity: true },
  });
  if (!m || m.entity.archivedAt) throw notFound('Ambiente não encontrado');
  if (m.role !== 'OWNER') throw forbidden('Somente o proprietário pode desativar o ambiente');
  if (m.entity.kind === 'PERSONAL') throw unprocessable('PERSONAL_REQUIRED', 'O ambiente Pessoal não pode ser desativado');
  await prisma.financialEntity.update({ where: { id: entityId }, data: { archivedAt: new Date() } });
}

export async function listEntities(userId: string) {
  const memberships = await prisma.entityMember.findMany({
    where: { userId, entity: { archivedAt: null } },
    include: { entity: true },
    // Enum no Postgres ordena pela declaração: PERSONAL antes de BUSINESS.
    orderBy: [{ entity: { kind: 'asc' } }, { createdAt: 'asc' }],
  });
  return memberships.map((m) => ({
    id: m.entity.id,
    name: m.entity.name,
    kind: m.entity.kind,
    document: m.entity.document,
    role: m.role,
    ownershipShareBps: m.ownershipShareBps,
  }));
}

export async function updateEntity(
  userId: string,
  entityId: string,
  data: { name?: string; document?: string | null; ownershipShareBps?: number },
) {
  const m = await prisma.entityMember.findUnique({ where: { entityId_userId: { entityId, userId } } });
  if (!m) throw notFound('Ambiente não encontrado');
  if (m.role !== 'OWNER' && m.role !== 'ADMIN') throw forbidden();
  return prisma.$transaction(async (tx) => {
    if (data.name !== undefined || data.document !== undefined) {
      await tx.financialEntity.update({ where: { id: entityId }, data: { name: data.name, document: data.document } });
    }
    if (data.ownershipShareBps !== undefined) {
      await tx.entityMember.update({
        where: { entityId_userId: { entityId, userId } },
        data: { ownershipShareBps: data.ownershipShareBps },
      });
    }
  });
}
