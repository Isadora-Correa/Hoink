import { Prisma } from '@prisma/client';
import { env } from '../../config/env';
import { applyShare } from '../../domain/consolidation';
import { flowTotals, type FlowGroup } from '../../domain/flows';
import { formatDate, monthRange, parseDate, shiftMonth, todayISO } from '../../lib/dates';
import { unprocessable } from '../../lib/errors';
import { toCents } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { payables } from '../contacts/contacts.service';
import { listDebts } from '../debts/debts.service';
import { listInvestments } from '../investments/investments.service';
import { history as patrimonyHistory } from '../patrimony/patrimony.service';
import { listPiggies } from '../piggy/piggy.service';
import { cashflow, listBudgets } from '../planning/planning.service';
import { ensureGenerated } from '../recurring/recurring.service';
import { settledAggregate } from '../settlements/settlements';
import { REPORT_TYPES, type Report, type ReportType, type Section } from './report.model';

export interface Scope {
  label: string;
  entities: { id: string; name: string; shareBps: number }[];
}

export interface ReportQuery {
  from: string;
  to: string;
  categoryId?: string;
}

/** Período a partir de um atalho (mês, trimestre, ano) ou datas personalizadas. */
export function resolvePeriod(q: { period?: 'month' | 'quarter' | 'year' | 'custom'; ref?: string; from?: string; to?: string }) {
  const ref = q.ref ?? todayISO().slice(0, 7);
  const [y, m] = ref.split('-').map(Number) as [number, number];
  let from: string;
  let to: string;
  let label: string;
  switch (q.period ?? (q.from && q.to ? 'custom' : 'month')) {
    case 'quarter': {
      const qStart = Math.floor((m - 1) / 3) * 3 + 1;
      const start = `${y}-${String(qStart).padStart(2, '0')}`;
      from = monthRange(start).from;
      to = monthRange(shiftMonth(start, 2)).to;
      label = `${Math.floor((m - 1) / 3) + 1}º trimestre de ${y}`;
      break;
    }
    case 'year':
      from = `${y}-01-01`;
      to = `${y}-12-31`;
      label = `Ano de ${y}`;
      break;
    case 'custom':
      if (!q.from || !q.to) throw unprocessable('PERIOD_REQUIRED', 'Informe o início e o fim do período');
      from = q.from;
      to = q.to;
      label = `${from.split('-').reverse().join('/')} a ${to.split('-').reverse().join('/')}`;
      break;
    default: {
      const r = monthRange(ref);
      from = r.from;
      to = r.to;
      label = new Date(`${ref}-15T12:00:00Z`).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric', timeZone: 'UTC' });
      label = label[0]!.toUpperCase() + label.slice(1);
    }
  }
  if (from > to) throw unprocessable('INVALID_PERIOD', 'O início deve ser antes do fim');
  if (parseDate(to).getTime() - parseDate(from).getTime() > 5 * 366 * 86_400_000) {
    throw unprocessable('PERIOD_TOO_LONG', 'Período máximo de 5 anos');
  }
  return { from, to, label };
}

const months = (from: string, to: string) => {
  const out: string[] = [];
  for (let m = from.slice(0, 7); m <= to.slice(0, 7); m = shiftMonth(m, 1)) out.push(m);
  return out;
};

const multi = (s: Scope) => s.entities.length > 1;
const ids = (s: Scope) => s.entities.map((e) => e.id);
const sum = <T>(xs: T[], f: (x: T) => number) => xs.reduce((a, x) => a + f(x), 0);

// ───────────── Construtores ─────────────

