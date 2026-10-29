import { env } from '../../config/env';
import {
  isAllowedSefazUrl,
  isCaptchaPage,
  parseQrContent,
  parseSefazHtml,
  suggestCategory,
  type ReceiptItem,
} from '../../domain/nfce';
import { unprocessable } from '../../lib/errors';
import { logger } from '../../lib/logger';
import { prisma } from '../../lib/prisma';

const MAX_BYTES = 1_000_000;
const TIMEOUT_MS = 10_000;

/** Busca a página de consulta da Sefaz seguindo só redirecionamentos para domínios permitidos. */
async function fetchSefaz(url: string): Promise<string | null> {
  let current = url;
  for (let hop = 0; hop < 4; hop++) {
    if (!isAllowedSefazUrl(current)) return null;
    const res = await fetch(current, {
      redirect: 'manual',
      headers: { 'User-Agent': 'Mozilla/5.0 (hoink; leitura de NFC-e)', Accept: 'text/html' },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
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
    sefazUrl: info.url,
    alreadyRegistered: existing > 0,
  };
}
