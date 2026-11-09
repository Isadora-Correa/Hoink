import { Router } from 'express';
import { env } from '../../config/env';
import { logger } from '../../lib/logger';
import { syncMarketRates } from '../market/market.service';
import { generateAll } from '../recurring/recurring.service';

/**
 * Tarefas diárias para hospedagens sem processo contínuo (Vercel): gera as ocorrências de recorrências e
 * atualiza CDI, Selic e IPCA. A Vercel chama esta rota pelo cron do vercel.json enviando
 * "Authorization: Bearer <CRON_SECRET>". Sem CRON_SECRET configurado, a rota fica desligada.
 */
export const cronRouter = Router();

cronRouter.get('/daily', async (req, res) => {
  if (!env.CRON_SECRET || req.get('authorization') !== `Bearer ${env.CRON_SECRET}`) {
    res.status(401).end();
    return;
  }
  const result: Record<string, string> = {};
  try {
    await generateAll();
    result.recurring = 'ok';
  } catch (err) {
    logger.error({ err }, 'Cron: falha ao gerar ocorrências de recorrências');
    result.recurring = 'error';
  }
  try {
    await syncMarketRates();
    result.market = 'ok';
  } catch (err) {
    logger.warn({ err }, 'Cron: sincronização de índices falhou');
    result.market = 'error';
  }
  res.json(result);
});
