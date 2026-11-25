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

async function fetchSgs(
  index: MarketIndex,
  from: string,
  to: string,
  attempts = 3,
): Promise<{ date: string; ratePct: number }[]> {
  const url = `https://api.bcb.gov.br/dados/serie/bcdata.sgs.${SGS[index]}/dados?formato=json&dataInicial=${br(from)}&dataFinal=${br(to)}`;
  for (let attempt = 1; attempt <= attempts; attempt++) {
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
    if (attempt < attempts) await new Promise((r) => setTimeout(r, 1500 * attempt));
  }
  throw new Error(`Não foi possível obter a série ${index} do Banco Central`);
}

/** Fontes de reserva: o dado oficial do SGS as substitui quando volta a responder. */
const FALLBACK_SOURCES = ['BRASILAPI', 'IBGE'] as const;
/** Sem nenhum dado guardado, a reserva de CDI/Selic preenche só os últimos dias (não é histórico oficial). */
const FALLBACK_MAX_DAYS = 31;

const isWeekday = (iso: string) => {
  const dow = parseDate(iso).getUTCDay();
  return dow !== 0 && dow !== 6;
};

/**
 * Reserva de CDI/Selic: taxa anual vigente na BrasilAPI (que repassa o Banco Central),
 * convertida para diária (base 252), como o SGS entrega.
 */
async function fetchBrasilApiDailyPct(index: 'CDI' | 'SELIC'): Promise<number> {
  const res = await fetch('https://brasilapi.com.br/api/taxas/v1', {
    headers: { 'User-Agent': 'hoink/1.0', Accept: 'application/json' },
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`BrasilAPI respondeu ${res.status}`);
  const rows = (await res.json()) as { nome: string; valor: number }[];
  const annual = rows.find((r) => r.nome?.toUpperCase() === index)?.valor;
  if (typeof annual !== 'number' || !Number.isFinite(annual) || annual <= 0) throw new Error(`BrasilAPI sem a taxa ${index}`);
  return (Math.pow(1 + annual / 100, 1 / 252) - 1) * 100;
}

/** Reserva do IPCA: variação mensal oficial no SIDRA do IBGE (tabela 1737, variável 63). */
async function fetchIbgeIpca(months: number): Promise<{ date: string; ratePct: number }[]> {
  const url = `https://apisidra.ibge.gov.br/values/t/1737/n1/all/v/63/p/last%20${months}`;
  const res = await fetch(url, { headers: { 'User-Agent': 'hoink/1.0', Accept: 'application/json' }, signal: AbortSignal.timeout(15_000) });
  if (!res.ok) throw new Error(`IBGE respondeu ${res.status}`);
  const rows = (await res.json()) as { V: string; D3C: string }[];
  // A primeira linha é o cabeçalho; meses sem divulgação vêm como "..." ou "-".
  return rows
    .slice(1)
    .map((r) => ({ date: `${r.D3C.slice(0, 4)}-${r.D3C.slice(4, 6)}-01`, ratePct: Number(r.V) }))
    .filter((r) => /^\d{4}-\d{2}-01$/.test(r.date) && Number.isFinite(r.ratePct));
}

/** Quando o SGS falha: grava o índice pela fonte de reserva sem sobrescrever dados oficiais ou manuais. */
async function syncFromFallback(index: MarketIndex, today: string): Promise<number> {
  const last = await prisma.marketRate.findFirst({ where: { index }, orderBy: { date: 'desc' } });
  if (index === 'IPCA') {
    const lastMonth = last ? formatDate(last.date).slice(0, 7) : null;
    const months = lastMonth ? Math.max(1, Math.min(36, monthsBetween(lastMonth, today.slice(0, 7)))) : 36;
    const rows = (await fetchIbgeIpca(months)).filter((r) => !lastMonth || r.date.slice(0, 7) > lastMonth);
    const created = await prisma.marketRate.createMany({
      skipDuplicates: true,
      data: rows.map((r) => ({ index, date: parseDate(r.date), ratePct: new Prisma.Decimal(r.ratePct), source: 'IBGE' as const })),
    });
    return created.count;
  }
  const dailyPct = await fetchBrasilApiDailyPct(index);
  const floor = addDays(today, -FALLBACK_MAX_DAYS);
  let from = last ? addDays(formatDate(last.date), 1) : floor;
  if (from < floor) from = floor;
  // Mesma convenção do SGS: só dias úteis entram na série (feriados não são conhecidos aqui).
  const days: string[] = [];
  for (let d = from; d <= today; d = addDays(d, 1)) if (isWeekday(d)) days.push(d);
  const created = await prisma.marketRate.createMany({
    skipDuplicates: true,
    data: days.map((d) => ({ index, date: parseDate(d), ratePct: new Prisma.Decimal(dailyPct.toFixed(8)), source: 'BRASILAPI' as const })),
  });
  return created.count;
}

const monthsBetween = (fromMonth: string, toMonth: string) => {
  const [fy, fm] = fromMonth.split('-').map(Number) as [number, number];
  const [ty, tm] = toMonth.split('-').map(Number) as [number, number];
  return (ty - fy) * 12 + (tm - fm);
};

/**
 * Busca no SGS os dados posteriores ao último já guardado. Se o SGS falhar, usa a fonte de reserva
 * (BrasilAPI para CDI/Selic, IBGE para o IPCA). Falhas não derrubam nada: as telas mostram a data do último dado.
 */
export async function syncMarketRates(
  indexes: MarketIndex[] = ['CDI', 'SELIC', 'IPCA'],
  { sgsAttempts = 3 }: { sgsAttempts?: number } = {},
) {
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
      const rows = await fetchSgs(index, from, today, sgsAttempts);
      const data = rows.map((r) => ({
        index,
        date: parseDate(index === 'IPCA' ? `${r.date.slice(0, 7)}-01` : r.date),
        ratePct: new Prisma.Decimal(r.ratePct),
        source: 'BCB' as const,
      }));
      // O oficial substitui o que a reserva gravou nas mesmas datas.
      const created = await prisma.$transaction(async (tx) => {
        if (data.length > 0) {
          await tx.marketRate.deleteMany({
            where: { index, source: { in: [...FALLBACK_SOURCES] }, date: { in: data.map((d) => d.date) } },
          });
        }
        return tx.marketRate.createMany({ skipDuplicates: true, data });
      });
      result[index] = created.count;
    } catch (err) {
      logger.warn({ err, index }, 'Falha ao sincronizar índice no Banco Central; tentando a fonte de reserva');
      try {
        const count = await syncFromFallback(index, today);
        result[index] = `reserva:${count}`;
      } catch (fallbackErr) {
        logger.warn({ err: fallbackErr, index }, 'Fonte de reserva também indisponível');
        result[index] = 'erro';
      }
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
    // IPCA acumulado nos últimos 12 meses divulgados (um mês isolado distorce a projeção anual).
    const last12 = await prisma.marketRate.findMany({ where: { index: 'IPCA' }, orderBy: { date: 'desc' }, take: 12 });
    if (last12.length === 0) return null;
    const accumulated = last12.reduce((f, r) => f * (1 + Number(r.ratePct) / 100), 1);
    const annualIpca = last12.length === 12 ? accumulated : accumulated ** (12 / last12.length);
    return (annualIpca * (1 + rateBps / 10000) - 1) * 100;
  }
  const s = status.find((x) => x.index === (kind === 'CDI_PERCENT' ? 'CDI' : 'SELIC'));
  if (s?.ratePct === null || s?.ratePct === undefined) return null;
  return ((1 + (s.ratePct / 100) * (rateBps / 10000)) ** 252 - 1) * 100;
}

