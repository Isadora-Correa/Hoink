import { expect, test } from '@playwright/test';
import { api, login, reveal, see, seedUser, typeInto } from './helpers';

test('guardar no cofrinho de um desejo tira do saldo, não vira despesa e desbloqueia conquista', async ({ page }) => {
  const u = await seedUser();
  const { piggy } = (
    await api(`/entities/${u.personalId}/piggy-banks`, {
      method: 'POST',
      token: u.token,
      body: JSON.stringify({ kind: 'WISH', name: 'Drone E2E', goalCents: 80000, priority: 1 }),
    })
  ).data;

  await page.goto('/cofrinhos');
  await login(page, u.email);
  await expect(see(page, 'Drone E2E')).toBeVisible();
  await (await reveal(page, page.getByRole('button', { name: 'Guardar' }).first())).click();
  await typeInto(page, 'Valor', '400,00');
  await page.getByRole('button', { name: 'Guardar', exact: true }).last().click();
  await expect(see(page, 'Conquista')).toBeVisible();

  const after = (await api(`/entities/${u.personalId}/piggy-banks/${piggy.id}`, { token: u.token })).data;
  expect(after).toMatchObject({ balanceCents: 40000, progressBps: 5000 });
  const account = (await api(`/entities/${u.personalId}/accounts/${u.accountId}`, { token: u.token })).data;
  expect(account.balanceCents).toBe(60000);
  const dash = (await api(`/entities/${u.personalId}/dashboard`, { token: u.token })).data;
  expect(dash.realized.expenseCents).toBe(0);
  const profile = (await api('/gamification', { token: u.token })).data;
  expect(profile.unlocked.map((a: { code: string }) => a.code)).toEqual(expect.arrayContaining(['FIRST_DEPOSIT', 'GOAL_50']));
});

test('patrimônio mostra ativos menos passivos', async ({ page }) => {
  const u = await seedUser();
  await page.goto('/patrimonio');
  await login(page, u.email);
  await expect(see(page, 'PATRIMÔNIO LÍQUIDO')).toBeVisible();
  await expect(see(page, 'R$ 1.000,00')).toBeVisible();
});