async function incomeExpense(s: Scope, q: ReportQuery): Promise<Section[]> {
  const byEntity = await Promise.all(
    s.entities.map(async (e) => ({ e, rows: await settledAggregate({ entityIds: [e.id], from: q.from, to: q.to }) })),
  );
  const cat = q.categoryId;
  const groups: FlowGroup[] = [];
  const perMonth = new Map<string, FlowGroup[]>(months(q.from, q.to).map((m) => [m, []]));
  const perCategory = new Map<string, { type: 'INCOME' | 'EXPENSE'; cents: number }>();
  for (const { e, rows } of byEntity) {
    for (const r of rows) {
      if (cat && r.categoryId !== cat) continue;
      const g = { type: r.type, direction: r.direction, cents: applyShare(r.cents, e.shareBps) };
      groups.push(g);
      perMonth.get(r.month)?.push(g);
      if (r.type === 'INCOME' || r.type === 'EXPENSE' || r.type === 'REFUND') {
        const key = r.categoryId ?? '';
        const signed = r.type === 'REFUND' ? (r.direction === 'IN' ? -g.cents : g.cents) : g.cents;
        const kind = r.type === 'INCOME' ? 'INCOME' : 'EXPENSE';
        const cur = perCategory.get(`${kind}:${key}`) ?? { type: kind, cents: 0 };
        cur.cents += signed;
        perCategory.set(`${kind}:${key}`, cur);
      }
    }
  }
  const t = flowTotals(groups);
  const cats = await prisma.category.findMany({
    where: { id: { in: [...perCategory.keys()].map((k) => k.split(':')[1]!).filter(Boolean) } },
  });
  const catName = (id: string) => cats.find((c) => c.id === id)?.name ?? 'Sem categoria';
  const catRows = [...perCategory.entries()]
    .map(([k, v]) => ({ tipo: v.type === 'INCOME' ? 'Receita' : 'Despesa', categoria: catName(k.split(':')[1]!), valor: v.cents }))
    .filter((r) => r.valor !== 0)
    .sort((a, b) => a.tipo.localeCompare(b.tipo) || b.valor - a.valor);
  return [
    {
      title: 'Resumo',
      columns: [
        { key: 'item', label: 'Item', type: 'text' },
        { key: 'valor', label: 'Valor (R$)', type: 'money' },
      ],
      rows: [
        { item: 'Receitas', valor: t.incomeCents },
        { item: 'Despesas (líquidas de reembolsos)', valor: t.expenseCents },
        { item: 'Resultado', valor: t.netCents },
        { item: 'Aportes em investimentos', valor: t.contributionsCents },
        { item: 'Resgates de investimentos', valor: t.redemptionsCents },
      ],
      note: 'Transferências entre contas e ambientes não são receita nem despesa.',
    },
    {
      title: 'Por categoria',
      columns: [
        { key: 'tipo', label: 'Tipo', type: 'text' },
        { key: 'categoria', label: 'Categoria', type: 'text' },
        { key: 'valor', label: 'Valor (R$)', type: 'money' },
      ],
      rows: catRows,
    },
    {
      title: 'Por mês',
      columns: [
        { key: 'mes', label: 'Mês', type: 'date' },
        { key: 'receitas', label: 'Receitas (R$)', type: 'money' },
        { key: 'despesas', label: 'Despesas (R$)', type: 'money' },
        { key: 'resultado', label: 'Resultado (R$)', type: 'money' },
      ],
      rows: [...perMonth.entries()].map(([m, g]) => {
        const x = flowTotals(g);
        return { mes: m, receitas: x.incomeCents, despesas: x.expenseCents, resultado: x.netCents };
      }),
      totals: { mes: 'Total', receitas: t.incomeCents, despesas: t.expenseCents, resultado: t.netCents },
    },
  ];
}

async function cashFlowReport(s: Scope, q: ReportQuery): Promise<Section[]> {
  const rows = (
    await Promise.all(s.entities.map(async (e) => (await settledAggregate({ entityIds: [e.id], from: q.from, to: q.to })).map((r) => ({ ...r, cents: applyShare(r.cents, e.shareBps) }))))
  ).flat();
  const monthly = months(q.from, q.to).map((m) => {
    const g = rows.filter((r) => r.month === m);
    // Transferências entre ambientes do próprio usuário se anulam no consolidado.
    const visible = multi(s) ? g.filter((r) => r.type !== 'TRANSFER') : g;
    const inCents = sum(visible.filter((r) => r.direction === 'IN'), (r) => r.cents);
    const outCents = sum(visible.filter((r) => r.direction === 'OUT'), (r) => r.cents);
    return { mes: m, entradas: inCents, saidas: outCents, variacao: inCents - outCents };
  });
  const cf = await cashflow(s.entities.map((e) => ({ entityId: e.id, shareBps: e.shareBps })));
  return [
    {
      title: 'Realizado por mês',
      columns: [
        { key: 'mes', label: 'Mês', type: 'date' },
        { key: 'entradas', label: 'Entradas (R$)', type: 'money' },
        { key: 'saidas', label: 'Saídas (R$)', type: 'money' },
        { key: 'variacao', label: 'Variação (R$)', type: 'money' },
      ],
      rows: monthly,
      totals: { mes: 'Total', entradas: sum(monthly, (m) => m.entradas), saidas: sum(monthly, (m) => m.saidas), variacao: sum(monthly, (m) => m.variacao) },
    },
    {
      title: 'Projeção a partir de hoje',
      columns: [
        { key: 'horizonte', label: 'Horizonte', type: 'text' },
        { key: 'recConf', label: 'Receitas confirmadas', type: 'money' },
        { key: 'recPrev', label: 'Receitas previstas', type: 'money' },
        { key: 'despConf', label: 'Despesas confirmadas', type: 'money' },
        { key: 'despPrev', label: 'Despesas previstas', type: 'money' },
        { key: 'saldo', label: 'Saldo projetado', type: 'money' },
      ],
      rows: cf.horizons.map((h) => ({
        horizonte: `${h.days} dias`,
        recConf: h.incomeConfirmedCents,
        recPrev: h.incomePlannedCents,
        despConf: h.expenseConfirmedCents,
        despPrev: h.expensePlannedCents,
        saldo: h.endBalanceProjectedCents,
      })),
      note: `Saldo inicial em contas: ${(cf.startBalanceCents / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })}. Previstos são estimativas.`,
    },
  ];
}

