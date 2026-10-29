import type { Prisma, RecurringRule } from '@prisma/client';
import type { RecurringCreateInput, RecurringUpdateInput } from '../../contracts';
import { addDaysISO, dayBefore, nextOccurrence, occurrencesBetween, type Schedule } from '../../domain/recurrence';
import { formatDate, parseDate, todayISO } from '../../lib/dates';
import { notFound, unprocessable } from '../../lib/errors';
import { recordEvent } from '../../lib/events';
import { logger } from '../../lib/logger';
import { toCents } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { audit } from '../audit/audit.service';
import { resolveContact, serializeTransaction, transactionInclude } from '../transactions/transactions.service';
import { cashAccountType } from '../../lib/ledgers';

type Ctx = { userId: string; entityId: string; ip?: string };

/** Quantos dias à frente as ocorrências ficam materializadas (sempre ao menos a próxima). */
export const HORIZON_DAYS = 90;
const OPEN = ['PLANNED', 'PENDING'] as const;

export function scheduleOf(r: RecurringRule): Schedule {
  return {
    frequency: r.frequency,
    interval: r.intervalCount,
    unit: r.intervalUnit ?? undefined,
    startDate: formatDate(r.startDate),
    endDate: r.endDate ? formatDate(r.endDate) : null,
    maxOccurrences: r.maxOccurrences,
  };
}

/** Lançamentos ainda não realizados de uma regra (nem parcialmente). */
function openOccurrences(ruleId: string, extra: Prisma.TransactionWhereInput = {}): Prisma.TransactionWhereInput {
  return { recurringRuleId: ruleId, deletedAt: null, status: { in: [...OPEN] }, settledAmountCents: 0, ...extra };
}

/**
 * Materializa as ocorrências da regra até o horizonte. Idempotente: o índice único
 * (regra, data) faz o banco ignorar datas já existentes — inclusive ocorrências canceladas
 * individualmente, que assim não "ressuscitam".
 */
export async function generateForRule(db: Tx | typeof prisma, rule: RecurringRule, today = todayISO()): Promise<number> {
  if (rule.status !== 'ACTIVE') return 0;
  const s = scheduleOf(rule);
  const from = formatDate(rule.activeSince);
  const horizon = addDaysISO(today, HORIZON_DAYS);
  const next = nextOccurrence(s, horizon > from ? today : from);
  const to = next && next > horizon ? next : horizon;
  const dates = occurrencesBetween(s, from, to);
  if (dates.length === 0) return 0;
  const result = await db.transaction.createMany({
    skipDuplicates: true,
    data: dates.map(({ date }) => ({
      entityId: rule.entityId,
      accountId: rule.accountId,
      categoryId: rule.categoryId,
      type: rule.type,
      direction: rule.type === 'INCOME' ? 'IN' : 'OUT',
      amountCents: rule.amountCents,
      settledAmountCents: 0n,
      status: 'PLANNED',
      competenceDate: parseDate(date),
      dueDate: parseDate(date),
      description: rule.description,
      counterparty: rule.counterparty,
      contactId: rule.contactId,
      notes: rule.notes,
      recurringRuleId: rule.id,
      occurrenceDate: parseDate(date),
      createdById: rule.createdById,
    })),
  });
  return result.count;
}

/** Gera as ocorrências pendentes de todas as regras ativas (agendador diário e chamadas sob demanda). */
export async function generateAll(entityIds?: string[]) {
  const rules = await prisma.recurringRule.findMany({
    where: { status: 'ACTIVE', ...(entityIds ? { entityId: { in: entityIds } } : {}) },
  });
  let created = 0;
  for (const rule of rules) created += await generateForRule(prisma, rule);
  if (created > 0) logger.info({ event: 'recurring.generated', created, rules: rules.length }, 'recurring.generated');
  return created;
}

const lastRun = new Map<string, number>();
/** Garante a geração antes de leituras (dashboard, extrato), no máximo a cada 10 minutos por ambiente. */
export async function ensureGenerated(entityIds: string[]) {
  const now = Date.now();
  const due = entityIds.filter((id) => now - (lastRun.get(id) ?? 0) > 10 * 60 * 1000);
  if (due.length === 0) return;
  due.forEach((id) => lastRun.set(id, now));
  await generateAll(due);
}
export function resetGenerationThrottle() {
  lastRun.clear();
}

