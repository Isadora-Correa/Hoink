import type { Investment, InvestmentMovement, MarketIndex } from '@prisma/client';
import { Prisma } from '@prisma/client';
import type { z } from 'zod';
import type {
  investmentCreateSchema,
  investmentMoveSchema,
  investmentUpdateSchema,
  investmentValueSchema,
} from '../../contracts';
import { accrue, estimateTax, openLots, type Flow, type RateSeries } from '../../domain/yields';
import { formatDate, parseDate, todayISO } from '../../lib/dates';
import { notFound, unprocessable } from '../../lib/errors';
import { cashAccountType } from '../../lib/ledgers';
import { recordEvent } from '../../lib/events';
import { toCents } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { audit } from '../audit/audit.service';
import { loadSeries } from '../market/market.service';
import { addSettlement } from '../settlements/settlements';

type Ctx = { userId: string; entityId: string; ip?: string };
type Move = Pick<InvestmentMovement, 'kind' | 'date' | 'amountCents' | 'quantity' | 'unitPrice'>;

/** Preço de mercado ou valor manual mais antigo que isso é sinalizado como desatualizado. */
const STALE_PRICE_DAYS = 7;
const STALE_MANUAL_DAYS = 35;
const FIXED = ['CDI_PERCENT', 'SELIC_PERCENT', 'PREFIXED', 'IPCA_PLUS'] as const;
type FixedEngine = (typeof FIXED)[number];
const isFixed = (i: string): i is FixedEngine => (FIXED as readonly string[]).includes(i);

const SERIES_OF: Partial<Record<FixedEngine, MarketIndex>> = { CDI_PERCENT: 'CDI', SELIC_PERCENT: 'SELIC', IPCA_PLUS: 'IPCA' };

export const KIND_LABELS = {
  CDB: 'CDB',
  LCI: 'LCI',
  LCA: 'LCA',
  TESOURO: 'Tesouro Direto',
  FUND: 'Fundo',
  STOCK: 'Ação',
  ETF: 'ETF',
  OTHER: 'Outro',
} as const;

const days = (from: string, to: string) => Math.round((parseDate(to).getTime() - parseDate(from).getTime()) / 86_400_000);
const signedCash = (m: Move) =>
  m.kind === 'CONTRIBUTION' ? toCents(m.amountCents) : m.kind === 'REDEMPTION' ? -toCents(m.amountCents) : 0;

export interface Valuation {
  valueCents: number;
  /** ESTIMATED (motor de renda fixa), INFORMED (extrato/valor manual), MARKET_PRICE (cotas × preço informado). */
  source: 'ESTIMATED' | 'INFORMED' | 'MARKET_PRICE' | 'NONE';
  valueDate: string | null;
  stale: boolean;
  missingRates: number;
  ratesUpTo: string | null;
  quantity: number | null;
  unitPrice: number | null;
}

/**
 * Valor do investimento numa data, pelo motor adequado ao produto:
 *  - renda fixa: parte do último valor informado (ou do primeiro aporte) e aplica o indexador;
 *  - mercado (ações, ETFs, fundos): cotas × último preço informado — nunca inventa cotação;
 *  - manual: último valor informado.
 */
