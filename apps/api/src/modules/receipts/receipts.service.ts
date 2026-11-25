import { env } from '../../config/env';
import {
  isAllowedSefazUrl,
  isCaptchaPage,
  parseQrContent,
  publicConsultUrl,
  parseSefazHtml,
  suggestCategory,
  type ReceiptItem,
} from '../../domain/nfce';
import { unprocessable } from '../../lib/errors';
import { logger } from '../../lib/logger';
import { prisma } from '../../lib/prisma';

const MAX_BYTES = 1_000_000;
const TIMEOUT_MS = 10_000;

/** Tentativas por requisição: o portal da Sefaz-SP derruba conexões de vez em quando ("connection reset"). */
const ATTEMPTS = 5;
const RETRY_DELAY_MS = 500;

/** fetch com novas tentativas em falha de rede ou erro 5xx do portal. */
async function fetchWithRetry(url: string, init: RequestInit): Promise<Response> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
    try {
      const res = await fetch(url, { ...init, signal: AbortSignal.timeout(TIMEOUT_MS) });
      if (res.status < 500 || attempt === ATTEMPTS) return res;
      lastError = new Error(`Sefaz respondeu ${res.status}`);
    } catch (err) {
      lastError = err;
    }
    logger.warn({ err: lastError, attempt }, 'Consulta à Sefaz falhou; tentando de novo');
    if (attempt < ATTEMPTS) await new Promise((r) => setTimeout(r, RETRY_DELAY_MS * attempt));
  }
  throw lastError;
}

/**
 * Busca a página de consulta da Sefaz seguindo só redirecionamentos para domínios permitidos.
 * Guarda os cookies entre os passos como um navegador: o firewall do portal de SP (F5, cookie `TS01…`)
 * entrega um cookie no redirecionamento de `/qrcode` e derruba a conexão seguinte que vier sem ele.
 */
async function fetchSefaz(url: string): Promise<string | null> {
  let current = url;
  const jar = new Map<string, Map<string, string>>();
  for (let hop = 0; hop < 4; hop++) {
    if (!isAllowedSefazUrl(current)) return null;
    const host = new URL(current).hostname;
    const cookies = jar.get(host);
    const res = await fetchWithRetry(current, {
      redirect: 'manual',
      headers: {
        'User-Agent': 'Mozilla/5.0 (hoink; leitura de NFC-e)',
        Accept: 'text/html',
        ...(cookies?.size ? { Cookie: [...cookies].map(([k, v]) => `${k}=${v}`).join('; ') } : {}),
      },
    });
    for (const sc of res.headers.getSetCookie?.() ?? []) {
      const pair = sc.split(';', 1)[0]!;
      const eq = pair.indexOf('=');
      if (eq <= 0) continue;
      if (!jar.has(host)) jar.set(host, new Map());
      jar.get(host)!.set(pair.slice(0, eq).trim(), pair.slice(eq + 1).trim());
    }
    if (res.status >= 300 && res.status < 400) {
      const location = res.headers.get('location');
      if (!location) return null;
      current = new URL(location, current).toString();
      continue;
    }
    if (!res.ok) return null;
    const buf = new Uint8Array(await res.arrayBuffer());
    if (buf.byteLength > MAX_BYTES) return null;
    // Vários portais ainda servem ISO-8859-1.
    const charset = /charset=([\w-]+)/i.exec(res.headers.get('content-type') ?? '')?.[1] ?? 'utf-8';
    try {
      return new TextDecoder(charset).decode(buf);
    } catch {
      return new TextDecoder('utf-8').decode(buf);
    }
  }
  return null;
}

