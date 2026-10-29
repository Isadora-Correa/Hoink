import { describe, expect, it } from 'vitest';
import { goalMilestones, levelFor, weeklyStreak, weekStart } from './gamification';
import {
  accrue,
  dailyToAnnualPct,
  estimateTax,
  iofRate,
  monthsToGoal,
  openLots,
  regressiveIrRate,
  simulateGrowth,
} from './yields';

const series = (days: string[], rate: number) => ({ daily: new Map(days.map((d) => [d, rate])) });

describe('rendimentos — % do CDI', () => {
  const days = ['2026-10-01', '2026-10-02', '2026-10-05'];

  it('aplica a taxa diária × percentual em cada dia útil da série', () => {
    const r = accrue(1_000_000, '2026-09-30', '2026-10-05', [], { engine: 'CDI_PERCENT', rateBps: 11500 }, series(days, 0.05));
    const expected = Math.round(1_000_000 * Math.pow(1 + 0.0005 * 1.15, 3));
    expect(r).toMatchObject({ balanceCents: expected, businessDays: 3, missingRates: 0, ratesUpTo: '2026-10-05' });
    expect(r!.yieldCents).toBe(expected - 1_000_000);
  });

  it('fluxos entram na data e só rendem a partir do dia útil seguinte', () => {
    const r = accrue(0, '2026-09-30', '2026-10-05', [{ date: '2026-10-01', cents: 100_000 }], { engine: 'CDI_PERCENT', rateBps: 10000 }, series(days, 0.05));
    expect(r!.balanceCents).toBe(Math.round(100_000 * Math.pow(1.0005, 2)));
    expect(r!.yieldCents).toBe(r!.balanceCents - 100_000);
  });

  it('sem nenhuma taxa conhecida não estima (não inventa dados)', () => {
    expect(accrue(1000, '2026-10-01', '2026-10-10', [], { engine: 'CDI_PERCENT', rateBps: 10000 }, { daily: new Map() })).toBeNull();
  });

  it('dias além da série usam a última taxa conhecida e ficam sinalizados', () => {
    const r = accrue(1_000_000, '2026-10-04', '2026-10-07', [], { engine: 'CDI_PERCENT', rateBps: 10000 }, series(days, 0.05));
    // 05/10 está na série; 06 e 07 (dias úteis) não.
    expect(r).toMatchObject({ businessDays: 3, missingRates: 2 });
  });
});

describe('rendimentos — prefixado, IPCA+ e custos', () => {
  it('12% a.a. em 252 dias úteis rende ~12%', () => {
    let to = '2026-01-01';
    let count = 0;
    while (count < 252) {
      const d = new Date(`${to}T00:00:00Z`);
      d.setUTCDate(d.getUTCDate() + 1);
      to = d.toISOString().slice(0, 10);
      if (d.getUTCDay() !== 0 && d.getUTCDay() !== 6) count++;
    }
    const r = accrue(1_000_000, '2026-01-01', to, [], { engine: 'PREFIXED', rateBps: 1200 }, { daily: new Map() });
    expect(r!.balanceCents).toBe(1_120_000);
    const withCosts = accrue(1_000_000, '2026-01-01', to, [], { engine: 'PREFIXED', rateBps: 1200, costsBps: 20 }, { daily: new Map() });
    expect(withCosts!.balanceCents).toBeLessThan(1_120_000);
  });

  it('IPCA+ precisa da série mensal e usa o último mês conhecido quando falta', () => {
    const none = accrue(1000, '2026-10-01', '2026-10-05', [], { engine: 'IPCA_PLUS', rateBps: 600 }, { daily: new Map() });
    expect(none).toBeNull();
    const r = accrue(1_000_000, '2026-09-30', '2026-10-02', [], { engine: 'IPCA_PLUS', rateBps: 600 }, { daily: new Map(), monthly: new Map([['2026-09', 0.5]]) });
    expect(r!.missingRates).toBe(2);
    expect(r!.balanceCents).toBeGreaterThan(1_000_000);
  });

  it('converte taxa diária em anual', () => {
    expect(dailyToAnnualPct(0.050788)).toBeCloseTo(13.65, 1);
  });
});