/** Intervalo mínimo entre buscas sob demanda (por instância da API). */
const ON_DEMAND_INTERVAL_MS = 10 * 60 * 1000;
/** Quanto a tela espera pela busca antes de responder com o que já tem. */
const ON_DEMAND_WAIT_MS = 8_000;
let lastOnDemandSync = 0;

/** Só para testes: libera a próxima busca sob demanda. */
export function resetOnDemandSync() {
  lastOnDemandSync = 0;
}

/**
 * Na Vercel a API não fica ligada: os índices dependiam só do cron diário. Quando alguém abre uma tela
 * com índice desatualizado (ou sem dado), busca na hora — no máximo a cada 10 minutos e sem segurar a
 * resposta mais que alguns segundos (uma tentativa no Banco Central e já vai para a fonte de reserva).
 */
export async function refreshStaleRates() {
  if (env.MARKET_DATA_SYNC !== 'true') return;
  if (Date.now() - lastOnDemandSync < ON_DEMAND_INTERVAL_MS) return;
  const stale = (await marketStatus()).filter((s) => s.stale).map((s) => s.index);
  if (stale.length === 0) return;
  lastOnDemandSync = Date.now();
  const sync = syncMarketRates(stale, { sgsAttempts: 1 }).catch((err) =>
    logger.warn({ err }, 'Busca sob demanda dos índices falhou'),
  );
  await Promise.race([sync, new Promise((r) => setTimeout(r, ON_DEMAND_WAIT_MS))]);
}
