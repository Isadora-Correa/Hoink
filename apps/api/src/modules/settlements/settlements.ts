import { Prisma, type Direction, type TransactionType } from '@prisma/client';
import { parseDate } from '../../lib/dates';
import { toCents } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';

/**
 * Liquidações são a fonte de verdade do dinheiro que efetivamente entrou/saiu (RN15).
 * Todo código que altera `settled_amount_cents` de um lançamento deve passar por aqui.
 */
export async function addSettlement(db: Tx, transactionId: string, amountCents: number, date: string, userId: string) {
  if (amountCents <= 0) return;
  await db.settlement.create({
    data: { transactionId, amountCents: BigInt(amountCents), date: parseDate(date), createdById: userId },
  });
}

/** Substitui o histórico por uma única liquidação (ou nenhuma) — usado quando o lançamento é editado por inteiro. */
export async function replaceSettlements(
  db: Tx,
  transactionId: string,
  amountCents: number,
  date: string | null,
  userId: string,
) {
  await db.settlement.deleteMany({ where: { transactionId } });
  if (amountCents > 0 && date) await addSettlement(db, transactionId, amountCents, date, userId);
}

export interface SettledRow {
  accountId: string;
  entityId: string;
  type: TransactionType;
  direction: Direction;
  categoryId: string | null;
  month: string;
  cents: number;
}

/**
 * Valores liquidados agregados (somente lançamentos ativos e não cancelados), por conta,
 * tipo, sentido, categoria e mês da liquidação. Base de saldos, extratos e realizado.
 */
export async function settledAggregate(
  filter: { accountIds?: string[]; entityIds?: string[]; from?: string; to?: string; before?: string; types?: string[] },
  db: Tx | typeof prisma = prisma,
): Promise<SettledRow[]> {
  const conds: Prisma.Sql[] = [Prisma.sql`t.deleted_at IS NULL`, Prisma.sql`t.status IN ('SETTLED', 'PARTIAL')`];
  if (filter.accountIds) {
    if (filter.accountIds.length === 0) return [];
    conds.push(Prisma.sql`t.account_id IN (${Prisma.join(filter.accountIds.map((id) => Prisma.sql`${id}::uuid`))})`);
  }
  if (filter.entityIds) {
    if (filter.entityIds.length === 0) return [];
    conds.push(Prisma.sql`t.entity_id IN (${Prisma.join(filter.entityIds.map((id) => Prisma.sql`${id}::uuid`))})`);
  }
  if (filter.types) conds.push(Prisma.sql`t.type::text IN (${Prisma.join(filter.types)})`);
  if (filter.from) conds.push(Prisma.sql`s.date >= ${filter.from}::date`);
  if (filter.to) conds.push(Prisma.sql`s.date <= ${filter.to}::date`);
  if (filter.before) conds.push(Prisma.sql`s.date < ${filter.before}::date`);
  const rows = await db.$queryRaw<
    { account_id: string; entity_id: string; type: string; direction: string; category_id: string | null; month: string; cents: bigint }[]
  >`
    SELECT t.account_id, t.entity_id, t.type::text AS type, t.direction::text AS direction, t.category_id,
           to_char(s.date, 'YYYY-MM') AS month, SUM(s.amount_cents)::bigint AS cents
    FROM transaction_settlements s
    JOIN transactions t ON t.id = s.transaction_id
    WHERE ${Prisma.join(conds, ' AND ')}
    GROUP BY 1, 2, 3, 4, 5, 6`;
  return rows.map((r) => ({
    accountId: r.account_id,
    entityId: r.entity_id,
    type: r.type as SettledRow['type'],
    direction: r.direction as SettledRow['direction'],
    categoryId: r.category_id,
    month: r.month,
    cents: toCents(r.cents),
  }));
}