export function valueAt(inv: Investment, moves: Move[], date: string, series: RateSeries | null): Valuation {
  const upTo = moves.filter((m) => formatDate(m.date) <= date).sort((a, b) => a.date.getTime() - b.date.getTime());
  const none: Valuation = { valueCents: 0, source: 'NONE', valueDate: null, stale: false, missingRates: 0, ratesUpTo: null, quantity: null, unitPrice: null };
  if (upTo.length === 0) return none;
  const lastUpdate = upTo.filter((m) => m.kind === 'VALUE_UPDATE').at(-1);

  if (inv.indexer === 'MARKET') {
    let qty = 0;
    let price: number | null = null;
    let priceDate: string | null = null;
    for (const m of upTo) {
      const q = m.quantity ? Number(m.quantity) : 0;
      if (m.kind === 'CONTRIBUTION') qty += q;
      if (m.kind === 'REDEMPTION') qty -= q;
      if (m.unitPrice !== null) {
        price = Number(m.unitPrice);
        priceDate = formatDate(m.date);
      }
    }
    if (price === null) return { ...none, quantity: qty };
    return {
      valueCents: Math.round(qty * price),
      source: 'MARKET_PRICE',
      valueDate: priceDate,
      stale: days(priceDate!, date) > STALE_PRICE_DAYS,
      missingRates: 0,
      ratesUpTo: null,
      quantity: qty,
      unitPrice: price,
    };
  }

  const startIdx = lastUpdate ? upTo.lastIndexOf(lastUpdate) : -1;
  const start = lastUpdate ? toCents(lastUpdate.amountCents) : 0;
  const from = lastUpdate ? formatDate(lastUpdate.date) : formatDate(upTo[0]!.date);
  const flows: Flow[] = upTo
    .slice(startIdx + 1)
    .filter((m) => m.kind === 'CONTRIBUTION' || m.kind === 'REDEMPTION')
    .map((m) => ({ date: formatDate(m.date), cents: signedCash(m) }));
  // Fluxos do próprio dia de partida (1º aporte, ou resgate no dia do valor informado) entram no saldo inicial.
  const sameDay = flows.filter((f) => f.date === from).reduce((s, f) => s + f.cents, 0);
  const rest = flows.filter((f) => f.date !== from);
  const startCents = start + sameDay;

  if (inv.indexer === 'MANUAL' || !isFixed(inv.indexer)) {
    const value = startCents + rest.reduce((s, f) => s + f.cents, 0);
    return {
      ...none,
      valueCents: value,
      source: lastUpdate ? 'INFORMED' : 'NONE',
      valueDate: lastUpdate ? from : null,
      stale: lastUpdate ? days(from, date) > STALE_MANUAL_DAYS : true,
    };
  }
  const r = accrue(startCents, from, date, rest, { engine: inv.indexer, rateBps: inv.rateBps, costsBps: inv.costsBps }, series ?? { daily: new Map() });
  if (!r) {
    // Sem índice disponível: mostra o último valor conhecido e marca como desatualizado.
    return { ...none, valueCents: startCents + rest.reduce((s, f) => s + f.cents, 0), source: lastUpdate ? 'INFORMED' : 'NONE', valueDate: lastUpdate ? from : null, stale: true };
  }
  const exact = lastUpdate && from === date && rest.length === 0;
  return {
    valueCents: r.balanceCents,
    source: exact ? 'INFORMED' : 'ESTIMATED',
    valueDate: exact ? from : date,
    stale: r.missingRates > 5,
    missingRates: r.missingRates,
    ratesUpTo: r.ratesUpTo,
    quantity: null,
    unitPrice: null,
  };
}

async function seriesFor(inv: Investment, from: string, to: string) {
  if (!isFixed(inv.indexer)) return null;
  const index = SERIES_OF[inv.indexer];
  return index ? loadSeries(index, from, to) : { daily: new Map<string, number>() };
}

async function movesOf(id: string, db: Tx | typeof prisma = prisma) {
  return db.investmentMovement.findMany({ where: { investmentId: id, deletedAt: null }, orderBy: [{ date: 'asc' }, { createdAt: 'asc' }] });
}

async function getRow(entityId: string, id: string, db: Tx | typeof prisma = prisma) {
  const inv = await db.investment.findFirst({ where: { id, entityId } });
  if (!inv) throw notFound('Investimento não encontrado');
  return inv;
}

export async function summarize(inv: Investment, moves: InvestmentMovement[], today = todayISO()) {
  const first = moves[0] ? formatDate(moves[0].date) : today;
  const v = valueAt(inv, moves, today, await seriesFor(inv, first, today));
  const flows: Flow[] = moves
    .filter((m) => m.kind === 'CONTRIBUTION' || m.kind === 'REDEMPTION')
    .map((m) => ({ date: formatDate(m.date), cents: signedCash(m) }));
  const principal = flows.reduce((s, f) => s + f.cents, 0);
  const contributed = flows.filter((f) => f.cents > 0).reduce((s, f) => s + f.cents, 0);
  const redeemed = -flows.filter((f) => f.cents < 0).reduce((s, f) => s + f.cents, 0);
  const incomeReceived = moves.filter((m) => m.kind === 'INCOME').reduce((s, m) => s + toCents(m.amountCents), 0);
  const gain = v.valueCents - principal;
  const tax = estimateTax(inv.taxation, openLots(flows), gain, today);
  const maturity = inv.maturityDate ? formatDate(inv.maturityDate) : null;
  return {
    id: inv.id,
    entityId: inv.entityId,
    kind: inv.kind,
    kindLabel: KIND_LABELS[inv.kind],
    name: inv.name,
    institution: inv.institution,
    ticker: inv.ticker,
    indexer: inv.indexer,
    rateBps: inv.rateBps,
    maturityDate: maturity,
    daysToMaturity: maturity ? days(today, maturity) : null,
    liquidity: inv.liquidity,
    liquidityDays: inv.liquidityDays,
    costsBps: inv.costsBps,
    taxation: inv.taxation,
    status: inv.status,
    notes: inv.notes,
    firstDate: moves[0] ? first : null,
    contributedCents: contributed,
    redeemedCents: redeemed,
    /** Principal aplicado líquido (aportes − resgates). */
    principalCents: principal,
    valueCents: v.valueCents,
    valueSource: v.source,
    valueDate: v.valueDate,
    stale: v.stale,
    missingRates: v.missingRates,
    ratesUpTo: v.ratesUpTo,
    quantity: v.quantity,
    unitPrice: v.unitPrice,
    gainCents: gain,
    incomeReceivedCents: incomeReceived,
    /** Retorno sobre o principal (pontos-base), incluindo proventos recebidos. */
    returnBps: principal > 0 ? Math.round(((gain + incomeReceived) * 10000) / principal) : null,
    taxEstimatedCents: tax.iofCents + tax.irCents,
    netEstimatedCents: v.valueCents - tax.iofCents - tax.irCents,
  };
}

