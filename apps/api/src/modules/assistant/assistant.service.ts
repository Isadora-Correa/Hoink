import Anthropic from '@anthropic-ai/sdk';
import { env } from '../../config/env';
import { changeBps, classify, investCapacity, SUGGESTED_QUESTIONS, type Intent } from '../../domain/assistant';
import { applyShare } from '../../domain/consolidation';
import { addDaysISO } from '../../domain/recurrence';
import { monthRange, shiftMonth, todayISO } from '../../lib/dates';
import { logger } from '../../lib/logger';
import { prisma } from '../../lib/prisma';
import { accountBalances } from '../accounts/balances';
import { payables } from '../contacts/contacts.service';
import { listDebts } from '../debts/debts.service';
import { marketStatus } from '../market/market.service';
import { history as patrimonyHistory } from '../patrimony/patrimony.service';
import { listPiggies } from '../piggy/piggy.service';
import { cashflow, listBudgets, reserve } from '../planning/planning.service';
import { settledAggregate } from '../settlements/settlements';
import { cashAccountType } from '../../lib/ledgers';

export interface Scope {
  label: string;
  entities: { id: string; name: string; kind: string; shareBps: number }[];
}

export type FactType = 'money' | 'text' | 'percent' | 'date' | 'number';
export interface Fact {
  label: string;
  value: string | number | null;
  type: FactType;
}
export interface Source {
  label: string;
  date: string | null;
}

export interface Answer {
  intent: Intent;
  question: string;
  title: string;
  /** Texto pronto, montado só com números calculados pelo backend. */
  text: string;
  facts: Fact[];
  sources: Source[];
  suggestions: string[];
  /** RULES: texto determinístico; AI: explicação gerada pela IA a partir dos mesmos fatos. */
  generatedBy: 'RULES' | 'AI';
}

