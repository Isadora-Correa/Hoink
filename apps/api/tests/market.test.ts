import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { env } from '../src/config/env';
import { formatDate, todayISO } from '../src/lib/dates';
import { prisma } from '../src/lib/prisma';
import { marketStatus, syncMarketRates } from '../src/modules/market/market.service';
import { resetDb } from './helpers';

type Handler = (url: string) => Response | Promise<Response>;

/** Substitui o fetch global: cada fonte responde conforme o cenário do teste. */
function mockFetch(handler: Handler) {
  vi.stubGlobal('fetch', vi.fn(async (input: string | URL) => handler(String(input))));
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
// O SGS bloqueado costuma devolver uma página HTML com status 200, não um erro de rede.
const sgsBlocked = () => new Response('<html>Access Denied</html>', { status: 200 });
const brasilApi = () => json([{ nome: 'Selic', valor: 15 }, { nome: 'CDI', valor: 14.9 }, { nome: 'IPCA', valor: 4.6 }]);
const sidra = () =>
  json([
    { V: 'Valor', D3C: 'Mês (Código)' },
    { V: '0.48', D3C: '202608' },
    { V: '0.82', D3C: '202609' },
  ]);

const daily = (annual: number) => (Math.pow(1 + annual / 100, 1 / 252) - 1) * 100;

beforeEach(async () => {
  await resetDb();
  await prisma.marketRate.deleteMany();
  env.MARKET_DATA_SYNC = 'true';
  vi.useFakeTimers({ shouldAdvanceTime: true, toFake: ['setTimeout'] });
});

afterEach(() => {
  env.MARKET_DATA_SYNC = 'false';
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

/** As novas tentativas do SGS esperam alguns segundos; avança o relógio para o teste não demorar. */
async function sync() {
  let done = false;
  const p = syncMarketRates().finally(() => {
    done = true;
  });
  while (!done) await vi.advanceTimersByTimeAsync(2_000);
  return p;
}

describe('Índices de mercado — reserva quando o Banco Central falha', () => {
  it('SGS fora do ar: CDI/Selic vêm da BrasilAPI e o IPCA do IBGE, marcados como reserva', async () => {
    mockFetch((url) => {
      if (url.includes('api.bcb.gov.br')) return sgsBlocked();
      if (url.includes('brasilapi.com.br/api/taxas')) return brasilApi();
      if (url.includes('apisidra.ibge.gov.br')) return sidra();
      throw new Error(`URL inesperada: ${url}`);
    });

    const r = await sync();
    expect(r.skipped).toBe(false);

    const status = await marketStatus();
    const cdi = status.find((s) => s.index === 'CDI')!;
    const selic = status.find((s) => s.index === 'SELIC')!;
    const ipca = status.find((s) => s.index === 'IPCA')!;

    expect(cdi.source).toBe('BRASILAPI');
    expect(cdi.annualPct).toBeCloseTo(14.9, 4);
    expect(cdi.stale).toBe(false);
    expect(selic.source).toBe('BRASILAPI');
    expect(selic.annualPct).toBeCloseTo(15, 4);
    expect(ipca).toMatchObject({ source: 'IBGE', lastDate: '2026-09-01', ratePct: 0.82 });

    // Só dias úteis entram na série (mesma convenção do SGS).
    const days = await prisma.marketRate.findMany({ where: { index: 'CDI' } });
    expect(days.length).toBeGreaterThan(0);
    for (const d of days) expect([0, 6]).not.toContain(d.date.getUTCDay());
  });

  it('quando o SGS volta, o dado oficial substitui o da reserva nas mesmas datas', async () => {
    const today = todayISO();
    const lastWeekday = (() => {
      const d = new Date(`${today}T00:00:00Z`);
      while ([0, 6].includes(d.getUTCDay())) d.setUTCDate(d.getUTCDate() - 1);
      return formatDate(d);
    })();
    await prisma.marketRate.create({
      data: { index: 'CDI', date: new Date(`${lastWeekday}T00:00:00Z`), ratePct: daily(14.9).toFixed(8), source: 'BRASILAPI' },
    });

    const br = lastWeekday.split('-').reverse().join('/');
    mockFetch((url) => {
      if (url.includes('bcdata.sgs.12/')) return json([{ data: br, valor: '0.055131' }]);
      if (url.includes('api.bcb.gov.br')) return json([]);
      throw new Error(`URL inesperada: ${url}`);
    });

    await sync();
    const row = await prisma.marketRate.findMany({ where: { index: 'CDI', date: new Date(`${lastWeekday}T00:00:00Z`) } });
    expect(row).toHaveLength(1);
    expect(row[0]).toMatchObject({ source: 'BCB' });
    expect(Number(row[0]!.ratePct)).toBeCloseTo(0.055131, 6);
  });

  it('SGS e reservas fora do ar: não inventa taxa e marca como erro', async () => {
    mockFetch(() => {
      throw new Error('sem rede');
    });
    const r = await sync();
    expect(r).toMatchObject({ skipped: false, result: { CDI: 'erro', SELIC: 'erro', IPCA: 'erro' } });
    expect(await prisma.marketRate.count()).toBe(0);
  });
});
