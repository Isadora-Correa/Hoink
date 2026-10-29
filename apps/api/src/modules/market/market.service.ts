import type { MarketIndex } from '@prisma/client';
import { Prisma } from '@prisma/client';
import { env } from '../../config/env';
import type { RateSeries } from '../../domain/yields';
import { formatDate, parseDate, todayISO } from '../../lib/dates';
import { unprocessable } from '../../lib/errors';
import { logger } from '../../lib/logger';
import { prisma } from '../../lib/prisma';

/** Séries do SGS (Banco Central): 12 = CDI diário, 11 = Selic diária, 433 = IPCA mensal. */
const SGS: Record<MarketIndex, number> = { CDI: 12, SELIC: 11, IPCA: 433 };
/** Histórico inicial buscado na primeira sincronização. */
const BACKFILL_DAYS = 3 * 365;
/** Uma taxa é considerada desatualizada se o último dado tem mais de N dias (feriados e fins de semana incluídos). */
// O IPCA de um mês só sai por volta do dia 10 do mês seguinte: até ~75 dias é normal.
const STALE_DAYS: Record<MarketIndex, number> = { CDI: 5, SELIC: 5, IPCA: 75 };

const br = (iso: string) => iso.split('-').reverse().join('/');
const fromBr = (d: string) => d.split('/').reverse().join('-');
const addDays = (iso: string, n: number) => formatDate(new Date(parseDate(iso).getTime() + n * 86_400_000));

async function fetchSgs(index: MarketIndex, from: string, to: string): Promise<{ date: string; ratePct: number }[]> {
  const url = `https://api.bcb.gov.br/dados/serie/bcdata.sgs.${SGS[index]}/dados?formato=json&dataInicial=${br(from)}&dataFinal=${br(to)}`;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': 'hoink/1.0', Accept: 'application/json' }, signal: AbortSignal.timeout(15_000) });
      const text = await res.text();
      if (res.ok && text.trimStart().startsWith('[')) {
        const rows = JSON.parse(text) as { data: string; valor: string }[];
        return rows.map((r) => ({ date: fromBr(r.data), ratePct: Number(r.valor) })).filter((r) => Number.isFinite(r.ratePct));
      }
      // Sem dados no período a API responde 404/HTML: não é erro de rede.
      if (res.status === 404) return [];
    } catch (err) {
      logger.warn({ err, index, attempt }, 'SGS indisponível');
    }
    await new Promise((r) => setTimeout(r, 1500 * attempt));
  }
  throw new Error(`Não foi possível obter a série ${index} do Banco Central`);
}

/** Busca no SGS os dados posteriores ao último já guardado. Falhas não derrubam nada: as telas mostram a data do último dado. */
export async function syncMarketRates(indexes: MarketIndex[] = ['CDI', 'SELIC', 'IPCA']) {
  if (env.MARKET_DATA_SYNC !== 'true') return { skipped: true as const };
  const today = todayISO();
  const result: Record<string, number | string> = {};
  for (const index of indexes) {
    try {
      const last = await prisma.marketRate.findFirst({ where: { index, source: 'BCB' }, orderBy: { date: 'desc' } });
      const from = last ? addDays(formatDate(last.date), 1) : addDays(today, -BACKFILL_DAYS);
      if (from > today) {
        result[index] = 0;
        continue;
      }
      const rows = await fetchSgs(index, from, today);
      const created = await prisma.marketRate.createMany({
        skipDuplicates: true,
        data: rows.map((r) => ({ index, date: parseDate(index === 'IPCA' ? `${r.date.slice(0, 7)}-01` : r.date), ratePct: new Prisma.Decimal(r.ratePct), source: 'BCB' as const })),
      });
      result[index] = created.count;
    } catch (err) {
      logger.warn({ err, index }, 'Falha ao sincronizar índice');
      result[index] = 'erro';
    }
  }
  logger.info({ result }, 'Índices de mercado sincronizados');
  return { skipped: false as const, result };
}