/** Nome e atividade (CNAE) da loja pela BrasilAPI (dados públicos da Receita Federal). */
async function lookupCnpj(cnpj: string): Promise<{ name: string | null; cnae: string | null }> {
  try {
    // A BrasilAPI recusa (403) chamadas sem identificação do cliente.
    const res = await fetch(`https://brasilapi.com.br/api/cnpj/v1/${cnpj}`, {
      headers: { 'User-Agent': 'hoink/1.0 (+https://github.com/Isadora-Correa/Hoink)', Accept: 'application/json' },
      signal: AbortSignal.timeout(6_000),
    });
    if (!res.ok) return { name: null, cnae: null };
    const j = (await res.json()) as { nome_fantasia?: string; razao_social?: string; cnae_fiscal?: number };
    return { name: j.nome_fantasia || j.razao_social || null, cnae: j.cnae_fiscal ? String(j.cnae_fiscal) : null };
  } catch {
    return { name: null, cnae: null };
  }
}

export interface ReceiptPreview {
  accessKey: string;
  model: string;
  uf: string | null;
  cnpj: string;
  issuerName: string | null;
  issuedAt: string | null;
  issuedMonth: string;
  totalCents: number | null;
  discountCents: number | null;
  paymentMethod: string | null;
  items: ReceiptItem[];
  suggestedCategoryId: string | null;
  suggestedCategoryName: string | null;
  /** SEFAZ: dados da página oficial; QR: só o que o QR Code traz (o usuário completa). */
  source: 'SEFAZ' | 'QR';
  /** A Fazenda do estado exige verificação anti-robô (captcha): a página só abre no navegador da pessoa. */
  captcha: boolean;
  /** Link oficial da nota, para a pessoa conferir o valor no site da Fazenda. */
  sefazUrl: string | null;
  /** Veio só a chave digitada (sem o link do QR Code): a Sefaz não abre a nota sem o hash do QR. */
  keyOnly: boolean;
  alreadyRegistered: boolean;
}

/**
 * Lê o QR Code (ou a chave) de uma NFC-e e devolve uma prévia do gasto. Nada é gravado: o app
 * abre o formulário preenchido e o usuário confirma.
 */
export async function previewReceipt(entityId: string, qr: string): Promise<ReceiptPreview> {
  const info = parseQrContent(qr);
  if (!info) throw unprocessable('INVALID_RECEIPT', 'Não reconhecemos o QR Code nem a chave de acesso da nota fiscal');
  let page: ReturnType<typeof parseSefazHtml> | null = null;
  let captcha = false;
  let company: { name: string | null; cnae: string | null } = { name: null, cnae: null };
  if (env.RECEIPT_LOOKUP === 'true') {
    const [html, comp] = await Promise.all([
      info.url ? fetchSefaz(info.url).catch((err) => (logger.warn({ err }, 'Consulta à Sefaz falhou'), null)) : null,
      lookupCnpj(info.cnpj),
    ]);
    company = comp;
    if (html) {
      captcha = isCaptchaPage(html);
      const parsed = parseSefazHtml(html);
      if (parsed.totalCents !== null || parsed.items.length) page = parsed;
    }
  }
  const issuerName = page?.issuerName ?? company.name;
  const categoryName = suggestCategory(issuerName, company.cnae);
  const category = categoryName
    ? await prisma.category.findFirst({ where: { entityId, kind: 'EXPENSE', name: categoryName, archivedAt: null } })
    : null;
  const issuedAt =
    page?.issuedAt ?? (info.offlineDay ? `${info.issuedMonth}-${String(info.offlineDay).padStart(2, '0')}` : null);
  const existing = await prisma.transaction.count({ where: { entityId, receiptKey: info.accessKey, deletedAt: null } });
  return {
    accessKey: info.accessKey,
    model: info.model,
    uf: info.uf,
    cnpj: info.cnpj,
    issuerName,
    issuedAt,
    issuedMonth: info.issuedMonth,
    totalCents: page?.totalCents ?? info.offlineTotalCents,
    discountCents: page?.discountCents ?? null,
    paymentMethod: page?.paymentMethod ?? null,
    items: page?.items ?? [],
    suggestedCategoryId: category?.id ?? null,
    suggestedCategoryName: category?.name ?? null,
    source: page ? 'SEFAZ' : 'QR',
    captcha,
    sefazUrl: info.url ?? publicConsultUrl(info.uf),
    keyOnly: info.url === null,
    alreadyRegistered: existing > 0,
  };
}
