import { Router } from 'express';
import { env } from '../../config/env';
import { manualRateSchema } from '../../contracts';
import { AppError } from '../../lib/errors';
import { authOf, parse } from '../../lib/http';
import { gamificationProfile } from '../piggy/piggy.service';
import { marketStatus, setManualRate } from './market.service';

/** Índices de mercado (CDI, Selic, IPCA): situação e taxa manual quando o Banco Central não responde. */
export const marketRouter = Router();
marketRouter.get('/', async (_req, res) => {
  res.json({ data: await marketStatus() });
});
/** Índices são compartilhados por todos os usuários: só a administração (ADMIN_TOKEN) lança manualmente. */
marketRouter.put('/', async (req, res) => {
  if (!env.ADMIN_TOKEN || req.get('x-admin-token') !== env.ADMIN_TOKEN) {
    throw new AppError(403, 'FORBIDDEN', 'Somente a administração pode lançar índices manualmente');
  }
  res.json({ data: await setManualRate(parse(manualRateSchema, req.body)) });
});

/** Nível, conquistas e sequência de depósitos do usuário. */
export const gamificationRouter = Router();
gamificationRouter.get('/', async (req, res) => {
  res.json({ data: await gamificationProfile(authOf(req).userId) });
});
