import type { Debt, DebtInstallment, Prisma, Transaction } from '@prisma/client';
import type { z } from 'zod';
import type {
  debtCreateSchema,
  debtPayoffSchema,
  debtPrepaySchema,
  debtSimulationSchema,
  debtUpdateSchema,
} from '../../contracts';
import {
  amortizationSchedule,
  payoffQuote,
  remainingTerm,
  type OpenInstallment,
  type ScheduleRow,
} from '../../domain/debts';
import { addDaysISO } from '../../domain/recurrence';
import { formatDate, parseDate, todayISO } from '../../lib/dates';
import { notFound, unprocessable } from '../../lib/errors';
import { recordEvent } from '../../lib/events';
import { toCents } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { audit } from '../audit/audit.service';
import { addSettlement } from '../settlements/settlements';
import { cashAccountType } from '../../lib/ledgers';

type Ctx = { userId: string; entityId: string; ip?: string };

export const DEBT_CATEGORY = 'Empréstimos e financiamentos';

export const DEBT_KIND_LABELS = {
  FINANCING: 'Financiamento',
  LOAN: 'Empréstimo',
  OVERDRAFT: 'Cheque especial',
  OTHER: 'Dívida',
} as const;

type InstallmentRow = DebtInstallment & { transaction: Transaction | null };
type DebtRow = Debt & { installments: InstallmentRow[]; account: { id: string; name: string } };

const debtInclude = {
  installments: { where: { replacedAt: null }, include: { transaction: true }, orderBy: [{ dueDate: 'asc' }, { createdAt: 'asc' }] },
  account: { select: { id: true, name: true } },
} satisfies Prisma.DebtInclude;

/** Simulação do cronograma, sem gravar nada (usada no formulário antes de cadastrar). */
export function simulate(input: z.infer<typeof debtSimulationSchema>) {
  const rows = amortizationSchedule({
    principalCents: input.principalCents,
    monthlyRatePpm: input.monthlyRatePpm,
    installments: input.installmentCount,
    system: input.system,
    firstDueDate: input.firstDueDate,
    feesCents: input.feesCents,
  });
  return {
    installments: rows,
    totalCents: rows.reduce((s, r) => s + r.totalCents, 0),
    totalInterestCents: rows.reduce((s, r) => s + r.interestCents, 0),
    totalFeesCents: rows.reduce((s, r) => s + r.feesCents, 0),
    firstPaymentCents: rows[0]!.totalCents,
    lastPaymentCents: rows.at(-1)!.totalCents,
  };
}

type PaymentState = 'PAID' | 'PARTIAL' | 'OPEN' | 'OVERDUE';

function paymentState(i: InstallmentRow, today: string): PaymentState {
  if (i.paidBeforeApp) return 'PAID';
  const t = i.transaction;
  if (!t || t.deletedAt) return 'OPEN';
  if (t.status === 'SETTLED') return 'PAID';
  if (formatDate(i.dueDate) < today) return 'OVERDUE';
  return t.status === 'PARTIAL' ? 'PARTIAL' : 'OPEN';
}

const scheduled = (i: InstallmentRow) => toCents(i.principalCents) + toCents(i.interestCents) + toCents(i.feesCents);

function serializeInstallment(i: InstallmentRow, today: string) {
  const state = paymentState(i, today);
  const paid = i.transaction && !i.transaction.deletedAt ? toCents(i.transaction.settledAmountCents) : 0;
  return {
    id: i.id,
    kind: i.kind,
    number: i.number,
    dueDate: formatDate(i.dueDate),
    principalCents: toCents(i.principalCents),
    interestCents: toCents(i.interestCents),
    feesCents: toCents(i.feesCents),
    totalCents: scheduled(i),
    balanceAfterCents: toCents(i.balanceAfterCents),
    state,
    paidBeforeApp: i.paidBeforeApp,
    paidCents: i.paidBeforeApp ? scheduled(i) : paid,
    paidDate: i.transaction?.settledDate ? formatDate(i.transaction.settledDate) : null,
    /** Multa e juros de mora: o que foi pago além do previsto na parcela. */
    penaltyCents: state === 'PAID' && !i.paidBeforeApp ? Math.max(0, paid - scheduled(i)) : 0,
    transactionId: i.transactionId,
  };
}

