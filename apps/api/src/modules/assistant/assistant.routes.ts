import { Router, type Request } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { centsSchema } from '../../contracts';
import { compareInvestments } from '../../domain/yields';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { currentAnnualPct, marketStatus } from '../market/market.service';
import * as notifications from '../notifications/notifications.service';
import { ask, assistantInfo, insights, type Scope } from './assistant.service';

const askSchema = z.object({ question: z.string().trim().min(2, 'Faça uma pergunta').max(300) });
// Perguntas podem chamar a IA (custo por uso): limite por IP.
const askLimiter = rateLimit({ windowMs: 60_000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false });

async function entityScope(req: Request): Promise<Scope> {
  const e = await prisma.financialEntity.findUniqueOrThrow({ where: { id: membershipOf(req).entityId } });
  return { label: e.name, entities: [{ id: e.id, name: e.name, kind: e.kind, shareBps: 10000 }] };
}

async function userScope(req: Request): Promise<Scope> {
  const ms = await prisma.entityMember.findMany({ where: { userId: authOf(req).userId, entity: { archivedAt: null } }, include: { entity: true } });
  return { label: 'Consolidado (Total)', entities: ms.map((m) => ({ id: m.entityId, name: m.entity.name, kind: m.entity.kind, shareBps: m.ownershipShareBps })) };
}

/** Costelinha no ambiente: /entities/:id/assistant */
export const entityAssistantRouter = Router({ mergeParams: true });
entityAssistantRouter.post('/ask', askLimiter, async (req, res) => {
  res.json({ data: await ask(await entityScope(req), parse(askSchema, req.body).question) });
});
entityAssistantRouter.get('/insights', async (req, res) => {
  res.json({ data: await insights(await entityScope(req)) });
});

/** Costelinha no consolidado + informações gerais: /assistant */
export const assistantRouter = Router();
assistantRouter.get('/', (_req, res) => {
  res.json({ data: assistantInfo() });
});
assistantRouter.post('/ask', askLimiter, async (req, res) => {
  res.json({ data: await ask(await userScope(req), parse(askSchema, req.body).question) });
});
assistantRouter.get('/insights', async (req, res) => {
  res.json({ data: await insights(await userScope(req)) });
});

/** Comparador de investimentos (estimativa com as taxas atuais dos índices). */
const compareSchema = z.object({
  amountCents: centsSchema.refine((v) => v > 0, 'Informe o valor'),
  months: z.number().int().min(1).max(600),
  options: z
    .array(
      z.object({
        label: z.string().trim().min(1).max(60),
        indexer: z.enum(['CDI_PERCENT', 'SELIC_PERCENT', 'PREFIXED', 'IPCA_PLUS']),
        rateBps: z.number().int().min(0).max(100_000),
        taxation: z.enum(['REGRESSIVE', 'EXEMPT', 'STOCKS']),
        costsBps: z.number().int().min(0).max(10_000).default(0),
      }),
    )
    .min(1)
    .max(8),
});
assistantRouter.post('/compare-investments', async (req, res) => {
  const body = parse(compareSchema, req.body);
  const resolved = await Promise.all(
    body.options.map(async (o) => ({ ...o, annualPct: await currentAnnualPct(o.indexer, o.rateBps) })),
  );
  const missing = resolved.filter((o) => o.annualPct === null).map((o) => o.label);
  const results = compareInvestments(
    body.amountCents,
    body.months,
    resolved.filter((o) => o.annualPct !== null).map((o) => ({ ...o, annualPct: o.annualPct! })),
  );
  res.json({ data: { estimate: true, results, missingRates: missing, rates: await marketStatus() } });
});

/** Notificações do usuário. */
export const notificationsRouter = Router();
notificationsRouter.get('/', async (req, res) => {
  res.json({ data: await notifications.list(authOf(req).userId) });
});
notificationsRouter.post('/read-all', async (req, res) => {
  await notifications.markAllRead(authOf(req).userId);
  res.status(204).end();
});
notificationsRouter.post('/:id/read', async (req, res) => {
  await notifications.markRead(authOf(req).userId, param(req, 'id'));
  res.status(204).end();
});
