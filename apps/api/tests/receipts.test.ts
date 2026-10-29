import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { env } from '../src/config/env';
import { accessKeyCheckDigit } from '../src/domain/nfce';
import { categoryId, createAccount, createUser, resetDb, type TestUser } from './helpers';

let u: TestUser;
let base: string;
let acc: { id: string };

function key(tpEmis = '1') {
  const first43 = `352610${'12345678000195'}65001000012345${tpEmis}12345678`;
  return first43 + accessKeyCheckDigit(first43);
}
const html = readFileSync(join(__dirname, 'fixtures/nfce-padrao.html'), 'utf8');

beforeEach(async () => {
  await resetDb();
  u = await createUser();
  base = `/api/entities/${u.personalId}`;
  acc = await createAccount(u, u.personalId, 100_000);
});
afterEach(() => {
  vi.unstubAllGlobals();
  env.RECEIPT_LOOKUP = 'false';
});

describe('nota fiscal (NFC-e)', () => {
  it('sem consulta externa, usa o que o QR offline traz e o usuário completa', async () => {
    const k = key('9');
    const res = await u.api.post(`${base}/receipts/preview`, { qr: `http://www.sefaz.rs.gov.br/NFCE/NFCE-COM.aspx?p=${k}|2|1|15|35.00|ab|1|H` });
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ source: 'QR', accessKey: k, totalCents: 3500, issuedAt: '2026-10-15', cnpj: '12345678000195', alreadyRegistered: false });
    expect((await u.api.post(`${base}/receipts/preview`, { qr: 'https://exemplo.com/qualquer-coisa' })).body.error.code).toBe('INVALID_RECEIPT');
  });

  it('consulta a página da Sefaz e sugere a categoria; não segue redirecionamento para fora do gov.br', async () => {
    env.RECEIPT_LOOKUP = 'true';
    const k = key();
    const fetchMock = vi.fn(async (url: string) => {
      if (url.includes('brasilapi')) return new Response(JSON.stringify({ nome_fantasia: 'BOM PREÇO', cnae_fiscal: 4711302 }), { status: 200 });
      return new Response(html, { status: 200, headers: { 'content-type': 'text/html; charset=utf-8' } });
    });
    vi.stubGlobal('fetch', fetchMock);
    const brasilApiHeaders = () =>
      (fetchMock.mock.calls.find((c) => String(c[0]).includes('brasilapi')) as unknown as [string, RequestInit])[1].headers;
    const res = await u.api.post(`${base}/receipts/preview`, { qr: `https://www.nfce.fazenda.sp.gov.br/qrcode?p=${k}|2|1|1|H` });
    expect(res.body.data).toMatchObject({
      source: 'SEFAZ',
      issuerName: 'SUPERMERCADO BOM PREÇO LTDA',
      totalCents: 3500,
      issuedAt: '2026-10-15',
      suggestedCategoryName: 'Mercado',
      suggestedCategoryId: await categoryId(u, u.personalId, 'Mercado'),
    });
    expect(res.body.data.items).toHaveLength(2);
    expect(res.body.data).toMatchObject({ captcha: false, sefazUrl: expect.stringContaining('fazenda.sp.gov.br') });
    // Sem User-Agent a BrasilAPI responde 403.
    expect(brasilApiHeaders()).toMatchObject({ 'User-Agent': expect.stringContaining('hoink') });

    // Fazenda com verificação anti-robô (ex.: ES): avisa e usa o nome da loja pela BrasilAPI.
    fetchMock.mockImplementation(async (url: string) =>
      url.includes('brasilapi')
        ? new Response(JSON.stringify({ razao_social: 'MERCADINHO CAPIXABA LTDA', cnae_fiscal: 4712100 }), { status: 200 })
        : new Response('<div class="cf-turnstile" data-sitekey="x"></div>', { status: 200, headers: { 'content-type': 'text/html; charset=iso-8859-1' } }),
    );
    const es = (await u.api.post(`${base}/receipts/preview`, { qr: `https://app.sefaz.es.gov.br/ConsultaNFCe/qrcode.aspx?p=${k}|2|1|1|H` })).body.data;
    expect(es).toMatchObject({ source: 'QR', captcha: true, issuerName: 'MERCADINHO CAPIXABA LTDA', suggestedCategoryName: 'Mercado', totalCents: null });

    // Redirecionamento para fora: não é seguido (proteção contra SSRF), cai para os dados do QR.
    fetchMock.mockImplementation(async (url: string) =>
      url.includes('brasilapi')
        ? new Response('{}', { status: 404 })
        : new Response('', { status: 302, headers: { location: 'http://169.254.169.254/latest/meta-data' } }),
    );
    const redirected = await u.api.post(`${base}/receipts/preview`, { qr: `https://www.nfce.fazenda.sp.gov.br/qrcode?p=${k}|2|1|1|H` });
    expect(redirected.body.data.source).toBe('QR');
    expect(fetchMock.mock.calls.map((c) => String(c[0])).some((x) => x.includes('169.254'))).toBe(false);
  });

  it('a mesma nota não pode ser lançada duas vezes', async () => {
    const k = key();
    const body = { type: 'EXPENSE', description: 'Supermercado', amountCents: 3500, accountId: acc.id, competenceDate: '2026-10-15', receiptKey: k };
    expect((await u.api.post(`${base}/transactions`, body)).status).toBe(201);
    const dup = await u.api.post(`${base}/transactions`, body);
    expect(dup.status).toBe(409);
    expect(dup.body.error.code).toBe('RECEIPT_ALREADY_USED');
    expect((await u.api.post(`${base}/receipts/preview`, { qr: k })).body.data.alreadyRegistered).toBe(true);
    expect((await u.api.post(`${base}/transactions`, { ...body, receiptKey: '123' })).status).toBe(400);
  });
});