function summarize(d: DebtRow, today: string) {
  const items = d.installments.map((i) => serializeInstallment(i, today));
  const regular = items.filter((i) => i.kind === 'REGULAR');
  const paid = items.filter((i) => i.state === 'PAID');
  const open = items.filter((i) => i.state !== 'PAID');
  const sum = (xs: typeof items, k: 'principalCents' | 'interestCents' | 'feesCents' | 'penaltyCents' | 'totalCents') =>
    xs.reduce((s, i) => s + i[k], 0);
  const principal = toCents(d.principalCents);
  const outstanding = sum(open, 'principalCents');
  return {
    id: d.id,
    entityId: d.entityId,
    kind: d.kind,
    kindLabel: DEBT_KIND_LABELS[d.kind],
    name: d.name,
    creditor: d.creditor,
    principalCents: principal,
    monthlyRatePpm: d.monthlyRatePpm,
    system: d.system,
    installmentCount: d.installmentCount,
    startDate: formatDate(d.startDate),
    firstDueDate: formatDate(d.firstDueDate),
    feesCents: toCents(d.feesCents),
    account: d.account,
    categoryId: d.categoryId,
    status: d.status,
    notes: d.notes,
    summary: {
      outstandingPrincipalCents: outstanding,
      remainingTotalCents: sum(open, 'totalCents'),
      paidPrincipalCents: sum(paid, 'principalCents'),
      paidInterestCents: sum(paid, 'interestCents'),
      paidFeesCents: sum(paid, 'feesCents'),
      paidPenaltiesCents: sum(paid, 'penaltyCents'),
      paidInstallments: regular.filter((i) => i.state === 'PAID').length,
      remainingInstallments: regular.filter((i) => i.state !== 'PAID').length,
      overdueInstallments: items.filter((i) => i.state === 'OVERDUE').length,
      progressBps: principal > 0 ? Math.round(((principal - outstanding) * 10000) / principal) : 10000,
      nextInstallment: open[0] ?? null,
    },
    installments: items,
  };
}

async function getDebtRow(entityId: string, id: string, db: Tx | typeof prisma = prisma): Promise<DebtRow> {
  const d = await db.debt.findFirst({ where: { id, entityId }, include: debtInclude });
  if (!d) throw notFound('Dívida não encontrada');
  return d;
}

export async function listDebts(entityId: string, includeClosed = false) {
  const rows = await prisma.debt.findMany({
    where: { entityId, ...(includeClosed ? {} : { status: 'ACTIVE' }) },
    include: debtInclude,
    orderBy: { createdAt: 'asc' },
  });
  const today = todayISO();
  return rows.map((d) => {
    const { installments: _omit, ...rest } = summarize(d, today);
    return rest;
  });
}

export async function getDebt(entityId: string, id: string) {
  return summarize(await getDebtRow(entityId, id), todayISO());
}

/** Categoria de despesa usada nas parcelas — criada sob demanda em ambientes antigos. */
async function debtCategoryId(db: Tx, entityId: string, requested: string | null | undefined) {
  if (requested) {
    const c = await db.category.findFirst({ where: { id: requested, entityId, kind: 'EXPENSE' } });
    if (!c) throw unprocessable('INVALID_CATEGORY', 'Categoria de despesa não pertence a este ambiente');
    return c.id;
  }
  const c = await db.category.upsert({
    where: { entityId_kind_name: { entityId, kind: 'EXPENSE', name: DEBT_CATEGORY } },
    create: { entityId, kind: 'EXPENSE', name: DEBT_CATEGORY, icon: 'credit_score', color: '#5A2734', isSystem: true },
    update: {},
  });
  return c.id;
}

async function paymentAccount(db: Tx, entityId: string, id: string) {
  const a = await db.account.findFirst({ where: { id, entityId, archivedAt: null, type: cashAccountType } });
  if (!a) throw unprocessable('INVALID_ACCOUNT', 'Conta de pagamento não pertence a este ambiente');
  return a;
}

