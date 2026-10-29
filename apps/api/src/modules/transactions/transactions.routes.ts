import { Router, type Request } from 'express';
import { z } from 'zod';
import {
  centsSchema,
  dateSchema,
  transactionCreateSchema,
  transactionListQuerySchema,
  transactionUpdateSchema,
} from '../../contracts';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import { idempotency } from '../../middleware/idempotency';
import { ensureGenerated } from '../recurring/recurring.service';
import * as svc from './transactions.service';

export const transactionsRouter = Router({ mergeParams: true });

const ctx = (req: Request) => ({ userId: authOf(req).userId, entityId: membershipOf(req).entityId, ip: req.ip });

transactionsRouter.get('/', async (req, res) => {
  await ensureGenerated([membershipOf(req).entityId]);
  res.json(await svc.listTransactions([membershipOf(req).entityId], parse(transactionListQuerySchema, req.query)));
});

transactionsRouter.post('/', idempotency, async (req, res) => {
  res.status(201).json({ data: await svc.createTransaction(ctx(req), parse(transactionCreateSchema, req.body)) });
});

transactionsRouter.get('/:id', async (req, res) => {
  res.json({ data: await svc.getTransaction(membershipOf(req).entityId, param(req, 'id')) });
});

transactionsRouter.patch('/:id', async (req, res) => {
  res.json({ data: await svc.updateTransaction(ctx(req), param(req, 'id'), parse(transactionUpdateSchema, req.body)) });
});

transactionsRouter.post('/:id/settle', idempotency, async (req, res) => {
  const body = parse(
    z.object({
      date: dateSchema,
      amountCents: centsSchema.optional(),
      finalAmountCents: centsSchema.refine((v) => v > 0).optional(),
    }),
    req.body,
  );
  res.json({ data: await svc.settleTransaction(ctx(req), param(req, 'id'), body) });
});

transactionsRouter.delete('/:id', async (req, res) => {
  await svc.deleteTransaction(ctx(req), param(req, 'id'));
  res.status(204).end();
});
