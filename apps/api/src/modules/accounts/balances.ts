import { Prisma } from '@prisma/client';
import { toCents } from '../../lib/money';
import { type Tx } from '../../lib/prisma';
import { settledAggregate } from '../settlements/settlements';

/** Filtro de lançamentos com parte liquidada (ativos). */
export const settledMovementWhere = {
  deletedAt: null,
  status: { in: ['SETTLED', 'PARTIAL'] },
} satisfies Prisma.TransactionWhereInput;

/**
 * Soma com sinal das liquidações por conta (RN15), opcionalmente até uma data (inclusive) ou antes dela.
 * Saldo = saldo inicial + entradas liquidadas − saídas liquidadas.
 */
export async function settledNetByAccount(
  accountIds: string[],
  opts: { until?: string; before?: string; db?: Tx } = {},
): Promise<Map<string, number>> {
  const result = new Map<string, number>(accountIds.map((id) => [id, 0]));
  const rows = await settledAggregate({ accountIds, to: opts.until, before: opts.before }, opts.db);
  for (const r of rows) {
    result.set(r.accountId, (result.get(r.accountId) ?? 0) + (r.direction === 'IN' ? r.cents : -r.cents));
  }
  return result;
}

export async function accountBalances(
  accounts: { id: string; initialBalanceCents: bigint }[],
  opts: { until?: string; db?: Tx } = {},
): Promise<Map<string, number>> {
  const net = await settledNetByAccount(
    accounts.map((a) => a.id),
    opts,
  );
  return new Map(accounts.map((a) => [a.id, toCents(a.initialBalanceCents) + (net.get(a.id) ?? 0)]));
}
