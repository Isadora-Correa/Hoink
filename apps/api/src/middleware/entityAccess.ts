import type { MemberRole } from '@prisma/client';
import type { NextFunction, Request, Response } from 'express';
import { AppError, forbidden, notFound } from '../lib/errors';
import { prisma } from '../lib/prisma';

const WRITE_ROLES: MemberRole[] = ['OWNER', 'ADMIN', 'MEMBER'];
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Resolve o ambiente (:entityId) e garante que o usuário autenticado é membro (RN11).
 * Responde 404 (e não 403) para ambientes de terceiros, sem revelar sua existência.
 * Métodos de escrita exigem papel com permissão de escrita.
 */
export async function requireEntityAccess(req: Request, _res: Response, next: NextFunction) {
  const entityId = req.params.entityId;
  if (!req.auth) throw new AppError(401, 'UNAUTHORIZED', 'Não autenticado');
  if (typeof entityId !== 'string' || !UUID_RE.test(entityId)) throw notFound('Ambiente não encontrado');

  const membership = await prisma.entityMember.findUnique({
    where: { entityId_userId: { entityId, userId: req.auth.userId } },
    include: { entity: { select: { archivedAt: true } } },
  });
  if (!membership || membership.entity.archivedAt) throw notFound('Ambiente não encontrado');

  if (req.method !== 'GET' && !WRITE_ROLES.includes(membership.role)) {
    throw forbidden('Seu papel neste ambiente permite apenas leitura');
  }
  req.membership = { entityId, role: membership.role, ownershipShareBps: membership.ownershipShareBps };
  next();
}
