import request from 'supertest';
import { beforeAll, describe, expect, it } from 'vitest';
import { app, createAccount, createUser, resetDb } from './helpers';

beforeAll(resetDb);

// PNG 1×1 válido
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);

describe('conta profissional opcional', () => {
  it('cadastro sem PJ cria apenas o ambiente Pessoal', async () => {
    const res = await request(app)
      .post('/api/auth/signup')
      .send({ name: 'Bia Solo', email: `solo-${Date.now()}@hoink.test`, password: 'senhaForte123' });
    const token = res.body.data.token;
    const entities = await request(app).get('/api/entities').set('Authorization', `Bearer ${token}`);
    expect(entities.body.data.map((e: { kind: string }) => e.kind)).toEqual(['PERSONAL']);
  });

  it('ativar, desativar e reativar preserva os dados do PJ', async () => {
    const u = await createUser();
    await createAccount(u, u.businessId, 50000, 'Inter PJ');

    expect((await u.api.post(`/api/entities/${u.personalId}/archive`)).body.error.code).toBe('PERSONAL_REQUIRED');
    expect((await u.api.post(`/api/entities/${u.businessId}/archive`)).status).toBe(204);
    expect((await u.api.get('/api/entities')).body.data).toHaveLength(1);
    // Ambiente desativado fica inacessível e fora do consolidado.
    expect((await u.api.get(`/api/entities/${u.businessId}/accounts`)).status).toBe(404);
    expect((await u.api.get('/api/consolidated/dashboard?month=2025-06')).body.data.totalBalanceCents).toBe(0);

    const enabled = await u.api.post('/api/entities/business');
    expect(enabled.status).toBe(201);
    expect(enabled.body.data.id).toBe(u.businessId);
    const accounts = await u.api.get(`/api/entities/${u.businessId}/accounts`);
    expect(accounts.body.data.map((a: { name: string }) => a.name)).toEqual(['Inter PJ']);
    // Idempotente: ativar de novo não cria outro ambiente.
    expect((await u.api.post('/api/entities/business')).body.data.id).toBe(u.businessId);
  });

  it('ativar PJ pela primeira vez cria o ambiente com categorias padrão', async () => {
    const signup = await request(app)
      .post('/api/auth/signup')
      .send({ name: 'Caio Novo', email: `novo-${Date.now()}@hoink.test`, password: 'senhaForte123' });
    const auth = { Authorization: `Bearer ${signup.body.data.token}` };
    const created = await request(app).post('/api/entities/business').set(auth);
    expect(created.body.data.kind).toBe('BUSINESS');
    const cats = await request(app).get(`/api/entities/${created.body.data.id}/categories`).set(auth);
    expect(cats.body.data.map((c: { name: string }) => c.name)).toContain('Serviços prestados');
  });
});

describe('foto de perfil', () => {
  it('envia, consulta e remove a foto', async () => {
    const u = await createUser();
    expect((await u.api.get('/api/auth/me')).body.data.avatarUpdatedAt).toBeNull();
    expect((await u.api.get('/api/auth/me/avatar')).status).toBe(404);

    const up = await request(app)
      .put('/api/auth/me/avatar')
      .set('Authorization', `Bearer ${u.token}`)
      .set('Content-Type', 'image/png')
      .send(PNG);
    expect(up.status).toBe(200);
    expect(up.body.data.avatarUpdatedAt).toBeTypeOf('string');

    const got = await u.api.get('/api/auth/me/avatar').buffer(true).parse((res, cb) => {
      const chunks: Buffer[] = [];
      res.on('data', (c: Buffer) => chunks.push(c));
      res.on('end', () => cb(null, Buffer.concat(chunks)));
    });
    expect(got.headers['content-type']).toBe('image/png');
    expect(Buffer.compare(got.body as Buffer, PNG)).toBe(0);

    expect((await u.api.delete('/api/auth/me/avatar')).body.data.avatarUpdatedAt).toBeNull();
  });

  it('recusa arquivos que não são imagem (pelo conteúdo) e arquivos grandes', async () => {
    const u = await createUser();
    const put = (body: Buffer, type = 'image/png') =>
      request(app).put('/api/auth/me/avatar').set('Authorization', `Bearer ${u.token}`).set('Content-Type', type).send(body);
    expect((await put(Buffer.from('<script>alert(1)</script>'))).status).toBe(415);
    expect((await put(Buffer.alloc(3 * 1024 * 1024, 1))).status).toBe(413);
    // Foto de outro usuário não é acessível: o endpoint sempre usa o usuário autenticado.
    expect((await request(app).get('/api/auth/me/avatar')).status).toBe(401);
  });
});