/** Séries para os motores de rendimento. IPCA vem como variação mensal por AAAA-MM. */
export async function loadSeries(index: MarketIndex, from: string, to: string): Promise<RateSeries> {
  const rows = await prisma.marketRate.findMany({
    where: { index, date: { gte: parseDate(index === 'IPCA' ? `${from.slice(0, 7)}-01` : addDays(from, -10)), lte: parseDate(to) } },
    orderBy: { date: 'asc' },
  });
  if (index === 'IPCA') {
    return { daily: new Map(), monthly: new Map(rows.map((r) => [formatDate(r.date).slice(0, 7), Number(r.ratePct)])) };
  }
  return { daily: new Map(rows.map((r) => [formatDate(r.date), Number(r.ratePct)])) };
}

export async function marketStatus() {
  const today = todayISO();
  const out = [];
  for (const index of ['CDI', 'SELIC', 'IPCA'] as const) {
    const last = await prisma.marketRate.findFirst({ where: { index }, orderBy: { date: 'desc' } });
    const lastDate = last ? formatDate(last.date) : null;
    const age = lastDate ? Math.round((parseDate(today).getTime() - parseDate(lastDate).getTime()) / 86_400_000) : null;
    out.push({
      index,
      lastDate,
      ratePct: last ? Number(last.ratePct) : null,
      /** CDI/Selic: taxa anual equivalente (base 252). */
      annualPct: last && index !== 'IPCA' ? (Math.pow(1 + Number(last.ratePct) / 100, 252) - 1) * 100 : null,
      source: last?.source ?? null,
      stale: age === null || age > STALE_DAYS[index],
    });
  }
  return out;
}

/**
 * Taxa informada manualmente quando o Banco Central está indisponível. CDI/Selic aceitam a taxa
 * ANUAL (% a.a.), convertida para diária; IPCA, a variação do mês (%).
 */
export async function setManualRate(input: { index: MarketIndex; date: string; annualPct?: number; monthlyPct?: number }) {
  const ratePct =
    input.index === 'IPCA' ? input.monthlyPct! : (Math.pow(1 + input.annualPct! / 100, 1 / 252) - 1) * 100;
  const date = input.index === 'IPCA' ? `${input.date.slice(0, 7)}-01` : input.date;
  const existing = await prisma.marketRate.findUnique({ where: { index_date: { index: input.index, date: parseDate(date) } } });
  if (existing?.source === 'BCB') throw unprocessable('OFFICIAL_RATE', 'Já existe o dado oficial do Banco Central para esta data');
  await prisma.marketRate.upsert({
    where: { index_date: { index: input.index, date: parseDate(date) } },
    create: { index: input.index, date: parseDate(date), ratePct: new Prisma.Decimal(ratePct.toFixed(8)), source: 'MANUAL' },
    update: { ratePct: new Prisma.Decimal(ratePct.toFixed(8)), source: 'MANUAL' },
  });
  return marketStatus();
}

/** Taxa anual corrente (estimativa para simulações): % a.a. do índice × percentual, ou taxa prefixada. */
export async function currentAnnualPct(kind: 'CDI_PERCENT' | 'SELIC_PERCENT' | 'PREFIXED' | 'IPCA_PLUS', rateBps: number) {
  if (kind === 'PREFIXED') return rateBps / 100;
  const status = await marketStatus();
  if (kind === 'IPCA_PLUS') {
    const ipca = status.find((s) => s.index === 'IPCA');
    if (ipca?.ratePct === null || ipca?.ratePct === undefined) return null;
    return ((1 + ipca.ratePct / 100) ** 12 * (1 + rateBps / 10000) - 1) * 100;
  }
  const s = status.find((x) => x.index === (kind === 'CDI_PERCENT' ? 'CDI' : 'SELIC'));
  if (s?.ratePct === null || s?.ratePct === undefined) return null;
  return ((1 + (s.ratePct / 100) * (rateBps / 10000)) ** 252 - 1) * 100;
}
