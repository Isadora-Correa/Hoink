import { Router } from 'express';
import { z } from 'zod';
import { authOf, param, parse } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { archiveEntity, createEntity, enableBusiness, listEntities, updateEntity } from './entities.service';

export const entitiesRouter = Router();

entitiesRouter.get('/', async (req, res) => {
  res.json({ data: await listEntities(authOf(req).userId) });
});

entitiesRouter.post('/', async (req, res) => {
  const { userId } = authOf(req);
  const body = parse(z.object({ name: z.string().trim().min(1).max(80) }), req.body);
  // Ambientes adicionais são sempre profissionais (ex.: outra empresa); há um único Pessoal por usuário.
  const entity = await prisma.$transaction((tx) => createEntity(tx, userId, body.name, 'BUSINESS'));
  res.status(201).json({ data: entity });
});

/** Ativa (ou reativa) a conta profissional do usuário. */
entitiesRouter.post('/business', async (req, res) => {
  const entity = await enableBusiness(authOf(req).userId);
  res.status(201).json({ data: (await listEntities(authOf(req).userId)).find((e) => e.id === entity.id) });
});

/** Desativa um ambiente profissional, preservando os dados. */
entitiesRouter.post('/:entityId/archive', async (req, res) => {
  await archiveEntity(authOf(req).userId, param(req, 'entityId'));
  res.status(204).end();
});

entitiesRouter.patch('/:entityId', async (req, res) => {
  const body = parse(
    z.object({
      name: z.string().trim().min(1).max(80).optional(),
      document: z.string().trim().max(20).nullable().optional(),
      ownershipShareBps: z.number().int().min(0).max(10000).optional(),
    }),
    req.body,
  );
  await updateEntity(authOf(req).userId, param(req, 'entityId'), body);
  res.json({ data: (await listEntities(authOf(req).userId)).find((e) => e.id === req.params.entityId) });
});