describe('tributação', () => {
  it('IR regressivo e IOF', () => {
    expect([100, 200, 400, 800].map(regressiveIrRate)).toEqual([0.225, 0.2, 0.175, 0.15]);
    expect(iofRate(1)).toBe(0.96);
    expect(iofRate(29)).toBe(0.03);
    expect(iofRate(30)).toBe(0);
  });

  it('estima IR por lote e isenta LCI/LCA', () => {
    const lots = [{ date: '2025-01-01', cents: 100_000 }];
    expect(estimateTax('REGRESSIVE', lots, 10_000, '2026-01-10')).toEqual({ iofCents: 0, irCents: 1_750 });
    expect(estimateTax('EXEMPT', lots, 10_000, '2026-01-10')).toEqual({ iofCents: 0, irCents: 0 });
    expect(estimateTax('STOCKS', lots, 10_000, '2026-01-10').irCents).toBe(1_500);
    const early = estimateTax('REGRESSIVE', [{ date: '2026-01-01', cents: 100 }], 1_000, '2026-01-11');
    expect(early.iofCents).toBe(660);
  });

  it('resgates consomem os lotes mais antigos (FIFO)', () => {
    expect(
      openLots([
        { date: '2026-01-01', cents: 100 },
        { date: '2026-02-01', cents: 200 },
        { date: '2026-03-01', cents: -150 },
      ]),
    ).toEqual([{ date: '2026-02-01', cents: 150 }]);
  });
});

describe('simulações (estimativas)', () => {
  it('aportes mensais com juros compostos', () => {
    const pts = simulateGrowth(0, 100_000, 12, 0, '2026-01-31');
    expect(pts.at(-1)).toMatchObject({ month: 12, contributedCents: 1_200_000, balanceCents: 1_200_000 });
    expect(pts[0]!.date).toBe('2026-02-28');
    expect(simulateGrowth(1_000_000, 0, 12, 12, '2026-01-01').at(-1)!.balanceCents).toBe(1_120_000);
  });

  it('meses até a meta', () => {
    expect(monthsToGoal(0, 100_000, 500_000, 0)).toBe(5);
    expect(monthsToGoal(600_000, 0, 500_000, 0)).toBe(0);
    expect(monthsToGoal(0, 0, 500_000, 0)).toBeNull();
  });
});

describe('gamificação', () => {
  it('níveis de porquinho', () => {
    expect(levelFor(0)).toMatchObject({ level: 1, name: 'Leitãozinho', pointsToNext: 100 });
    expect(levelFor(150)).toMatchObject({ level: 2, progressBps: 2500 });
    expect(levelFor(5000)).toMatchObject({ level: 5, nextLevelName: null, progressBps: 10000 });
  });

  it('marcos da meta', () => {
    expect(goalMilestones(600, 1000)).toEqual(['GOAL_25', 'GOAL_50']);
    expect(goalMilestones(1000, 1000)).toHaveLength(4);
    expect(goalMilestones(1000, null)).toEqual([]);
  });

  it('sequência semanal de depósitos', () => {
    expect(weekStart('2026-10-28')).toBe('2026-10-26');
    const dates = ['2026-10-06', '2026-10-13', '2026-10-21', '2026-09-01'];
    expect(weeklyStreak(dates, '2026-10-28')).toEqual({ current: 3, best: 3, depositedThisWeek: false });
    expect(weeklyStreak([...dates, '2026-10-27'], '2026-10-28')).toMatchObject({ current: 4, depositedThisWeek: true });
    expect(weeklyStreak(['2026-09-01'], '2026-10-28').current).toBe(0);
  });
});
