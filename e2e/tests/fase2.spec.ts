import { expect, test } from '@playwright/test';
import { api, login, reveal, see, seedUser, typeInto } from './helpers';

test('compra parcelada no cartão e pagamento da fatura não duplicam a despesa (RN08)', async ({ page }) => {
  const u = await seedUser();
  const card = (
    await api(`/entities/${u.personalId}/cards`, {
      method: 'POST',
      token: u.token,
      body: JSON.stringify({ name: 'Cartão E2E', limitCents: 500000, closingDay: 3, dueDay: 10, paymentAccountId: u.accountId }),
    })
  ).data;

  await page.goto(`/cartoes/${u.personalId}/${card.id}`);
  await login(page, u.email);
  await expect(see(page, 'Cartão E2E')).toBeVisible();

  await page.getByRole('button', { name: 'Nova compra' }).click();
  await typeInto(page, 'Descrição', 'Fone E2E');
  await typeInto(page, 'Valor total', '300,00');
  await page.getByRole('button', { name: /Parcelas/ }).click();
  await page.getByRole('menuitem', { name: '3x', exact: true }).or(page.getByRole('button', { name: '3x', exact: true })).last().click();
  await page.getByRole('button', { name: 'Registrar' }).click();
  await expect(see(page, 'Compra parcelada em 3x registrada')).toBeVisible();

  // A API dividiu a compra em 3 faturas e o limite foi consumido; o caixa não mudou.
  const purchased = (await api(`/entities/${u.personalId}/cards/${card.id}`, { token: u.token })).data;
  expect(purchased).toMatchObject({ usedCents: 30000, availableCents: 470000 });
  const before = (await api(`/entities/${u.personalId}/accounts/${u.accountId}`, { token: u.token })).data;
  expect(before.balanceCents).toBe(100000);

  // Paga a fatura atual (1ª parcela) pela interface.
  await (await reveal(page, page.getByRole('button', { name: /Pagar fatura|Antecipar pagamento/ }))).click();
  await page.getByRole('button', { name: 'Pagar', exact: true }).click();
  await expect(see(page, 'Fatura paga')).toBeVisible();

  const after = (await api(`/entities/${u.personalId}/accounts/${u.accountId}`, { token: u.token })).data;
  expect(after.balanceCents).toBe(90000);
  // Sem ?month, a API usa o mês corrente no fuso da aplicação (mesmo da data da compra no app).
  const dash = (await api(`/entities/${u.personalId}/dashboard`, { token: u.token })).data;
  // Despesa do mês = só a 1ª parcela; o pagamento da fatura é transferência.
  expect(dash.realized.expenseCents).toBe(10000);
  expect(dash.realized.transfersOutCents).toBe(10000);
});

test('planejamento mostra a projeção de caixa de 30/60/90 dias', async ({ page }) => {
  const u = await seedUser();
  await page.goto('/planejamento');
  await login(page, u.email);
  await expect(see(page, 'Fluxo de caixa projetado')).toBeVisible();
  await expect(see(page, 'Próximos 30 dias')).toBeVisible();
  await page.getByRole('button', { name: '90 dias' }).click();
  await expect(see(page, 'Próximos 90 dias')).toBeVisible();
  await expect(see(page, 'R$ 1.000,00')).toBeVisible();
});
