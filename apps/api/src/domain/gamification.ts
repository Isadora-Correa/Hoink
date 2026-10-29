/**
 * Gamificação dos cofrinhos (funções puras): conquistas, sequência semanal e níveis de porquinho.
 * Pontos vêm de marcos de progresso e constância — não da quantidade de depósitos, para que
 * guardar e retirar repetidamente não "gere" pontos.
 */

export interface AchievementDef {
  code: string;
  title: string;
  description: string;
  icon: string;
  points: number;
  /** Conquista por cofrinho (marcos de uma meta) ou global. */
  perPiggy?: boolean;
}

export const ACHIEVEMENTS: AchievementDef[] = [
  { code: 'FIRST_PIGGY', title: 'Primeiro cofrinho', description: 'Criou seu primeiro cofrinho', icon: 'savings', points: 10 },
  { code: 'FIRST_WISH', title: 'Sonhar é o começo', description: 'Colocou um desejo na lista', icon: 'favorite', points: 10 },
  { code: 'FIRST_DEPOSIT', title: 'Primeira moedinha', description: 'Guardou dinheiro pela primeira vez', icon: 'paid', points: 20 },
  { code: 'GOAL_25', title: '25% do caminho', description: 'Chegou a 1/4 da meta', icon: 'flag', points: 25, perPiggy: true },
  { code: 'GOAL_50', title: 'Metade lá!', description: 'Chegou à metade da meta', icon: 'flag', points: 50, perPiggy: true },
  { code: 'GOAL_75', title: 'Reta final', description: 'Chegou a 3/4 da meta', icon: 'flag', points: 75, perPiggy: true },
  { code: 'GOAL_100', title: 'Meta batida!', description: 'Juntou todo o valor da meta', icon: 'emoji_events', points: 150, perPiggy: true },
  { code: 'WISH_ACHIEVED', title: 'Desejo realizado', description: 'Comprou algo com o dinheiro guardado', icon: 'celebration', points: 100, perPiggy: true },
  { code: 'SAVED_1K', title: 'Mil no porquinho', description: 'R$ 1.000 guardados nos cofrinhos', icon: 'savings', points: 50 },
  { code: 'SAVED_10K', title: 'Porquinho gordo', description: 'R$ 10.000 guardados nos cofrinhos', icon: 'savings', points: 150 },
  { code: 'STREAK_4', title: 'Um mês de constância', description: '4 semanas seguidas guardando dinheiro', icon: 'local_fire_department', points: 60 },
  { code: 'STREAK_12', title: 'Hábito formado', description: '12 semanas seguidas guardando dinheiro', icon: 'local_fire_department', points: 200 },
];

export const achievementDef = (code: string) => ACHIEVEMENTS.find((a) => a.code === code);

export const LEVELS = [
  { level: 1, name: 'Leitãozinho', minPoints: 0 },
  { level: 2, name: 'Porquinho Poupador', minPoints: 100 },
  { level: 3, name: 'Porco Planejador', minPoints: 300 },
  { level: 4, name: 'Porco Investidor', minPoints: 700 },
  { level: 5, name: 'Lenda do Chiqueiro', minPoints: 1500 },
] as const;

export function levelFor(points: number) {
  const current = [...LEVELS].reverse().find((l) => points >= l.minPoints)!;
  const next = LEVELS.find((l) => l.minPoints > points) ?? null;
  return {
    level: current.level,
    name: current.name,
    points,
    nextLevelName: next?.name ?? null,
    pointsToNext: next ? next.minPoints - points : 0,
    progressBps: next ? Math.round(((points - current.minPoints) * 10000) / (next.minPoints - current.minPoints)) : 10000,
  };
}

/** Segunda-feira da semana (ISO) da data. */
export function weekStart(iso: string): string {
  const d = new Date(`${iso}T00:00:00Z`);
  const dow = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - dow);
  return d.toISOString().slice(0, 10);
}

/**
 * Sequência de semanas consecutivas com ao menos um depósito, contando até a semana atual
 * (a semana atual ainda sem depósito não quebra a sequência).
 */
export function weeklyStreak(depositDates: string[], today: string): { current: number; best: number; depositedThisWeek: boolean } {
  const weeks = new Set(depositDates.map(weekStart));
  const prevWeek = (w: string) => {
    const d = new Date(`${w}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() - 7);
    return d.toISOString().slice(0, 10);
  };
  const thisWeek = weekStart(today);
  let w = weeks.has(thisWeek) ? thisWeek : prevWeek(thisWeek);
  let current = 0;
  while (weeks.has(w)) {
    current++;
    w = prevWeek(w);
  }
  let best = 0;
  for (const start of weeks) {
    if (weeks.has(prevWeek(start))) continue;
    let len = 0;
    let x = start;
    while (weeks.has(x)) {
      len++;
      const d = new Date(`${x}T00:00:00Z`);
      d.setUTCDate(d.getUTCDate() + 7);
      x = d.toISOString().slice(0, 10);
    }
    best = Math.max(best, len);
  }
  return { current, best, depositedThisWeek: weeks.has(thisWeek) };
}

/** Marcos de meta atingidos para um saldo. */
export function goalMilestones(balanceCents: number, goalCents: number | null): string[] {
  if (!goalCents || goalCents <= 0) return [];
  const pct = balanceCents / goalCents;
  return (
    [
      [0.25, 'GOAL_25'],
      [0.5, 'GOAL_50'],
      [0.75, 'GOAL_75'],
      [1, 'GOAL_100'],
    ] as const
  )
    .filter(([p]) => pct >= p)
    .map(([, c]) => c);
}
