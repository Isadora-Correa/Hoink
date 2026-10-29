/**
 * Motores de rendimento (funções puras). Nada aqui inventa taxa: as séries vêm do Banco Central
 * ou do usuário. Quando faltam dados, o resultado diz isso (`missingRates`) em vez de supor valores.
 *
 * Convenções:
 *  - CDI/Selic: taxa diária em % (série SGS), aplicada por dia útil; "% do CDI" multiplica a taxa diária.
 *  - Prefixado: taxa anual efetiva, base 252 dias úteis.
 *  - IPCA+: variação mensal do IPCA distribuída nos dias úteis do mês + taxa real anual (base 252).
 */

export type YieldEngine = 'CDI_PERCENT' | 'SELIC_PERCENT' | 'PREFIXED' | 'IPCA_PLUS';

export interface RateSeries {
  /** Taxa diária (%) por data útil, AAAA-MM-DD. Datas ausentes = sem dado. */
  daily: Map<string, number>;
  /** Para IPCA: variação mensal (%) por AAAA-MM. */
  monthly?: Map<string, number>;
}

const addDays = (iso: string, n: number) => {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};

const isWeekday = (iso: string) => {
  const w = new Date(`${iso}T00:00:00Z`).getUTCDay();
  return w !== 0 && w !== 6;
};

/** Taxa anual efetiva → fator diário (base 252). */
export const annualToDailyFactor = (annualPct: number) => Math.pow(1 + annualPct / 100, 1 / 252);

/** Taxa diária (%) → anual efetiva (%), base 252. */
export const dailyToAnnualPct = (dailyPct: number) => (Math.pow(1 + dailyPct / 100, 252) - 1) * 100;

export interface AccrualConfig {
  engine: YieldEngine;
  /** % do índice (11500 = 115% do CDI) ou taxa anual (prefixado / real do IPCA+), em pontos-base. */
  rateBps: number;
  /** Custos anuais (custódia, administração) em pontos-base, descontados diariamente. */
  costsBps?: number;
}

export interface Flow {
  date: string;
  cents: number;
}

export interface AccrualResult {
  balanceCents: number;
  /** Rendimento estimado no período (saldo final − saldo inicial − fluxos). */
  yieldCents: number;
  businessDays: number;
  /** Dias úteis sem taxa conhecida (usou-se a última taxa conhecida). */
  missingRates: number;
  /** Última data com taxa real do índice. */
  ratesUpTo: string | null;
}

/**
 * Evolui um saldo de `from` (exclusive) até `to` (inclusive) aplicando o rendimento a cada dia útil
 * e somando os fluxos (aportes +, resgates −) nas suas datas. Sem nenhuma taxa disponível para
 * índices pós-fixados, retorna null — nunca supõe uma taxa.
 */
export function accrue(
  startCents: number,
  from: string,
  to: string,
  flows: Flow[],
  cfg: AccrualConfig,
  series: RateSeries,
): AccrualResult | null {
  const byDate = new Map<string, number>();
  for (const f of flows) byDate.set(f.date, (byDate.get(f.date) ?? 0) + f.cents);
  const costFactor = cfg.costsBps ? Math.pow(1 - cfg.costsBps / 10000, 1 / 252) : 1;
  const fixedFactor = cfg.engine === 'PREFIXED' ? annualToDailyFactor(cfg.rateBps / 100) : 1;
  const realFactor = cfg.engine === 'IPCA_PLUS' ? annualToDailyFactor(cfg.rateBps / 100) : 1;

  const known = [...series.daily.keys()].sort();
  const needsSeries = cfg.engine === 'CDI_PERCENT' || cfg.engine === 'SELIC_PERCENT';
  if (needsSeries && known.length === 0) return null;
  if (cfg.engine === 'IPCA_PLUS' && (!series.monthly || series.monthly.size === 0)) return null;
  const lastKnown = known.at(-1) ?? null;
  let lastRate = known.length ? series.daily.get(known.filter((d) => d <= from).at(-1) ?? known[0]!)! : 0;
  const monthKeys = series.monthly ? [...series.monthly.keys()].sort() : [];

  let balance = startCents;
  let businessDays = 0;
  let missing = 0;
  let flowsTotal = 0;
  for (let d = addDays(from, 1); d <= to; d = addDays(d, 1)) {
    // Dia útil: presente na série do CDI/Selic; sem série (prefixado/IPCA) ou além dela, dia de semana.
    const inSeries = series.daily.has(d);
    const business = inSeries || ((lastKnown === null || d > lastKnown) && isWeekday(d));
    if (business && balance > 0) {
      businessDays++;
      let factor = costFactor;
      if (needsSeries) {
        if (inSeries) lastRate = series.daily.get(d)!;
        else missing++;
        factor *= 1 + (lastRate / 100) * (cfg.rateBps / 10000);
      } else if (cfg.engine === 'PREFIXED') {
        factor *= fixedFactor;
      } else {
        const month = d.slice(0, 7);
        let ipca = series.monthly!.get(month);
        if (ipca === undefined) {
          missing++;
          ipca = series.monthly!.get(monthKeys.filter((m) => m < month).at(-1) ?? monthKeys[0]!)!;
        }
        factor *= Math.pow(1 + ipca / 100, 1 / 21) * realFactor;
      }
      balance *= factor;
    }
    const f = byDate.get(d);
    if (f) {
      balance += f;
      flowsTotal += f;
    }
  }
  const rounded = Math.round(balance);
  return {
    balanceCents: rounded,
    yieldCents: rounded - startCents - flowsTotal,
    businessDays,
    missingRates: missing,
    ratesUpTo: needsSeries ? lastKnown : cfg.engine === 'IPCA_PLUS' ? (monthKeys.at(-1) ?? null) : null,
  };
}

