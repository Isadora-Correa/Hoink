/**
 * Leitura de NFC-e/NF-e (funções puras): QR Code, chave de acesso e página de consulta da Sefaz.
 *
 * Chave de acesso (44 dígitos): cUF(2) AAMM(4) CNPJ(14) modelo(2) série(3) número(9) tpEmis(1) código(8) DV(1).
 * QR Code da NFC-e: URL da Sefaz do estado com `p=chave|versão|ambiente|...`. Na emissão em contingência
 * (offline) o QR traz também o dia da emissão e o valor total da nota.
 */

const UF_BY_CODE: Record<string, string> = {
  '11': 'RO', '12': 'AC', '13': 'AM', '14': 'RR', '15': 'PA', '16': 'AP', '17': 'TO',
  '21': 'MA', '22': 'PI', '23': 'CE', '24': 'RN', '25': 'PB', '26': 'PE', '27': 'AL', '28': 'SE', '29': 'BA',
  '31': 'MG', '32': 'ES', '33': 'RJ', '35': 'SP', '41': 'PR', '42': 'SC', '43': 'RS',
  '50': 'MS', '51': 'MT', '52': 'GO', '53': 'DF',
};

/** Dígito verificador da chave (módulo 11, pesos 2 a 9 da direita para a esquerda). */
export function accessKeyCheckDigit(first43: string): number {
  let sum = 0;
  let weight = 2;
  for (let i = first43.length - 1; i >= 0; i--) {
    sum += Number(first43[i]) * weight;
    weight = weight === 9 ? 2 : weight + 1;
  }
  const rest = sum % 11;
  return rest < 2 ? 0 : 11 - rest;
}

export function isValidAccessKey(key: string): boolean {
  return /^\d{44}$/.test(key) && accessKeyCheckDigit(key.slice(0, 43)) === Number(key[43]);
}

export interface AccessKeyInfo {
  accessKey: string;
  uf: string | null;
  /** AAAA-MM da emissão. */
  issuedMonth: string;
  cnpj: string;
  /** 65 = NFC-e (cupom), 55 = NF-e. */
  model: string;
  series: number;
  number: number;
  /** Emissão em contingência (offline). */
  offline: boolean;
}

export function parseAccessKey(key: string): AccessKeyInfo {
  return {
    accessKey: key,
    uf: UF_BY_CODE[key.slice(0, 2)] ?? null,
    issuedMonth: `20${key.slice(2, 4)}-${key.slice(4, 6)}`,
    cnpj: key.slice(6, 20),
    model: key.slice(20, 22),
    series: Number(key.slice(22, 25)),
    number: Number(key.slice(25, 34)),
    offline: key[34] === '9',
  };
}

export interface QrInfo extends AccessKeyInfo {
  /** URL de consulta (somente quando o texto lido é um link). */
  url: string | null;
  /** Só no QR offline: dia da emissão e valor total. */
  offlineDay: number | null;
  offlineTotalCents: number | null;
}

/**
 * Interpreta o conteúdo lido do QR Code (link da Sefaz) ou a chave digitada (com ou sem espaços).
 * Retorna null se não houver uma chave de acesso válida.
 */
export function parseQrContent(text: string): QrInfo | null {
  const raw = text.trim();
  let url: string | null = null;
  let key: string | null = null;
  let parts: string[] = [];
  if (/^https?:\/\//i.test(raw)) {
    try {
      const u = new URL(raw);
      url = u.toString();
      const p = u.searchParams.get('p') ?? u.searchParams.get('chNFe') ?? '';
      parts = p.split('|');
      key = parts[0]?.replace(/\D/g, '') ?? null;
      // Alguns estados usam ?chNFe=...&nVersao=...
      if (!key || key.length !== 44) key = raw.match(/\d{44}/)?.[0] ?? null;
    } catch {
      return null;
    }
  } else {
    key = raw.replace(/\D/g, '');
  }
  if (!key || !isValidAccessKey(key)) return null;
  const info = parseAccessKey(key);
  // QR v2 offline: chave|2|tpAmb|diaEmissão|vNF|digVal|idCSC|hash
  const offline = info.offline && parts.length >= 5;
  const total = offline ? Number(parts[4]) : NaN;
  return {
    ...info,
    url,
    offlineDay: offline && /^\d{1,2}$/.test(parts[3] ?? '') ? Number(parts[3]) : null,
    offlineTotalCents: Number.isFinite(total) && total > 0 ? Math.round(total * 100) : null,
  };
}

