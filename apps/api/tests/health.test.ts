import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { app } from './helpers';

describe('operação', () => {
  it('health e versão', async () => {
    expect((await request(app).get('/health')).body).toEqual({ status: 'ok', db: 'ok' });
    expect((await request(app).get('/version')).body.name).toBe('hoink-api');
  });
});

describe('observabilidade', () => {
  it('expõe métricas Prometheus com requisições e eventos de negócio', async () => {
    await request(app).post('/api/auth/login').send({ email: 'ninguem@hoink.test', password: 'x' });
    const res = await request(app).get('/metrics');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('text/plain');
    expect(res.text).toContain('http_requests_total{method="POST",route="/api/auth/login",status="401"');
    expect(res.text).toContain('hoink_business_events_total{event="auth.login_failed"');
    expect(res.text).toContain('http_request_duration_seconds_bucket');
  });

  it('versão identifica o commit publicado', async () => {
    const res = await request(app).get('/version');
    expect(res.body).toMatchObject({ name: 'hoink-api', commit: expect.any(String), startedAt: expect.any(String) });
  });
});
