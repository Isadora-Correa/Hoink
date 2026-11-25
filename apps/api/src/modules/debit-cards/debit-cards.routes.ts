import { Router, type Request } from 'express';
import { z } from 'zod';
import { debitCardCreateSchema, debitCardUpdateSchema } from '../../contracts';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import * as svc from './debit-cards.service';

export const debitCardsRouter = Router({ mergeParams: true });
const ctx = (req: Request) => ({ userId: authOf(req).userId, entityId: membershipOf(req).entityId, ip: req.ip });

debitCardsRouter.get('/', async (req, res) => {
  const q = parse(z.object({ includeArchived: z.enum(['true', 'false']).optional() }), req.query);
  res.json({ data: await svc.listDebitCards(membershipOf(req).entityId, q.includeArchived === 'true') });
});
debitCardsRouter.post('/', async (req, res) => {
  res.status(201).json({ data: await svc.createDebitCard(ctx(req), parse(debitCardCreateSchema, req.body)) });
});
debitCardsRouter.patch('/:cardId', async (req, res) => {
  res.json({ data: await svc.updateDebitCard(ctx(req), param(req, 'cardId'), parse(debitCardUpdateSchema, req.body)) });
});
debitCardsRouter.post('/:cardId/archive', async (req, res) => {
  res.json({ data: await svc.setDebitCardArchived(ctx(req), param(req, 'cardId'), true) });
});
debitCardsRouter.post('/:cardId/unarchive', async (req, res) => {
  res.json({ data: await svc.setDebitCardArchived(ctx(req), param(req, 'cardId'), false) });
});