/**
 * Só consultamos páginas de Secretarias da Fazenda (domínios gov.br) — o servidor nunca busca
 * endereços arbitrários informados pelo usuário (proteção contra SSRF).
 */
export function isAllowedSefazUrl(url: string): boolean {
  try {
    const u = new URL(url);
    if (u.protocol !== 'https:' && u.protocol !== 'http:') return false;
    if (u.port && u.port !== '80' && u.port !== '443') return false;
    if (u.username || u.password) return false;
    const host = u.hostname.toLowerCase();
    return host.endsWith('.gov.br') && /(fazenda|sefaz|sef|nfce|nfe|sefin|set|economia|receita)/.test(host);
  } catch {
    return false;
  }
}

export interface ReceiptItem {
  description: string;
  quantity: number | null;
  unit: string | null;
  unitPriceCents: number | null;
  totalCents: number;
}

export interface SefazReceipt {
  issuerName: string | null;
  cnpj: string | null;
  issuedAt: string | null;
  totalCents: number | null;
  discountCents: number | null;
  items: ReceiptItem[];
  paymentMethod: string | null;
}

/** Entidades nomeadas usadas pelas páginas da Sefaz (acentos do português). */
const NAMED: Record<string, string> = {
  aacute: 'á', agrave: 'à', acirc: 'â', atilde: 'ã', eacute: 'é', ecirc: 'ê', iacute: 'í', oacute: 'ó',
  ocirc: 'ô', otilde: 'õ', uacute: 'ú', uuml: 'ü', ccedil: 'ç', ordm: 'º', ordf: 'ª', deg: '°',
};

const decode = (s: string) =>
  s
    .replace(/<[^>]+>/g, ' ')
    .replace(/&([A-Za-z])(acute|grave|circ|tilde|cedil|uml);/g, (m, l: string, k: string) => {
      const v = NAMED[`${l.toLowerCase()}${k}`];
      return v ? (l === l.toUpperCase() ? v.toUpperCase() : v) : m;
    })
    .replace(/&(ordm|ordf|deg);/g, (_, k: string) => NAMED[k]!)
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&#(\d+);/g, (_, n: string) => String.fromCharCode(Number(n)))
    .replace(/\s+/g, ' ')
    .trim();

/** "1.234,56" → 123456 centavos. */
export function brlToCents(s: string | null | undefined): number | null {
  if (!s) return null;
  const m = s.replace(/\s/g, '').match(/-?\d{1,3}(?:\.\d{3})*,\d{2}|-?\d+,\d{2}|-?\d+(?:\.\d+)?/);
  if (!m) return null;
  const v = m[0].includes(',') ? Number(m[0].replace(/\./g, '').replace(',', '.')) : Number(m[0]);
  return Number.isFinite(v) ? Math.round(v * 100) : null;
}

const brNumber = (s: string | null | undefined) => {
  if (!s) return null;
  const v = Number(s.replace(/\s/g, '').replace(/\./g, '').replace(',', '.'));
  return Number.isFinite(v) ? v : null;
};

/**
 * Lê a página de consulta da NFC-e no layout padrão dos portais estaduais (tabela `#tabResult`,
 * itens `.txtTit`, totais em `#totalNota`). Campos ausentes ficam null — nada é presumido.
 */
