import { Router, type Request } from 'express';
import { z } from 'zod';
import { cardCreateSchema, cardPurchaseSchema, cardUpdateSchema, invoicePaymentSchema, monthSchema } from '../../contracts';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import { idempotency } from '../../middleware/idempotency';
import * as svc from './cards.service';

export const cardsRouter = Router({ mergeParams: true });
const ctx = (req: Request) => ({ userId: authOf(req).userId, entityId: membershipOf(req).entityId, ip: req.ip });
const entityOf = (req: Request) => membershipOf(req).entityId;

cardsRouter.get('/', async (req, res) => {
  const q = parse(z.object({ includeArchived: z.enum(['true', 'false']).optional() }), req.query);
  res.json({ data: await svc.listCards(entityOf(req), q.includeArchived === 'true') });
});

cardsRouter.post('/', async (req, res) => {
  res.status(201).json({ data: await svc.createCard(ctx(req), parse(cardCreateSchema, req.body)) });
});

cardsRouter.get('/:cardId', async (req, res) => {
  res.json({ data: await svc.getCard(entityOf(req), param(req, 'cardId')) });
});

cardsRouter.patch('/:cardId', async (req, res) => {
  res.json({ data: await svc.updateCard(ctx(req), param(req, 'cardId'), parse(cardUpdateSchema, req.body)) });
});

cardsRouter.post('/:cardId/archive', async (req, res) => {
  res.json({ data: await svc.setCardArchived(ctx(req), param(req, 'cardId'), true) });
});

cardsRouter.post('/:cardId/unarchive', async (req, res) => {
  res.json({ data: await svc.setCardArchived(ctx(req), param(req, 'cardId'), false) });
});

/** Fatura de um mês (?month=AAAA-MM; padrão: a fatura que recebe as compras de hoje). */
cardsRouter.get('/:cardId/invoice', async (req, res) => {
  const { month } = parse(z.object({ month: monthSchema.optional() }), req.query);
  res.json({ data: await svc.getInvoice(entityOf(req), param(req, 'cardId'), month) });
});

cardsRouter.post('/:cardId/invoices/:invoiceId/pay', idempotency, async (req, res) => {
  const body = parse(invoicePaymentSchema, req.body);
  res.json({ data: await svc.payInvoice(ctx(req), param(req, 'cardId'), param(req, 'invoiceId'), body) });
});

cardsRouter.post('/:cardId/purchases', idempotency, async (req, res) => {
  res.status(201).json({ data: await svc.createPurchase(ctx(req), param(req, 'cardId'), parse(cardPurchaseSchema, req.body)) });
});

cardsRouter.get('/:cardId/purchases/:purchaseId', async (req, res) => {
  res.json({ data: await svc.getPurchase(entityOf(req), param(req, 'cardId'), param(req, 'purchaseId')) });
});

cardsRouter.delete('/:cardId/purchases/:purchaseId', async (req, res) => {
  await svc.deletePurchase(ctx(req), param(req, 'cardId'), param(req, 'purchaseId'));
  res.status(204).end();
});
