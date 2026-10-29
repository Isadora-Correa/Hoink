import { Router } from 'express';
import { z } from 'zod';
import { accountCreateSchema, accountUpdateSchema, dateSchema, reconcileSchema } from '../../contracts';
import { monthRange, todayISO } from '../../lib/dates';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import * as svc from './accounts.service';

export const accountsRouter = Router({ mergeParams: true });

const ctx = (req: Parameters<typeof authOf>[0]) => ({
  userId: authOf(req).userId,
  entityId: membershipOf(req).entityId,
  ip: req.ip,
});

accountsRouter.get('/', async (req, res) => {
  const q = parse(z.object({ includeArchived: z.enum(['true', 'false']).optional() }), req.query);
  res.json({ data: await svc.listAccounts(membershipOf(req).entityId, q.includeArchived === 'true') });
});

accountsRouter.post('/', async (req, res) => {
  res.status(201).json({ data: await svc.createAccount(ctx(req), parse(accountCreateSchema, req.body)) });
});

accountsRouter.get('/:accountId', async (req, res) => {
  res.json({ data: await svc.getAccount(membershipOf(req).entityId, param(req, 'accountId')) });
});

accountsRouter.patch('/:accountId', async (req, res) => {
  res.json({ data: await svc.updateAccount(ctx(req), param(req, 'accountId'), parse(accountUpdateSchema, req.body)) });
});

accountsRouter.post('/:accountId/archive', async (req, res) => {
  res.json({ data: await svc.setArchived(ctx(req), param(req, 'accountId'), true) });
});

accountsRouter.post('/:accountId/unarchive', async (req, res) => {
  res.json({ data: await svc.setArchived(ctx(req), param(req, 'accountId'), false) });
});

accountsRouter.get('/:accountId/statement', async (req, res) => {
  const current = monthRange(todayISO().slice(0, 7));
  const q = parse(z.object({ from: dateSchema.default(current.from), to: dateSchema.default(current.to) }), req.query);
  res.json({ data: await svc.statement(membershipOf(req).entityId, param(req, 'accountId'), q.from, q.to) });
});

accountsRouter.post('/:accountId/reconcile', async (req, res) => {
  res.json({ data: await svc.reconcile(ctx(req), param(req, 'accountId'), parse(reconcileSchema, req.body)) });
});
