import { createApp } from './app';
import { env } from './config/env';
import { logger } from './lib/logger';
import { prisma } from './lib/prisma';
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
