import cors from 'cors';
import express, { Router } from 'express';
import helmet from 'helmet';
import { pinoHttp } from 'pino-http';
import { env } from './config/env';
import { logger } from './lib/logger';
import { metricsMiddleware, registry } from './lib/metrics';
import { prisma } from './lib/prisma';
import { requireAuth } from './middleware/auth';
import { requireEntityAccess } from './middleware/entityAccess';
import { errorHandler, notFoundHandler } from './middleware/error';
import { accountsRouter } from './modules/accounts/accounts.routes';
import { authRouter } from './modules/auth/auth.routes';
import { categoriesRouter } from './modules/categories/categories.routes';
import { consolidatedRouter, entityDashboardRouter } from './modules/dashboard/dashboard.routes';
import { entitiesRouter } from './modules/entities/entities.routes';
import { cardsRouter } from './modules/cards/cards.routes';
import { contactsRouter, payablesRouter } from './modules/contacts/contacts.routes';
import { debtsRouter } from './modules/debts/debts.routes';
import { gamificationRouter, marketRouter } from './modules/market/market.routes';
import { piggyRouter } from './modules/piggy/piggy.routes';
import { receiptsRouter } from './modules/receipts/receipts.routes';
import { assistantRouter, entityAssistantRouter, notificationsRouter } from './modules/assistant/assistant.routes';
import { consolidatedReportsRouter, entityReportsRouter, reportTypesRouter } from './modules/reports/reports.routes';
import { investmentsRouter } from './modules/investments/investments.routes';
import { consolidatedPatrimonyRouter, patrimonyRouter } from './modules/patrimony/patrimony.routes';
import { consolidatedPlanningRouter, planningRouter } from './modules/planning/planning.routes';
import { recurringRouter } from './modules/recurring/recurring.routes';
import { transactionsRouter } from './modules/transactions/transactions.routes';
import { transfersRouter } from './modules/transfers/transfers.routes';

const LOCALHOST = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

const startedAt = new Date().toISOString();

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);
  app.use(helmet());
  app.use(
    cors({
      origin(origin, cb) {
        // Apps nativos não enviam Origin. Flutter Web em desenvolvimento usa portas variáveis em localhost.
        if (!origin || env.corsOrigins.includes(origin) || (env.NODE_ENV !== 'production' && LOCALHOST.test(origin))) {
          return cb(null, true);
        }
        cb(null, false);
      },
      allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key'],
      exposedHeaders: ['Idempotent-Replayed'],
    }),
  );
  app.use(express.json({ limit: '1mb' }));
  app.use(metricsMiddleware);
  if (env.NODE_ENV !== 'test') app.use(pinoHttp({ logger }));

  app.get('/health', async (_req, res) => {
    try {
      await prisma.$queryRaw`SELECT 1`;
      res.json({ status: 'ok', db: 'ok' });
    } catch {
      res.status(503).json({ status: 'degraded', db: 'unavailable' });
    }
  });
  app.get('/version', (_req, res) => {
    res.json({ name: 'hoink-api', version: env.APP_VERSION, commit: env.GIT_SHA, env: env.NODE_ENV, startedAt });
  });
  // Métricas Prometheus. Se METRICS_TOKEN estiver definido, exige "Authorization: Bearer <token>".
  app.get('/metrics', async (req, res) => {
    if (env.METRICS_TOKEN && req.get('authorization') !== `Bearer ${env.METRICS_TOKEN}`) {
      res.status(401).end();
      return;
    }
    res.set('Content-Type', registry.contentType);
    res.send(await registry.metrics());
  });

  const api = Router();
  api.use('/auth', authRouter);
  api.use(requireAuth);
  api.use('/entities', entitiesRouter);
  api.use('/transfers', transfersRouter);
  api.use('/consolidated', consolidatedRouter);
  api.use('/consolidated/planning', consolidatedPlanningRouter);
  api.use('/consolidated/patrimony', consolidatedPatrimonyRouter);
  api.use('/consolidated/reports', consolidatedReportsRouter);
  api.use('/reports', reportTypesRouter);
  api.use('/market-rates', marketRouter);
  api.use('/assistant', assistantRouter);
  api.use('/notifications', notificationsRouter);
  api.use('/gamification', gamificationRouter);

  const entity = Router({ mergeParams: true });
  entity.use(requireEntityAccess);
  entity.use('/accounts', accountsRouter);
  entity.use('/categories', categoriesRouter);
  entity.use('/transactions', transactionsRouter);
  entity.use('/dashboard', entityDashboardRouter);
  entity.use('/recurring', recurringRouter);
  entity.use('/contacts', contactsRouter);
  entity.use('/payables', payablesRouter);
  entity.use('/cards', cardsRouter);
  entity.use('/debts', debtsRouter);
  entity.use('/planning', planningRouter);
  entity.use('/piggy-banks', piggyRouter);
  entity.use('/receipts', receiptsRouter);
  entity.use('/reports', entityReportsRouter);
  entity.use('/assistant', entityAssistantRouter);
  entity.use('/investments', investmentsRouter);
  entity.use('/patrimony', patrimonyRouter);
  api.use('/entities/:entityId', entity);

  app.use('/api', api);
  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
