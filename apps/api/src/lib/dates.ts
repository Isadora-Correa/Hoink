import { env } from '../config/env';

/** Data civil (AAAA-MM-DD) → Date em UTC meia-noite, formato usado pelo Prisma para colunas DATE. */
export function parseDate(iso: string): Date {
  return new Date(`${iso}T00:00:00.000Z`);
}

export function formatDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/** "Hoje" no fuso da aplicação, como data civil. */
export function todayISO(now: Date = new Date(), timeZone = env.APP_TIMEZONE): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

/** Intervalo [início, fim] do mês (AAAA-MM). */
export function monthRange(month: string): { from: string; to: string } {
  const [y, m] = month.split('-').map(Number) as [number, number];
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const mm = String(m).padStart(2, '0');
  return { from: `${y}-${mm}-01`, to: `${y}-${mm}-${String(last).padStart(2, '0')}` };
}

export function shiftMonth(month: string, delta: number): string {
  const [y, m] = month.split('-').map(Number) as [number, number];
  const d = new Date(Date.UTC(y, m - 1 + delta, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}