async function clients(s: Scope, q: ReportQuery): Promise<Section[]> {
  const contacts = await prisma.contact.findMany({ where: { entityId: { in: ids(s) }, kind: { in: ['CLIENT', 'BOTH'] } }, include: { entity: true } });
  const cids = contacts.map((c) => c.id);
  const billed = cids.length
    ? await prisma.transaction.groupBy({
        by: ['contactId'],
        where: { contactId: { in: cids }, type: 'INCOME', deletedAt: null, status: { not: 'CANCELED' }, competenceDate: { gte: parseDate(q.from), lte: parseDate(q.to) } },
        _sum: { amountCents: true },
      })
    : [];
  const received = cids.length
    ? await prisma.$queryRaw<{ contact_id: string; cents: bigint }[]>`
        SELECT t.contact_id, SUM(s.amount_cents)::bigint AS cents
        FROM transaction_settlements s JOIN transactions t ON t.id = s.transaction_id
        WHERE t.contact_id IN (${Prisma.join(cids.map((id) => Prisma.sql`${id}::uuid`))})
          AND t.type = 'INCOME' AND t.deleted_at IS NULL AND s.date BETWEEN ${q.from}::date AND ${q.to}::date
        GROUP BY 1`
    : [];
  const today = todayISO();
  const open = cids.length
    ? await prisma.transaction.findMany({
        where: { contactId: { in: cids }, type: 'INCOME', deletedAt: null, status: { in: ['PLANNED', 'PENDING', 'PARTIAL'] } },
        select: { contactId: true, amountCents: true, settledAmountCents: true, dueDate: true, competenceDate: true },
      })
    : [];
  const rows = contacts
    .map((c) => {
      const mine = open.filter((o) => o.contactId === c.id);
      const remaining = (o: (typeof open)[number]) => toCents(o.amountCents) - toCents(o.settledAmountCents);
      return {
        cliente: c.name,
        ...(multi(s) ? { ambiente: c.entity.name } : {}),
        faturado: toCents(billed.find((b) => b.contactId === c.id)?._sum.amountCents ?? 0n),
        recebido: toCents(received.find((r) => r.contact_id === c.id)?.cents ?? 0n),
        aberto: sum(mine, remaining),
        atrasado: sum(mine.filter((o) => formatDate(o.dueDate ?? o.competenceDate) < today), remaining),
      };
    })
    .filter((r) => r.faturado || r.recebido || r.aberto)
    .sort((a, b) => b.recebido - a.recebido);
  return [
    {
      title: 'Faturado × recebido por cliente',
      columns: [
        { key: 'cliente', label: 'Cliente', type: 'text' },
        ...(multi(s) ? [{ key: 'ambiente', label: 'Ambiente', type: 'text' as const }] : []),
        { key: 'faturado', label: 'Faturado no período', type: 'money' },
        { key: 'recebido', label: 'Recebido no período', type: 'money' },
        { key: 'aberto', label: 'Em aberto hoje', type: 'money' },
        { key: 'atrasado', label: 'Em atraso hoje', type: 'money' },
      ],
      rows,
      totals: { cliente: 'Total', faturado: sum(rows, (r) => r.faturado), recebido: sum(rows, (r) => r.recebido), aberto: sum(rows, (r) => r.aberto), atrasado: sum(rows, (r) => r.atrasado) },
    },
  ];
}

