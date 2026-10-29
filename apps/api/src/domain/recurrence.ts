/**
 * Motor de datas das recorrências (funções puras, sem fuso: datas civis AAAA-MM-DD).
 *
 * As datas são sempre calculadas a partir da data inicial (início + n × intervalo), nunca
 * somando ao resultado anterior. Assim uma conta todo dia 31 cai em 30/04, 28/02 e volta a 31/05,
 * sem "escorregar" para o dia 28 para sempre.
 */
export type Frequency = 'DAILY' | 'WEEKLY' | 'BIWEEKLY' | 'MONTHLY' | 'YEARLY' | 'CUSTOM';
export type IntervalUnit = 'DAY' | 'WEEK' | 'MONTH' | 'YEAR';

export interface Schedule {
  frequency: Frequency;
  /** Intervalo da frequência personalizada (ex.: a cada 3 meses). Ignorado nas demais. */
  interval?: number;
  unit?: IntervalUnit;
  startDate: string;
  endDate?: string | null;
  /** Número máximo de ocorrências desde o início (inclusive as já passadas). */
  maxOccurrences?: number | null;
}

function step(s: Schedule): { unit: IntervalUnit; every: number } {
  switch (s.frequency) {
    case 'DAILY':
      return { unit: 'DAY', every: 1 };
    case 'WEEKLY':
      return { unit: 'WEEK', every: 1 };
    case 'BIWEEKLY':
      return { unit: 'WEEK', every: 2 };
    case 'MONTHLY':
      return { unit: 'MONTH', every: 1 };
    case 'YEARLY':
      return { unit: 'YEAR', every: 1 };
    case 'CUSTOM': {
      const every = s.interval ?? 1;
      if (!Number.isInteger(every) || every < 1) throw new Error('Intervalo personalizado inválido');
      return { unit: s.unit ?? 'MONTH', every };
    }
  }
}

const pad = (n: number) => String(n).padStart(2, '0');
const toISO = (d: Date) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
const parse = (iso: string) => {
  const [y, m, d] = iso.split('-').map(Number) as [number, number, number];
  return { y, m, d };
};

function addMonthsClamped(iso: string, months: number): string {
  const { y, m, d } = parse(iso);
  const target = new Date(Date.UTC(y, m - 1 + months, 1));
  const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  target.setUTCDate(Math.min(d, lastDay));
  return toISO(target);
}

function addDays(iso: string, days: number): string {
  const { y, m, d } = parse(iso);
  return toISO(new Date(Date.UTC(y, m - 1, d + days)));
}

/** n-ésima ocorrência (0 = data inicial). */
export function nthOccurrence(s: Schedule, n: number): string {
  const { unit, every } = step(s);
  switch (unit) {
    case 'DAY':
      return addDays(s.startDate, n * every);
    case 'WEEK':
      return addDays(s.startDate, n * every * 7);
    case 'MONTH':
      return addMonthsClamped(s.startDate, n * every);
    case 'YEAR':
      return addMonthsClamped(s.startDate, n * every * 12);
  }
}

/**
 * Ocorrências dentro de [from, to] (inclusive), respeitando data final e limite de ocorrências.
 * Retorna também o índice de cada uma (posição na série).
 */
export function occurrencesBetween(s: Schedule, from: string, to: string): { index: number; date: string }[] {
  const out: { index: number; date: string }[] = [];
  const limit = s.maxOccurrences ?? Number.POSITIVE_INFINITY;
  // Proteção contra laços enormes (ex.: diária por décadas).
  for (let n = 0; n < limit && n < 50_000; n++) {
    const date = nthOccurrence(s, n);
    if (s.endDate && date > s.endDate) break;
    if (date > to) break;
    if (date >= from) out.push({ index: n, date });
  }
  return out;
}

/** Próxima ocorrência a partir de uma data (inclusive), ou null se a série terminou. */
export function nextOccurrence(s: Schedule, from: string): string | null {
  const limit = s.maxOccurrences ?? Number.POSITIVE_INFINITY;
  for (let n = 0; n < limit && n < 50_000; n++) {
    const date = nthOccurrence(s, n);
    if (s.endDate && date > s.endDate) return null;
    if (date >= from) return date;
  }
  return null;
}

export function dayBefore(iso: string): string {
  return addDays(iso, -1);
}

export function addDaysISO(iso: string, days: number): string {
  return addDays(iso, days);
}
