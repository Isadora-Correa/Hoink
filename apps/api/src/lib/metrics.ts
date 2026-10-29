import type { NextFunction, Request, Response } from 'express';
import { Counter, Histogram, Registry, collectDefaultMetrics } from 'prom-client';

/** Métricas operacionais no formato Prometheus, expostas em GET /metrics. */
export const registry = new Registry();
registry.setDefaultLabels({ app: 'hoink-api' });
collectDefaultMetrics({ register: registry });

const httpRequests = new Counter({
  name: 'http_requests_total',
  help: 'Requisições HTTP por método, rota e status',
  labelNames: ['method', 'route', 'status'] as const,
  registers: [registry],
});

const httpDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'Latência das requisições HTTP',
  labelNames: ['method', 'route', 'status'] as const,
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [registry],
});

export const appErrors = new Counter({
  name: 'app_errors_total',
  help: 'Erros não tratados (HTTP 5xx)',
  registers: [registry],
});

export const businessEvents = new Counter({
  name: 'hoink_business_events_total',
  help: 'Eventos de negócio (cadastros, logins, lançamentos, transferências)',
  labelNames: ['event'] as const,
  registers: [registry],
});

const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

/** Mede cada requisição pelo padrão da rota (ex.: /api/entities/:id/transactions), evitando alta cardinalidade. */
export function metricsMiddleware(req: Request, res: Response, next: NextFunction) {
  const end = httpDuration.startTimer();
  res.on('finish', () => {
    // Rotas não encontradas viram "unmatched"; identificadores (UUID) viram ":id".
    const route = req.route ? req.originalUrl.split('?')[0]!.replace(UUID_RE, ':id') : 'unmatched';
    const labels = { method: req.method, route, status: String(res.statusCode) };
    httpRequests.inc(labels);
    end(labels);
  });
  next();
}