export async function listInvestments(entityId: string, includeClosed = false) {
  const rows = await prisma.investment.findMany({
    where: { entityId, ...(includeClosed ? {} : { status: 'ACTIVE' }) },
    include: { movements: { where: { deletedAt: null }, orderBy: [{ date: 'asc' }, { createdAt: 'asc' }] } },
    orderBy: { createdAt: 'asc' },
  });
  const today = todayISO();
  return Promise.all(rows.map((r) => summarize(r, r.movements, today)));
}

/** Valor de mercado/estimado de cada mês (fim do mês) para o gráfico de evolução. */
export async function investmentHistory(inv: Investment, moves: InvestmentMovement[], months = 12) {
  const today = todayISO();
  if (moves.length === 0) return [];
  const first = formatDate(moves[0]!.date);
  const series = await seriesFor(inv, first, today);
  const out = [];
  for (let k = months - 1; k >= 0; k--) {
    const d = new Date(Date.UTC(Number(today.slice(0, 4)), Number(today.slice(5, 7)) - 1 - k + 1, 0));
    const end = k === 0 ? today : d.toISOString().slice(0, 10);
    if (end < first) continue;
    const v = valueAt(inv, moves, end, series);
    const principal = moves.filter((m) => formatDate(m.date) <= end).reduce((s, m) => s + signedCash(m), 0);
    out.push({ date: end, valueCents: v.valueCents, principalCents: principal });
  }
  return out;
}

export async function getInvestment(entityId: string, id: string) {
  const inv = await getRow(entityId, id);
  const moves = await movesOf(id);
  const accounts = await prisma.account.findMany({ where: { id: { in: moves.map((m) => m.accountId).filter((x): x is string => !!x) } } });
  return {
    ...(await summarize(inv, moves)),
    history: await investmentHistory(inv, moves),
    movements: [...moves].reverse().map((m) => ({
      id: m.id,
      kind: m.kind,
      date: formatDate(m.date),
      amountCents: toCents(m.amountCents),
      quantity: m.quantity ? Number(m.quantity) : null,
      unitPrice: m.unitPrice ? Number(m.unitPrice) : null,
      account: accounts.find((a) => a.id === m.accountId)?.name ?? null,
    })),
  };
}

async function cashAccount(db: Tx, entityId: string, accountId: string, date: string) {
  const a = await db.account.findFirst({ where: { id: accountId, entityId, archivedAt: null, type: cashAccountType } });
  if (!a) throw unprocessable('INVALID_ACCOUNT', 'Conta não pertence a este ambiente');
  if (date < formatDate(a.referenceDate)) throw unprocessable('SETTLED_BEFORE_REFERENCE', 'Data anterior à data de referência da conta');
  return a;
}

const DEFAULT_TAX = { LCI: 'EXEMPT', LCA: 'EXEMPT', STOCK: 'STOCKS', ETF: 'STOCKS' } as const;

/**
 * Registra uma movimentação. Aporte e resgate com conta geram a perna de caixa (CONTRIBUTION/REDEMPTION,
 * que não são receita nem despesa); sem conta, registram posição anterior ao uso da hoink.
 * Proventos (INCOME) entram como receita na conta.
 */
