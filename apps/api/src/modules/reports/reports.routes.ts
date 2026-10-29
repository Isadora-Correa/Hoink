import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { dateSchema, monthSchema } from '../../contracts';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import { notFound } from '../../lib/errors';
import { prisma } from '../../lib/prisma';
import { REPORT_TYPES, type Report, type ReportType } from './report.model';
import { buildReport, resolvePeriod, type Scope } from './reports.service';
import { toCsv, toPdf, toXlsx } from './render';

const querySchema = z.object({
  format: z.enum(['json', 'csv', 'xlsx', 'pdf']).default('json'),
  period: z.enum(['month', 'quarter', 'year', 'custom']).optional(),
  ref: monthSchema.optional(),
  from: dateSchema.optional(),
  to: dateSchema.optional(),
  categoryId: z.string().uuid().optional(),
});

const MIME = {
  csv: 'text/csv; charset=utf-8',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  pdf: 'application/pdf',
} as const;

function reportType(req: Request): ReportType {
  const t = param(req, 'type');
  if (!(t in REPORT_TYPES)) throw notFound('Relatório não encontrado');
  return t as ReportType;
}

async function respond(req: Request, res: Response, scope: Scope) {
  const q = parse(querySchema, req.query);
  const period = resolvePeriod(q);
  const type = reportType(req);
  const report: Report = await buildReport(type, scope, { ...period, categoryId: q.categoryId });
  if (q.format === 'json') {
    res.json({ data: report });
    return;
  }
  const body = q.format === 'csv' ? toCsv(report) : q.format === 'xlsx' ? await toXlsx(report) : await toPdf(report);
  const file = `hoink-${type}-${period.from}-a-${period.to}.${q.format}`;
  res.setHeader('Content-Type', MIME[q.format]);
  res.setHeader('Content-Disposition', `attachment; filename="${file}"`);
  res.setHeader('Cache-Control', 'no-store');
  res.send(body);
}

/** Lista dos relatórios disponíveis. */
export const reportTypesRouter = Router();
reportTypesRouter.get('/', (_req, res) => {
  res.json({ data: Object.entries(REPORT_TYPES).map(([type, title]) => ({ type, title })) });
});

export const entityReportsRouter = Router({ mergeParams: true });
entityReportsRouter.get('/:type', async (req, res) => {
  const entity = await prisma.financialEntity.findUniqueOrThrow({ where: { id: membershipOf(req).entityId } });
  await respond(req, res, { label: entity.name, entities: [{ id: entity.id, name: entity.name, shareBps: 10000 }] });
});

export const consolidatedReportsRouter = Router();
consolidatedReportsRouter.get('/:type', async (req, res) => {
  const memberships = await prisma.entityMember.findMany({
    where: { userId: authOf(req).userId, entity: { archivedAt: null } },
    include: { entity: true },
  });
  await respond(req, res, {
    label: 'Consolidado (Total)',
    entities: memberships.map((m) => ({ id: m.entityId, name: m.entity.name, shareBps: m.ownershipShareBps })),
  });
});
