import { logger } from './logger';
import { businessEvents } from './metrics';

/**
 * Registra um evento importante: log estruturado (pesquisável por `event`) + contador Prometheus.
 * Nunca inclua senhas, tokens ou valores sensíveis em `data`.
 */
export function recordEvent(event: string, data: Record<string, unknown> = {}) {
  businessEvents.inc({ event });
  logger.info({ event, ...data }, event);
}
