import { Router, type Request } from 'express';
import { z } from 'zod';
import { investmentCreateSchema, investmentMoveSchema, investmentUpdateSchema, investmentValueSchema } from '../../contracts';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import { idempotency } from '../../middleware/idempotency';
import * as svc from './investments.service';

export const investmentsRouter = Router({ mergeParams: true });
const ctx = (req: Request) => ({ userId: authOf(req).userId, entityId: membershipOf(req).entityId, ip: req.ip });
const entityOf = (req: Request) => membershipOf(req).entityId;

investmentsRouter.get('/', async (req, res) => {
  const q = parse(z.object({ includeClosed: z.enum(['true', 'false']).optional() }), req.query);
  res.json({ data: await svc.listInvestments(entityOf(req), q.includeClosed === 'true') });
});
investmentsRouter.post('/', idempotency, async (req, res) => {
  res.status(201).json({ data: await svc.createInvestment(ctx(req), parse(investmentCreateSchema, req.body)) });
});
investmentsRouter.get('/:investmentId', async (req, res) => {
  res.json({ data: await svc.getInvestment(entityOf(req), param(req, 'investmentId')) });
});
investmentsRouter.patch('/:investmentId', async (req, res) => {
  res.json({ data: await svc.updateInvestment(ctx(req), param(req, 'investmentId'), parse(investmentUpdateSchema, req.body)) });
});
for (const [path, kind] of [
  ['contributions', 'CONTRIBUTION'],
  ['redemptions', 'REDEMPTION'],
  ['income', 'INCOME'],
] as const) {
  investmentsRouter.post(`/:investmentId/${path}`, idempotency, async (req, res) => {
    res.json({ data: await svc.move(ctx(req), param(req, 'investmentId'), kind, parse(investmentMoveSchema, req.body)) });
  });
}
investmentsRouter.post('/:investmentId/value', async (req, res) => {
  res.json({ data: await svc.updateValue(ctx(req), param(req, 'investmentId'), parse(investmentValueSchema, req.body)) });
});
investmentsRouter.delete('/:investmentId/movements/:movementId', async (req, res) => {
  res.json({ data: await svc.deleteMovement(ctx(req), param(req, 'investmentId'), param(req, 'movementId')) });
});
