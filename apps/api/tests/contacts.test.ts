import { beforeAll, describe, expect, it } from 'vitest';
import { balanceOf, categoryId, createAccount, createUser, resetDb, type TestUser } from './helpers';

let u: TestUser;
let e: string;
let accountId: string;
let servicos: string;

beforeAll(async () => {
  await resetDb();
  u = await createUser();
  e = u.businessId;
  accountId = (await createAccount(u, e, 0, 'Inter PJ')).id;
  servicos = await categoryId(u, e, 'Serviços prestados');
});

const contact = async (body: object) => {
  const r = await u.api.post(`/api/entities/${e}/contacts`, body);
  expect(r.status).toBe(201);
  return r.body.data as { id: string };
};

describe('clientes e fornecedores', () => {
  it('valida CPF/CNPJ e e-mail', async () => {
    const bad = await u.api.post(`/api/entities/${e}/contacts`, { kind: 'CLIENT', name: 'X', document: '123', email: 'nope' });
    expect(bad.status).toBe(400);
    expect(Object.keys(bad.body.error.details.fieldErrors).sort()).toEqual(['document', 'email']);
    const ok = await u.api.post(`/api/entities/${e}/contacts`, { kind: 'CLIENT', name: 'Studio Alpha', document: '12.345.678/0001-90' });
    expect(ok.body.data.document).toBe('12345678000190');
  });

  it('recebimento parcial em meses diferentes aparece em cada mês (faturado ≠ recebido)', async () => {
    const c = await contact({ kind: 'CLIENT', name: 'Cliente Parcial' });
    const inv = await u.api.post(`/api/entities/${e}/transactions`, {
      type: 'INCOME', description: 'Projeto site', amountCents: 300000, accountId, categoryId: servicos,
      contactId: c.id, status: 'PENDING', competenceDate: '2025-03-01', dueDate: '2025-03-05',
    });
    expect(inv.body.data.counterparty).toBe('Cliente Parcial');
    expect(inv.body.data.contact.id).toBe(c.id);
    const id = inv.body.data.id;
    await u.api.post(`/api/entities/${e}/transactions/${id}/settle`, { date: '2025-03-10', amountCents: 100000 });
    await u.api.post(`/api/entities/${e}/transactions/${id}/settle`, { date: '2025-04-12', amountCents: 200000 });

    const detail = (await u.api.get(`/api/entities/${e}/transactions/${id}`)).body.data;
    expect(detail.status).toBe('SETTLED');
    expect(detail.settlements.map((s: { date: string; amountCents: number }) => [s.date, s.amountCents])).toEqual([
      ['2025-03-10', 100000],
      ['2025-04-12', 200000],
    ]);

    const march = (await u.api.get(`/api/entities/${e}/dashboard?month=2025-03`)).body.data;
    const april = (await u.api.get(`/api/entities/${e}/dashboard?month=2025-04`)).body.data;
    expect(march.realized.incomeCents).toBe(100000);
    expect(april.realized.incomeCents).toBe(200000);

    const st = (await u.api.get(`/api/entities/${e}/accounts/${accountId}/statement?from=2025-03-01&to=2025-03-31`)).body.data;
    expect(st.entries).toHaveLength(1);
    expect(st.entries[0]).toMatchObject({ amountCents: 100000, partial: true, date: '2025-03-10' });
    expect(st.closingBalanceCents).toBe(100000);

    const summary = (await u.api.get(`/api/entities/${e}/contacts/${c.id}`)).body.data.summary;
    expect(summary).toMatchObject({ billedCents: 300000, receivedCents: 300000, receivableOpenCents: 0 });
    expect(await balanceOf(u, e, accountId)).toBe(300000);
  });

  it('inadimplência: cobrança vencida aparece em atraso no cliente e nas contas a receber', async () => {
    const c = await contact({ kind: 'CLIENT', name: 'Cliente Atrasado' });
    await u.api.post(`/api/entities/${e}/transactions`, {
      type: 'INCOME', description: 'Mensalidade fevereiro', amountCents: 150000, accountId, contactId: c.id,
      status: 'PENDING', competenceDate: '2025-02-01', dueDate: '2025-02-10',
    });
    const partial = await u.api.post(`/api/entities/${e}/transactions`, {
      type: 'INCOME', description: 'Mensalidade março', amountCents: 150000, accountId, contactId: c.id,
      status: 'PENDING', competenceDate: '2025-03-01', dueDate: '2025-03-10',
    });
    await u.api.post(`/api/entities/${e}/transactions/${partial.body.data.id}/settle`, { date: '2025-03-10', amountCents: 50000 });

    const s = (await u.api.get(`/api/entities/${e}/contacts/${c.id}`)).body.data.summary;
    expect(s).toMatchObject({ billedCents: 300000, receivedCents: 50000, receivableOpenCents: 250000, receivableOverdueCents: 250000 });

    const overdue = await u.api.get(`/api/entities/${e}/payables?kind=receivable&status=overdue&contactId=${c.id}`);
    expect(overdue.body.totals).toMatchObject({ count: 2, overdueCents: 250000 });
    expect(overdue.body.data.every((t: { effectiveStatus: string }) => t.effectiveStatus === 'OVERDUE')).toBe(true);

    const clients = (await u.api.get(`/api/entities/${e}/contacts?kind=CLIENT`)).body.data;
    expect(clients.find((x: { id: string }) => x.id === c.id).summary.receivableOverdueCents).toBe(250000);
  });

  it('fornecedor: contas a pagar e histórico de pagamentos', async () => {
    const f = await contact({ kind: 'SUPPLIER', name: 'Gráfica Rápida' });
    const bill = await u.api.post(`/api/entities/${e}/transactions`, {
      type: 'EXPENSE', description: 'Cartões de visita', amountCents: 45000, accountId, contactId: f.id,
      status: 'PENDING', competenceDate: '2099-01-01', dueDate: '2099-01-10',
    });
    const payables = await u.api.get(`/api/entities/${e}/payables?kind=payable`);
    expect(payables.body.data.map((t: { id: string }) => t.id)).toContain(bill.body.data.id);
    await u.api.post(`/api/entities/${e}/transactions/${bill.body.data.id}/settle`, { date: '2025-06-01' });
    const s = (await u.api.get(`/api/entities/${e}/contacts/${f.id}`)).body.data;
    expect(s.summary).toMatchObject({ purchasedCents: 45000, paidCents: 45000, payableOpenCents: 0 });
    expect(s.transactions).toHaveLength(1);
    const suppliers = (await u.api.get(`/api/entities/${e}/contacts?kind=SUPPLIER`)).body.data;
    expect(suppliers.map((x: { name: string }) => x.name)).toEqual(['Gráfica Rápida']);
  });

  it('editar um lançamento liquidado reescreve o histórico de liquidações e mantém o saldo coerente', async () => {
    const acc = (await createAccount(u, e, 0, 'Conta Edição')).id;
    const t = await u.api.post(`/api/entities/${e}/transactions`, {
      type: 'EXPENSE', description: 'Software', amountCents: 10000, accountId: acc, competenceDate: '2025-05-01',
    });
    await u.api.patch(`/api/entities/${e}/transactions/${t.body.data.id}`, { amountCents: 12000 });
    expect(await balanceOf(u, e, acc)).toBe(-12000);
    const d = (await u.api.get(`/api/entities/${e}/transactions/${t.body.data.id}`)).body.data;
    expect(d.settlements).toEqual([expect.objectContaining({ amountCents: 12000, date: '2025-05-01' })]);
    await u.api.patch(`/api/entities/${e}/transactions/${t.body.data.id}`, { status: 'PENDING' });
    expect(await balanceOf(u, e, acc)).toBe(0);
  });

  it('isola contatos por ambiente e arquiva sem perder histórico', async () => {
    const c = await contact({ kind: 'CLIENT', name: 'Somente PJ' });
    const pf = await createAccount(u, u.personalId, 0, 'PF');
    const cross = await u.api.post(`/api/entities/${u.personalId}/transactions`, {
      type: 'INCOME', description: 'X', amountCents: 100, accountId: pf.id, contactId: c.id, competenceDate: '2025-06-01',
    });
    expect(cross.body.error.code).toBe('INVALID_CONTACT');
    const archived = await u.api.post(`/api/entities/${e}/contacts/${c.id}/archive`);
    expect(archived.body.data.archived).toBe(true);
    const list = (await u.api.get(`/api/entities/${e}/contacts`)).body.data;
    expect(list.map((x: { id: string }) => x.id)).not.toContain(c.id);
    const other = await createUser('Intrusa');
    expect((await other.api.get(`/api/entities/${e}/contacts/${c.id}`)).status).toBe(404);
  });
});
