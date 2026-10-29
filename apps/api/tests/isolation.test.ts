import { beforeAll, describe, expect, it } from 'vitest';
import { createAccount, createUser, resetDb } from './helpers';

beforeAll(resetDb);

describe('isolamento (RN11)', () => {
  it('usuário não acessa ambientes, contas ou lançamentos de outro usuário', async () => {
    const ana = await createUser('Ana');
    const bruno = await createUser('Bruno');
    const acc = await createAccount(ana, ana.personalId, 100000);
    const tx = await ana.api.post(`/api/entities/${ana.personalId}/transactions`, {
      type: 'EXPENSE', description: 'Mercado', amountCents: 5000, accountId: acc.id, competenceDate: '2025-06-10',
    });
    expect(tx.status).toBe(201);

    expect((await bruno.api.get(`/api/entities/${ana.personalId}/accounts`)).status).toBe(404);
    expect((await bruno.api.get(`/api/entities/${ana.personalId}/transactions/${tx.body.data.id}`)).status).toBe(404);
    expect((await bruno.api.get(`/api/entities/${ana.personalId}/dashboard`)).status).toBe(404);
    expect((await bruno.api.delete(`/api/entities/${ana.personalId}/transactions/${tx.body.data.id}`)).status).toBe(404);
    // Tentar lançar em conta alheia a partir do próprio ambiente.
    const cross = await bruno.api.post(`/api/entities/${bruno.personalId}/transactions`, {
      type: 'EXPENSE', description: 'X', amountCents: 100, accountId: acc.id, competenceDate: '2025-06-10',
    });
    expect(cross.status).toBe(422);
    // Transferir a partir da conta alheia.
    const bAcc = await createAccount(bruno, bruno.personalId);
    const steal = await bruno.api.post('/api/transfers', { fromAccountId: acc.id, toAccountId: bAcc.id, amountCents: 100, date: '2025-06-10' });
    expect(steal.status).toBe(404);
    // Consolidado do Bruno não enxerga nada da Ana.
    const cons = await bruno.api.get('/api/consolidated/transactions');
    expect(cons.body.meta.total).toBe(0);
  });

  it('ambientes Pessoal e Profissional do mesmo usuário são isolados', async () => {
    const u = await createUser();
    const pAcc = await createAccount(u, u.personalId, 0, 'Nubank PF');
    await createAccount(u, u.businessId, 0, 'Inter PJ');
    // Conta do Pessoal não pode ser usada em lançamentos do Profissional.
    const res = await u.api.post(`/api/entities/${u.businessId}/transactions`, {
      type: 'INCOME', description: 'Cliente', amountCents: 1000, accountId: pAcc.id, competenceDate: '2025-06-10',
    });
    expect(res.status).toBe(422);
    const bizAccounts = await u.api.get(`/api/entities/${u.businessId}/accounts`);
    expect(bizAccounts.body.data.map((a: { name: string }) => a.name)).toEqual(['Inter PJ']);
  });
});