async function validateRefs(
  db: Tx,
  entityId: string,
  type: 'INCOME' | 'EXPENSE',
  accountId?: string,
  categoryId?: string | null,
  contactId?: string | null,
) {
  if (contactId) await resolveContact(db, entityId, contactId);
  if (accountId) {
    const account = await db.account.findFirst({ where: { id: accountId, entityId, archivedAt: null, type: cashAccountType } });
    if (!account) throw unprocessable('INVALID_ACCOUNT', 'Conta não pertence a este ambiente');
  }
  if (categoryId) {
    const category = await db.category.findFirst({ where: { id: categoryId, entityId } });
    if (!category) throw unprocessable('INVALID_CATEGORY', 'Categoria não pertence a este ambiente');
    if (category.kind !== type) throw unprocessable('CATEGORY_KIND_MISMATCH', 'Categoria incompatível com o tipo');
  }
}

export async function serializeRule(r: RecurringRule & { category?: { id: string; name: string; icon: string } | null; account?: { id: string; name: string } }, today = todayISO()) {
  const [counts, nextOpen] = await Promise.all([
    prisma.transaction.groupBy({
      by: ['status'],
      where: { recurringRuleId: r.id, deletedAt: null },
      _count: true,
    }),
    prisma.transaction.findFirst({
      where: openOccurrences(r.id),
      orderBy: { occurrenceDate: 'asc' },
      select: { id: true, occurrenceDate: true, amountCents: true },
    }),
  ]);
  const count = (s: string) => counts.find((c) => c.status === s)?._count ?? 0;
  const overdue = await prisma.transaction.count({ where: openOccurrences(r.id, { occurrenceDate: { lt: parseDate(today) } }) });
  return {
    id: r.id,
    entityId: r.entityId,
    type: r.type,
    description: r.description,
    amountCents: toCents(r.amountCents),
    amountKind: r.amountKind,
    account: r.account ?? null,
    category: r.category ?? null,
    counterparty: r.counterparty,
    notes: r.notes,
    frequency: r.frequency,
    intervalCount: r.intervalCount,
    intervalUnit: r.intervalUnit,
    startDate: formatDate(r.startDate),
    endDate: r.endDate ? formatDate(r.endDate) : null,
    maxOccurrences: r.maxOccurrences,
    status: r.status,
    previousRuleId: r.previousRuleId,
    nextOccurrence: nextOpen
      ? { transactionId: nextOpen.id, date: formatDate(nextOpen.occurrenceDate!), amountCents: toCents(nextOpen.amountCents) }
      : null,
    stats: { settled: count('SETTLED') + count('PARTIAL'), open: count('PLANNED') + count('PENDING'), overdue, canceled: count('CANCELED') },
  };
}

const ruleInclude = {
  category: { select: { id: true, name: true, icon: true } },
  account: { select: { id: true, name: true } },
} satisfies Prisma.RecurringRuleInclude;

async function getRuleOrThrow(entityId: string, id: string, db: Tx | typeof prisma = prisma) {
  const r = await db.recurringRule.findFirst({ where: { id, entityId }, include: ruleInclude });
  if (!r) throw notFound('Recorrência não encontrada');
  return r;
}

export async function listRules(entityId: string, status?: 'ACTIVE' | 'PAUSED' | 'CANCELED') {
  await ensureGenerated([entityId]);
  const rules = await prisma.recurringRule.findMany({
    where: { entityId, ...(status ? { status } : {}) },
    include: ruleInclude,
    orderBy: [{ status: 'asc' }, { description: 'asc' }],
  });
  return Promise.all(rules.map((r) => serializeRule(r)));
}

export async function getRule(entityId: string, id: string) {
  const r = await getRuleOrThrow(entityId, id);
  // Inclui a cadeia de regras anteriores (divisões por "esta e as próximas") para mostrar o histórico completo.
  const occurrences = await prisma.transaction.findMany({
    where: { recurringRuleId: id, deletedAt: null },
    include: transactionInclude,
    orderBy: { occurrenceDate: 'asc' },
  });
  const today = todayISO();
  return { ...(await serializeRule(r, today)), occurrences: occurrences.map((t) => serializeTransaction(t, today)) };
}

