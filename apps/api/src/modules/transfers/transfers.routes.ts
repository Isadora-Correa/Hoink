import { Router } from 'express';
import { transferCreateSchema } from '../../contracts';
import { authOf, param, parse } from '../../lib/http';
import { idempotency } from '../../middleware/idempotency';
import { createTransfer, deleteTransfer } from './transfers.service';

/** Rotas de transferência não ficam sob um ambiente, pois podem cruzar Pessoal ↔ Profissional. */
export const transfersRouter = Router();

transfersRouter.post('/', idempotency, async (req, res) => {
  res.status(201).json({ data: await createTransfer(authOf(req).userId, parse(transferCreateSchema, req.body), req.ip) });
});

transfersRouter.delete('/:id', async (req, res) => {
  await deleteTransfer(authOf(req).userId, param(req, 'id'), req.ip);
  res.status(204).end();
});
