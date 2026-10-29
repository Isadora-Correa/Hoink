import request from 'supertest';
import { createApp } from '../src/app';
import { prisma } from '../src/lib/prisma';

export const app = createApp();

export async function resetDb() {
  await prisma.$executeRawUnsafe(`
    TRUNCATE TABLE audit_logs, idempotency_keys, market_rates, achievements, notifications, transactions, transfers, categories, accounts,
      entity_members, financial_entities, password_reset_tokens, sessions, users RESTART IDENTITY CASCADE`);
}

let seq = 0;

export interface TestUser {
  token: string;
  userId: string;
  email: string;
  personalId: string;
  businessId: string;
  api: {
    get: (url: string) => request.Test;
    post: (url: string, body?: object) => request.Test;
    patch: (url: string, body?: object) => request.Test;
    put: (url: string, body?: object) => request.Test;
    delete: (url: string) => request.Test;
  };
}

export async function createUser(name = 'Miguel'): Promise<TestUser> {
  const email = `user${++seq}-${Date.now()}@hoink.test`;
  const res = await request(app).post('/api/auth/signup').send({ name, email, password: 'senhaForte123', withBusiness: true });
  if (res.status !== 201) throw new Error(`signup falhou: ${res.status} ${JSON.stringify(res.body)}`);
  const token: string = res.body.data.token;
  const auth = (t: request.Test) => t.set('Authorization', `Bearer ${token}`);
  const api = {
    get: (url: string) => auth(request(app).get(url)),
    post: (url: string, body: object = {}) => auth(request(app).post(url)).send(body),
    patch: (url: string, body: object = {}) => auth(request(app).patch(url)).send(body),
    put: (url: string, body: object = {}) => auth(request(app).put(url)).send(body),
    delete: (url: string) => auth(request(app).delete(url)),
  };
  const entities = (await api.get('/api/entities')).body.data as { id: string; kind: string }[];
  return {
    token,
    userId: res.body.data.user.id,
    email,
    personalId: entities.find((e) => e.kind === 'PERSONAL')!.id,
    businessId: entities.find((e) => e.kind === 'BUSINESS')!.id,
    api,
  };
}

export async function createAccount(u: TestUser, entityId: string, initialBalanceCents = 0, name = 'Nubank') {
  const res = await u.api.post(`/api/entities/${entityId}/accounts`, {
    name,
    institution: name,
    type: 'CHECKING',
    initialBalanceCents,
    referenceDate: '2025-01-01',
  });
  if (res.status !== 201) throw new Error(`conta falhou: ${JSON.stringify(res.body)}`);
  return res.body.data as { id: string; balanceCents: number };
}

export async function categoryId(u: TestUser, entityId: string, name: string) {
  const res = await u.api.get(`/api/entities/${entityId}/categories`);
  return (res.body.data as { id: string; name: string }[]).find((c) => c.name === name)!.id;
}

export async function balanceOf(u: TestUser, entityId: string, accountId: string): Promise<number> {
  return (await u.api.get(`/api/entities/${entityId}/accounts/${accountId}`)).body.data.balanceCents;
}
