import { Router, type Request } from 'express';
import { z } from 'zod';
import { recurringCreateSchema, recurringUpdateSchema } from '../../contracts';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import * as svc from './recurring.service';

export const recurringRouter = Router({ mergeParams: true });

const ctx = (req: Request) => ({ userId: authOf(req).userId, entityId: membershipOf(req).entityId, ip: req.ip });

recurringRouter.get('/', async (req, res) => {
  const q = parse(z.object({ status: z.enum(['ACTIVE', 'PAUSED', 'CANCELED']).optional() }), req.query);
  res.json({ data: await svc.listRules(membershipOf(req).entityId, q.status) });
});

recurringRouter.post('/', async (req, res) => {
  res.status(201).json({ data: await svc.createRule(ctx(req), parse(recurringCreateSchema, req.body)) });
});

recurringRouter.get('/:ruleId', async (req, res) => {
  res.json({ data: await svc.getRule(membershipOf(req).entityId, param(req, 'ruleId')) });
});

recurringRouter.patch('/:ruleId', async (req, res) => {
  res.json({ data: await svc.updateRule(ctx(req), param(req, 'ruleId'), parse(recurringUpdateSchema, req.body)) });
});

recurringRouter.post('/:ruleId/pause', async (req, res) => {
  res.json({ data: await svc.pauseRule(ctx(req), param(req, 'ruleId')) });
});

recurringRouter.post('/:ruleId/resume', async (req, res) => {
  res.json({ data: await svc.resumeRule(ctx(req), param(req, 'ruleId')) });
});

recurringRouter.post('/:ruleId/cancel', async (req, res) => {
  res.json({ data: await svc.cancelRule(ctx(req), param(req, 'ruleId')) });
});
