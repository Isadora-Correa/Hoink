// Teste de performance da API hoink. (k6)
// Avalia latência, volume e taxa de erros nos fluxos mais usados: dashboard, extrato e novo lançamento.
// Uso: k6 run -e API_URL=http://localhost:3333 perf/load.js
import http from 'k6/http';
import { check, sleep } from 'k6';

const API = `${__ENV.API_URL || 'http://localhost:3333'}/api`;

export const options = {
  scenarios: {
    carga: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '10s', target: 10 },
        { duration: '30s', target: 20 },
        { duration: '10s', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'], // menos de 1% de erros
    http_req_duration: ['p(95)<500'], // 95% das requisições abaixo de 500 ms
    'http_req_duration{name:dashboard}': ['p(95)<800'],
    checks: ['rate>0.99'],
  },
};

const json = (token) => ({
  headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
});

// Prepara um usuário e uma conta; o token é compartilhado pelos usuários virtuais.
export function setup() {
  const email = `perf-${Date.now()}@hoink.test`;
  const signup = http.post(`${API}/auth/signup`, JSON.stringify({ name: 'Perf Test', email, password: 'senhaPerf123' }), json());
  check(signup, { 'cadastro 201': (r) => r.status === 201 });
  const token = signup.json('data.token');
  const entities = http.get(`${API}/entities`, json(token)).json('data');
  const entityId = entities.find((e) => e.kind === 'PERSONAL').id;
  const today = new Date().toISOString().slice(0, 10);
  const account = http.post(
    `${API}/entities/${entityId}/accounts`,
    JSON.stringify({ name: 'Conta Perf', type: 'CHECKING', initialBalanceCents: 1000000, referenceDate: today }),
    json(token),
  );
  return { token, entityId, accountId: account.json('data.id'), today };
}

export default function (data) {
  const p = json(data.token);
  const base = `${API}/entities/${data.entityId}`;

  const dash = http.get(`${base}/dashboard`, { ...p, tags: { name: 'dashboard' } });
  check(dash, { 'dashboard 200': (r) => r.status === 200 });

  const list = http.get(`${base}/transactions?page=1&pageSize=20`, { ...p, tags: { name: 'transactions_list' } });
  check(list, { 'extrato 200': (r) => r.status === 200 });

  const created = http.post(
    `${base}/transactions`,
    JSON.stringify({
      type: 'EXPENSE',
      description: `Carga VU ${__VU}`,
      amountCents: 1000 + (__ITER % 500),
      accountId: data.accountId,
      competenceDate: data.today,
    }),
    { ...p, tags: { name: 'transaction_create' } },
  );
  check(created, { 'lançamento 201': (r) => r.status === 201 });

  const cashflow = http.get(`${base}/planning/cashflow`, { ...p, tags: { name: 'cashflow' } });
  check(cashflow, { 'projeção 200': (r) => r.status === 200 });

  const health = http.get(`${API.replace('/api', '')}/health`, { tags: { name: 'health' } });
  check(health, { 'health ok': (r) => r.status === 200 });

  sleep(0.5);
}
