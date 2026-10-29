import { beforeEach, describe, expect, it } from 'vitest';
import { classify } from '../src/domain/assistant';
import { addDaysISO } from '../src/domain/recurrence';
import { todayISO } from '../src/lib/dates';
import { resetThrottle } from '../src/modules/notifications/notifications.service';
import { categoryId, createAccount, createUser, resetDb, type TestUser } from './helpers';

let u: TestUser;
let base: string;
let acc: { id: string };
const today = todayISO();

beforeEach(async () => {
  await resetDb();
  resetThrottle();
  u = await createUser();
  base = `/api/entities/${u.personalId}`;
  acc = await createAccount(u, u.personalId, 300_000);
});

const ask = (question: string, path = base) => u.api.post(`${path}/assistant/ask`, { question });

describe('Costelinha — perguntas', () => {
  it('reconhece as perguntas do roteiro sem IA', () => {
    expect(classify('Quanto posso investir neste mês?')).toBe('INVEST_CAPACITY');
    expect(classify('Quais despesas aumentaram?')).toBe('EXPENSE_GROWTH');
    expect(classify('Quanto meus cofrinhos renderam?')).toBe('PIGGY_YIELD');
    expect(classify('Qual cliente mais me pagou?')).toBe('TOP_CLIENT');
    expect(classify('Quais contas vencem esta semana?')).toBe('DUE_THIS_WEEK');
    expect(classify('Meu patrimônio aumentou?')).toBe('NET_WORTH_CHANGE');
    expect(classify('qual a cor do céu')).toBe('UNKNOWN');
  });

  it('quanto posso investir: usa o menor saldo projetado em 30 dias e a folga', async () => {
    const in5 = addDaysISO(today, 5);
    await u.api.post(`${base}/transactions`, { type: 'EXPENSE', description: 'Aluguel', amountCents: 100_000, accountId: acc.id, status: 'PENDING', competenceDate: in5, dueDate: in5 });
    const r = (await ask('Quanto posso investir este mês?')).body.data;
    expect(r).toMatchObject({ intent: 'INVEST_CAPACITY' });
    const fact = (label: string) => r.facts.find((f: { label: string }) => f.label === label).value;
    expect(fact('Saldo disponível hoje')).toBe(300_000);
    expect(fact('Menor saldo previsto em 30 dias')).toBe(200_000);
    expect(fact('Pode investir com segurança')).toBe(200_000 - fact('Folga mantida em conta'));
    expect(r.text).toContain('R$');
    expect(r.sources.length).toBeGreaterThan(0);
  });

  it('não conta o dinheiro da reserva de emergência como sobra para investir', async () => {
    const poupanca = (await u.api.post(`${base}/accounts`, { name: 'Reserva', type: 'SAVINGS', initialBalanceCents: 1_000_000, referenceDate: '2025-01-01' })).body.data;
    await u.api.put(`${base}/planning/reserve`, { targetMonths: 6, accountIds: [poupanca.id] });
    const r = (await ask('Quanto posso investir este mês?')).body.data;
    const fact = (label: string) => r.facts.find((f: { label: string }) => f.label === label)?.value;
    expect(fact('Saldo disponível hoje')).toBe(1_300_000);
    expect(fact('Já separado como reserva (não entra)')).toBe(1_000_000);
    expect(fact('Pode investir com segurança')).toBeLessThanOrEqual(300_000);
  });

  it('contas da semana, cliente que mais pagou e pergunta desconhecida', async () => {
    const in2 = addDaysISO(today, 2);
    await u.api.post(`${base}/transactions`, { type: 'EXPENSE', description: 'Internet', amountCents: 9_990, accountId: acc.id, status: 'PENDING', competenceDate: in2, dueDate: in2 });
    const due = (await ask('Quais contas vencem esta semana?')).body.data;
    expect(due.text).toContain('1 conta');
    expect(due.facts[0].value).toBe(9_990);

    const pj = `/api/entities/${u.businessId}`;
    const pjAcc = await createAccount(u, u.businessId, 0, 'Inter PJ');
    const client = (await u.api.post(`${pj}/contacts`, { kind: 'CLIENT', name: 'Studio Alpha' })).body.data;
    await u.api.post(`${pj}/transactions`, { type: 'INCOME', description: 'Projeto', amountCents: 500_000, accountId: pjAcc.id, contactId: client.id, categoryId: await categoryId(u, u.businessId, 'Serviços prestados'), competenceDate: today });
    const top = (await ask('Qual cliente mais me pagou?', pj)).body.data;
    expect(top.text).toContain('Studio Alpha');
    const consolidated = (await u.api.post('/api/assistant/ask', { question: 'qual cliente mais me pagou?' })).body.data;
    expect(consolidated.facts[0]).toMatchObject({ label: 'Studio Alpha', value: 500_000 });

    const unknown = (await ask('Qual a capital da França?')).body.data;
    expect(unknown).toMatchObject({ intent: 'UNKNOWN' });
    expect(unknown.suggestions).toHaveLength(8);
  });

  it('dúvidas comuns têm respostas prontas, sem IA paga', async () => {
    expect(classify('O que é o CDI?')).toBe('FAQ');
    expect(classify('Pagar a fatura conta como despesa?')).toBe('FAQ');
    expect(classify('qual a diferença entre PRICE e SAC?')).toBe('FAQ');
    const r = (await ask('O que é o CDI?')).body.data;
    expect(r).toMatchObject({ intent: 'FAQ', title: 'O que é o CDI', facts: [] });
    expect(r.text).toContain('Banco Central');
    const info = (await u.api.get('/api/assistant')).body.data;
    expect(info).toEqual({ suggestions: expect.arrayContaining(['O que é o CDI?']) });
  });
});

