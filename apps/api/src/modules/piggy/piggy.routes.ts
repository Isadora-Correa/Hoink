import { Router, type Request } from 'express';
import { z } from 'zod';
import {
  piggyAchieveSchema,
  piggyCreateSchema,
  piggyDepositSchema,
  piggyMoveSchema,
  piggyUpdateSchema,
  piggyYieldSchema,
  simulateQuerySchema,
} from '../../contracts';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import { idempotency } from '../../middleware/idempotency';
import * as svc from './piggy.service';

export const piggyRouter = Router({ mergeParams: true });
const ctx = (req: Request) => ({ userId: authOf(req).userId, entityId: membershipOf(req).entityId, ip: req.ip });
const entityOf = (req: Request) => membershipOf(req).entityId;

piggyRouter.get('/', async (req, res) => {
  const q = parse(z.object({ includeArchived: z.enum(['true', 'false']).optional() }), req.query);
  res.json({ data: await svc.listPiggies(entityOf(req), q.includeArchived === 'true') });
});
piggyRouter.post('/', async (req, res) => {
  res.status(201).json({ data: await svc.createPiggy(ctx(req), parse(piggyCreateSchema, req.body)) });
});
piggyRouter.get('/:piggyId', async (req, res) => {
  res.json({ data: await svc.getPiggy(entityOf(req), param(req, 'piggyId')) });
});
piggyRouter.patch('/:piggyId', async (req, res) => {
  res.json({ data: await svc.updatePiggy(ctx(req), param(req, 'piggyId'), parse(piggyUpdateSchema, req.body)) });
});
piggyRouter.post('/:piggyId/deposit', idempotency, async (req, res) => {
  res.json({ data: await svc.deposit(ctx(req), param(req, 'piggyId'), parse(piggyDepositSchema, req.body)) });
});
piggyRouter.post('/:piggyId/withdraw', idempotency, async (req, res) => {
  res.json({ data: await svc.withdraw(ctx(req), param(req, 'piggyId'), parse(piggyMoveSchema, req.body)) });
});
piggyRouter.post('/:piggyId/yield', idempotency, async (req, res) => {
  res.json({ data: await svc.confirmYield(ctx(req), param(req, 'piggyId'), parse(piggyYieldSchema, req.body)) });
});
piggyRouter.post('/:piggyId/achieve', idempotency, async (req, res) => {
  res.json({ data: await svc.achieve(ctx(req), param(req, 'piggyId'), parse(piggyAchieveSchema, req.body)) });
});
piggyRouter.post('/:piggyId/archive', async (req, res) => {
  await svc.archivePiggy(ctx(req), param(req, 'piggyId'));
  res.status(204).end();
});
piggyRouter.get('/:piggyId/simulate', async (req, res) => {
  res.json({ data: await svc.simulatePiggy(entityOf(req), param(req, 'piggyId'), parse(simulateQuerySchema, req.query)) });
});