async function addMovement(
  db: Tx,
  ctx: Ctx,
  inv: Investment,
  kind: InvestmentMovement['kind'],
  input: { date: string; amountCents: number; accountId?: string | null; quantity?: number | null; unitPrice?: number | null },
) {
  let transactionId: string | null = null;
  if (input.accountId && kind !== 'VALUE_UPDATE') {
    await cashAccount(db, ctx.entityId, input.accountId, input.date);
    const type = kind === 'CONTRIBUTION' ? 'CONTRIBUTION' : kind === 'REDEMPTION' ? 'REDEMPTION' : 'INCOME';
    const label = { CONTRIBUTION: 'Aporte', REDEMPTION: 'Resgate', INCOME: 'Proventos' }[kind];
    let categoryId: string | null = null;
    if (kind === 'INCOME') {
      categoryId = (
        await db.category.upsert({
          where: { entityId_kind_name: { entityId: ctx.entityId, kind: 'INCOME', name: 'Rendimentos' } },
          create: { entityId: ctx.entityId, kind: 'INCOME', name: 'Rendimentos', icon: 'trending_up', isSystem: true },
          update: {},
        })
      ).id;
    }
    const t = await db.transaction.create({
      data: {
        entityId: ctx.entityId,
        accountId: input.accountId,
        categoryId,
        type,
        direction: kind === 'CONTRIBUTION' ? 'OUT' : 'IN',
        amountCents: BigInt(input.amountCents),
        settledAmountCents: BigInt(input.amountCents),
        status: 'SETTLED',
        competenceDate: parseDate(input.date),
        settledDate: parseDate(input.date),
        description: `${label} ${inv.name}`,
        counterparty: inv.institution,
        createdById: ctx.userId,
      },
    });
    await addSettlement(db, t.id, input.amountCents, input.date, ctx.userId);
    transactionId = t.id;
  }
  return db.investmentMovement.create({
    data: {
      investmentId: inv.id,
      kind,
      date: parseDate(input.date),
      amountCents: BigInt(input.amountCents),
      quantity: input.quantity ? new Prisma.Decimal(input.quantity) : null,
      unitPrice: input.unitPrice !== null && input.unitPrice !== undefined ? new Prisma.Decimal(input.unitPrice) : null,
      accountId: transactionId ? input.accountId : null,
      transactionId,
      createdById: ctx.userId,
    },
  });
}

export async function createInvestment(ctx: Ctx, input: z.infer<typeof investmentCreateSchema>) {
  const id = await prisma.$transaction(async (tx) => {
    const inv = await tx.investment.create({
      data: {
        entityId: ctx.entityId,
        kind: input.kind,
        name: input.name,
        institution: input.institution ?? null,
        ticker: input.ticker ? input.ticker.toUpperCase() : null,
        indexer: input.indexer,
        rateBps: input.rateBps,
        maturityDate: input.maturityDate ? parseDate(input.maturityDate) : null,
        liquidity: input.liquidity,
        liquidityDays: input.liquidityDays,
        costsBps: input.costsBps,
        taxation: input.taxation ?? DEFAULT_TAX[input.kind as keyof typeof DEFAULT_TAX] ?? 'REGRESSIVE',
        notes: input.notes ?? null,
        createdById: ctx.userId,
      },
    });
    if (input.initial) {
      const q = input.initial.quantity;
      const unitPrice = inv.indexer === 'MARKET' && q ? input.initial.amountCents / q : null;
      await addMovement(tx, ctx, inv, 'CONTRIBUTION', { ...input.initial, unitPrice });
    }
    await audit(tx, { ...ctx, action: 'create', resourceType: 'investment', resourceId: inv.id, after: inv });
    return inv.id;
  });
  recordEvent('investment.created', { entityId: ctx.entityId, kind: input.kind });
  return getInvestment(ctx.entityId, id);
}

export async function updateInvestment(ctx: Ctx, id: string, input: z.infer<typeof investmentUpdateSchema>) {
  const before = await getRow(ctx.entityId, id);
  await prisma.$transaction(async (tx) => {
    const after = await tx.investment.update({
      where: { id },
      data: {
        name: input.name,
        institution: input.institution,
        ticker: input.ticker,
        rateBps: input.rateBps,
        maturityDate: input.maturityDate === undefined ? undefined : input.maturityDate ? parseDate(input.maturityDate) : null,
        liquidity: input.liquidity,
        liquidityDays: input.liquidityDays,
        costsBps: input.costsBps,
        taxation: input.taxation,
        notes: input.notes,
        status: input.status,
      },
    });
    await audit(tx, { ...ctx, action: 'update', resourceType: 'investment', resourceId: id, before, after });
  });
  return getInvestment(ctx.entityId, id);
}

