/**
 * Costelinha (funções puras): reconhece a pergunta, responde dúvidas comuns com textos prontos e
 * calcula quanto dá para investir. Sem IA paga: as respostas sobre o dinheiro do usuário são
 * montadas com números calculados pelo backend (Seção 15).
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
  | 'FAQ'
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

/** Dúvidas comuns com respostas prontas (educação financeira e uso do app). */
export const FAQ: { match: RegExp; title: string; answer: string }[] = [
  {
    match: /\b(o que e|que e|significa).*\bcdi\b|\bcdi\b.*(e o que|significa)/,
    title: 'O que é o CDI',
    answer:
      'O CDI é a taxa que os bancos usam para emprestar dinheiro entre si, e anda junto da Selic. Muitas aplicações rendem "um percentual do CDI": 100% do CDI acompanha a taxa; 115% rende 15% a mais que ela. A hoink. busca o CDI diário no Banco Central para estimar seus rendimentos.',
  },
  {
    match: /(o que e|que e|significa).*selic|selic.*(o que e|significa)/,
    title: 'O que é a Selic',
    answer:
      'A Selic é a taxa básica de juros do Brasil, definida pelo Banco Central. Quando ela sobe, aplicações de renda fixa tendem a render mais e empréstimos ficam mais caros.',
  },
  {
    match: /(o que e|que e|como funciona|para que serve|quanto).*(reserva de emergencia)|reserva de emergencia.*(quanto|ideal)/,
    title: 'Reserva de emergência',
    answer:
      'É um dinheiro guardado para imprevistos (perda de renda, saúde, conserto). O comum é juntar de 3 a 6 meses dos seus gastos, em aplicação segura e com resgate no mesmo dia. Em Planejamento a hoink. calcula a sua meta pela média de despesas.',
  },
  {
    match: /(como funciona|o que e|para que serve).*(cofrinho|lista de desejo)/,
    title: 'Como funciona o cofrinho',
    answer:
      'Você cria um cofrinho para cada objetivo (reserva, viagem, PS5…) e guarda dinheiro quando quiser. Guardar é uma transferência da sua conta para o cofrinho: o dinheiro sai do saldo disponível, mas não vira despesa. Quando comprar, toque em "Comprei!" e só a compra conta como gasto.',
  },
  {
    match: /fatura.*(despesa|duplic|conta duas)|(pagar|pago|paguei).*fatura/,
    title: 'Pagar a fatura conta como despesa?',
    answer:
      'Não. Cada compra no cartão já é a despesa, no mês da compra (ou da parcela). Pagar a fatura é uma transferência da sua conta para o cartão — por isso o saldo cai, mas a despesa não é contada de novo.',
  },
  {
    match: /(previsto|confirmado).*(diferenca|o que e)|diferenca.*(previsto|confirmado)/,
    title: 'Previsto × confirmado',
    answer:
      'Confirmado é o que já está lançado com data: contas pendentes, faturas fechadas e parcelas de dívidas. Previsto é o que deve acontecer, como as próximas ocorrências de contas fixas e valores estimados. A projeção de caixa mostra os dois separados.',
  },
  {
    match: /(o que e|que e|significa).*patrimonio( liquido)?|patrimonio liquido.*(o que|significa)/,
    title: 'O que é patrimônio líquido',
    answer:
      'É tudo o que você tem (contas, cofrinhos, investimentos e bens) menos tudo o que deve (empréstimos, financiamentos e faturas). É diferente do saldo disponível, que é só o dinheiro em conta.',
  },
  {
    match: /(imposto|ir |imposto de renda|tributa).*(investimento|cdb|lci|lca|tesouro|rendimento)|(cdb|lci|lca).*(imposto|ir\b|isent)/,
    title: 'Imposto sobre investimentos',
    answer:
      'CDB, Tesouro e fundos de renda fixa pagam IR sobre o rendimento, que cai com o tempo: 22,5% até 6 meses, 20% até 1 ano, 17,5% até 2 anos e 15% depois disso (e IOF nos primeiros 30 dias). LCI, LCA e poupança são isentas para pessoa física.',
  },
  {
    match: /(price|sac).*(diferenca|o que e|qual)|(diferenca|o que e).*(price|sac)|amortiza(cao|r).*(o que|como)/,
    title: 'PRICE, SAC e amortização',
    answer:
      'No PRICE as parcelas são iguais; no SAC elas começam maiores e vão diminuindo. Amortizar é pagar uma parte da dívida antes: você escolhe reduzir o prazo (economiza mais juros) ou o valor das parcelas. Em Dívidas dá para simular a quitação.',
  },
  {
    match: /(como|onde).*(esconder|ocultar).*(valor|saldo)|olhinho/,
    title: 'Esconder valores',
    answer: 'Toque no olho ao lado do sino, no topo. Todos os valores do app ficam escondidos até você tocar de novo.',
  },
];

export function faqAnswer(question: string) {
  const q = normalize(question);
  return FAQ.find((f) => f.match.test(q)) ?? null;
}

export function classify(question: string): Intent {
  const q = normalize(question);
  // Dúvidas conceituais ("o que é…", "como funciona…") têm resposta pronta.
  if (FAQ.some((f) => f.match.test(q))) return 'FAQ';
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
  'O que é o CDI?',
  'Pagar a fatura conta como despesa?',
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
