import { Router, type Request } from 'express';
import { patrimonyItemSchema, patrimonyItemUpdateSchema } from '../../contracts';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import * as svc from './patrimony.service';

export const patrimonyRouter = Router({ mergeParams: true });
const ctx = (req: Request) => ({ userId: authOf(req).userId, entityId: membershipOf(req).entityId, ip: req.ip });

patrimonyRouter.get('/', async (req, res) => {
  res.json({ data: await svc.patrimony(membershipOf(req).entityId) });
});
patrimonyRouter.post('/items', async (req, res) => {
  res.status(201).json({ data: await svc.createItem(ctx(req), parse(patrimonyItemSchema, req.body)) });
});
patrimonyRouter.patch('/items/:itemId', async (req, res) => {
  res.json({ data: await svc.updateItem(ctx(req), param(req, 'itemId'), parse(patrimonyItemUpdateSchema, req.body)) });
});
patrimonyRouter.delete('/items/:itemId', async (req, res) => {
  await svc.deleteItem(ctx(req), param(req, 'itemId'));
  res.status(204).end();
});

export const consolidatedPatrimonyRouter = Router();
consolidatedPatrimonyRouter.get('/', async (req, res) => {
  res.json({ data: await svc.consolidatedPatrimony(authOf(req).userId) });
});