describe('comparador e notificações', () => {
  it('compara aplicações com a taxa atual e avisa índice ausente', async () => {
    const res = await u.api.post('/api/assistant/compare-investments', {
      amountCents: 1_000_000,
      months: 12,
      options: [
        { label: 'Prefixado 12%', indexer: 'PREFIXED', rateBps: 1200, taxation: 'REGRESSIVE' },
        { label: 'CDB 110% CDI', indexer: 'CDI_PERCENT', rateBps: 11000, taxation: 'REGRESSIVE' },
      ],
    });
    expect(res.body.data.results).toHaveLength(1);
    expect(res.body.data.results[0]).toMatchObject({ label: 'Prefixado 12%', grossCents: 1_120_000 });
    expect(res.body.data.missingRates).toEqual(['CDB 110% CDI']);
  });

  it('gera notificações de contas e orçamentos sem repetir', async () => {
    const in1 = addDaysISO(today, 1);
    await u.api.post(`${base}/transactions`, { type: 'EXPENSE', description: 'Luz', amountCents: 25_000, accountId: acc.id, status: 'PENDING', competenceDate: in1, dueDate: in1 });
    const mercado = await categoryId(u, u.personalId, 'Mercado');
    await u.api.put(`${base}/planning/budgets`, { categoryId: mercado, limitCents: 10_000 });
    await u.api.post(`${base}/transactions`, { type: 'EXPENSE', description: 'Feira', amountCents: 20_000, accountId: acc.id, categoryId: mercado, competenceDate: today });
    const first = (await u.api.get('/api/notifications')).body.data;
    expect(first.unread).toBeGreaterThanOrEqual(2);
    expect(first.items.map((n: { title: string }) => n.title)).toEqual(expect.arrayContaining(['Luz vence em ' + in1.split('-').reverse().join('/'), 'Orçamento estourado']));
    resetThrottle();
    const again = (await u.api.get('/api/notifications')).body.data;
    expect(again.items).toHaveLength(first.items.length);
    expect((await u.api.post(`/api/notifications/${first.items[0].id}/read`)).status).toBe(204);
    expect((await u.api.get('/api/notifications')).body.data.unread).toBe(first.unread - 1);
    await u.api.post('/api/notifications/read-all');
    expect((await u.api.get('/api/notifications')).body.data.unread).toBe(0);
    const other = await createUser('Outra');
    expect((await other.api.post(`/api/notifications/${first.items[0].id}/read`)).status).toBe(404);
  });
});
