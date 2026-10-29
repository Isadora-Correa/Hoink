import { describe, expect, it } from 'vitest';
import { nextOccurrence, nthOccurrence, occurrencesBetween } from './recurrence';

describe('recorrências — datas', () => {
  it('mensal no dia 31 não escorrega (fevereiro e meses de 30 dias)', () => {
    const s = { frequency: 'MONTHLY' as const, startDate: '2025-01-31' };
    expect([0, 1, 2, 3, 4].map((n) => nthOccurrence(s, n))).toEqual([
      '2025-01-31',
      '2025-02-28',
      '2025-03-31',
      '2025-04-30',
      '2025-05-31',
    ]);
  });

  it('anual em 29/02 cai em 28/02 nos anos não bissextos', () => {
    const s = { frequency: 'YEARLY' as const, startDate: '2024-02-29' };
    expect([0, 1, 4].map((n) => nthOccurrence(s, n))).toEqual(['2024-02-29', '2025-02-28', '2028-02-29']);
  });

  it('diária, semanal, quinzenal e personalizada', () => {
    expect(nthOccurrence({ frequency: 'DAILY', startDate: '2025-12-31' }, 1)).toBe('2026-01-01');
    expect(nthOccurrence({ frequency: 'WEEKLY', startDate: '2025-06-02' }, 2)).toBe('2025-06-16');
    expect(nthOccurrence({ frequency: 'BIWEEKLY', startDate: '2025-06-02' }, 2)).toBe('2025-06-30');
    expect(nthOccurrence({ frequency: 'CUSTOM', interval: 3, unit: 'MONTH', startDate: '2025-01-15' }, 2)).toBe('2025-07-15');
    expect(() => nthOccurrence({ frequency: 'CUSTOM', interval: 0, unit: 'DAY', startDate: '2025-01-01' }, 1)).toThrow();
  });

  it('janela respeita data final e limite de ocorrências', () => {
    const s = { frequency: 'MONTHLY' as const, startDate: '2025-01-10', maxOccurrences: 3 };
    expect(occurrencesBetween(s, '2025-01-01', '2025-12-31').map((o) => o.date)).toEqual(['2025-01-10', '2025-02-10', '2025-03-10']);
    const e = { frequency: 'MONTHLY' as const, startDate: '2025-01-10', endDate: '2025-02-15' };
    expect(occurrencesBetween(e, '2025-01-01', '2025-12-31')).toHaveLength(2);
    expect(occurrencesBetween(e, '2025-02-01', '2025-12-31')).toEqual([{ index: 1, date: '2025-02-10' }]);
  });

  it('próxima ocorrência', () => {
    const s = { frequency: 'MONTHLY' as const, startDate: '2025-01-10', endDate: '2025-03-10' };
    expect(nextOccurrence(s, '2025-02-11')).toBe('2025-03-10');
    expect(nextOccurrence(s, '2025-03-11')).toBeNull();
  });
});
