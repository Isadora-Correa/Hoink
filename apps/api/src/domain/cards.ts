/**
 * Regras de cartão de crédito (funções puras, datas civis AAAA-MM-DD).
 *
 * Uma fatura é identificada pelo mês do vencimento. Compras feitas a partir do dia do
 * fechamento entram na fatura seguinte ("melhor dia de compra").
 */

const pad = (n: number) => String(n).padStart(2, '0');

function lastDay(y: number, m: number): number {
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** Desloca um mês AAAA-MM. */
export function addMonths(month: string, delta: number): string {
  const [y, m] = month.split('-').map(Number) as [number, number];
  const d = new Date(Date.UTC(y, m - 1 + delta, 1));
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}`;
}

function dayIn(month: string, day: number): string {
  const [y, m] = month.split('-').map(Number) as [number, number];
  return `${month}-${pad(Math.min(day, lastDay(y, m)))}`;
}

export interface InvoiceDates {
  /** Mês da fatura (mês do vencimento), AAAA-MM. */
  month: string;
  closingDate: string;
  dueDate: string;
}

/**
 * Datas da fatura que vence no mês informado. Se o vencimento é depois do fechamento no mês,
 * a fatura fecha no mesmo mês; senão, fecha no mês anterior (ex.: fecha 28, vence 5).
 */
export function invoiceDates(month: string, closingDay: number, dueDay: number): InvoiceDates {
  const closingMonth = dueDay > closingDay ? month : addMonths(month, -1);
  return { month, closingDate: dayIn(closingMonth, closingDay), dueDate: dayIn(month, dueDay) };
}

/** Fatura em que cai uma compra feita na data informada. */
export function invoiceForPurchase(purchaseDate: string, closingDay: number, dueDay: number): InvoiceDates {
  let month = addMonths(purchaseDate.slice(0, 7), -1);
  for (;;) {
    const inv = invoiceDates(month, closingDay, dueDay);
    if (purchaseDate < inv.closingDate) return inv;
    month = addMonths(month, 1);
  }
}

/**
 * Divide o total em parcelas inteiras em centavos; a diferença de arredondamento vai para a
 * primeira parcela (R$ 100,00 em 3x = 33,34 + 33,33 + 33,33). A soma é sempre exatamente o total.
 */
export function splitInstallments(totalCents: number, count: number): number[] {
  if (!Number.isInteger(count) || count < 1) throw new Error('Número de parcelas inválido');
  const base = Math.floor(totalCents / count);
  const out = Array.from({ length: count }, () => base);
  out[0]! += totalCents - base * count;
  return out;
}

export type InvoiceStatus = 'OPEN' | 'CLOSED' | 'PARTIAL' | 'PAID' | 'OVERDUE';

/** Situação da fatura: aberta até o fechamento; depois fechada, paga, parcialmente paga ou atrasada. */
export function invoiceStatus(
  inv: { closingDate: string; dueDate: string; totalCents: number; paidCents: number },
  today: string,
): InvoiceStatus {
  if (today < inv.closingDate) return 'OPEN';
  if (inv.paidCents >= inv.totalCents) return 'PAID';
  if (today > inv.dueDate) return 'OVERDUE';
  return inv.paidCents > 0 ? 'PARTIAL' : 'CLOSED';
}