export async function move(
  ctx: Ctx,
  id: string,
  kind: 'CONTRIBUTION' | 'REDEMPTION' | 'INCOME',
  input: z.infer<typeof investmentMoveSchema>,
) {
  const inv = await getRow(ctx.entityId, id);
  if (inv.status !== 'ACTIVE') throw unprocessable('INVESTMENT_CLOSED', 'Investimento encerrado');
  if (inv.indexer === 'MARKET' && kind !== 'INCOME' && !input.quantity) {
    throw unprocessable('QUANTITY_REQUIRED', 'Informe a quantidade de cotas/ações');
  }
  if (kind === 'REDEMPTION') {
    const s = await summarize(inv, await movesOf(id));
    if (inv.indexer === 'MARKET' ? (input.quantity ?? 0) > (s.quantity ?? 0) + 1e-9 : input.amountCents > s.valueCents) {
      throw unprocessable('INSUFFICIENT_POSITION', 'Resgate maior que a posição atual');
    }
  }
  const unitPrice = inv.indexer === 'MARKET' && input.quantity ? input.amountCents / input.quantity : null;
  await prisma.$transaction(async (tx) => {
    const m = await addMovement(tx, ctx, inv, kind, { ...input, unitPrice });
    await audit(tx, { ...ctx, action: kind.toLowerCase(), resourceType: 'investment', resourceId: id, after: m });
  });
  return getInvestment(ctx.entityId, id);
}

/** Valor atualizado (extrato) ou cotação informada. Não movimenta caixa. */
export async function updateValue(ctx: Ctx, id: string, input: z.infer<typeof investmentValueSchema>) {
  const inv = await getRow(ctx.entityId, id);
  if (inv.indexer === 'MARKET' && input.unitPriceCents === undefined) {
    throw unprocessable('PRICE_REQUIRED', 'Informe o preço da cota/ação');
  }
  if (inv.indexer !== 'MARKET' && input.valueCents === undefined) throw unprocessable('VALUE_REQUIRED', 'Informe o valor atualizado');
  await prisma.$transaction(async (tx) => {
    const m = await tx.investmentMovement.create({
      data: {
        investmentId: id,
        kind: 'VALUE_UPDATE',
        date: parseDate(input.date),
        amountCents: BigInt(input.valueCents ?? 0),
        unitPrice: input.unitPriceCents !== undefined ? new Prisma.Decimal(input.unitPriceCents) : null,
        createdById: ctx.userId,
      },
    });
    await audit(tx, { ...ctx, action: 'value_update', resourceType: 'investment', resourceId: id, after: m });
  });
  return getInvestment(ctx.entityId, id);
}

/** Exclui (logicamente) uma movimentação e sua perna de caixa. */
export async function deleteMovement(ctx: Ctx, id: string, movementId: string) {
  await getRow(ctx.entityId, id);
  const m = await prisma.investmentMovement.findFirst({ where: { id: movementId, investmentId: id, deletedAt: null } });
  if (!m) throw notFound('Movimentação não encontrada');
  await prisma.$transaction(async (tx) => {
    const now = new Date();
    await tx.investmentMovement.update({ where: { id: movementId }, data: { deletedAt: now } });
    if (m.transactionId) await tx.transaction.update({ where: { id: m.transactionId }, data: { deletedAt: now } });
    await audit(tx, { ...ctx, action: 'delete_movement', resourceType: 'investment', resourceId: id, before: m });
  });
  return getInvestment(ctx.entityId, id);
}

/** Valor da carteira numa data (para o patrimônio e seus snapshots). */
export async function portfolioValueAt(entityId: string, date: string) {
  const rows = await prisma.investment.findMany({
    where: { entityId },
    include: { movements: { where: { deletedAt: null }, orderBy: [{ date: 'asc' }, { createdAt: 'asc' }] } },
  });
  let total = 0;
  for (const inv of rows) {
    if (inv.movements.length === 0) continue;
    const first = formatDate(inv.movements[0]!.date);
    if (first > date) continue;
    total += valueAt(inv, inv.movements, date, await seriesFor(inv, first, date)).valueCents;
  }
  return total;
}
