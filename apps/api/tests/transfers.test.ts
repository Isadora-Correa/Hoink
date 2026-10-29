import { beforeAll, describe, expect, it } from 'vitest';
import { balanceOf, createAccount, createUser, resetDb } from './helpers';

beforeAll(resetDb);

describe('transferências (RN01, RN09, RN10)', () => {
  it('entre contas próprias movimenta saldos sem gerar receita/despesa', async () => {
    const u = await createUser();
    const e = u.personalId;
    const a = await createAccount(u, e, 100000, 'Itaú');
    const b = await createAccount(u, e, 0, 'Nubank');
    const t = await u.api.post('/api/transfers', { fromAccountId: a.id, toAccountId: b.id, amountCents: 30000, date: '2025-06-10' });
    expect(t.status).toBe(201);
    expect(t.body.data.classification).toBe('INTERNAL');
    expect(await balanceOf(u, e, a.id)).toBe(70000);
    expect(await balanceOf(u, e, b.id)).toBe(30000);
    const dash = (await u.api.get(`/api/entities/${e}/dashboard?month=2025-06`)).body.data;
    expect(dash.realized.incomeCents).toBe(0);
    expect(dash.realized.expenseCents).toBe(0);
    expect(dash.totalBalanceCents).toBe(100000);

    // Pernas não podem ser editadas isoladamente; excluir a transferência remove as duas.
    const leg = await u.api.patch(`/api/entities/${e}/transactions/${t.body.data.outTransactionId}`, { amountCents: 1 });
    expect(leg.body.error.code).toBe('TRANSFER_LEG');
    expect((await u.api.delete(`/api/transfers/${t.body.data.id}`)).status).toBe(204);
    expect(await balanceOf(u, e, a.id)).toBe(100000);
    expect(await balanceOf(u, e, b.id)).toBe(0);
  });

  it('entre Pessoal e Profissional exige classificação e não duplica no consolidado', async () => {
    const u = await createUser();
    const pf = await createAccount(u, u.personalId, 0, 'Nubank PF');
    const pj = await createAccount(u, u.businessId, 0, 'Inter PJ');
    await u.api.post(`/api/entities/${u.businessId}/transactions`, {
      type: 'INCOME', description: 'Cliente Studio', amountCents: 500000, accountId: pj.id, competenceDate: '2025-06-03',
    });
    const noClass = await u.api.post('/api/transfers', { fromAccountId: pj.id, toAccountId: pf.id, amountCents: 200000, date: '2025-06-05' });
    expect(noClass.body.error.code).toBe('CLASSIFICATION_REQUIRED');
    const ok = await u.api.post('/api/transfers', {
      fromAccountId: pj.id, toAccountId: pf.id, amountCents: 200000, date: '2025-06-05', classification: 'PRO_LABORE',
    });
    expect(ok.status).toBe(201);

    const cons = (await u.api.get('/api/consolidated/dashboard?month=2025-06')).body.data;
    expect(cons.totalBalanceCents).toBe(500000);
    expect(cons.realized.incomeCents).toBe(500000);
    expect(cons.realized.transfersInCents).toBe(0);
    expect(cons.recent.filter((t: { transfer: unknown }) => t.transfer)).toHaveLength(1);
  });

  it('consolidado respeita participação societária', async () => {
    const u = await createUser();
    const pf = await createAccount(u, u.personalId, 100000, 'PF');
    await createAccount(u, u.businessId, 400000, 'PJ');
    await u.api.patch(`/api/entities/${u.businessId}`, { ownershipShareBps: 5000 });
    const cons = (await u.api.get('/api/consolidated/dashboard?month=2025-06')).body.data;
    expect(cons.totalBalanceCents).toBe(100000 + 200000);
    expect(pf.balanceCents).toBe(100000);
  });
});