/** Cria as parcelas do cronograma, cada uma com seu lançamento pendente (confirmado) na conta de pagamento. */
async function createInstallments(
  db: Tx,
  ctx: Ctx,
  debt: Debt,
  rows: ScheduleRow[],
  opts: { paidBeforeApp?: (r: ScheduleRow) => boolean } = {},
) {
  const label = debt.name;
  for (const r of rows) {
    const before = opts.paidBeforeApp?.(r) ?? false;
    let transactionId: string | null = null;
    if (!before) {
      const t = await db.transaction.create({
        data: {
          entityId: debt.entityId,
          accountId: debt.accountId,
          categoryId: debt.categoryId,
          type: 'EXPENSE',
          direction: 'OUT',
          amountCents: BigInt(r.totalCents),
          settledAmountCents: 0n,
          status: 'PENDING',
          competenceDate: parseDate(r.dueDate),
          dueDate: parseDate(r.dueDate),
          description: `${label} (${r.number}/${debt.installmentCount})`,
          counterparty: debt.creditor,
          createdById: ctx.userId,
        },
      });
      transactionId = t.id;
    }
    await db.debtInstallment.create({
      data: {
        debtId: debt.id,
        kind: 'REGULAR',
        number: r.number,
        dueDate: parseDate(r.dueDate),
        principalCents: BigInt(r.principalCents),
        interestCents: BigInt(r.interestCents),
        feesCents: BigInt(r.feesCents),
        balanceAfterCents: BigInt(r.balanceAfterCents),
        paidBeforeApp: before,
        transactionId,
      },
    });
  }
}

export async function createDebt(ctx: Ctx, input: z.infer<typeof debtCreateSchema>) {
  const rows = amortizationSchedule({
    principalCents: input.principalCents,
    monthlyRatePpm: input.monthlyRatePpm,
    installments: input.installmentCount,
    system: input.system,
    firstDueDate: input.firstDueDate,
    feesCents: input.feesCents,
  });
  const startDate = input.startDate ?? addDaysISO(input.firstDueDate, -30);
  const id = await prisma.$transaction(async (tx) => {
    await paymentAccount(tx, ctx.entityId, input.accountId);
    const categoryId = await debtCategoryId(tx, ctx.entityId, input.categoryId);
    const debt = await tx.debt.create({
      data: {
        entityId: ctx.entityId,
        kind: input.kind,
        name: input.name,
        creditor: input.creditor ?? null,
        principalCents: BigInt(input.principalCents),
        monthlyRatePpm: input.monthlyRatePpm,
        system: input.system,
        installmentCount: input.installmentCount,
        startDate: parseDate(startDate),
        firstDueDate: parseDate(input.firstDueDate),
        feesCents: BigInt(input.feesCents),
        accountId: input.accountId,
        categoryId,
        notes: input.notes ?? null,
        createdById: ctx.userId,
      },
    });
    await createInstallments(tx, ctx, debt, rows, { paidBeforeApp: (r) => r.number <= input.paidInstallments });
    await audit(tx, { ...ctx, action: 'create', resourceType: 'debt', resourceId: debt.id, after: debt });
    return debt.id;
  });
  recordEvent('debt.created', { entityId: ctx.entityId, debtId: id, system: input.system });
  return getDebt(ctx.entityId, id);
}

export async function updateDebt(ctx: Ctx, id: string, input: z.infer<typeof debtUpdateSchema>) {
  const before = await getDebtRow(ctx.entityId, id);
  await prisma.$transaction(async (tx) => {
    const after = await tx.debt.update({ where: { id }, data: { name: input.name, creditor: input.creditor, notes: input.notes } });
    await audit(tx, { ...ctx, action: 'update', resourceType: 'debt', resourceId: id, before, after });
  });
  return getDebt(ctx.entityId, id);
}

/** Parcelas ainda não pagas nem parcialmente (podem ser recalculadas). */
function untouched(i: InstallmentRow) {
  return !i.paidBeforeApp && i.transaction && !i.transaction.deletedAt && i.transaction.status === 'PENDING' && i.transaction.settledAmountCents === 0n;
}

/** Substitui parcelas abertas: o lançamento pendente é excluído logicamente e a linha marcada como substituída. */
async function replaceInstallments(db: Tx, rows: InstallmentRow[]) {
  const now = new Date();
  await db.debtInstallment.updateMany({ where: { id: { in: rows.map((r) => r.id) } }, data: { replacedAt: now } });
  await db.transaction.updateMany({
    where: { id: { in: rows.map((r) => r.transactionId).filter((v): v is string => !!v) } },
    data: { deletedAt: now },
  });
}

