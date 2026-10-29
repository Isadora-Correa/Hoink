import { beforeAll, describe, expect, it } from 'vitest';
import { balanceOf, categoryId, createAccount, createUser, resetDb } from './helpers';

beforeAll(resetDb);

describe('contas e saldo (RN15)', () => {
  it('saldo = inicial + liquidados; pendentes não afetam', async () => {
    const u = await createUser();
    const e = u.personalId;
    const acc = await createAccount(u, e, 100000);
    const salario = await categoryId(u, e, 'Salário');
    const mercado = await categoryId(u, e, 'Mercado');
    const base = { accountId: acc.id, competenceDate: '2025-06-05' };

    await u.api.post(`/api/entities/${e}/transactions`, { ...base, type: 'INCOME', description: 'Salário', amountCents: 780000, categoryId: salario });
    await u.api.post(`/api/entities/${e}/transactions`, { ...base, type: 'EXPENSE', description: 'Pão de Açúcar', amountCents: 35000, categoryId: mercado });
    const pend = await u.api.post(`/api/entities/${e}/transactions`, {
      ...base, type: 'EXPENSE', description: 'Enel', amountCents: 28750, status: 'PENDING', dueDate: '2099-01-10',
    });
    expect(pend.body.data.settledAmountCents).toBe(0);
    expect(await balanceOf(u, e, acc.id)).toBe(100000 + 780000 - 35000);

    // Liquidação parcial e depois total.
    const partial = await u.api.post(`/api/entities/${e}/transactions/${pend.body.data.id}/settle`, { date: '2025-06-10', amountCents: 10000 });
    expect(partial.body.data.status).toBe('PARTIAL');
    expect(await balanceOf(u, e, acc.id)).toBe(845000 - 10000);
    const full = await u.api.post(`/api/entities/${e}/transactions/${pend.body.data.id}/settle`, { date: '2025-06-11' });
    expect(full.body.data.status).toBe('SETTLED');
    expect(await balanceOf(u, e, acc.id)).toBe(845000 - 28750);
  });

  it('editar e excluir lançamento recalcula o saldo e gera auditoria', async () => {
    const u = await createUser();
    const e = u.personalId;
    const acc = await createAccount(u, e, 0);
    const t = await u.api.post(`/api/entities/${e}/transactions`, {
      type: 'EXPENSE', description: 'Uber', amountCents: 2000, accountId: acc.id, competenceDate: '2025-06-05',
    });
    await u.api.patch(`/api/entities/${e}/transactions/${t.body.data.id}`, { amountCents: 2500 });
    expect(await balanceOf(u, e, acc.id)).toBe(-2500);
    await u.api.delete(`/api/entities/${e}/transactions/${t.body.data.id}`);
    expect(await balanceOf(u, e, acc.id)).toBe(0);
    const { prisma } = await import('../src/lib/prisma');
    const logs = await prisma.auditLog.findMany({ where: { resourceId: t.body.data.id }, orderBy: { createdAt: 'asc' } });
    expect(logs.map((l) => l.action)).toEqual(['create', 'update', 'delete']);
  });

  it('rejeita liquidação anterior à data de referência e categoria incompatível', async () => {
    const u = await createUser();
    const e = u.personalId;
    const acc = await createAccount(u, e, 0);
    const before = await u.api.post(`/api/entities/${e}/transactions`, {
      type: 'EXPENSE', description: 'Antigo', amountCents: 100, accountId: acc.id, competenceDate: '2024-12-31',
    });
    expect(before.status).toBe(422);
    expect(before.body.error.code).toBe('SETTLED_BEFORE_REFERENCE');
    const wrongCat = await u.api.post(`/api/entities/${e}/transactions`, {
      type: 'EXPENSE', description: 'X', amountCents: 100, accountId: acc.id, competenceDate: '2025-06-01',
      categoryId: await categoryId(u, e, 'Salário'),
    });
    expect(wrongCat.body.error.code).toBe('CATEGORY_KIND_MISMATCH');
  });

  it('extrato traz saldo de abertura e saldo acumulado', async () => {
    const u = await createUser();
    const e = u.personalId;
    const acc = await createAccount(u, e, 10000);
    const post = (d: string, type: string, cents: number) =>
      u.api.post(`/api/entities/${e}/transactions`, { type, description: type, amountCents: cents, accountId: acc.id, competenceDate: d });
    await post('2025-05-20', 'INCOME', 5000);
    await post('2025-06-02', 'EXPENSE', 3000);
    await post('2025-06-15', 'INCOME', 1000);
    const st = await u.api.get(`/api/entities/${e}/accounts/${acc.id}/statement?from=2025-06-01&to=2025-06-30`);
    expect(st.body.data.openingBalanceCents).toBe(15000);
    expect(st.body.data.entries.map((x: { balanceAfterCents: number }) => x.balanceAfterCents)).toEqual([12000, 13000]);
    expect(st.body.data.closingBalanceCents).toBe(13000);
  });

  it('conciliação calcula diferença e cria ajuste rastreável', async () => {
    const u = await createUser();
    const e = u.personalId;
    const acc = await createAccount(u, e, 50000);
    const dry = await u.api.post(`/api/entities/${e}/accounts/${acc.id}/reconcile`, { statementBalanceCents: 49000, date: '2025-06-30' });
    expect(dry.body.data.differenceCents).toBe(-1000);
    expect(dry.body.data.adjustmentId).toBeNull();
    const fix = await u.api.post(`/api/entities/${e}/accounts/${acc.id}/reconcile`, { statementBalanceCents: 49000, date: '2025-06-30', createAdjustment: true });
    expect(fix.body.data.adjustmentId).toBeTypeOf('string');
    expect(await balanceOf(u, e, acc.id)).toBe(49000);
  });

  it('arquivar exige saldo zero', async () => {
    const u = await createUser();
    const acc = await createAccount(u, u.personalId, 100);
    const r = await u.api.post(`/api/entities/${u.personalId}/accounts/${acc.id}/archive`);
    expect(r.body.error.code).toBe('ACCOUNT_HAS_BALANCE');
    const zero = await createAccount(u, u.personalId, 0, 'Vazia');
    expect((await u.api.post(`/api/entities/${u.personalId}/accounts/${zero.id}/archive`)).body.data.archived).toBe(true);
  });

  it('idempotency-key evita lançamento duplicado', async () => {
    const u = await createUser();
    const acc = await createAccount(u, u.personalId, 0);
    const body = { type: 'EXPENSE', description: 'Pix', amountCents: 999, accountId: acc.id, competenceDate: '2025-06-01' };
    const a = await u.api.post(`/api/entities/${u.personalId}/transactions`, body).set('Idempotency-Key', 'k-1');
    const b = await u.api.post(`/api/entities/${u.personalId}/transactions`, body).set('Idempotency-Key', 'k-1');
    expect(a.status).toBe(201);
    expect(b.status).toBe(201);
    expect(b.headers['idempotent-replayed']).toBe('true');
    expect(b.body.data.id).toBe(a.body.data.id);
    expect(await balanceOf(u, u.personalId, acc.id)).toBe(-999);
  });
});
