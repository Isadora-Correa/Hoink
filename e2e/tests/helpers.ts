import { expect, type Locator, type Page } from '@playwright/test';

const API = process.env.E2E_API_URL ?? 'http://localhost:3333';
const PASSWORD = 'senhaE2e123';

export async function api(path: string, init: RequestInit & { token?: string } = {}) {
  const res = await fetch(`${API}/api${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', ...(init.token ? { authorization: `Bearer ${init.token}` } : {}) },
  });
  const body = res.status === 204 ? null : await res.json();
  if (!res.ok) throw new Error(`${path}: ${res.status} ${JSON.stringify(body)}`);
  return body;
}

/** Cria um usuário isolado com uma conta de R$ 1.000,00 no ambiente Pessoal. */
export async function seedUser() {
  const email = `e2e-${Date.now()}-${Math.random().toString(36).slice(2, 7)}@hoink.test`;
  const { data } = await api('/auth/signup', { method: 'POST', body: JSON.stringify({ name: 'Ana Teste', email, password: PASSWORD }) });
  const token = data.token as string;
  const entities = (await api('/entities', { token })).data as { id: string; kind: string }[];
  const personalId = entities.find((e) => e.kind === 'PERSONAL')!.id;
  // Data de referência no passado: evita depender do fuso (o app usa America/Sao_Paulo; toISOString, UTC).
  const referenceDate = new Date(Date.now() - 30 * 86_400_000).toISOString().slice(0, 10);
  const account = (
    await api(`/entities/${personalId}/accounts`, {
      method: 'POST',
      token,
      body: JSON.stringify({ name: 'Conta E2E', institution: 'Banco Teste', type: 'CHECKING', initialBalanceCents: 100000, referenceDate }),
    })
  ).data;
  return { email, token, personalId, accountId: account.id as string };
}

/**
 * Campos do Flutter Web: o editor de texto interno é anexado ao receber foco; digitar
 * imediatamente pode perder o primeiro caractere. Foca, aguarda e digita tecla a tecla.
 */
export async function typeInto(page: Page, name: string | RegExp, value: string, { secret = false } = {}) {
  const box = page.getByRole('textbox', { name });
  await box.click();
  await page.waitForTimeout(300);
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.type(value, { delay: 15 });
  if (!secret) await expect(box).toHaveValue(value);
}

/**
 * Texto visível na árvore de acessibilidade do Flutter: pode estar no conteúdo do nó
 * ou agrupado no aria-label de um container.
 */
export function see(page: Page, text: string) {
  return page.getByText(text).or(page.locator(`[aria-label*="${text}"]`)).first();
}

/**
 * O Flutter só cria nós de acessibilidade para o que está na tela; rola (roda do mouse)
 * até o elemento existir, já que scrollIntoView não atua sobre o canvas.
 */
export async function reveal(page: Page, locator: Locator) {
  const { width, height } = page.viewportSize()!;
  await page.mouse.move(width / 2, height / 2);
  for (let i = 0; i < 20 && !(await locator.isVisible().catch(() => false)); i++) {
    await page.mouse.wheel(0, 300);
    await page.waitForTimeout(150);
  }
  return locator;
}

export async function login(page: Page, email: string) {
  await expect(page.getByRole('button', { name: 'Entrar' })).toBeVisible();
  await page.waitForTimeout(500);
  await typeInto(page, 'E-mail', email);
  await typeInto(page, 'Senha', PASSWORD, { secret: true });
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).not.toHaveURL(/\/login/);
}