async function settledPayment(
  db: Tx,
  ctx: Ctx,
  debt: Debt,
  input: { date: string; amountCents: number; accountId?: string; description: string },
) {
  const accountId = input.accountId ?? debt.accountId;
  const account = await paymentAccount(db, ctx.entityId, accountId);
  if (input.date < formatDate(account.referenceDate)) {
    throw unprocessable('SETTLED_BEFORE_REFERENCE', 'Data anterior à data de referência da conta');
  }
  const t = await db.transaction.create({
    data: {
      entityId: debt.entityId,
      accountId,
      categoryId: debt.categoryId,
      type: 'EXPENSE',
      direction: 'OUT',
      amountCents: BigInt(input.amountCents),
      settledAmountCents: BigInt(input.amountCents),
      status: 'SETTLED',
      competenceDate: parseDate(input.date),
      dueDate: parseDate(input.date),
      settledDate: parseDate(input.date),
      description: input.description,
      counterparty: debt.creditor,
      createdById: ctx.userId,
    },
  });
  await addSettlement(db, t.id, input.amountCents, input.date, ctx.userId);
  return t;
}

/**
 * Amortização extraordinária: o valor abate o saldo devedor das parcelas a vencer, que são
 * recalculadas mantendo a parcela (reduz o prazo) ou o prazo (reduz a parcela).
 */
export async function prepay(ctx: Ctx, id: string, input: z.infer<typeof debtPrepaySchema>) {
  await prisma.$transaction(async (tx) => {
    const d = await getDebtRow(ctx.entityId, id, tx);
    if (d.status !== 'ACTIVE') throw unprocessable('DEBT_CLOSED', 'Dívida não está ativa');
    const future = d.installments.filter((i) => i.kind === 'REGULAR' && formatDate(i.dueDate) >= input.date && untouched(i));
    if (future.length === 0) throw unprocessable('NOTHING_TO_AMORTIZE', 'Não há parcelas a vencer para amortizar');
    const outstanding = future.reduce((s, i) => s + toCents(i.principalCents), 0);
    if (input.amountCents >= outstanding) {
      throw unprocessable('USE_PAYOFF', 'O valor quita o saldo devedor: use a quitação antecipada');
    }
    const first = future[0]!;
    const newPrincipal = outstanding - input.amountCents;
    const n =
      input.mode === 'REDUCE_INSTALLMENT'
        ? future.length
        : Math.min(
            future.length,
            remainingTerm(newPrincipal, d.monthlyRatePpm, d.system, {
              paymentCents: toCents(first.principalCents) + toCents(first.interestCents),
              amortizationCents: toCents(first.principalCents),
            }),
          );
    const rows = amortizationSchedule({
      principalCents: newPrincipal,
      monthlyRatePpm: d.monthlyRatePpm,
      installments: n,
      system: d.system,
      firstDueDate: formatDate(first.dueDate),
      feesCents: toCents(d.feesCents),
      startNumber: first.number ?? 1,
    });
    const payment = await settledPayment(tx, ctx, d, {
      date: input.date,
      amountCents: input.amountCents,
      accountId: input.accountId,
      description: `${d.name} — amortização extraordinária`,
    });
    await tx.debtInstallment.create({
      data: {
        debtId: d.id,
        kind: 'EXTRA',
        dueDate: parseDate(input.date),
        principalCents: BigInt(input.amountCents),
        interestCents: 0n,
        feesCents: 0n,
        balanceAfterCents: BigInt(newPrincipal),
        transactionId: payment.id,
      },
    });
    await replaceInstallments(tx, future);
    // O total de parcelas da dívida passa a refletir o novo prazo.
    const installmentCount = d.installmentCount - (future.length - n);
    const updated = await tx.debt.update({ where: { id }, data: { installmentCount } });
    await createInstallments(tx, ctx, updated, rows);
    await audit(tx, {
      ...ctx,
      action: 'prepay',
      resourceType: 'debt',
      resourceId: id,
      after: { amountCents: input.amountCents, mode: input.mode, newPrincipal, installments: n },
    });
  });
  recordEvent('debt.prepaid', { entityId: ctx.entityId, debtId: id, mode: input.mode });
  return getDebt(ctx.entityId, id);
}