export async function createRule(ctx: Ctx, input: RecurringCreateInput) {
  const rule = await prisma.$transaction(async (tx) => {
    await validateRefs(tx, ctx.entityId, input.type, input.accountId, input.categoryId, input.contactId);
    const r = await tx.recurringRule.create({
      data: {
        entityId: ctx.entityId,
        type: input.type,
        description: input.description,
        amountCents: BigInt(input.amountCents),
        amountKind: input.amountKind,
        accountId: input.accountId,
        categoryId: input.categoryId ?? null,
        counterparty: input.counterparty ?? null,
        contactId: input.contactId ?? null,
        notes: input.notes ?? null,
        frequency: input.frequency,
        intervalCount: input.frequency === 'CUSTOM' ? input.intervalCount : 1,
        intervalUnit: input.frequency === 'CUSTOM' ? input.intervalUnit : null,
        startDate: parseDate(input.startDate),
        endDate: input.endDate ? parseDate(input.endDate) : null,
        maxOccurrences: input.maxOccurrences ?? null,
        activeSince: parseDate(input.startDate),
        createdById: ctx.userId,
      },
    });
    await generateForRule(tx, r);
    await audit(tx, { ...ctx, action: 'create', resourceType: 'recurring_rule', resourceId: r.id, after: r });
    return r;
  });
  recordEvent('recurring.created', { entityId: ctx.entityId, ruleId: rule.id, frequency: rule.frequency });
  return getRule(ctx.entityId, rule.id);
}

const SCHEDULE_FIELDS = ['frequency', 'intervalCount', 'intervalUnit', 'endDate', 'maxOccurrences'] as const;

function ruleData(changes: RecurringUpdateInput['changes']): Prisma.RecurringRuleUncheckedUpdateInput {
  return {
    description: changes.description,
    amountCents: changes.amountCents === undefined ? undefined : BigInt(changes.amountCents),
    amountKind: changes.amountKind,
    accountId: changes.accountId,
    categoryId: changes.categoryId,
    counterparty: changes.counterparty,
    contactId: changes.contactId,
    notes: changes.notes,
    frequency: changes.frequency,
    intervalCount: changes.intervalCount,
    intervalUnit: changes.intervalUnit,
    endDate: changes.endDate === undefined ? undefined : changes.endDate ? parseDate(changes.endDate) : null,
    maxOccurrences: changes.maxOccurrences,
  };
}

/** Valores que as ocorrências em aberto herdam da regra. */
function occurrenceValues(changes: RecurringUpdateInput['changes']): Prisma.TransactionUncheckedUpdateManyInput {
  return {
    description: changes.description,
    amountCents: changes.amountCents === undefined ? undefined : BigInt(changes.amountCents),
    accountId: changes.accountId,
    categoryId: changes.categoryId,
    counterparty: changes.counterparty,
    contactId: changes.contactId,
    notes: changes.notes,
  };
}

/**
 * Edita a série (SERIES) ou desta ocorrência em diante (FROM). Lançamentos realizados — total
 * ou parcialmente — nunca são alterados (RN05). Ocorrências editadas individualmente mantêm seus
 * valores, salvo quando o calendário muda.
 */
