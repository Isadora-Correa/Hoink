/**
 * Cronogramas de amortização (funções puras, valores em centavos inteiros).
 *
 *  - PRICE: parcela constante; os juros caem e a amortização cresce a cada mês.
 *  - SAC: amortização constante; os juros e a parcela caem a cada mês.
 *
 * Os juros de cada parcela são arredondados ao centavo e a última parcela amortiza exatamente
 * o saldo restante, então a soma do principal é sempre igual ao valor financiado.
 */
import { nthOccurrence } from './recurrence';

export type AmortizationSystem = 'PRICE' | 'SAC';

export interface ScheduleInput {
  principalCents: number;
  /** Taxa mensal em partes por milhão (1,99% a.m. = 19900). */
  monthlyRatePpm: number;
  installments: number;
  system: AmortizationSystem;
  firstDueDate: string;
  /** Encargos fixos por parcela (seguro, tarifa). */
  feesCents?: number;
  /** Número da primeira parcela gerada (recálculos continuam a numeração). */
  startNumber?: number;
}

export interface ScheduleRow {
  number: number;
  dueDate: string;
  principalCents: number;
  interestCents: number;
  feesCents: number;
  totalCents: number;
  balanceAfterCents: number;
}

const rate = (ppm: number) => ppm / 1_000_000;

/** Parcela (principal + juros) do sistema PRICE, sem arredondar. */
export function pricePayment(principalCents: number, ppm: number, n: number): number {
  const i = rate(ppm);
  if (i === 0) return principalCents / n;
  return (principalCents * i) / (1 - Math.pow(1 + i, -n));
}

export function amortizationSchedule(input: ScheduleInput): ScheduleRow[] {
  const { principalCents, monthlyRatePpm, installments: n, system } = input;
  if (!Number.isInteger(n) || n < 1) throw new Error('Número de parcelas inválido');
  if (principalCents <= 0) throw new Error('Valor financiado deve ser positivo');
  const i = rate(monthlyRatePpm);
  const fees = input.feesCents ?? 0;
  const start = input.startNumber ?? 1;
  const pmt = Math.round(pricePayment(principalCents, monthlyRatePpm, n));
  const sacAmortization = Math.round(principalCents / n);
  const rows: ScheduleRow[] = [];
  let balance = principalCents;
  for (let k = 0; k < n; k++) {
    const interest = Math.round(balance * i);
    const last = k === n - 1;
    let principal = system === 'PRICE' ? pmt - interest : sacAmortization;
    if (last || principal > balance) principal = balance;
    principal = Math.max(0, principal);
    balance -= principal;
    rows.push({
      number: start + k,
      dueDate: nthOccurrence({ frequency: 'MONTHLY', startDate: input.firstDueDate }, k),
      principalCents: principal,
      interestCents: interest,
      feesCents: fees,
      totalCents: principal + interest + fees,
      balanceAfterCents: balance,
    });
  }
  return rows;
}

/**
 * Quantas parcelas restam para quitar `principalCents` mantendo a parcela (PRICE) ou a
 * amortização (SAC) atual — usado na amortização extraordinária com redução de prazo.
 */
export function remainingTerm(
  principalCents: number,
  ppm: number,
  system: AmortizationSystem,
  current: { paymentCents: number; amortizationCents: number },
): number {
  if (principalCents <= 0) return 0;
  if (system === 'SAC') return Math.max(1, Math.ceil(principalCents / Math.max(1, current.amortizationCents)));
  const i = rate(ppm);
  if (i === 0) return Math.max(1, Math.ceil(principalCents / current.paymentCents));
  const x = 1 - (principalCents * i) / current.paymentCents;
  if (x <= 0) throw new Error('A parcela atual não cobre os juros do saldo');
  return Math.max(1, Math.ceil(-Math.log(x) / Math.log(1 + i) - 1e-9));
}

function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);
}

export interface OpenInstallment {
  dueDate: string;
  principalCents: number;
  interestCents: number;
  feesCents: number;
}

export interface PayoffQuote {
  date: string;
  /** Parcelas vencidas e não pagas, pelo valor integral (sem multa/mora, que dependem do contrato). */
  overdueCents: number;
  /** Saldo devedor (principal) das parcelas a vencer. */
  outstandingPrincipalCents: number;
  /** Juros proporcionais desde o último vencimento (ou da contratação) até a data da quitação. */
  accruedInterestCents: number;
  payoffCents: number;
  /** Quanto custariam as parcelas restantes se pagas normalmente. */
  remainingTotalCents: number;
  /** Economia de juros e encargos futuros ao quitar (CDC, art. 52, §2º). */
  savingsCents: number;
}

/**
 * Simulação de quitação antecipada: parcelas vencidas pelo valor integral + principal das
 * parcelas a vencer + juros pro rata (capitalização composta, mês de 30 dias) desde a última
 * data de referência. Juros e encargos futuros não são cobrados.
 */
export function payoffQuote(
  open: OpenInstallment[],
  ppm: number,
  date: string,
  lastReferenceDate: string,
): PayoffQuote {
  const total = (r: OpenInstallment) => r.principalCents + r.interestCents + r.feesCents;
  const overdue = open.filter((r) => r.dueDate < date);
  const future = open.filter((r) => r.dueDate >= date);
  const outstanding = future.reduce((s, r) => s + r.principalCents, 0);
  const days = Math.max(0, daysBetween(lastReferenceDate, date));
  const accrued = outstanding > 0 ? Math.round(outstanding * (Math.pow(1 + rate(ppm), days / 30) - 1)) : 0;
  const overdueCents = overdue.reduce((s, r) => s + total(r), 0);
  const payoffCents = overdueCents + outstanding + accrued;
  const remainingTotalCents = open.reduce((s, r) => s + total(r), 0);
  return {
    date,
    overdueCents,
    outstandingPrincipalCents: outstanding,
    accruedInterestCents: accrued,
    payoffCents,
    remainingTotalCents,
    savingsCents: Math.max(0, remainingTotalCents - payoffCents),
  };
}
