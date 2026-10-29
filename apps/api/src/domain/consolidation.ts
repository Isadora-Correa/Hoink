/** Aplica a participação do usuário (pontos-base) a um valor, arredondando ao centavo (meio para cima). */
export function applyShare(cents: number, shareBps: number): number {
  if (shareBps === 10000) return cents;
  const sign = cents < 0 ? -1 : 1;
  return sign * Math.floor((Math.abs(cents) * shareBps + 5000) / 10000);
}

export interface EntityFigure {
  entityId: string;
  shareBps: number;
  values: Record<string, number>;
}

/**
 * Consolida valores de vários ambientes ponderando pela participação do usuário (RN10).
 * Transferências entre ambientes já não são receita/despesa (RN01), portanto não há
 * duplicação em receitas/despesas; saldos são somados conta a conta, sem dupla contagem.
 */
export function consolidate(figures: EntityFigure[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const f of figures) {
    for (const [k, v] of Object.entries(f.values)) {
      out[k] = (out[k] ?? 0) + applyShare(v, f.shareBps);
    }
  }
  return out;
}
