import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  accessKeyCheckDigit,
  brlToCents,
  isAllowedSefazUrl,
  isValidAccessKey,
  parseQrContent,
  parseSefazHtml,
  suggestCategory,
} from './nfce';

/** Monta uma chave válida: SP (35), out/2026, CNPJ, NFC-e (65), série 1, número 12345. */
function key(tpEmis = '1') {
  const first43 = `35${'2610'}${'12345678000195'}65${'001'}${'000012345'}${tpEmis}${'12345678'}`;
  return first43 + accessKeyCheckDigit(first43);
}

describe('NFC-e — chave de acesso e QR Code', () => {
  it('valida o dígito verificador (módulo 11)', () => {
    const k = key();
    expect(k).toHaveLength(44);
    expect(isValidAccessKey(k)).toBe(true);
    const wrong = k.slice(0, 43) + String((Number(k[43]) + 1) % 10);
    expect(isValidAccessKey(wrong)).toBe(false);
    expect(isValidAccessKey('123')).toBe(false);
  });

  it('lê o link do QR (online) e a chave digitada com espaços', () => {
    const k = key();
    const qr = parseQrContent(`https://www.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx?p=${k}|2|1|1|ABCDEF`);
    expect(qr).toMatchObject({ uf: 'SP', issuedMonth: '2026-10', cnpj: '12345678000195', model: '65', number: 12345, offline: false, offlineTotalCents: null });
    expect(qr!.url).toContain('fazenda.sp.gov.br');
    const typed = parseQrContent(k.replace(/(\d{4})/g, '$1 '));
    expect(typed).toMatchObject({ accessKey: k, url: null });
    expect(parseQrContent('https://exemplo.com/?p=123')).toBeNull();
  });

  it('QR offline traz dia e valor total', () => {
    const k = key('9');
    const qr = parseQrContent(`http://www.sefaz.rs.gov.br/NFCE/NFCE-COM.aspx?p=${k}|2|1|15|35.00|abcd|1|HASH`);
    expect(qr).toMatchObject({ offline: true, offlineDay: 15, offlineTotalCents: 3500 });
  });

  it('só consulta domínios de Fazenda (gov.br) — proteção contra SSRF', () => {
    expect(isAllowedSefazUrl('https://www.nfce.fazenda.sp.gov.br/x')).toBe(true);
    expect(isAllowedSefazUrl('http://www.sefaz.rs.gov.br/NFCE')).toBe(true);
    expect(isAllowedSefazUrl('http://localhost:3333/api')).toBe(false);
    expect(isAllowedSefazUrl('http://169.254.169.254/latest')).toBe(false);
    expect(isAllowedSefazUrl('https://fazenda.gov.br.evil.com/x')).toBe(false);
    expect(isAllowedSefazUrl('https://www.prefeitura.gov.br/x')).toBe(false);
    expect(isAllowedSefazUrl('file:///etc/passwd')).toBe(false);
    expect(isAllowedSefazUrl('https://user:pw@sefaz.sp.gov.br/')).toBe(false);
  });
});

describe('NFC-e — página de consulta da Sefaz (layout padrão)', () => {
  const html = readFileSync(join(__dirname, '../../tests/fixtures/nfce-padrao.html'), 'utf8');

  it('extrai loja, CNPJ, data, itens, desconto, total a pagar e forma de pagamento', () => {
    const r = parseSefazHtml(html);
    expect(r).toMatchObject({
      issuerName: 'SUPERMERCADO BOM PREÇO LTDA',
      cnpj: '12345678000195',
      issuedAt: '2026-10-15',
      totalCents: 3500,
      discountCents: 153,
      paymentMethod: 'Cartão de Débito',
    });
    expect(r.items).toEqual([
      { description: 'ARROZ TIPO 1 5KG', quantity: 1, unit: 'UN', unitPriceCents: 2790, totalCents: 2790 },
      { description: 'BANANA PRATA KG', quantity: 1.235, unit: 'KG', unitPriceCents: 699, totalCents: 863 },
    ]);
  });

  it('página desconhecida (captcha) não inventa dados', () => {
    expect(parseSefazHtml('<html><body>Digite o código da imagem</body></html>')).toEqual({
      issuerName: null,
      cnpj: null,
      issuedAt: null,
      totalCents: null,
      discountCents: null,
      items: [],
      paymentMethod: null,
    });
  });

  it('valores e categorias', () => {
    expect(brlToCents('1.234,56')).toBe(123456);
    expect(brlToCents('R$ 35,00')).toBe(3500);
    expect(suggestCategory('SUPERMERCADO BOM PRECO', null)).toBe('Mercado');
    expect(suggestCategory('QUALQUER', '4771-7/01')).toBe('Saúde');
    expect(suggestCategory('AUTO POSTO SHELL', null)).toBe('Transporte');
    expect(suggestCategory('LOJA X', null)).toBeNull();
  });
});
