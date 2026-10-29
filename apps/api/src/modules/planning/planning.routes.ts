import { Router, type Request } from 'express';
import { z } from 'zod';
import { budgetUpsertSchema, monthSchema, reserveSettingsSchema } from '../../contracts';
import { todayISO } from '../../lib/dates';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import * as svc from './planning.service';

const ctx = (req: Request) => ({ userId: authOf(req).userId, entityId: membershipOf(req).entityId, ip: req.ip });

export const planningRouter = Router({ mergeParams: true });

planningRouter.get('/budgets', async (req, res) => {
  const { month = todayISO().slice(0, 7) } = parse(z.object({ month: monthSchema.optional() }), req.query);
  res.json({ data: await svc.listBudgets(membershipOf(req).entityId, month) });
});

planningRouter.put('/budgets', async (req, res) => {
  res.json({ data: await svc.upsertBudget(ctx(req), parse(budgetUpsertSchema, req.body)) });
});

planningRouter.delete('/budgets/:budgetId', async (req, res) => {
  await svc.deleteBudget(ctx(req), param(req, 'budgetId'));
  res.status(204).end();
});

planningRouter.get('/cashflow', async (req, res) => {
  const m = membershipOf(req);
  res.json({ data: await svc.cashflow([{ entityId: m.entityId, shareBps: 10000 }]) });
});

planningRouter.get('/reserve', async (req, res) => {
  res.json({ data: await svc.reserve(membershipOf(req).entityId) });
});

planningRouter.put('/reserve', async (req, res) => {
  res.json({ data: await svc.updateReserve(ctx(req), parse(reserveSettingsSchema, req.body)) });
});

/** Projeção consolidada (todos os ambientes, ponderados pela participação). */
export const consolidatedPlanningRouter = Router();
consolidatedPlanningRouter.get('/cashflow', async (req, res) => {
  const memberships = await prisma.entityMember.findMany({ where: { userId: authOf(req).userId, entity: { archivedAt: null } } });
  res.json({ data: await svc.cashflow(memberships.map((m) => ({ entityId: m.entityId, shareBps: m.ownershipShareBps }))) });
});
