import { expect, test } from '@playwright/test';
import { api, login, see, seedUser } from './helpers';

test('Costelinha responde "quanto posso investir" com números calculados pela API', async ({ page }) => {
  const u = await seedUser();
  await page.goto('/costelinha');
  await login(page, u.email);
  await page.getByRole('button', { name: /Quanto posso investir/ }).first().click();
  await expect(see(page, 'Calculado pela hoink.')).toBeVisible();
  const answer = (await api(`/entities/${u.personalId}/assistant/ask`, { method: 'POST', token: u.token, body: JSON.stringify({ question: 'Quanto posso investir este mês?' }) })).data;
  expect(answer.intent).toBe('INVEST_CAPACITY');
  expect(answer.facts.find((f: { label: string }) => f.label === 'Saldo disponível hoje').value).toBe(100000);
});

test('relatório de receitas e despesas: prévia na tela e PDF baixado pela API', async ({ page }) => {
  const u = await seedUser();
  await page.goto('/relatorios');
  await login(page, u.email);
  await page.getByRole('button', { name: 'Ver na tela' }).click();
  await expect(see(page, 'Resumo')).toBeVisible();
  const res = await fetch(`${process.env.E2E_API_URL ?? 'http://localhost:3333'}/api/entities/${u.personalId}/reports/receitas-despesas?format=pdf`, {
    headers: { authorization: `Bearer ${u.token}` },
  });
  expect(res.status).toBe(200);
  expect(res.headers.get('content-type')).toBe('application/pdf');
  expect(Buffer.from(await res.arrayBuffer()).subarray(0, 5).toString()).toBe('%PDF-');
});