async function openItems(s: Scope, q: ReportQuery, kind: 'receivable' | 'payable'): Promise<Section[]> {
  const today = todayISO();
  const page = await payables(ids(s), { kind, status: 'open' });
  const names = new Map(s.entities.map((e) => [e.id, e.name]));
  const items = page.data.filter((t) => {
    const due = t.dueDate ?? t.competenceDate;
    if (q.categoryId && t.category?.id !== q.categoryId) return false;
    return due < today || (due >= q.from && due <= q.to);
  });
  const rows = items.map((t) => ({
    vencimento: t.dueDate ?? t.competenceDate,
    descricao: t.description,
    contraparte: t.contact?.name ?? t.counterparty ?? '',
    ...(multi(s) ? { ambiente: names.get(t.entityId) ?? '' } : {}),
    situacao: t.effectiveStatus === 'OVERDUE' ? 'Atrasado' : t.status === 'PARTIAL' ? 'Parcial' : t.status === 'PLANNED' ? 'Previsto' : 'Pendente',
    valor: t.amountCents - t.settledAmountCents,
  }));
  if (kind === 'payable') {
    for (const inv of page.cardInvoices) {
      rows.push({
        vencimento: inv.dueDate,
        descricao: `Fatura ${inv.cardName} ${inv.month.slice(5)}/${inv.month.slice(0, 4)}`,
        contraparte: inv.cardName,
        ...(multi(s) ? { ambiente: names.get(inv.entityId) ?? '' } : {}),
        situacao: inv.dueDate < today ? 'Atrasado' : 'Fatura fechada',
        valor: inv.remainingCents,
      });
    }
  }
  rows.sort((a, b) => String(a.vencimento).localeCompare(String(b.vencimento)));
  return [
    {
      title: kind === 'receivable' ? 'A receber' : 'A pagar',
      columns: [
        { key: 'vencimento', label: 'Vencimento', type: 'date' },
        { key: 'descricao', label: 'Descrição', type: 'text' },
        { key: 'contraparte', label: kind === 'receivable' ? 'Cliente' : 'Fornecedor/credor', type: 'text' },
        ...(multi(s) ? [{ key: 'ambiente', label: 'Ambiente', type: 'text' as const }] : []),
        { key: 'situacao', label: 'Situação', type: 'text' },
        { key: 'valor', label: 'Valor em aberto', type: 'money' },
      ],
      rows,
      totals: { vencimento: 'Total', valor: sum(rows, (r) => r.valor) },
      note: 'Inclui itens em atraso e os que vencem no período.',
    },
  ];
}

async function perEntity<T>(s: Scope, fn: (entityId: string) => Promise<T[]>) {
  return (await Promise.all(s.entities.map(async (e) => (await fn(e.id)).map((x) => ({ x, entity: e.name }))))).flat();
}

async function debtsReport(s: Scope): Promise<Section[]> {
  const list = await perEntity(s, (id) => listDebts(id));
  const rows = list.map(({ x: d, entity }) => ({
    divida: d.name,
    ...(multi(s) ? { ambiente: entity } : {}),
    credor: d.creditor ?? '',
    sistema: d.system,
    taxa: d.monthlyRatePpm / 100,
    financiado: d.principalCents,
    saldo: d.summary.outstandingPrincipalCents,
    jurosPagos: d.summary.paidInterestCents,
    parcelas: `${d.summary.paidInstallments}/${d.summary.paidInstallments + d.summary.remainingInstallments}`,
    proxima: d.summary.nextInstallment?.dueDate ?? '',
  }));
  return [
    {
      title: 'Dívidas ativas',
      columns: [
        { key: 'divida', label: 'Dívida', type: 'text' },
        ...(multi(s) ? [{ key: 'ambiente', label: 'Ambiente', type: 'text' as const }] : []),
        { key: 'credor', label: 'Credor', type: 'text' },
        { key: 'sistema', label: 'Sistema', type: 'text' },
        { key: 'taxa', label: 'Juros a.m.', type: 'percent' },
        { key: 'financiado', label: 'Financiado', type: 'money' },
        { key: 'saldo', label: 'Saldo devedor', type: 'money' },
        { key: 'jurosPagos', label: 'Juros pagos', type: 'money' },
        { key: 'parcelas', label: 'Parcelas pagas', type: 'text' },
        { key: 'proxima', label: 'Próximo vencimento', type: 'date' },
      ],
      rows,
      totals: { divida: 'Total', financiado: sum(rows, (r) => r.financiado), saldo: sum(rows, (r) => r.saldo), jurosPagos: sum(rows, (r) => r.jurosPagos) },
    },
  ];
}

