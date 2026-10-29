import { Router } from 'express';
import { z } from 'zod';
import { categoryCreateSchema, categoryUpdateSchema } from '../../contracts';
import { notFound } from '../../lib/errors';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { audit } from '../audit/audit.service';

export const categoriesRouter = Router({ mergeParams: true });

categoriesRouter.get('/', async (req, res) => {
  const q = parse(z.object({ kind: z.enum(['INCOME', 'EXPENSE']).optional() }), req.query);
  const data = await prisma.category.findMany({
    where: { entityId: membershipOf(req).entityId, archivedAt: null, ...(q.kind ? { kind: q.kind } : {}) },
    orderBy: [{ kind: 'asc' }, { isSystem: 'desc' }, { name: 'asc' }],
    select: { id: true, name: true, kind: true, icon: true, color: true, isSystem: true },
  });
  res.json({ data });
});

categoriesRouter.post('/', async (req, res) => {
  const body = parse(categoryCreateSchema, req.body);
  const entityId = membershipOf(req).entityId;
  const data = await prisma.$transaction(async (tx) => {
    const c = await tx.category.create({ data: { ...body, entityId } });
    await audit(tx, { userId: authOf(req).userId, entityId, action: 'create', resourceType: 'category', resourceId: c.id, after: c });
    return c;
  });
  res.status(201).json({ data });
});

categoriesRouter.patch('/:categoryId', async (req, res) => {
  const body = parse(categoryUpdateSchema.omit({ kind: true }), req.body);
  const entityId = membershipOf(req).entityId;
  const id = param(req, 'categoryId');
  const before = await prisma.category.findFirst({ where: { id, entityId } });
  if (!before) throw notFound('Categoria não encontrada');
  const data = await prisma.$transaction(async (tx) => {
    const c = await tx.category.update({ where: { id }, data: body });
    await audit(tx, { userId: authOf(req).userId, entityId, action: 'update', resourceType: 'category', resourceId: id, before, after: c });
    return c;
  });
  res.json({ data });
});

/** Categorias são arquivadas (não excluídas) para preservar o histórico dos lançamentos. */
categoriesRouter.delete('/:categoryId', async (req, res) => {
  const entityId = membershipOf(req).entityId;
  const id = param(req, 'categoryId');
  const r = await prisma.category.updateMany({ where: { id, entityId, archivedAt: null }, data: { archivedAt: new Date() } });
  if (r.count === 0) throw notFound('Categoria não encontrada');
  res.status(204).end();
});