function quoteFor(d: DebtRow, date: string) {
  const open = d.installments.filter((i) => i.kind === 'REGULAR' && !i.paidBeforeApp && i.transaction?.status !== 'SETTLED');
  if (open.some((i) => i.transaction && i.transaction.settledAmountCents > 0n)) {
    throw unprocessable('PARTIAL_INSTALLMENT', 'Conclua o pagamento da parcela parcialmente paga antes de quitar');
  }
  // Referência dos juros pro rata: último vencimento anterior à data (pago ou não) ou a contratação.
  const previous = d.installments
    .filter((i) => i.kind === 'REGULAR' && formatDate(i.dueDate) <= date)
    .map((i) => formatDate(i.dueDate))
    .at(-1);
  const reference = previous ?? formatDate(d.startDate);
  const items: OpenInstallment[] = open.map((i) => ({
    dueDate: formatDate(i.dueDate),
    principalCents: toCents(i.principalCents),
    interestCents: toCents(i.interestCents),
    feesCents: toCents(i.feesCents),
  }));
  return { open, quote: payoffQuote(items, d.monthlyRatePpm, date, reference) };
}

/** Simulação de quitação antecipada numa data. */
export async function payoffSimulation(entityId: string, id: string, date: string) {
  const d = await getDebtRow(entityId, id);
  if (d.status !== 'ACTIVE') throw unprocessable('DEBT_CLOSED', 'Dívida não está ativa');
  return quoteFor(d, date).quote;
}

/** Quita a dívida: registra o pagamento do valor de quitação e encerra as parcelas restantes. */
export async function payoff(ctx: Ctx, id: string, input: z.infer<typeof debtPayoffSchema>) {
  await prisma.$transaction(async (tx) => {
    const d = await getDebtRow(ctx.entityId, id, tx);
    if (d.status !== 'ACTIVE') throw unprocessable('DEBT_CLOSED', 'Dívida não está ativa');
    const { open, quote } = quoteFor(d, input.date);
    if (quote.payoffCents <= 0) throw unprocessable('NOTHING_TO_PAY', 'Não há saldo devedor');
    const payment = await settledPayment(tx, ctx, d, {
      date: input.date,
      amountCents: quote.payoffCents,
      accountId: input.accountId,
      description: `${d.name} — quitação`,
    });
    const overdue = open.filter((i) => formatDate(i.dueDate) < input.date);
    const overdueInterest = overdue.reduce((s, i) => s + toCents(i.interestCents), 0);
    const overdueFees = overdue.reduce((s, i) => s + toCents(i.feesCents), 0);
    await tx.debtInstallment.create({
      data: {
        debtId: d.id,
        kind: 'PAYOFF',
        dueDate: parseDate(input.date),
        principalCents: BigInt(quote.payoffCents - quote.accruedInterestCents - overdueInterest - overdueFees),
        interestCents: BigInt(quote.accruedInterestCents + overdueInterest),
        feesCents: BigInt(overdueFees),
        balanceAfterCents: 0n,
        transactionId: payment.id,
      },
    });
    await replaceInstallments(tx, open);
    await tx.debt.update({ where: { id }, data: { status: 'PAID_OFF' } });
    await audit(tx, { ...ctx, action: 'payoff', resourceType: 'debt', resourceId: id, after: quote });
  });
  recordEvent('debt.paid_off', { entityId: ctx.entityId, debtId: id });
  return getDebt(ctx.entityId, id);
}

/** Cancela o cadastro: parcelas em aberto deixam de existir; pagamentos já feitos permanecem no histórico. */
export async function cancelDebt(ctx: Ctx, id: string) {
  await prisma.$transaction(async (tx) => {
    const d = await getDebtRow(ctx.entityId, id, tx);
    if (d.status !== 'ACTIVE') throw unprocessable('DEBT_CLOSED', 'Dívida não está ativa');
    await replaceInstallments(tx, d.installments.filter(untouched));
    await tx.debt.update({ where: { id }, data: { status: 'CANCELED' } });
    await audit(tx, { ...ctx, action: 'cancel', resourceType: 'debt', resourceId: id, before: d });
  });
  return getDebt(ctx.entityId, id);
}