async function piggyReport(s: Scope, q: ReportQuery): Promise<Section[]> {
  const list = await perEntity(s, (id) => listPiggies(id, true));
  const piggyIds = list.map(({ x }) => x.id);
  const moves = piggyIds.length
    ? await prisma.$queryRaw<{ account_id: string; type: string; direction: string; cents: bigint }[]>`
        SELECT t.account_id, t.type::text AS type, t.direction::text AS direction, SUM(s.amount_cents)::bigint AS cents
        FROM transaction_settlements s JOIN transactions t ON t.id = s.transaction_id
        WHERE t.account_id IN (${Prisma.join(piggyIds.map((id) => Prisma.sql`${id}::uuid`))})
          AND t.deleted_at IS NULL AND s.date BETWEEN ${q.from}::date AND ${q.to}::date
        GROUP BY 1, 2, 3`
    : [];
  const of = (id: string, f: (m: (typeof moves)[number]) => boolean) => sum(moves.filter((m) => m.account_id === id && f(m)), (m) => toCents(m.cents));
  const rows = list.map(({ x: p, entity }) => ({
    cofrinho: p.name,
    ...(multi(s) ? { ambiente: entity } : {}),
    tipo: { RESERVE: 'Reserva', WISH: 'Desejo', GOAL: 'Meta' }[p.kind],
    guardado: of(p.id, (m) => m.type === 'TRANSFER' && m.direction === 'IN'),
    retirado: of(p.id, (m) => m.type === 'TRANSFER' && m.direction === 'OUT'),
    rendimento: of(p.id, (m) => m.type === 'INCOME'),
    saldo: p.balanceCents,
    meta: p.goalCents,
    progresso: p.progressBps,
  }));
  return [
    {
      title: 'Cofrinhos',
      columns: [
        { key: 'cofrinho', label: 'Cofrinho', type: 'text' },
        ...(multi(s) ? [{ key: 'ambiente', label: 'Ambiente', type: 'text' as const }] : []),
        { key: 'tipo', label: 'Tipo', type: 'text' },
        { key: 'guardado', label: 'Guardado no período', type: 'money' },
        { key: 'retirado', label: 'Retirado no período', type: 'money' },
        { key: 'rendimento', label: 'Rendimento confirmado no período', type: 'money' },
        { key: 'saldo', label: 'Saldo atual', type: 'money' },
        { key: 'meta', label: 'Meta', type: 'money' },
        { key: 'progresso', label: 'Progresso', type: 'percent' },
      ],
      rows,
      totals: { cofrinho: 'Total', guardado: sum(rows, (r) => r.guardado), retirado: sum(rows, (r) => r.retirado), rendimento: sum(rows, (r) => r.rendimento), saldo: sum(rows, (r) => r.saldo) },
    },
  ];
}

