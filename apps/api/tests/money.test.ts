import { describe, expect, it } from 'vitest';
import { formatBRL, parseBRLToCents } from '../src/contracts/money';

describe('parseBRLToCents', () => {
  it.each([
    ['350', 35000],
    ['350,00', 35000],
    ['1.234,56', 123456],
    ['R$ 287,5', 28750],
    ['1234.56', 123456],
    ['-10,01', -1001],
  ])('%s → %d', (input, expected) => expect(parseBRLToCents(input)).toBe(expected));

  it.each(['', 'abc', '1,234', '1.2.3'])('rejeita %s', (input) => expect(parseBRLToCents(input)).toBeNull());
});

describe('formatBRL', () => {
  it('formata centavos em reais', () => {
    expect(formatBRL(35000).replace(/\s/g, ' ')).toBe('R$ 350,00');
  });
});
