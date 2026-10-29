import request from 'supertest';
import { beforeAll, describe, expect, it } from 'vitest';
import { mailer } from '../src/lib/mailer';
import { app, createUser, resetDb } from './helpers';

beforeAll(resetDb);

describe('autenticação', () => {
  it('cadastra, cria ambientes Pessoal e Profissional e autentica', async () => {
    const u = await createUser();
    const me = await u.api.get('/api/auth/me');
    expect(me.status).toBe(200);
    expect(me.body.data.email).toBe(u.email);
    expect(me.body.data.passwordHash).toBeUndefined();
    const entities = await u.api.get('/api/entities');
    expect(entities.body.data.map((e: { kind: string }) => e.kind).sort()).toEqual(['BUSINESS', 'PERSONAL']);
  });

  it('recusa e-mail duplicado e senha fraca', async () => {
    const u = await createUser();
    const dup = await request(app).post('/api/auth/signup').send({ name: 'Xavier', email: u.email, password: 'senhaForte123' });
    expect(dup.status).toBe(409);
    const weak = await request(app).post('/api/auth/signup').send({ name: 'Xavier', email: 'weak@hoink.test', password: '123' });
    expect(weak.status).toBe(400);
  });

  it('login com senha errada falha; correta funciona', async () => {
    const u = await createUser();
    expect((await request(app).post('/api/auth/login').send({ email: u.email, password: 'errada123' })).status).toBe(401);
    const ok = await request(app).post('/api/auth/login').send({ email: u.email, password: 'senhaForte123' });
    expect(ok.status).toBe(200);
    expect(ok.body.data.token).toBeTypeOf('string');
  });

  it('rotas protegidas exigem token', async () => {
    expect((await request(app).get('/api/entities')).status).toBe(401);
    expect((await request(app).get('/api/entities').set('Authorization', 'Bearer tokeninvalidotokeninvalido')).status).toBe(401);
  });

  it('logout revoga a sessão', async () => {
    const u = await createUser();
    expect((await u.api.post('/api/auth/logout')).status).toBe(204);
    expect((await u.api.get('/api/auth/me')).status).toBe(401);
  });

  it('troca de senha revoga as outras sessões', async () => {
    const u = await createUser();
    const other = await request(app).post('/api/auth/login').send({ email: u.email, password: 'senhaForte123' });
    const otherToken = other.body.data.token;
    expect((await u.api.post('/api/auth/change-password', { currentPassword: 'errada', newPassword: 'novaSenha456' })).status).toBe(400);
    expect((await u.api.post('/api/auth/change-password', { currentPassword: 'senhaForte123', newPassword: 'novaSenha456' })).status).toBe(200);
    expect((await u.api.get('/api/auth/me')).status).toBe(200);
    expect((await request(app).get('/api/auth/me').set('Authorization', `Bearer ${otherToken}`)).status).toBe(401);
  });

  it('lista e revoga sessões', async () => {
    const u = await createUser();
    await request(app).post('/api/auth/login').send({ email: u.email, password: 'senhaForte123' });
    const list = await u.api.get('/api/auth/sessions');
    expect(list.body.data).toHaveLength(2);
    const other = list.body.data.find((s: { current: boolean }) => !s.current);
    expect((await u.api.delete(`/api/auth/sessions/${other.id}`)).status).toBe(204);
    expect((await u.api.get('/api/auth/sessions')).body.data).toHaveLength(1);
  });

  it('recuperação de senha por código, de uso único', async () => {
    const u = await createUser();
    const unknown = await request(app).post('/api/auth/forgot-password').send({ email: 'ninguem@hoink.test' });
    expect(unknown.status).toBe(200);
    await request(app).post('/api/auth/forgot-password').send({ email: u.email });
    const mail = mailer.sent.at(-1)!;
    expect(mail.to).toBe(u.email);
    const token = mail.text.split(': ').at(-1)!;
    expect((await request(app).post('/api/auth/reset-password').send({ token, password: 'outraSenha789' })).status).toBe(200);
    expect((await request(app).post('/api/auth/reset-password').send({ token, password: 'outraSenha789' })).status).toBe(400);
    // Sessões antigas são revogadas após a redefinição.
    expect((await u.api.get('/api/auth/me')).status).toBe(401);
    expect((await request(app).post('/api/auth/login').send({ email: u.email, password: 'outraSenha789' })).status).toBe(200);
  });
});
