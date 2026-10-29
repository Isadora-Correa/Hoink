import { beforeEach, describe, expect, it } from 'vitest';
import { balanceOf, createAccount, createUser, resetDb, type TestUser } from './helpers';

let u: TestUser;
let base: string;
let accountId: string;
beforeEach(async () => {
  await resetDb();
  u = await createUser();
  base = `/api/entities/${u.personalId}`;
  accountId = (await createAccount(u, u.personalId, 5_000_000)).id;
});

const loan = (extra: object = {}) => ({
  kind: 'LOAN',
  name: 'Empréstimo pessoal',
  creditor: 'Banco X',
  principalCents: 1_000_000,
  monthlyRatePpm: 10_000,
  system: 'PRICE',
  installmentCount: 12,
  startDate: '2026-01-01',
  firstDueDate: '2026-02-01',
  accountId,
  ...extra,
});

describe('dívidas', () => {
  it('simula sem gravar', async () => {
    const res = await u.api.post(`${base}/debts/simulate`, {
      principalCents: 1_000_000,
      monthlyRatePpm: 10_000,
      installmentCount: 12,
      firstDueDate: '2026-02-01',
    });
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ firstPaymentCents: 88_849, totalInterestCents: res.body.data.totalCents - 1_000_000 });
    expect((await u.api.get(`${base}/debts`)).body.data).toHaveLength(0);
  });

  it('cadastra com parcelas pendentes (principal/juros separados) e parcelas já pagas', async () => {
    const res = await u.api.post(`${base}/debts`, loan({ paidInstallments: 2 }));
    expect(res.status).toBe(201);
    const d = res.body.data;
    expect(d.installments).toHaveLength(12);
    expect(d.installments[0]).toMatchObject({ number: 1, state: 'PAID', paidBeforeApp: true, transactionId: null });
    expect(d.installments[2]).toMatchObject({ number: 3, principalCents: expect.any(Number), interestCents: expect.any(Number) });
    expect(d.summary).toMatchObject({ paidInstallments: 2, remainingInstallments: 10 });
    expect(d.summary.outstandingPrincipalCents).toBe(d.installments[1].balanceAfterCents);

    // As parcelas aparecem em contas a pagar e não podem ser editadas/excluídas diretamente.
    const payables = (await u.api.get(`${base}/payables?kind=payable`)).body.data as { id: string; status: string }[];
    expect(payables.filter((p) => p.status === 'PENDING')).toHaveLength(10);
    const txId = d.installments[2].transactionId;
    expect((await u.api.delete(`${base}/transactions/${txId}`)).body.error.code).toBe('DEBT_INSTALLMENT');

    // Pagamento com multa: liquida pelo lançamento com valor final maior.
    const scheduled = d.installments[2].totalCents;
    const paid = await u.api.post(`${base}/transactions/${txId}/settle`, { date: '2026-04-03', finalAmountCents: scheduled + 1_500 });
    expect(paid.status).toBe(200);
    const after = (await u.api.get(`${base}/debts/${d.id}`)).body.data;
    expect(after.installments[2]).toMatchObject({ state: 'PAID', penaltyCents: 1_500 });
    expect(after.summary.paidPenaltiesCents).toBe(1_500);
    expect(await balanceOf(u, u.personalId, accountId)).toBe(5_000_000 - scheduled - 1_500);
  });

  it('amortização extraordinária reduzindo o prazo ou a parcela', async () => {
    const d = (await u.api.post(`${base}/debts`, loan())).body.data;
    const term = await u.api.post(`${base}/debts/${d.id}/prepay`, { date: '2026-01-15', amountCents: 300_000, mode: 'REDUCE_TERM' });
    expect(term.status).toBe(200);
    const t = term.body.data;
    expect(t.summary.outstandingPrincipalCents).toBe(700_000);
    expect(t.summary.remainingInstallments).toBeLessThan(12);
    expect(t.installments.find((i: { kind: string }) => i.kind === 'EXTRA')).toMatchObject({ principalCents: 300_000, state: 'PAID' });
    expect(await balanceOf(u, u.personalId, accountId)).toBe(4_700_000);

    const d2 = (await u.api.post(`${base}/debts`, loan({ name: 'Outro' }))).body.data;
    const inst = (await u.api.post(`${base}/debts/${d2.id}/prepay`, { date: '2026-01-15', amountCents: 300_000, mode: 'REDUCE_INSTALLMENT' })).body.data;
    expect(inst.summary.remainingInstallments).toBe(12);
    expect(inst.summary.nextInstallment.totalCents).toBeLessThan(88_849);

    const tooMuch = await u.api.post(`${base}/debts/${d2.id}/prepay`, { date: '2026-01-15', amountCents: 9_000_000, mode: 'REDUCE_TERM' });
    expect(tooMuch.body.error.code).toBe('USE_PAYOFF');
  });

  it('simula e executa a quitação antecipada com desconto dos juros futuros', async () => {
    const d = (await u.api.post(`${base}/debts`, loan())).body.data;
    const quote = (await u.api.get(`${base}/debts/${d.id}/payoff?date=2026-01-16`)).body.data;
    expect(quote.outstandingPrincipalCents).toBe(1_000_000);
    expect(quote.accruedInterestCents).toBeGreaterThan(0);
    expect(quote.savingsCents).toBeGreaterThan(0);
    expect(quote.payoffCents).toBe(1_000_000 + quote.accruedInterestCents);

    const done = await u.api.post(`${base}/debts/${d.id}/payoff`, { date: '2026-01-16' });
    expect(done.status).toBe(200);
    expect(done.body.data.status).toBe('PAID_OFF');
    expect(done.body.data.summary.outstandingPrincipalCents).toBe(0);
    expect(await balanceOf(u, u.personalId, accountId)).toBe(5_000_000 - quote.payoffCents);
    const open = (await u.api.get(`${base}/payables?kind=payable`)).body.data;
    expect(open).toHaveLength(0);
    expect((await u.api.get(`${base}/debts`)).body.data).toHaveLength(0);
    expect((await u.api.get(`${base}/debts?includeClosed=true`)).body.data).toHaveLength(1);
  });

  it('cancelar remove as parcelas em aberto', async () => {
    const d = (await u.api.post(`${base}/debts`, loan({ system: 'SAC', feesCents: 1_000 }))).body.data;
    expect(d.installments[0].feesCents).toBe(1_000);
    const res = await u.api.post(`${base}/debts/${d.id}/cancel`);
    expect(res.body.data.status).toBe('CANCELED');
    expect((await u.api.get(`${base}/payables?kind=payable`)).body.data).toHaveLength(0);
  });

  it('valida a conta de pagamento e isola ambientes', async () => {
    const other = await createUser('Outra');
    const otherAcc = await createAccount(other, other.personalId);
    const bad = await u.api.post(`${base}/debts`, loan({ accountId: otherAcc.id }));
    expect(bad.body.error.code).toBe('INVALID_ACCOUNT');
    const d = (await u.api.post(`${base}/debts`, loan())).body.data;
    expect((await other.api.get(`${base}/debts/${d.id}`)).status).toBe(404);
  });
});