export async function updateRule(ctx: Ctx, id: string, input: RecurringUpdateInput) {
  const resultId = await prisma.$transaction(async (tx) => {
    const before = await getRuleOrThrow(ctx.entityId, id, tx);
    if (before.status === 'CANCELED') throw unprocessable('RULE_CANCELED', 'Recorrência cancelada não pode ser editada');
    const type = before.type as 'INCOME' | 'EXPENSE';
    await validateRefs(tx, ctx.entityId, type, input.changes.accountId, input.changes.categoryId, input.changes.contactId);
    const c = input.changes;
    const scheduleChanged = SCHEDULE_FIELDS.some((f) => c[f] !== undefined);
    const startISO = formatDate(before.startDate);

    // "Desta em diante" a partir do início equivale a editar a série.
    const asSeries = input.scope === 'SERIES' || !input.fromDate || input.fromDate <= startISO;

    if (asSeries) {
      const updated = await tx.recurringRule.update({ where: { id }, data: ruleData(c) });
      if (scheduleChanged) {
        // Novo calendário: remove as ocorrências em aberto e gera novamente.
        await tx.transaction.updateMany({ where: openOccurrences(id), data: { deletedAt: new Date() } });
      } else {
        await tx.transaction.updateMany({ where: openOccurrences(id, { isOverride: false }), data: occurrenceValues(c) });
      }
      await generateForRule(tx, updated);
      await audit(tx, { ...ctx, action: 'update', resourceType: 'recurring_rule', resourceId: id, before, after: { scope: 'SERIES', ...updated } });
      return id;
    }

    // Divide a série: a regra atual termina na véspera e uma nova assume a partir de fromDate.
    const from = input.fromDate!;
    const s = scheduleOf(before);
    const usedBefore = occurrencesBetween(s, startISO, dayBefore(from)).length;
    await tx.recurringRule.update({ where: { id }, data: { endDate: parseDate(dayBefore(from)) } });
    const created = await tx.recurringRule.create({
      data: {
        entityId: before.entityId,
        type: before.type,
        description: c.description ?? before.description,
        amountCents: c.amountCents !== undefined ? BigInt(c.amountCents) : before.amountCents,
        amountKind: c.amountKind ?? before.amountKind,
        accountId: c.accountId ?? before.accountId,
        categoryId: c.categoryId !== undefined ? c.categoryId : before.categoryId,
        counterparty: c.counterparty !== undefined ? c.counterparty : before.counterparty,
        contactId: c.contactId !== undefined ? c.contactId : before.contactId,
        notes: c.notes !== undefined ? c.notes : before.notes,
        frequency: c.frequency ?? before.frequency,
        intervalCount: c.intervalCount ?? before.intervalCount,
        intervalUnit: c.intervalUnit !== undefined ? c.intervalUnit : before.intervalUnit,
        startDate: parseDate(from),
        endDate: c.endDate !== undefined ? (c.endDate ? parseDate(c.endDate) : null) : before.endDate,
        maxOccurrences:
          c.maxOccurrences !== undefined
            ? c.maxOccurrences
            : before.maxOccurrences !== null
              ? Math.max(1, before.maxOccurrences - usedBefore)
              : null,
        activeSince: parseDate(from),
        status: before.status,
        previousRuleId: before.id,
        createdById: ctx.userId,
      },
    });
    const fromDate = parseDate(from);
    // Em aberto a partir da data: substituídas pela nova regra.
    await tx.transaction.updateMany({ where: openOccurrences(id, { occurrenceDate: { gte: fromDate } }), data: { deletedAt: new Date() } });
    // Já realizadas a partir da data: preservadas e transferidas para a nova regra (evita duplicar a data).
    await tx.transaction.updateMany({
      where: { recurringRuleId: id, deletedAt: null, occurrenceDate: { gte: fromDate } },
      data: { recurringRuleId: created.id },
    });
    await generateForRule(tx, created);
    await audit(tx, { ...ctx, action: 'split', resourceType: 'recurring_rule', resourceId: id, before, after: { scope: 'FROM', from, newRuleId: created.id } });
    return created.id;
  });
  return getRule(ctx.entityId, resultId);
}

/** Pausa: não gera novas ocorrências e remove as previstas a partir de hoje. As vencidas continuam visíveis. */
export async function pauseRule(ctx: Ctx, id: string) {
  await prisma.$transaction(async (tx) => {
    const r = await getRuleOrThrow(ctx.entityId, id, tx);
    if (r.status !== 'ACTIVE') throw unprocessable('NOT_ACTIVE', 'Somente recorrências ativas podem ser pausadas');
    await tx.recurringRule.update({ where: { id }, data: { status: 'PAUSED' } });
    await tx.transaction.updateMany({
      where: openOccurrences(id, { occurrenceDate: { gte: parseDate(todayISO()) } }),
      data: { deletedAt: new Date() },
    });
    await audit(tx, { ...ctx, action: 'pause', resourceType: 'recurring_rule', resourceId: id });
  });
  return getRule(ctx.entityId, id);
}

/** Reativa a partir de hoje — o período pausado não é gerado retroativamente. */
export async function resumeRule(ctx: Ctx, id: string) {
  await prisma.$transaction(async (tx) => {
    const r = await getRuleOrThrow(ctx.entityId, id, tx);
    if (r.status === 'ACTIVE') throw unprocessable('ALREADY_ACTIVE', 'Recorrência já está ativa');
    const updated = await tx.recurringRule.update({
      where: { id },
      data: { status: 'ACTIVE', activeSince: parseDate(todayISO()) },
    });
    await generateForRule(tx, updated);
    await audit(tx, { ...ctx, action: 'resume', resourceType: 'recurring_rule', resourceId: id });
  });
  return getRule(ctx.entityId, id);
}

/** Cancela a série: remove as previstas a partir de hoje e preserva todo o histórico. */
export async function cancelRule(ctx: Ctx, id: string) {
  await prisma.$transaction(async (tx) => {
    await getRuleOrThrow(ctx.entityId, id, tx);
    await tx.recurringRule.update({ where: { id }, data: { status: 'CANCELED' } });
    await tx.transaction.updateMany({
      where: openOccurrences(id, { occurrenceDate: { gte: parseDate(todayISO()) } }),
      data: { deletedAt: new Date() },
    });
    await audit(tx, { ...ctx, action: 'cancel', resourceType: 'recurring_rule', resourceId: id });
  });
  return getRule(ctx.entityId, id);
}
