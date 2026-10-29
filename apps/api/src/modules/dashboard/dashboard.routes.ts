import { Router } from 'express';
import { z } from 'zod';
import { todayISO } from '../../lib/dates';
import { authOf, membershipOf, parse } from '../../lib/http';
import { transactionListQuerySchema } from '../../contracts';
import { prisma } from '../../lib/prisma';
import { ensureGenerated } from '../recurring/recurring.service';
import { listTransactions } from '../transactions/transactions.service';
import { getConsolidatedDashboard, getEntityDashboard } from './dashboard.service';

const monthQuery = z.object({ month: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/).optional() });

export const entityDashboardRouter = Router({ mergeParams: true });
entityDashboardRouter.get('/', async (req, res) => {
  const { month = todayISO().slice(0, 7) } = parse(monthQuery, req.query);
  res.json({ data: await getEntityDashboard(membershipOf(req).entityId, month) });
});

export const consolidatedRouter = Router();
consolidatedRouter.get('/dashboard', async (req, res) => {
  const { month = todayISO().slice(0, 7) } = parse(monthQuery, req.query);
  res.json({ data: await getConsolidatedDashboard(authOf(req).userId, month) });
});

consolidatedRouter.get('/transactions', async (req, res) => {
  const { userId } = authOf(req);
  const entityIds = (await prisma.entityMember.findMany({ where: { userId, entity: { archivedAt: null } } })).map((m) => m.entityId);
  await ensureGenerated(entityIds);
  res.json(await listTransactions(entityIds, parse(transactionListQuerySchema, req.query)));
});
