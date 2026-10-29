/**
 * Costelinha — parte determinística (funções puras): reconhecer a pergunta e calcular quanto
 * dá para investir. A IA, quando configurada, só EXPLICA números já calculados (Seção 15).
 */

export type Intent =
  | 'INVEST_CAPACITY'
  | 'EXPENSE_GROWTH'
  | 'PIGGY_YIELD'
  | 'TOP_CLIENT'
  | 'DUE_THIS_WEEK'
  | 'NET_WORTH_CHANGE'
  | 'BALANCE'
  | 'BUDGETS'
  | 'DEBTS'
  | 'UNKNOWN';

const normalize = (s: string) =>
  s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/\s+/g, ' ')
    .trim();

/** Reconhecimento por palavras-chave (sem IA), na ordem de especificidade. */
const RULES: [Intent, RegExp][] = [
  ['INVEST_CAPACITY', /(quanto|o que).*(posso|consigo|da para|devo).*(investir|guardar|aplicar|poupar)|sobra.*(investir|guardar)|onde investir/],
  ['EXPENSE_GROWTH', /(despesa|gasto|gastei|gastando).*(aument|subi|cresc|mais)|(aument|subi|cresc).*(despesa|gasto)|onde (estou )?gast/],
  ['PIGGY_YIELD', /(cofrinho|reserva|caixinha|investimento).*(rend|ganh)|(rend|ganh).*(cofrinho|reserva|caixinha)|quanto rendeu/],
  ['TOP_CLIENT', /cliente.*(mais|maior|melhor).*(pag|fatur|receb)|(quem|qual cliente).*(mais )?(me )?pag/],
  ['DUE_THIS_WEEK', /(conta|boleto|fatura|pagamento|parcela)s?.*(venc|pagar)|vence(m)?|esta semana|essa semana|proximos dias/],
  ['NET_WORTH_CHANGE', /patrimonio|estou mais rico|riqueza|meu valor/],
  ['BUDGETS', /orcamento|limite de gasto|estour/],
  ['DEBTS', /divida|emprestimo|financiamento|quitar|devo quanto|quanto devo/],
  ['BALANCE', /saldo|quanto (eu )?tenho|dinheiro (em|na) conta/],
];

export function classify(question: string): Intent {
  const q = normalize(question);
  for (const [intent, re] of RULES) if (re.test(q)) return intent;
  return 'UNKNOWN';
}

export const SUGGESTED_QUESTIONS = [
  'Quanto posso investir este mês?',
  'Quais despesas aumentaram?',
  'Quanto meus cofrinhos renderam?',
  'Qual cliente mais me pagou?',
  'Quais contas vencem esta semana?',
  'Meu patrimônio aumentou?',
];

export interface InvestCapacityInput {
  /** Saldo disponível hoje (contas de dinheiro). */
  balanceCents: number;
  /** Menor saldo projetado nos próximos 30 dias (confirmado + previsto). */
  lowestProjected30Cents: number;
  /** Média mensal de despesas (base da folga de segurança). */
  avgMonthlyExpenseCents: number;
  /** Quanto falta para a reserva de emergência. */
  reserveMissingCents: number;
  /** Dívidas com juros acima do CDI (taxa mensal em ppm). */
  expensiveDebts: { name: string; monthlyRatePpm: number; outstandingCents: number }[];
  /** CDI mensal equivalente em ppm (null se desconhecido). */
  cdiMonthlyPpm: number | null;
}

export interface InvestCapacity {
  /** Quanto pode sair das contas sem o saldo ficar negativo em 30 dias, já com a folga. */
  availableCents: number;
  /** Folga mantida em conta (10% da média mensal de despesas). */
  cushionCents: number;
  toReserveCents: number;
  toInvestCents: number;
  priorities: string[];
}

/**
 * Quanto dá para investir sem faltar dinheiro: o menor saldo projetado em 30 dias (já considera
 * contas, faturas e parcelas) menos uma folga. Prioridades: dívidas caras, depois reserva, depois investir.
 * Não recomenda produtos específicos.
 */
export function investCapacity(i: InvestCapacityInput): InvestCapacity {
  const cushion = Math.round(i.avgMonthlyExpenseCents * 0.1);
  const available = Math.max(0, Math.min(i.balanceCents, i.lowestProjected30Cents) - cushion);
  const toReserve = Math.min(available, Math.max(0, i.reserveMissingCents));
  const priorities: string[] = [];
  if (available === 0) {
    priorities.push('Segure o dinheiro em conta: o saldo projetado para os próximos 30 dias não deixa sobra com segurança.');
  }
  for (const d of i.expensiveDebts) {
    priorities.push(
      `Antes de investir, considere amortizar "${d.name}": os juros (${(d.monthlyRatePpm / 10000).toFixed(2).replace('.', ',')}% a.m.) são maiores que o rendimento do CDI.`,
    );
  }
  if (toReserve > 0) priorities.push('Complete primeiro a reserva de emergência, em aplicação com liquidez diária.');
  if (available - toReserve > 0) {
    priorities.push('O que sobrar pode ir para objetivos de prazo maior, conforme seu perfil de risco e o prazo de cada meta.');
  }
  return { availableCents: available, cushionCents: cushion, toReserveCents: toReserve, toInvestCents: available - toReserve, priorities };
}

/** Variação percentual em pontos-base (null quando a base é zero). */
export function changeBps(current: number, previous: number): number | null {
  if (previous === 0) return null;
  return Math.round(((current - previous) * 10000) / Math.abs(previous));
}
