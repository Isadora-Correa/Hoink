import { createApp } from './app';
import { env } from './config/env';
import { logger } from './lib/logger';
import { prisma } from './lib/prisma';
import { syncMarketRates } from './modules/market/market.service';
import { generateAll } from './modules/recurring/recurring.service';

/** Agendador simples: materializa ocorrências de recorrências na subida e a cada 6 horas. */
async function runRecurringJob() {
  try {
    await generateAll();
  } catch (err) {
    logger.error({ err }, 'Falha ao gerar ocorrências de recorrências');
  }
}
void runRecurringJob();
const recurringTimer = setInterval(() => void runRecurringJob(), 6 * 60 * 60 * 1000);
recurringTimer.unref();

/** Índices do Banco Central (CDI, Selic, IPCA): na subida e a cada 12 horas. Falhas só geram log. */
void syncMarketRates().catch((err) => logger.warn({ err }, 'Sincronização de índices falhou'));
const marketTimer = setInterval(() => void syncMarketRates().catch(() => undefined), 12 * 60 * 60 * 1000);
marketTimer.unref();

const server = createApp().listen(env.PORT, () => {
  logger.info({ port: env.PORT, version: env.APP_VERSION }, 'hoink. API em execução');
});

async function shutdown(signal: string) {
  logger.info({ signal }, 'Encerrando');
  server.close(async () => {
    await prisma.$disconnect();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