async function investmentsReport(s: Scope): Promise<Section[]> {
  const list = await perEntity(s, (id) => listInvestments(id));
  const source = { ESTIMATED: 'Estimado', INFORMED: 'Informado', MARKET_PRICE: 'Cotação informada', NONE: '—' } as const;
  const rows = list.map(({ x: i, entity }) => ({
    investimento: i.name,
    ...(multi(s) ? { ambiente: entity } : {}),
    tipo: i.kindLabel,
    aplicado: i.principalCents,
    valor: i.valueCents,
    origem: `${source[i.valueSource]}${i.stale ? ' (desatualizado)' : ''}`,
    ganho: i.gainCents,
    proventos: i.incomeReceivedCents,
    retorno: i.returnBps,
    impostos: i.taxEstimatedCents,
    liquido: i.netEstimatedCents,
    vencimento: i.maturityDate ?? '',
  }));
  return [
    {
      title: 'Carteira',
      columns: [
        { key: 'investimento', label: 'Investimento', type: 'text' },
        ...(multi(s) ? [{ key: 'ambiente', label: 'Ambiente', type: 'text' as const }] : []),
        { key: 'tipo', label: 'Tipo', type: 'text' },
        { key: 'aplicado', label: 'Aplicado', type: 'money' },
        { key: 'valor', label: 'Valor atual', type: 'money' },
        { key: 'origem', label: 'Origem do valor', type: 'text' },
        { key: 'ganho', label: 'Ganho', type: 'money' },
        { key: 'proventos', label: 'Proventos', type: 'money' },
        { key: 'retorno', label: 'Retorno', type: 'percent' },
        { key: 'impostos', label: 'IR/IOF estimados', type: 'money' },
        { key: 'liquido', label: 'Líquido estimado', type: 'money' },
        { key: 'vencimento', label: 'Vencimento', type: 'date' },
      ],
      rows,
      totals: { investimento: 'Total', aplicado: sum(rows, (r) => r.aplicado), valor: sum(rows, (r) => r.valor), ganho: sum(rows, (r) => r.ganho), proventos: sum(rows, (r) => r.proventos), impostos: sum(rows, (r) => r.impostos), liquido: sum(rows, (r) => r.liquido) },
      note: 'Valores de renda fixa são estimados pelo índice (Banco Central); ações e fundos usam a última cotação informada.',
    },
  ];
}

async function yieldsReport(s: Scope, q: ReportQuery): Promise<Section[]> {
  const entityIds = ids(s);
  const piggyIncome = await prisma.$queryRaw<{ name: string; entity: string; cents: bigint }[]>`
    SELECT a.name, e.name AS entity, SUM(st.amount_cents)::bigint AS cents
    FROM transaction_settlements st
    JOIN transactions t ON t.id = st.transaction_id
    JOIN accounts a ON a.id = t.account_id
    JOIN financial_entities e ON e.id = a.entity_id
    WHERE a.entity_id IN (${Prisma.join(entityIds.map((id) => Prisma.sql`${id}::uuid`))})
      AND a.type = 'PIGGY_BANK' AND t.type = 'INCOME' AND t.deleted_at IS NULL
      AND st.date BETWEEN ${q.from}::date AND ${q.to}::date
    GROUP BY 1, 2`;
  const proventos = await prisma.investmentMovement.findMany({
    where: { kind: 'INCOME', deletedAt: null, date: { gte: parseDate(q.from), lte: parseDate(q.to) }, investment: { entityId: { in: entityIds } } },
    include: { investment: { include: { entity: true } } },
  });
  const effective = [
    ...piggyIncome.map((r) => ({ origem: `Cofrinho ${r.name}`, ...(multi(s) ? { ambiente: r.entity } : {}), tipo: 'Rendimento confirmado', valor: toCents(r.cents) })),
    ...proventos.map((m) => ({ origem: m.investment.name, ...(multi(s) ? { ambiente: m.investment.entity.name } : {}), tipo: 'Proventos', valor: toCents(m.amountCents) })),
  ];
  const estimated = [
    ...(await perEntity(s, (id) => listPiggies(id))).filter(({ x }) => x.estimatedYieldCents > 0).map(({ x, entity }) => ({ origem: `Cofrinho ${x.name}`, ...(multi(s) ? { ambiente: entity } : {}), valor: x.estimatedYieldCents })),
    ...(await perEntity(s, (id) => listInvestments(id))).map(({ x, entity }) => ({ origem: x.name, ...(multi(s) ? { ambiente: entity } : {}), valor: x.gainCents })),
  ];
  const cols = (withType: boolean) => [
    { key: 'origem', label: 'Origem', type: 'text' as const },
    ...(multi(s) ? [{ key: 'ambiente', label: 'Ambiente', type: 'text' as const }] : []),
    ...(withType ? [{ key: 'tipo', label: 'Tipo', type: 'text' as const }] : []),
    { key: 'valor', label: 'Valor (R$)', type: 'money' as const },
  ];
  return [
    { title: 'Rendimentos efetivos no período', columns: cols(true), rows: effective, totals: { origem: 'Total', valor: sum(effective, (r) => r.valor) } },
    {
      title: 'Rendimentos estimados (ainda não realizados)',
      columns: cols(false),
      rows: estimated,
      totals: { origem: 'Total', valor: sum(estimated, (r) => r.valor) },
      note: 'Estimativas pela taxa do índice ou pela última cotação; não são rendimento garantido (RN07).',
    },
  ];
}

