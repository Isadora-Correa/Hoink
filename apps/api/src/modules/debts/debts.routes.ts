import { Router, type Request } from 'express';
import { z } from 'zod';
import {
  dateSchema,
  debtCreateSchema,
  debtPayoffSchema,
  debtPrepaySchema,
  debtSimulationSchema,
  debtUpdateSchema,
} from '../../contracts';
import { todayISO } from '../../lib/dates';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import { idempotency } from '../../middleware/idempotency';
import * as svc from './debts.service';

export const debtsRouter = Router({ mergeParams: true });
const ctx = (req: Request) => ({ userId: authOf(req).userId, entityId: membershipOf(req).entityId, ip: req.ip });
const entityOf = (req: Request) => membershipOf(req).entityId;

debtsRouter.get('/', async (req, res) => {
  const q = parse(z.object({ includeClosed: z.enum(['true', 'false']).optional() }), req.query);
  res.json({ data: await svc.listDebts(entityOf(req), q.includeClosed === 'true') });
});

/** Prévia do cronograma (PRICE/SAC) sem cadastrar. */
debtsRouter.post('/simulate', async (req, res) => {
  res.json({ data: svc.simulate(parse(debtSimulationSchema, req.body)) });
});

debtsRouter.post('/', idempotency, async (req, res) => {
  res.status(201).json({ data: await svc.createDebt(ctx(req), parse(debtCreateSchema, req.body)) });
});

debtsRouter.get('/:debtId', async (req, res) => {
  res.json({ data: await svc.getDebt(entityOf(req), param(req, 'debtId')) });
});

debtsRouter.patch('/:debtId', async (req, res) => {
  res.json({ data: await svc.updateDebt(ctx(req), param(req, 'debtId'), parse(debtUpdateSchema, req.body)) });
});

debtsRouter.post('/:debtId/prepay', idempotency, async (req, res) => {
  res.json({ data: await svc.prepay(ctx(req), param(req, 'debtId'), parse(debtPrepaySchema, req.body)) });
});

/** Simulação de quitação (?date=AAAA-MM-DD, padrão hoje). */
debtsRouter.get('/:debtId/payoff', async (req, res) => {
  const { date = todayISO() } = parse(z.object({ date: dateSchema.optional() }), req.query);
  res.json({ data: await svc.payoffSimulation(entityOf(req), param(req, 'debtId'), date) });
});

debtsRouter.post('/:debtId/payoff', idempotency, async (req, res) => {
  res.json({ data: await svc.payoff(ctx(req), param(req, 'debtId'), parse(debtPayoffSchema, req.body)) });
});

debtsRouter.post('/:debtId/cancel', async (req, res) => {
  res.json({ data: await svc.cancelDebt(ctx(req), param(req, 'debtId')) });
});
