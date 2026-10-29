import { beforeAll, describe, expect, it } from 'vitest';
import { categoryId, createAccount, createUser, resetDb, type TestUser } from './helpers';

let u: TestUser;
let accId: string;

beforeAll(async () => {
  await resetDb();
  u = await createUser();
  accId = (await createAccount(u, u.personalId, 0)).id;
  const e = u.personalId;
  const mercado = await categoryId(u, e, 'Mercado');
  const items = [
    { type: 'INCOME', description: 'Salário Tech Co.', amountCents: 780000, competenceDate: '2025-06-05' },
    { type: 'EXPENSE', description: 'Pão de Açúcar', amountCents: 24250, competenceDate: '2025-06-06', categoryId: mercado, tags: ['mercado'] },
    { type: 'EXPENSE', description: 'Carrefour', amountCents: 7840, competenceDate: '2025-06-14', categoryId: mercado },
    { type: 'EXPENSE', description: 'Enel', amountCents: 28750, competenceDate: '2025-06-01', status: 'PENDING', dueDate: '2025-06-10' },
    { type: 'EXPENSE', description: 'Aluguel', amountCents: 185000, competenceDate: '2099-07-01', status: 'PLANNED', dueDate: '2099-07-05' },
  ];
  for (const it of items) {
    const r = await u.api.post(`/api/entities/${e}/transactions`, { ...it, accountId: accId });
    if (r.status !== 201) throw new Error(JSON.stringify(r.body));
  }
});

const list = (qs: string) => u.api.get(`/api/entities/${u.personalId}/transactions?${qs}`);

describe('listagem de lançamentos', () => {
  it('pagina e ordena', async () => {
    const r = await list('pageSize=2&sort=amount_desc');
    expect(r.body.meta).toMatchObject({ total: 5, totalPages: 3, page: 1 });
    expect(r.body.data.map((t: { description: string }) => t.description)).toEqual(['Salário Tech Co.', 'Aluguel']);
  });

  it('filtra por tipo, busca textual, tag e período', async () => {
    expect((await list('kind=income')).body.meta.total).toBe(1);
    expect((await list('q=pão')).body.data[0].description).toBe('Pão de Açúcar');
    expect((await list('q=mercado')).body.meta.total).toBe(1);
    expect((await list('from=2025-06-05&to=2025-06-10')).body.meta.total).toBe(2);
  });

  it('deriva status Atrasado sem misturar com Pendente', async () => {
    const overdue = await list('status=OVERDUE');
    expect(overdue.body.data.map((t: { description: string }) => t.description)).toEqual(['Enel']);
    expect(overdue.body.data[0].effectiveStatus).toBe('OVERDUE');
    expect((await list('status=PENDING')).body.meta.total).toBe(0);
    expect((await list('status=PLANNED')).body.meta.total).toBe(1);
  });

  it('valida entrada', async () => {
    const r = await u.api.post(`/api/entities/${u.personalId}/transactions`, {
      type: 'EXPENSE', description: '', amountCents: -5, accountId: accId, competenceDate: '06/2025',
    });
    expect(r.status).toBe(400);
    expect(Object.keys(r.body.error.details.fieldErrors).sort()).toEqual(['amountCents', 'competenceDate', 'description']);
  });
});

describe('dashboard', () => {
  it('separa realizado de previsto (RN06) e agrupa por categoria', async () => {
    const d = (await u.api.get(`/api/entities/${u.personalId}/dashboard?month=2025-06`)).body.data;
    expect(d.realized.incomeCents).toBe(780000);
    expect(d.realized.expenseCents).toBe(24250 + 7840);
    expect(d.forecast.expenseCents).toBe(28750);
    expect(d.overdue.count).toBe(1);
    expect(d.expensesByCategory).toEqual([expect.objectContaining({ name: 'Mercado', cents: 32090, shareBps: 10000 })]);
    expect(d.series).toHaveLength(6);
    expect(d.series.at(-1)).toMatchObject({ month: '2025-06', incomeCents: 780000 });
    expect(d.totalBalanceCents).toBe(780000 - 24250 - 7840);
  });
});