async function patrimonyReport(s: Scope, q: ReportQuery): Promise<Section[]> {
  const span = Math.min(60, months(q.from, todayISO()).length);
  const hist = await Promise.all(s.entities.map(async (e) => ({ e, h: await patrimonyHistory(e.id, Math.max(1, span)) })));
  const wanted = months(q.from, q.to);
  const rows = wanted
    .map((m) => {
      let a = 0;
      let l = 0;
      let found = false;
      for (const { e, h } of hist) {
        const x = h.find((y) => y.month === m);
        if (!x) continue;
        found = true;
        a += applyShare(x.netWorth.assets.totalCents, e.shareBps);
        l += applyShare(x.netWorth.liabilities.totalCents, e.shareBps);
      }
      return found ? { mes: m, ativos: a, passivos: l, liquido: a - l } : null;
    })
    .filter((r): r is NonNullable<typeof r> => !!r);
  return [
    {
      title: 'Patrimônio no fim de cada mês',
      columns: [
        { key: 'mes', label: 'Mês', type: 'date' },
        { key: 'ativos', label: 'Ativos', type: 'money' },
        { key: 'passivos', label: 'Passivos', type: 'money' },
        { key: 'liquido', label: 'Patrimônio líquido', type: 'money' },
      ],
      rows,
      note: 'Meses encerrados vêm das fotografias mensais; o mês corrente é calculado agora.',
    },
  ];
}

async function budgetsReport(s: Scope, q: ReportQuery): Promise<Section[]> {
  const rows: Record<string, string | number | null>[] = [];
  for (const e of s.entities) {
    for (const m of months(q.from, q.to)) {
      const page = await listBudgets(e.id, m);
      for (const b of page.items) {
        if (q.categoryId && b.category.id !== q.categoryId) continue;
        rows.push({
          mes: m,
          ...(multi(s) ? { ambiente: e.name } : {}),
          categoria: b.category.name,
          limite: b.limitCents,
          gasto: b.spentCents,
          usado: b.usedBps,
          situacao: { OK: 'Dentro', WARNING: 'Atenção', EXCEEDED: 'Estourado' }[b.state],
        });
      }
    }
  }
  return [
    {
      title: 'Orçamentos por mês',
      columns: [
        { key: 'mes', label: 'Mês', type: 'date' },
        ...(multi(s) ? [{ key: 'ambiente', label: 'Ambiente', type: 'text' as const }] : []),
        { key: 'categoria', label: 'Categoria', type: 'text' },
        { key: 'limite', label: 'Limite', type: 'money' },
        { key: 'gasto', label: 'Gasto', type: 'money' },
        { key: 'usado', label: 'Usado', type: 'percent' },
        { key: 'situacao', label: 'Situação', type: 'text' },
      ],
      rows,
    },
  ];
}

export async function buildReport(type: ReportType, scope: Scope, q: ReportQuery & { label: string }): Promise<Report> {
  await ensureGenerated(ids(scope));
  const sections = await {
    'receitas-despesas': () => incomeExpense(scope, q),
    'fluxo-de-caixa': () => cashFlowReport(scope, q),
    clientes: () => clients(scope, q),
    'contas-a-receber': () => openItems(scope, q, 'receivable'),
    'contas-a-pagar': () => openItems(scope, q, 'payable'),
    dividas: () => debtsReport(scope),
    cofrinhos: () => piggyReport(scope, q),
    investimentos: () => investmentsReport(scope),
    rendimentos: () => yieldsReport(scope, q),
    patrimonio: () => patrimonyReport(scope, q),
    orcamentos: () => budgetsReport(scope, q),
  }[type]();
  const snapshot = ['dividas', 'investimentos'].includes(type);
  const now = new Date();
  return {
    type,
    title: REPORT_TYPES[type],
    scope: scope.label,
    period: { from: q.from, to: q.to, label: snapshot ? `Posição em ${todayISO().split('-').reverse().join('/')}` : q.label },
    generatedAt: now.toISOString(),
    sections,
    notes: [
      `Gerado em ${now.toLocaleString('pt-BR', { timeZone: env.APP_TIMEZONE })} pela hoink.`,
      multi(scope) ? 'Consolidado: valores ponderados pela sua participação em cada ambiente.' : '',
    ].filter(Boolean),
  };
}
