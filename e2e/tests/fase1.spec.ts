import { expect, test } from '@playwright/test';
import { api, login, reveal, see, seedUser, typeInto } from './helpers';

test('rota protegida exige login e preserva o destino', async ({ page }) => {
  const u = await seedUser();
  await page.goto('/contas');
  await expect(page).toHaveURL(/\/login\?from=%2Fcontas|\/login\?from=\/contas/);
  await login(page, u.email);
  await expect(page).toHaveURL(/\/contas$/);
  await expect(see(page, 'Conta E2E')).toBeVisible();
});

test('registra despesa pela interface e o saldo é recalculado pelo backend', async ({ page }) => {
  const u = await seedUser();
  await page.goto('/');
  await login(page, u.email);
  await expect(see(page, 'R$ 1.000,00')).toBeVisible();

  await page.goto('/lancamentos/novo');
  await typeInto(page, /0,00/, '350,00', { secret: true }); // nome vem do placeholder, que some ao digitar
  await typeInto(page, 'Descrição da despesa', 'Supermercado E2E');
  await (await reveal(page, page.getByRole('button', { name: 'Mercado', exact: true }))).click();
  await (await reveal(page, page.getByRole('button', { name: 'Origem do dinheiro' }))).click();
  // Opções do menu suspenso aparecem como botões/itens na árvore de acessibilidade.
  await page.getByRole('menuitem', { name: /Conta E2E/ }).or(page.getByRole('button', { name: /Conta E2E/ })).last().click();
  await expect(see(page, 'Conta E2E •')).toBeVisible();
  await (await reveal(page, page.getByRole('button', { name: 'Salvar despesa' }))).click();
  await expect(see(page, 'Lançamento salvo')).toBeVisible();

  // Fonte de verdade: o saldo calculado pela API a partir das movimentações.
  const account = (await api(`/entities/${u.personalId}/accounts/${u.accountId}`, { token: u.token })).data;
  expect(account.balanceCents).toBe(65000);
  const list = await api(`/entities/${u.personalId}/transactions?q=Supermercado%20E2E`, { token: u.token });
  expect(list.meta.total).toBe(1);
  expect(list.data[0]).toMatchObject({ amountCents: 35000, type: 'EXPENSE', status: 'SETTLED' });
  expect(list.data[0].category.name).toBe('Mercado');

  await page.goto('/contas');
  await expect(see(page, 'R$ 650,00')).toBeVisible();
});

test('lista de lançamentos filtra por busca', async ({ page }) => {
  const u = await seedUser();
  for (const [description, cents] of [['Padaria Central', 1250], ['Posto Shell', 20000]] as const) {
    await api(`/entities/${u.personalId}/transactions`, {
      method: 'POST',
      token: u.token,
      body: JSON.stringify({ type: 'EXPENSE', description, amountCents: cents, accountId: u.accountId, competenceDate: new Date().toISOString().slice(0, 10) }),
    });
  }
  await page.goto('/lancamentos');
  await login(page, u.email);
  await expect(see(page, '2 lançamento(s) encontrados')).toBeVisible();
  await typeInto(page, /Buscar por descrição/, 'padaria');
  await expect(see(page, '1 lançamento(s) encontrados')).toBeVisible();
  await expect(see(page, 'Padaria Central')).toBeVisible();
});

test('cria uma conta recorrente pela interface e as próximas ocorrências são geradas', async ({ page }) => {
  const u = await seedUser();
  await page.goto('/lancamentos/novo');
  await login(page, u.email);
  await typeInto(page, /0,00/, '250,00', { secret: true });
  await typeInto(page, 'Descrição da despesa', 'Conta de energia E2E');
  await (await reveal(page, page.getByRole('button', { name: 'Origem do dinheiro' }))).click();
  await page.getByRole('menuitem', { name: /Conta E2E/ }).or(page.getByRole('button', { name: /Conta E2E/ })).last().click();
  await (await reveal(page, page.getByRole('button', { name: /Mais opções/ }))).click();
  await (await reveal(page, page.getByRole('switch', { name: /recorrente/ }).or(page.getByRole('checkbox', { name: /recorrente/ })).first())).click();
  await (await reveal(page, page.getByRole('button', { name: 'Variável' }))).click();
  await (await reveal(page, page.getByRole('button', { name: 'Salvar despesa' }))).click();
  await expect(see(page, 'Recorrência criada')).toBeVisible();

  const rules = (await api(`/entities/${u.personalId}/recurring`, { token: u.token })).data;
  expect(rules).toHaveLength(1);
  expect(rules[0]).toMatchObject({ description: 'Conta de energia E2E', frequency: 'MONTHLY', amountKind: 'VARIABLE', amountCents: 25000 });
  // Horizonte de 90 dias: ao menos 3 ocorrências; a primeira já paga (status padrão "Liquidado").
  expect(rules[0].stats.settled).toBe(1);
  expect(rules[0].stats.settled + rules[0].stats.open).toBeGreaterThanOrEqual(3);

  await page.goto('/recorrencias');
  await expect(see(page, 'Conta de energia E2E')).toBeVisible();
});
