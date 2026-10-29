import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().default(3333),
  DATABASE_URL: z.string().url(),
  /** Origens permitidas para CORS (Flutter Web), separadas por vírgula. Em desenvolvimento, qualquer localhost é aceito. */
  CORS_ORIGINS: z.string().default(''),
  SESSION_TTL_DAYS: z.coerce.number().int().min(1).max(90).default(30),
  /** Fuso usado para determinar "hoje" (vencimentos, atrasos, mês corrente). */
  APP_TIMEZONE: z.string().default('America/Sao_Paulo'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  APP_VERSION: z.string().default('0.1.0'),
  /** Commit publicado (injetado no build da imagem) — identifica a versão em produção. */
  GIT_SHA: z.string().default('dev'),
  /** Token opcional para proteger GET /metrics. */
  METRICS_TOKEN: z.string().optional(),
  /** Tentativas de autenticação por IP a cada 15 minutos. */
  AUTH_RATE_LIMIT: z.coerce.number().int().min(1).default(20),
  /** Busca CDI, Selic e IPCA no SGS do Banco Central (API pública). Desligue para operar só com taxas manuais. */
  MARKET_DATA_SYNC: z.enum(['true', 'false']).default('true'),
  /** Token de administração: permite lançar índices manualmente (valem para todos os usuários). Sem ele, ninguém lança. */
  ADMIN_TOKEN: z.string().min(16).optional(),
});

const parsed = envSchema.safeParse(process.env);
if (!parsed.success) {
  console.error('Variáveis de ambiente inválidas:', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = {
  ...parsed.data,
  corsOrigins: parsed.data.CORS_ORIGINS.split(',')
    .map((o) => o.trim())
    .filter(Boolean),
};