const brl = (cents: number) => (cents / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const pct = (bps: number) => `${(bps / 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
const br = (iso: string) => iso.split('-').reverse().join('/');
const ids = (s: Scope) => s.entities.map((e) => e.id);
const today = () => todayISO();

// ───────────── 1 e 2: consulta + cálculos determinísticos, por pergunta ─────────────

type Partial = Omit<Answer, 'question' | 'suggestions' | 'generatedBy' | 'intent'>;

async function investCapacityAnswer(s: Scope): Promise<Partial> {
  const cf = await cashflow(s.entities.map((e) => ({ entityId: e.id, shareBps: e.shareBps })));
  const lowest30 = Math.min(...cf.points.slice(0, 31).map((p) => p.projectedCents));
  const personal = s.entities.find((e) => e.kind === 'PERSONAL') ?? s.entities[0]!;
  const r = await reserve(personal.id);
  const market = await marketStatus();
  const cdi = market.find((m) => m.index === 'CDI');
  const cdiMonthlyPpm = cdi?.annualPct ? Math.round((Math.pow(1 + cdi.annualPct / 100, 1 / 12) - 1) * 1_000_000) : null;
  // O dinheiro já separado como reserva de emergência (em conta de dinheiro) não é sobra para investir.
  const reserveCashAccounts = await prisma.account.findMany({
    where: { id: { in: r.accounts.map((a) => a.id) }, type: cashAccountType },
    select: { id: true },
  });
  const reserveCash = r.accounts.filter((a) => reserveCashAccounts.some((x) => x.id === a.id)).reduce((sum, a) => sum + Math.max(0, a.balanceCents), 0);
  const debts = (await Promise.all(s.entities.map((e) => listDebts(e.id)))).flat();
  const expensive = debts
    .filter((d) => cdiMonthlyPpm !== null && d.monthlyRatePpm > cdiMonthlyPpm && d.summary.outstandingPrincipalCents > 0)
    .map((d) => ({ name: d.name, monthlyRatePpm: d.monthlyRatePpm, outstandingCents: d.summary.outstandingPrincipalCents }));
  const c = investCapacity({
    balanceCents: cf.startBalanceCents - reserveCash,
    lowestProjected30Cents: lowest30 - reserveCash,
    avgMonthlyExpenseCents: r.avgMonthlyExpenseCents,
    reserveMissingCents: r.missingCents,
    expensiveDebts: expensive,
    cdiMonthlyPpm,
  });
  const text =
    c.availableCents > 0
      ? `Você pode separar até ${brl(c.availableCents)} sem que o saldo fique negativo nos próximos 30 dias, mantendo uma folga de ${brl(c.cushionCents)}.` +
        (c.toReserveCents > 0 ? ` Sugiro ${brl(c.toReserveCents)} para completar a reserva de emergência` : '') +
        (c.toInvestCents > 0 ? `${c.toReserveCents > 0 ? ' e' : ' Sugiro'} ${brl(c.toInvestCents)} para seus objetivos.` : '.') +
        // Dívidas com juros acima do CDI vêm antes de investir.
        ` ${c.priorities.filter((p) => p.startsWith('Antes')).join(' ')}`
      : c.priorities[0]!;
  return {
    title: 'Quanto posso investir',
    text: text.trim(),
    facts: [
      { label: 'Saldo disponível hoje', value: cf.startBalanceCents, type: 'money' },
      { label: 'Menor saldo previsto em 30 dias', value: lowest30, type: 'money' },
      ...(reserveCash > 0 ? [{ label: 'Já separado como reserva (não entra)', value: reserveCash, type: 'money' as const }] : []),
      { label: 'Folga mantida em conta', value: c.cushionCents, type: 'money' },
      { label: 'Pode investir com segurança', value: c.availableCents, type: 'money' },
      { label: 'Falta na reserva de emergência', value: r.missingCents, type: 'money' },
      ...(cdi?.annualPct ? [{ label: 'CDI atual (a.a.)', value: Math.round(cdi.annualPct * 100), type: 'percent' as const }] : []),
    ],
    sources: [
      { label: 'Projeção de caixa (contas, faturas, parcelas e recorrências)', date: today() },
      ...(cdi?.lastDate ? [{ label: 'CDI — Banco Central (SGS)', date: cdi.lastDate }] : []),
    ],
  };
}

async function expenseGrowthAnswer(s: Scope): Promise<Partial> {
  const last = shiftMonth(today().slice(0, 7), -1);
  const from = monthRange(shiftMonth(last, -3)).from;
  const to = monthRange(last).to;
  const rows = (
    await Promise.all(
      s.entities.map(async (e) =>
        (await settledAggregate({ entityIds: [e.id], types: ['EXPENSE', 'REFUND'], from, to })).map((r) => ({ ...r, cents: applyShare(r.cents, e.shareBps) })),
      ),
    )
  ).flat();
  const byCat = new Map<string, { last: number; before: number }>();
  for (const r of rows) {
    const k = r.categoryId ?? '';
    const cur = byCat.get(k) ?? { last: 0, before: 0 };
    const signed = r.type === 'REFUND' && r.direction === 'IN' ? -r.cents : r.cents;
    if (r.month === last) cur.last += signed;
    else cur.before += signed;
    byCat.set(k, cur);
  }
  const cats = await prisma.category.findMany({ where: { id: { in: [...byCat.keys()].filter(Boolean) } } });
  const ranked = [...byCat.entries()]
    .map(([id, v]) => {
      const avg = Math.round(v.before / 3);
      return { name: cats.find((c) => c.id === id)?.name ?? 'Sem categoria', last: v.last, avg, diff: v.last - avg, bps: changeBps(v.last, avg) };
    })
    .filter((x) => x.diff > 0 && x.last > 0)
    .sort((a, b) => b.diff - a.diff)
    .slice(0, 3);
  const monthName = new Date(`${last}-15T12:00:00Z`).toLocaleDateString('pt-BR', { month: 'long', timeZone: 'UTC' });
  return {
    title: 'Despesas que aumentaram',
    text: ranked.length
      ? `Em ${monthName}, comparado à média dos 3 meses anteriores, o maior aumento foi em ${ranked[0]!.name}: ${brl(ranked[0]!.last)} contra ${brl(ranked[0]!.avg)} de média (+${brl(ranked[0]!.diff)}).` +
        (ranked.length > 1 ? ` Também subiram: ${ranked.slice(1).map((r) => `${r.name} (+${brl(r.diff)})`).join(' e ')}.` : '')
      : `Nenhuma categoria gastou mais em ${monthName} do que a média dos 3 meses anteriores.`,
    facts: ranked.map((r) => ({ label: `${r.name}: ${monthName} × média`, value: `${brl(r.last)} × ${brl(r.avg)}${r.bps === null ? '' : ` (+${pct(r.bps)})`}`, type: 'text' as const })),
    sources: [{ label: `Despesas pagas de ${br(from)} a ${br(to)}`, date: to }],
  };
}

async function piggyYieldAnswer(s: Scope): Promise<Partial> {
  const piggies = (await Promise.all(s.entities.map((e) => listPiggies(e.id)))).flat();
  const effective = piggies.reduce((a, p) => a + p.effectiveYieldCents, 0);
  const estimated = piggies.reduce((a, p) => a + p.estimatedYieldCents, 0);
  const best = [...piggies].sort((a, b) => b.effectiveYieldCents + b.estimatedYieldCents - (a.effectiveYieldCents + a.estimatedYieldCents))[0];
  return {
    title: 'Rendimento dos cofrinhos',
    text: piggies.length
      ? `Seus cofrinhos já renderam ${brl(effective)} confirmados pelo banco` +
        (estimated > 0 ? ` e há mais ${brl(estimated)} estimados desde a última confirmação (estimativa, não garantia)` : '') +
        `.${best && best.effectiveYieldCents + best.estimatedYieldCents > 0 ? ` O que mais rendeu foi "${best.name}" (${best.yieldLabel}).` : ''}`
      : 'Você ainda não tem cofrinhos. Que tal criar um para sua reserva ou um desejo?',
    facts: [
      { label: 'Rendimento confirmado', value: effective, type: 'money' },
      { label: 'Rendimento estimado (não confirmado)', value: estimated, type: 'money' },
      { label: 'Total guardado', value: piggies.reduce((a, p) => a + p.balanceCents, 0), type: 'money' },
    ],
    sources: [{ label: 'Saldos dos cofrinhos e índices do Banco Central', date: today() }],
  };
}

async function topClientAnswer(s: Scope): Promise<Partial> {
  const from = addDaysISO(today(), -365);
  const rows = await prisma.$queryRaw<{ name: string; cents: bigint }[]>`
    SELECT c.name, SUM(st.amount_cents)::bigint AS cents
    FROM transaction_settlements st
    JOIN transactions t ON t.id = st.transaction_id
    JOIN contacts c ON c.id = t.contact_id
    WHERE t.entity_id = ANY(${ids(s)}::uuid[]) AND t.type = 'INCOME' AND t.deleted_at IS NULL AND st.date >= ${from}::date
    GROUP BY 1 ORDER BY 2 DESC LIMIT 3`;
  const top = rows.map((r) => ({ name: r.name, cents: Number(r.cents) }));
  return {
    title: 'Clientes que mais pagaram',
    text: top.length
      ? `Nos últimos 12 meses, quem mais te pagou foi ${top[0]!.name}: ${brl(top[0]!.cents)} recebidos.` +
        (top.length > 1 ? ` Depois vêm ${top.slice(1).map((t) => `${t.name} (${brl(t.cents)})`).join(' e ')}.` : '')
      : 'Ainda não há recebimentos ligados a clientes nos últimos 12 meses. Cadastre o cliente nas cobranças para acompanhar.',
    facts: top.map((t) => ({ label: t.name, value: t.cents, type: 'money' as const })),
    sources: [{ label: `Recebimentos de ${br(from)} até hoje`, date: today() }],
  };
}

async function dueThisWeekAnswer(s: Scope): Promise<Partial> {
  const t = today();
  const until = addDaysISO(t, 7);
  const page = await payables(ids(s), { kind: 'payable', status: 'open' });
  const items = [
    ...page.data
      .filter((x) => (x.dueDate ?? x.competenceDate) <= until)
      .map((x) => ({ name: x.description, due: x.dueDate ?? x.competenceDate, cents: x.amountCents - x.settledAmountCents })),
    ...page.cardInvoices.filter((i) => i.dueDate <= until).map((i) => ({ name: `Fatura ${i.cardName}`, due: i.dueDate, cents: i.remainingCents })),
  ].sort((a, b) => a.due.localeCompare(b.due));
  const overdue = items.filter((i) => i.due < t);
  const total = items.reduce((a, i) => a + i.cents, 0);
  return {
    title: 'Contas da semana',
    text: items.length
      ? `Até ${br(until)} você tem ${items.length} ${items.length === 1 ? 'conta' : 'contas'} somando ${brl(total)}` +
        (overdue.length ? `, sendo ${overdue.length} em atraso (${brl(overdue.reduce((a, i) => a + i.cents, 0))})` : '') +
        `. A próxima é "${items.find((i) => i.due >= t)?.name ?? items[0]!.name}".`
      : `Nenhuma conta vence até ${br(until)}. 🎉`,
    facts: items.slice(0, 8).map((i) => ({ label: `${i.name} — ${br(i.due)}${i.due < t ? ' (atrasada)' : ''}`, value: i.cents, type: 'money' as const })),
    sources: [{ label: 'Contas a pagar, faturas de cartão e parcelas de dívidas', date: t }],
  };
}

async function netWorthAnswer(s: Scope): Promise<Partial> {
  const hists = await Promise.all(s.entities.map(async (e) => ({ e, h: await patrimonyHistory(e.id, 12) })));
  const months = hists[0]?.h.map((x) => x.month) ?? [];
  const series = months.map((m) => ({
    month: m,
    cents: hists.reduce((a, { e, h }) => a + applyShare(h.find((x) => x.month === m)?.netWorth.netWorthCents ?? 0, e.shareBps), 0),
  }));
  const now = series.at(-1)?.cents ?? 0;
  const prev = series.at(-2)?.cents ?? now;
  const first = series.find((x) => x.cents !== 0) ?? series[0];
  const diff = now - prev;
  return {
    title: 'Evolução do patrimônio',
    text:
      `Seu patrimônio líquido hoje é ${brl(now)}. ` +
      (diff === 0 ? 'Ficou estável em relação ao fim do mês passado.' : `${diff > 0 ? 'Aumentou' : 'Diminuiu'} ${brl(Math.abs(diff))} desde o fim do mês passado.`) +
      (first && first.month !== series.at(-1)?.month ? ` Desde ${first.month.split('-').reverse().join('/')}, a variação foi de ${brl(now - first.cents)}.` : ''),
    facts: series.slice(-6).map((x) => ({ label: x.month.split('-').reverse().join('/'), value: x.cents, type: 'money' as const })),
    sources: [{ label: 'Fotografias mensais do patrimônio (ativos − passivos)', date: today() }],
  };
}

async function balanceAnswer(s: Scope): Promise<Partial> {
  let cash = 0;
  for (const e of s.entities) {
    const accounts = await prisma.account.findMany({ where: { entityId: e.id, archivedAt: null, type: cashAccountType } });
    cash += applyShare([...(await accountBalances(accounts, { until: today() })).values()].reduce((a, b) => a + b, 0), e.shareBps);
  }
  return {
    title: 'Saldo',
    text: `Você tem ${brl(cash)} disponíveis nas suas contas${s.entities.length > 1 ? ' (consolidado)' : ''}. Dinheiro em cofrinhos e investimentos não entra nesse valor.`,
    facts: [{ label: 'Saldo disponível', value: cash, type: 'money' }],
    sources: [{ label: 'Saldos calculados pelas movimentações', date: today() }],
  };
}

async function budgetsAnswer(s: Scope): Promise<Partial> {
  const month = today().slice(0, 7);
  const pages = await Promise.all(s.entities.map((e) => listBudgets(e.id, month)));
  const items = pages.flatMap((p) => p.items);
  const alerts = pages.flatMap((p) => p.alerts);
  return {
    title: 'Orçamentos do mês',
    text: items.length
      ? alerts.length
        ? `${alerts.length} ${alerts.length === 1 ? 'orçamento pede' : 'orçamentos pedem'} atenção: ${alerts.map((a) => a.message).join('; ')}.`
        : 'Todos os orçamentos do mês estão dentro do limite. 👏'
      : 'Você ainda não definiu orçamentos. Crie limites por categoria em Planejamento.',
    facts: items.map((b) => ({ label: b.category.name, value: `${brl(b.spentCents)} de ${brl(b.limitCents)} (${pct(b.usedBps)})`, type: 'text' as const })),
    sources: [{ label: 'Gastos pagos no mês por categoria', date: today() }],
  };
}

async function debtsAnswer(s: Scope): Promise<Partial> {
  const debts = (await Promise.all(s.entities.map((e) => listDebts(e.id)))).flat();
  const total = debts.reduce((a, d) => a + d.summary.outstandingPrincipalCents, 0);
  const next = debts
    .map((d) => d.summary.nextInstallment && { name: d.name, ...d.summary.nextInstallment })
    .filter((x): x is NonNullable<typeof x> => !!x)
    .sort((a, b) => a.dueDate.localeCompare(b.dueDate))[0];
  return {
    title: 'Dívidas',
    text: debts.length
      ? `Seu saldo devedor total é ${brl(total)} em ${debts.length} ${debts.length === 1 ? 'dívida' : 'dívidas'}.` +
        (next ? ` A próxima parcela é de "${next.name}": ${brl(next.totalCents)} em ${br(next.dueDate)}.` : '') +
        ' Em Dívidas você pode simular a quitação antecipada.'
      : 'Você não tem dívidas cadastradas. 🎉',
    facts: debts.map((d) => ({ label: d.name, value: d.summary.outstandingPrincipalCents, type: 'money' as const })),
    sources: [{ label: 'Cronogramas das dívidas', date: today() }],
  };
}

const BUILDERS: Record<Exclude<Intent, 'UNKNOWN'>, (s: Scope) => Promise<Partial>> = {
  INVEST_CAPACITY: investCapacityAnswer,
  EXPENSE_GROWTH: expenseGrowthAnswer,
  PIGGY_YIELD: piggyYieldAnswer,
  TOP_CLIENT: topClientAnswer,
  DUE_THIS_WEEK: dueThisWeekAnswer,
  NET_WORTH_CHANGE: netWorthAnswer,
  BALANCE: balanceAnswer,
  BUDGETS: budgetsAnswer,
  DEBTS: debtsAnswer,
};

// ───────────── 4: explicação pela IA (opcional) ─────────────

const SYSTEM_PROMPT = `Você é a Costelinha, assistente financeira do app hoink.
Explique para a pessoa, em português do Brasil, em no máximo 4 frases curtas e com tom acolhedor, a resposta à pergunta dela.
Use somente os números e fatos fornecidos em <fatos> e <resposta_calculada>: eles foram calculados pelo sistema e estão corretos.
Não faça contas novas, não invente valores, produtos, taxas ou ofertas, e não prometa rentabilidade.
Não recomende produtos financeiros específicos nem movimente dinheiro. Se os fatos não bastarem para responder, diga o que falta.`;

let client: Anthropic | null = null;
function aiClient() {
  if (!env.ANTHROPIC_API_KEY) return null;
  client ??= new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, timeout: 20_000, maxRetries: 1 });
  return client;
}

/** Pede à IA uma explicação dos fatos já calculados. Qualquer falha devolve null (fica o texto determinístico). */
async function explainWithAi(question: string, base: Partial): Promise<string | null> {
  const ai = aiClient();
  if (!ai) return null;
  try {
    const response = await ai.beta.messages.create({
      model: env.ASSISTANT_MODEL,
      max_tokens: 1024,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      output_config: { effort: 'low' },
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: 'user',
          content: `<pergunta>${question}</pergunta>\n<fatos>${JSON.stringify(base.facts)}</fatos>\n<fontes>${JSON.stringify(base.sources)}</fontes>\n<resposta_calculada>${base.text}</resposta_calculada>`,
        },
      ],
    });
    if (response.stop_reason === 'refusal') return null;
    const text = response.content
      .filter((b): b is Anthropic.Beta.BetaTextBlock => b.type === 'text')
      .map((b) => b.text)
      .join('')
      .trim();
    return text || null;
  } catch (err) {
    if (err instanceof Anthropic.APIError) logger.warn({ status: err.status }, 'IA indisponível; usando resposta determinística');
    else logger.warn({ err }, 'IA indisponível; usando resposta determinística');
    return null;
  }
}

// ───────────── 3: contexto + orquestração ─────────────

export async function ask(scope: Scope, question: string): Promise<Answer> {
  const intent = classify(question);
  if (intent === 'UNKNOWN') {
    return {
      intent,
      question,
      title: 'Ainda estou aprendendo',
      text: 'Ainda não sei responder essa. Experimente uma destas perguntas — eu calculo tudo com os seus dados reais.',
      facts: [],
      sources: [],
      suggestions: SUGGESTED_QUESTIONS,
      generatedBy: 'RULES',
    };
  }
  const base = await BUILDERS[intent](scope);
  const ai = await explainWithAi(question, base);
  return {
    intent,
    question,
    ...base,
    text: ai ?? base.text,
    suggestions: SUGGESTED_QUESTIONS.filter((q) => classify(q) !== intent).slice(0, 3),
    generatedBy: ai ? 'AI' : 'RULES',
  };
}

export function assistantInfo() {
  return { aiEnabled: !!env.ANTHROPIC_API_KEY, model: env.ANTHROPIC_API_KEY ? env.ASSISTANT_MODEL : null, suggestions: SUGGESTED_QUESTIONS };
}

// ───────────── Insights (cartões do dashboard e notificações) ─────────────

export interface Insight {
  key: string;
  severity: 'info' | 'warning' | 'danger' | 'success';
  title: string;
  body: string;
  link: string;
}

/** Insights determinísticos para o ambiente: contas, orçamento, caixa, reserva e conquistas. */
export async function insights(scope: Scope): Promise<Insight[]> {
  const out: Insight[] = [];
  const t = today();
  const due = await payables(ids(scope), { kind: 'payable', status: 'open' });
  const overdue = due.data.filter((x) => x.effectiveStatus === 'OVERDUE');
  if (overdue.length) {
    out.push({
      key: `overdue:${t}`,
      severity: 'danger',
      title: `${overdue.length} ${overdue.length === 1 ? 'conta atrasada' : 'contas atrasadas'}`,
      body: `Total em atraso: ${brl(due.totals.overdueCents)}.`,
      link: '/contas-a-pagar?tipo=pagar',
    });
  }
  const week = addDaysISO(t, 3);
  for (const x of due.data.filter((d) => (d.dueDate ?? d.competenceDate) >= t && (d.dueDate ?? d.competenceDate) <= week)) {
    out.push({
      key: `due:${x.id}:${x.dueDate}`,
      severity: 'warning',
      title: `${x.description} vence ${(x.dueDate ?? x.competenceDate) === t ? 'hoje' : `em ${br(x.dueDate ?? x.competenceDate)}`}`,
      body: `Valor: ${brl(x.amountCents - x.settledAmountCents)}.`,
      link: `/lancamentos/${x.entityId}/${x.id}`,
    });
  }
  for (const inv of due.cardInvoices.filter((i) => i.dueDate >= t && i.dueDate <= week)) {
    out.push({
      key: `invoice:${inv.id}`,
      severity: 'warning',
      title: `Fatura ${inv.cardName} vence em ${br(inv.dueDate)}`,
      body: `Falta pagar ${brl(inv.remainingCents)}.`,
      link: `/cartoes/${inv.entityId}/${inv.cardId}`,
    });
  }
  const month = t.slice(0, 7);
  for (const e of scope.entities) {
    const b = await listBudgets(e.id, month);
    for (const a of b.alerts) {
      out.push({
        key: `budget:${a.budgetId}:${month}:${a.state}`,
        severity: a.state === 'EXCEEDED' ? 'danger' : 'warning',
        title: a.state === 'EXCEEDED' ? 'Orçamento estourado' : 'Orçamento em alerta',
        body: a.message,
        link: '/planejamento',
      });
    }
  }
  const cf = await cashflow(scope.entities.map((e) => ({ entityId: e.id, shareBps: e.shareBps })));
  if (cf.lowest.projectedCents < 0) {
    out.push({
      key: `cash-negative:${cf.lowest.date}`,
      severity: 'danger',
      title: 'Saldo pode ficar negativo',
      body: `Pela projeção, o saldo chega a ${brl(cf.lowest.projectedCents)} em ${br(cf.lowest.date)}.`,
      link: '/planejamento',
    });
  }
  return out;
}