/** IR regressivo sobre o rendimento conforme o prazo (dias corridos). */
export function regressiveIrRate(days: number): number {
  if (days <= 180) return 0.225;
  if (days <= 360) return 0.2;
  if (days <= 720) return 0.175;
  return 0.15;
}

/** IOF regressivo sobre o rendimento nos primeiros 30 dias (96% no 1º dia … 0% no 30º). */
export function iofRate(days: number): number {
  if (days >= 30) return 0;
  const table = [
    96, 93, 90, 86, 83, 80, 76, 73, 70, 66, 63, 60, 56, 53, 50, 46, 43, 40, 36, 33, 30, 26, 23, 20, 16, 13, 10, 6, 3,
  ];
  return (table[Math.max(0, days - 1)] ?? 0) / 100;
}

export type TaxRule = 'REGRESSIVE' | 'EXEMPT' | 'STOCKS';

export interface Lot {
  date: string;
  cents: number;
}

/**
 * Imposto estimado sobre um ganho, rateado entre os lotes de aporte ainda aplicados (FIFO) pelo
 * prazo de cada um. Ações: 15% sobre o ganho (sem considerar a isenção de vendas até R$ 20 mil/mês).
 */
export function estimateTax(rule: TaxRule, lots: Lot[], gainCents: number, date: string): { iofCents: number; irCents: number } {
  if (gainCents <= 0 || rule === 'EXEMPT') return { iofCents: 0, irCents: 0 };
  if (rule === 'STOCKS') return { iofCents: 0, irCents: Math.round(gainCents * 0.15) };
  const total = lots.reduce((s, l) => s + l.cents, 0);
  if (total <= 0) return { iofCents: 0, irCents: Math.round(gainCents * 0.225) };
  let iof = 0;
  let ir = 0;
  for (const l of lots) {
    const days = Math.round((Date.parse(`${date}T00:00:00Z`) - Date.parse(`${l.date}T00:00:00Z`)) / 86_400_000);
    const part = (gainCents * l.cents) / total;
    const iofPart = part * iofRate(days);
    iof += iofPart;
    ir += (part - iofPart) * regressiveIrRate(days);
  }
  return { iofCents: Math.round(iof), irCents: Math.round(ir) };
}

/** Lotes aplicados após resgates (FIFO): resgates consomem os aportes mais antigos. */
export function openLots(flows: Flow[]): Lot[] {
  const lots: Lot[] = [];
  for (const f of [...flows].sort((a, b) => a.date.localeCompare(b.date))) {
    if (f.cents > 0) lots.push({ date: f.date, cents: f.cents });
    else {
      let out = -f.cents;
      while (out > 0 && lots.length) {
        const first = lots[0]!;
        const used = Math.min(first.cents, out);
        first.cents -= used;
        out -= used;
        if (first.cents === 0) lots.shift();
      }
    }
  }
  return lots;
}

export interface SimulationPoint {
  month: number;
  date: string;
  contributedCents: number;
  balanceCents: number;
}

/**
 * Simulação futura (estimativa): aportes mensais e taxa anual constante. A taxa usada é a última
 * conhecida e NÃO é garantia de rentabilidade futura.
 */
export function simulateGrowth(
  startCents: number,
  monthlyCents: number,
  months: number,
  annualPct: number,
  startDate: string,
): SimulationPoint[] {
  const monthly = Math.pow(1 + annualPct / 100, 1 / 12) - 1;
  const out: SimulationPoint[] = [];
  let balance = startCents;
  let contributed = startCents;
  const [y, m, d] = startDate.split('-').map(Number) as [number, number, number];
  for (let k = 1; k <= months; k++) {
    balance = balance * (1 + monthly) + monthlyCents;
    contributed += monthlyCents;
    const dt = new Date(Date.UTC(y, m - 1 + k, 1));
    const last = new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth() + 1, 0)).getUTCDate();
    dt.setUTCDate(Math.min(d, last));
    out.push({ month: k, date: dt.toISOString().slice(0, 10), contributedCents: contributed, balanceCents: Math.round(balance) });
  }
  return out;
}

/** Meses para atingir a meta com aporte mensal e taxa anual (estimativa); null se não chega em 50 anos. */
export function monthsToGoal(startCents: number, monthlyCents: number, goalCents: number, annualPct: number): number | null {
  if (startCents >= goalCents) return 0;
  const r = Math.pow(1 + annualPct / 100, 1 / 12) - 1;
  let b = startCents;
  for (let k = 1; k <= 600; k++) {
    b = b * (1 + r) + monthlyCents;
    if (b >= goalCents) return k;
  }
  return null;
}
