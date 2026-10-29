/** Converte BIGINT do banco para number, garantindo que não há perda de precisão. */
export function toCents(value: bigint): number {
  const n = Number(value);
  if (!Number.isSafeInteger(n)) throw new Error(`Valor monetário fora do intervalo seguro: ${value}`);
  return n;
}