export function parseSefazHtml(html: string): SefazReceipt {
  const pick = (re: RegExp) => {
    const m = html.match(re);
    return m ? decode(m[1]!) : null;
  };
  const issuerName = pick(/id=["']u20["'][^>]*>([\s\S]*?)<\/div>/i);
  const cnpjText = pick(/CNPJ:?\s*([\d./-]{14,18})/i);
  const cnpj = cnpjText ? cnpjText.replace(/\D/g, '') : null;
  const emission = decode(html).match(/Emiss[ãa]o:?\s*(\d{2})\/(\d{2})\/(\d{4})/i);
  const issuedAt = emission ? `${emission[3]}-${emission[2]}-${emission[1]}` : null;

  const items: ReceiptItem[] = [];
  const rows = html.match(/<tr[^>]*id=["']Item[\s\S]*?<\/tr>/gi) ?? [];
  for (const row of rows) {
    const description = row.match(/class=["']txtTit2?["'][^>]*>([\s\S]*?)<\/span>/i);
    const total = row.match(/class=["']valor["'][^>]*>([\s\S]*?)<\/span>/i);
    if (!description || !total) continue;
    const qty = row.match(/class=["']Rqtd["'][^>]*>([\s\S]*?)<\/span>/i);
    const unit = row.match(/class=["']RUN["'][^>]*>([\s\S]*?)<\/span>/i);
    const unitPrice = row.match(/class=["']RvlUnit["'][^>]*>([\s\S]*?)<\/span>/i);
    const totalCents = brlToCents(decode(total[1]!));
    if (totalCents === null) continue;
    items.push({
      description: decode(description[1]!),
      quantity: qty ? brNumber(decode(qty[1]!).replace(/^[^\d-]*/, '')) : null,
      unit: unit ? decode(unit[1]!).replace(/^UN:?\s*/i, '') || null : null,
      unitPriceCents: unitPrice ? brlToCents(decode(unitPrice[1]!).replace(/^[^\d-]*/, '')) : null,
      totalCents,
    });
  }

  const totals = html.match(/id=["']totalNota["'][\s\S]*?(?=<\/div>\s*<\/div>|id=["']infos|data-role)/i)?.[0] ?? '';
  const line = (label: RegExp) => {
    const m = totals.match(new RegExp(`${label.source}[\\s\\S]*?class=["']totalNumb[^"']*["'][^>]*>([\\s\\S]*?)<\\/span>`, 'i'));
    return m ? brlToCents(decode(m[1]!)) : null;
  };
  const toPay = line(/Valor a pagar/);
  const total = line(/Valor total/);
  const discount = line(/Descontos?/);
  const payment = totals.match(/<label class=["']tx["'][^>]*>([\s\S]*?)<\/label>/i);
  return {
    issuerName,
    cnpj: cnpj && cnpj.length === 14 ? cnpj : null,
    issuedAt,
    totalCents: toPay ?? total ?? (items.length ? items.reduce((s, i) => s + i.totalCents, 0) : null),
    discountCents: discount,
    items,
    paymentMethod: payment ? decode(payment[1]!) : null,
  };
}

/** Sugestão de categoria pela atividade (CNAE) ou pelo nome da loja. */
export function suggestCategory(name: string | null, cnae: string | null): string | null {
  const c = (cnae ?? '').replace(/\D/g, '');
  const byCnae: [string, string][] = [
    ['4711', 'Mercado'], ['4712', 'Mercado'], ['4721', 'Mercado'], ['4722', 'Mercado'], ['4724', 'Mercado'], ['4729', 'Mercado'],
    ['4771', 'Saúde'], ['4772', 'Saúde'], ['8630', 'Saúde'], ['8640', 'Saúde'],
    ['5611', 'Alimentação'], ['5612', 'Alimentação'], ['5620', 'Alimentação'],
    ['4731', 'Transporte'], ['4732', 'Transporte'], ['4930', 'Transporte'],
    ['8511', 'Educação'], ['8512', 'Educação'], ['8513', 'Educação'], ['8520', 'Educação'], ['4761', 'Educação'],
    ['5914', 'Lazer'], ['9001', 'Lazer'], ['9311', 'Lazer'], ['9313', 'Lazer'],
  ];
  for (const [prefix, category] of byCnae) if (c.startsWith(prefix)) return category;
  const n = (name ?? '').toUpperCase();
  const byName: [RegExp, string][] = [
    [/SUPERMERC|MERCADO|ATACAD|HORTIFRUTI|SACOL[ÃA]O|EMP[ÓO]RIO/, 'Mercado'],
    [/DROGA|FARM[ÁA]C|PHARMA/, 'Saúde'],
    [/AUTO ?POSTO|POSTO |COMBUST/, 'Transporte'],
    [/RESTAUR|LANCH|PADARIA|PANIFIC|PIZZ|BURGER|CAF[EÉ]|BAR /, 'Alimentação'],
    [/CINEMA|TEATRO|PARQUE/, 'Lazer'],
    [/LIVRARIA|PAPELARIA|ESCOLA/, 'Educação'],
  ];
  for (const [re, category] of byName) if (re.test(n)) return category;
  return null;
}

/** Página de verificação anti-robô (Cloudflare Turnstile, reCAPTCHA, hCaptcha) em vez da nota. */
export function isCaptchaPage(html: string): boolean {
  return /cf-turnstile|challenges\.cloudflare\.com|g-recaptcha|recaptcha\/api|hcaptcha\.com/i.test(html);
}
