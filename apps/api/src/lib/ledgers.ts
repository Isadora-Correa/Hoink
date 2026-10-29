import type { AccountType } from '@prisma/client';

/**
 * Contas-razão de módulos (cartão, cofrinho): não são dinheiro disponível e só são movimentadas
 * pelos próprios módulos. Contas "de dinheiro" são todas as demais.
 */
export const LEDGER_TYPES: AccountType[] = ['CREDIT_CARD', 'PIGGY_BANK'];
export const cashAccountType = { notIn: LEDGER_TYPES };
