import { beforeEach, describe, expect, it } from 'vitest';
import { invoiceForPurchase } from '../src/domain/cards';
import { todayISO } from '../src/lib/dates';
import { balanceOf, categoryId, createAccount, createUser, resetDb, type TestUser } from './helpers';

let u: TestUser;
let base: string;
beforeEach(async () => {
  await resetDb();
  u = await createUser();
  base = `/api/entities/${u.personalId}`;
});

async function newCard(paymentAccountId?: string, limitCents = 500_000) {
  const res = await u.api.post(`${base}/cards`, {
    name: 'Nubank Roxinho',
    institution: 'Nubank',
    limitCents,
    closingDay: 3,
    dueDay: 10,
    paymentAccountId,
  });
  expect(res.status).toBe(201);
  return res.body.data as { id: string; availableCents: number };
}

describe('cartões de crédito', () => {
  it('compra parcelada consome o limite, distribui as parcelas nas faturas e não mexe no caixa', async () => {
    const acc = await createAccount(u, u.personalId, 1_000_000);
    const card = await newCard(acc.id);
    const cat = await categoryId(u, u.personalId, 'Lazer');
    const res = await u.api.post(`${base}/cards/${card.id}/purchases`, {
      description: 'Notebook',
      totalCents: 300_000,
      installments: 3,
      purchaseDate: '2026-04-02',
      categoryId: cat,
    });
    expect(res.status).toBe(201);
    expect(res.body.data.installments.map((i: { invoiceMonth: string; amountCents: number }) => [i.invoiceMonth, i.amountCents])).toEqual([
      ['2026-04', 100_000],
      ['2026-05', 100_000],
      ['2026-06', 100_000],
    ]);

    const got = (await u.api.get(`${base}/cards/${card.id}`)).body.data;
    expect(got).toMatchObject({ limitCents: 500_000, usedCents: 300_000, availableCents: 200_000 });
    expect(await balanceOf(u, u.personalId, acc.id)).toBe(1_000_000);

    // A conta-razão do cartão não aparece entre as contas de dinheiro.
    const accounts = (await u.api.get(`${base}/accounts`)).body.data as { id: string }[];
    expect(accounts.map((a) => a.id)).toEqual([acc.id]);

    const may = (await u.api.get(`${base}/cards/${card.id}/invoice?month=2026-05`)).body.data;
    expect(may).toMatchObject({ month: '2026-05', closingDate: '2026-05-03', dueDate: '2026-05-10', totalCents: 100_000 });
    expect(may.items[0].description).toBe('Notebook (2/3)');
  });

  it('pagar a fatura é transferência: despesa conta uma vez só (RN08)', async () => {
    const acc = await createAccount(u, u.personalId, 1_000_000);
    const card = await newCard(acc.id);
    const cat = await categoryId(u, u.personalId, 'Mercado');
    await u.api.post(`${base}/cards/${card.id}/purchases`, {
      description: 'Mercado',
      totalCents: 45_000,
      purchaseDate: '2026-03-15',
      categoryId: cat,
    });
    const inv = (await u.api.get(`${base}/cards/${card.id}/invoice?month=2026-04`)).body.data;
    expect(inv.totalCents).toBe(45_000);

    const partial = await u.api.post(`${base}/cards/${card.id}/invoices/${inv.id}/pay`, {
      fromAccountId: acc.id,
      amountCents: 20_000,
      date: '2026-04-08',
    });
    expect(partial.status).toBe(200);
    expect(partial.body.data.invoice).toMatchObject({ paidCents: 20_000, remainingCents: 25_000 });
    const full = await u.api.post(`${base}/cards/${card.id}/invoices/${inv.id}/pay`, { fromAccountId: acc.id, date: '2026-04-09' });
    expect(full.body.data.invoice).toMatchObject({ paidCents: 45_000, remainingCents: 0, status: 'PAID' });
    expect(full.body.data.invoice.payments).toHaveLength(2);

    expect(await balanceOf(u, u.personalId, acc.id)).toBe(955_000);
    expect((await u.api.get(`${base}/cards/${card.id}`)).body.data.usedCents).toBe(0);

    // Despesa de março: só a compra. Abril: nada (pagamento é transferência).
    const march = (await u.api.get(`${base}/dashboard?month=2026-03`)).body.data;
    const april = (await u.api.get(`${base}/dashboard?month=2026-04`)).body.data;
    expect(march.realized.expenseCents).toBe(45_000);
    expect(april.realized.expenseCents).toBe(0);
    expect(april.realized.transfersOutCents).toBe(45_000);

    const again = await u.api.post(`${base}/cards/${card.id}/invoices/${inv.id}/pay`, { fromAccountId: acc.id, date: '2026-04-09' });
    expect(again.status).toBe(422);
    expect(again.body.error.code).toBe('INVOICE_PAID');
  });

  it('bloqueia compra acima do limite e lançamentos/transferências diretos no cartão', async () => {
    const acc = await createAccount(u, u.personalId, 100_000);
    const card = await newCard(acc.id, 10_000);
    const over = await u.api.post(`${base}/cards/${card.id}/purchases`, { description: 'TV', totalCents: 10_001, purchaseDate: '2026-04-01' });
    expect(over.body.error.code).toBe('LIMIT_EXCEEDED');

    const direct = await u.api.post(`${base}/transactions`, {
      type: 'EXPENSE',
      description: 'x',
      amountCents: 100,
      accountId: card.id,
      competenceDate: '2026-04-01',
    });
    expect(direct.body.error.code).toBe('USE_CARD_PURCHASE');

    const transfer = await u.api.post('/api/transfers', { fromAccountId: acc.id, toAccountId: card.id, amountCents: 100, date: '2026-04-01' });
    expect(transfer.body.error.code).toBe('USE_INVOICE_PAYMENT');
    expect((await u.api.get(`${base}/accounts/${card.id}`)).status).toBe(404);
  });

  it('parcelas só mudam pela compra; excluir a compra devolve o limite', async () => {
    const card = await newCard();
    const p = (await u.api.post(`${base}/cards/${card.id}/purchases`, {
      description: 'Curso',
      totalCents: 100_000,
      installments: 4,
      purchaseDate: '2026-04-01',
    })).body.data;
    const edit = await u.api.patch(`${base}/transactions/${p.installments[0].transactionId}`, { amountCents: 1 });
    expect(edit.body.error.code).toBe('CARD_INSTALLMENT');
    expect((await u.api.delete(`${base}/cards/${card.id}/purchases/${p.id}`)).status).toBe(204);
    expect((await u.api.get(`${base}/cards/${card.id}`)).body.data.availableCents).toBe(500_000);
  });

  it('fatura atual, faturas pendentes e arquivamento', async () => {
    const card = await newCard();
    const today = todayISO();
    const current = invoiceForPurchase(today, 3, 10).month;
    await u.api.post(`${base}/cards/${card.id}/purchases`, { description: 'Café', totalCents: 1_500, purchaseDate: today });
    const got = (await u.api.get(`${base}/cards/${card.id}`)).body.data;
    expect(got.currentInvoice).toMatchObject({ month: current, totalCents: 1_500, status: 'OPEN' });
    const blocked = await u.api.post(`${base}/cards/${card.id}/archive`);
    expect(blocked.body.error.code).toBe('CARD_HAS_BALANCE');

    const updated = await u.api.patch(`${base}/cards/${card.id}`, { limitCents: 800_000, name: 'Roxinho' });
    expect(updated.body.data).toMatchObject({ name: 'Roxinho', limitCents: 800_000, availableCents: 798_500 });
    expect((await u.api.get(`${base}/cards`)).body.data).toHaveLength(1);
  });

  it('outro usuário não enxerga o cartão (RN11)', async () => {
    const card = await newCard();
    const other = await createUser('Outra');
    expect((await other.api.get(`${base}/cards/${card.id}`)).status).toBe(404);
    expect((await other.api.get(`/api/entities/${other.personalId}/cards/${card.id}`)).status).toBe(404);
  });
});
