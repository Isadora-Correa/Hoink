/**
 * Utilitários de dinheiro. Todos os valores trafegam como centavos inteiros.
 */
const brl = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });

export function formatBRL(cents: number): string {
  return brl.format(cents / 100);
}

/** Converte "1.234,56", "1234.56" ou "350" para centavos. Retorna null se inválido. */
export function parseBRLToCents(input: string): number | null {
  const cleaned = input.replace(/[R$\s]/g, '');
  if (!cleaned) return null;
  let normalized = cleaned;
  if (cleaned.includes(',')) {
    normalized = cleaned.replace(/\./g, '').replace(',', '.');
  }
  if (!/^-?\d+(\.\d{1,2})?$/.test(normalized)) return null;
  const [int, frac = ''] = normalized.replace('-', '').split('.');
  const cents = Number(int) * 100 + Number(frac.padEnd(2, '0'));
  if (!Number.isSafeInteger(cents)) return null;
  return normalized.startsWith('-') ? -cents : cents;
}
