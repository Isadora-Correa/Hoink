import { z } from 'zod';
import {
  ACCOUNT_TYPES,
  CATEGORY_KINDS,
  DIRECTIONS,
  STORED_TRANSACTION_STATUSES,
  TRANSACTION_STATUSES,
  TRANSACTION_TYPES,
  TRANSFER_CLASSIFICATIONS,
} from './enums';

/** Até 1 trilhão de reais em centavos — bem abaixo de Number.MAX_SAFE_INTEGER. */
const MAX_CENTS = 100_000_000_000_000;
export const centsSchema = z.number().int().min(0).max(MAX_CENTS);
export const signedCentsSchema = z.number().int().min(-MAX_CENTS).max(MAX_CENTS);
export const dateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Data deve estar no formato AAAA-MM-DD');

export const passwordSchema = z
  .string()
  .min(8, 'A senha deve ter pelo menos 8 caracteres')
  .max(128)
  .regex(/[A-Za-z]/, 'A senha deve conter letras')
  .regex(/\d/, 'A senha deve conter números');

export const signupSchema = z.object({
  name: z.string().trim().min(2, 'Informe seu nome').max(120),
  email: z.string().trim().toLowerCase().email('E-mail inválido'),
  password: passwordSchema,
  /** Cria também o ambiente Profissional (PJ). Pode ser ativado depois em Configurações. */
  withBusiness: z.boolean().default(false),
});
export const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email('E-mail inválido'),
  password: z.string().min(1, 'Informe a senha'),
});
export const forgotPasswordSchema = z.object({ email: z.string().trim().toLowerCase().email('E-mail inválido') });
export const resetPasswordSchema = z.object({ token: z.string().min(20), password: passwordSchema });
export const changePasswordSchema = z.object({ currentPassword: z.string().min(1), newPassword: passwordSchema });
export const updateProfileSchema = z.object({ name: z.string().trim().min(2).max(120) });

export const accountCreateSchema = z.object({
  name: z.string().trim().min(1, 'Informe o nome').max(80),
  institution: z.string().trim().max(80).optional().nullable(),
  type: z.enum(ACCOUNT_TYPES),
  initialBalanceCents: signedCentsSchema.default(0),
  referenceDate: dateSchema,
  color: z.string().max(20).optional().nullable(),
});
export const accountUpdateSchema = accountCreateSchema.partial();

export const reconcileSchema = z.object({
  statementBalanceCents: signedCentsSchema,
  date: dateSchema,
  createAdjustment: z.boolean().default(false),
});

export const categoryCreateSchema = z.object({
  name: z.string().trim().min(1).max(60),
  kind: z.enum(CATEGORY_KINDS),
  icon: z.string().max(40).default('category'),
  color: z.string().max(20).optional().nullable(),
});
export const categoryUpdateSchema = categoryCreateSchema.partial();

export const transactionCreateSchema = z
  .object({
    type: z.enum(TRANSACTION_TYPES).refine((t) => t !== 'TRANSFER', 'Use o endpoint de transferências'),
    direction: z.enum(DIRECTIONS).optional(),
    description: z.string().trim().min(1, 'Informe a descrição').max(160),
    amountCents: centsSchema.refine((v) => v > 0, 'Valor deve ser maior que zero'),
    accountId: z.string().uuid('Selecione uma conta'),
    categoryId: z.string().uuid().optional().nullable(),
    status: z.enum(STORED_TRANSACTION_STATUSES).default('SETTLED'),
    settledAmountCents: centsSchema.optional(),
    competenceDate: dateSchema,
    dueDate: dateSchema.optional().nullable(),
    settledDate: dateSchema.optional().nullable(),
    counterparty: z.string().trim().max(120).optional().nullable(),
    contactId: z.string().uuid().optional().nullable(),
    notes: z.string().max(1000).optional().nullable(),
    tags: z.array(z.string().trim().min(1).max(40)).max(20).default([]),
  })
  .superRefine((v, ctx) => {
    if (v.status === 'PARTIAL') {
      if (v.settledAmountCents === undefined || v.settledAmountCents <= 0 || v.settledAmountCents >= v.amountCents) {
        ctx.addIssue({
          code: 'custom',
          path: ['settledAmountCents'],
          message: 'Valor liquidado parcial deve ser maior que zero e menor que o total',
        });
      }
    }
  });
export type TransactionCreateInput = z.infer<typeof transactionCreateSchema>;

export const transactionUpdateSchema = z.object({
  description: z.string().trim().min(1).max(160).optional(),
  amountCents: centsSchema.refine((v) => v > 0).optional(),
  accountId: z.string().uuid().optional(),
  categoryId: z.string().uuid().nullable().optional(),
  status: z.enum(STORED_TRANSACTION_STATUSES).optional(),
  settledAmountCents: centsSchema.optional(),
  competenceDate: dateSchema.optional(),
  dueDate: dateSchema.nullable().optional(),
  settledDate: dateSchema.nullable().optional(),
  counterparty: z.string().trim().max(120).nullable().optional(),
  contactId: z.string().uuid().nullable().optional(),
  notes: z.string().max(1000).nullable().optional(),
  tags: z.array(z.string().trim().min(1).max(40)).max(20).optional(),
});

export const transferCreateSchema = z
  .object({
    fromAccountId: z.string().uuid(),
    toAccountId: z.string().uuid(),
    amountCents: centsSchema.refine((v) => v > 0, 'Valor deve ser maior que zero'),
    date: dateSchema,
    description: z.string().trim().max(160).optional(),
    classification: z.enum(TRANSFER_CLASSIFICATIONS).optional(),
    notes: z.string().max(1000).optional().nullable(),
  })
  .refine((v) => v.fromAccountId !== v.toAccountId, {
    message: 'Contas de origem e destino devem ser diferentes',
    path: ['toAccountId'],
  });

export const transactionListQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
  q: z.string().trim().max(100).optional(),
  type: z.enum(TRANSACTION_TYPES).optional(),
  kind: z.enum(['income', 'expense', 'transfer', 'recurring']).optional(),
  status: z.enum(TRANSACTION_STATUSES).optional(),
  accountId: z.string().uuid().optional(),
  categoryId: z.string().uuid().optional(),
  contactId: z.string().uuid().optional(),
  from: dateSchema.optional(),
  to: dateSchema.optional(),
  sort: z.enum(['date_desc', 'date_asc', 'amount_desc', 'amount_asc']).default('date_desc'),
});
export type TransactionListQuery = z.infer<typeof transactionListQuerySchema>;

// ───────────── Recorrências ─────────────
export const RECURRENCE_FREQUENCIES = ['DAILY', 'WEEKLY', 'BIWEEKLY', 'MONTHLY', 'YEARLY', 'CUSTOM'] as const;
export const INTERVAL_UNITS = ['DAY', 'WEEK', 'MONTH', 'YEAR'] as const;
export const AMOUNT_KINDS = ['FIXED', 'VARIABLE', 'ESTIMATED'] as const;

const recurringFields = {
  description: z.string().trim().min(1, 'Informe a descrição').max(160),
  amountCents: centsSchema.refine((v) => v > 0, 'Valor deve ser maior que zero'),
  amountKind: z.enum(AMOUNT_KINDS),
  accountId: z.string().uuid('Selecione uma conta'),
  categoryId: z.string().uuid().nullable(),
  counterparty: z.string().trim().max(120).nullable(),
  contactId: z.string().uuid().nullable(),
  notes: z.string().max(1000).nullable(),
  frequency: z.enum(RECURRENCE_FREQUENCIES),
  intervalCount: z.number().int().min(1).max(365),
  intervalUnit: z.enum(INTERVAL_UNITS).nullable(),
  endDate: dateSchema.nullable(),
  maxOccurrences: z.number().int().min(1).max(1000).nullable(),
};

export const recurringCreateSchema = z
  .object({
    type: z.enum(['INCOME', 'EXPENSE']),
    startDate: dateSchema,
    ...recurringFields,
    amountKind: recurringFields.amountKind.default('FIXED'),
    categoryId: recurringFields.categoryId.optional(),
    counterparty: recurringFields.counterparty.optional(),
    contactId: recurringFields.contactId.optional(),
    notes: recurringFields.notes.optional(),
    intervalCount: recurringFields.intervalCount.default(1),
    intervalUnit: recurringFields.intervalUnit.optional(),
    endDate: recurringFields.endDate.optional(),
    maxOccurrences: recurringFields.maxOccurrences.optional(),
  })
  .refine((v) => v.frequency !== 'CUSTOM' || !!v.intervalUnit, {
    message: 'Frequência personalizada exige a unidade (dias, semanas, meses ou anos)',
    path: ['intervalUnit'],
  })
  .refine((v) => !v.endDate || v.endDate >= v.startDate, { message: 'Data final anterior ao início', path: ['endDate'] });
export type RecurringCreateInput = z.infer<typeof recurringCreateSchema>;

/**
 * Edição de uma recorrência:
 *  - SERIES: altera a série inteira, preservando o que já foi realizado;
 *  - FROM: altera desta ocorrência em diante (`fromDate`), mantendo as anteriores como estavam.
 * Para alterar somente uma ocorrência, edite o próprio lançamento (PATCH /transactions/:id).
 */
export const recurringUpdateSchema = z
  .object({
    scope: z.enum(['SERIES', 'FROM']),
    fromDate: dateSchema.optional(),
    changes: z.object(recurringFields).partial(),
  })
  .refine((v) => v.scope !== 'FROM' || !!v.fromDate, { message: 'Informe a partir de qual data', path: ['fromDate'] });
export type RecurringUpdateInput = z.infer<typeof recurringUpdateSchema>;

// ───────────── Clientes e fornecedores ─────────────
export const CONTACT_KINDS = ['CLIENT', 'SUPPLIER', 'BOTH'] as const;

const documentSchema = z
  .string()
  .trim()
  .transform((v) => v.replace(/\D/g, ''))
  .refine((v) => v === '' || v.length === 11 || v.length === 14, 'CPF deve ter 11 dígitos e CNPJ, 14');

export const contactCreateSchema = z.object({
  kind: z.enum(CONTACT_KINDS),
  name: z.string().trim().min(1, 'Informe o nome').max(120),
  document: documentSchema.nullable().optional(),
  email: z.union([z.string().trim().toLowerCase().email('E-mail inválido'), z.literal('')]).nullable().optional(),
  phone: z.string().trim().max(30).nullable().optional(),
  notes: z.string().max(1000).nullable().optional(),
});
export const contactUpdateSchema = contactCreateSchema.partial();

export const payablesQuerySchema = z.object({
  kind: z.enum(['receivable', 'payable']),
  status: z.enum(['open', 'overdue']).default('open'),
  contactId: z.string().uuid().optional(),
});

// ───────────── Cartões de crédito ─────────────
const dayOfMonth = z.number().int().min(1).max(31);

export const cardCreateSchema = z
  .object({
    name: z.string().trim().min(1, 'Informe o nome do cartão').max(80),
    institution: z.string().trim().max(80).nullable().optional(),
    brand: z.string().trim().max(30).nullable().optional(),
    limitCents: centsSchema,
    closingDay: dayOfMonth,
    dueDay: dayOfMonth,
    paymentAccountId: z.string().uuid().nullable().optional(),
    color: z.string().max(20).nullable().optional(),
  })
  .refine((v) => v.closingDay !== v.dueDay, { message: 'Fechamento e vencimento devem ser dias diferentes', path: ['dueDay'] });
export const cardUpdateSchema = z.object({
  name: z.string().trim().min(1).max(80).optional(),
  institution: z.string().trim().max(80).nullable().optional(),
  brand: z.string().trim().max(30).nullable().optional(),
  limitCents: centsSchema.optional(),
  paymentAccountId: z.string().uuid().nullable().optional(),
  color: z.string().max(20).nullable().optional(),
});

export const cardPurchaseSchema = z.object({
  description: z.string().trim().min(1, 'Informe a descrição').max(160),
  totalCents: centsSchema.refine((v) => v > 0, 'Valor deve ser maior que zero'),
  installments: z.number().int().min(1).max(48).default(1),
  purchaseDate: dateSchema,
  categoryId: z.string().uuid().nullable().optional(),
});

export const invoicePaymentSchema = z.object({
  fromAccountId: z.string().uuid('Selecione a conta de pagamento'),
  amountCents: centsSchema.refine((v) => v > 0).optional(),
  date: dateSchema,
  classification: z.enum(TRANSFER_CLASSIFICATIONS).optional(),
});

// ───────────── Dívidas ─────────────
export const DEBT_KINDS = ['FINANCING', 'LOAN', 'OVERDRAFT', 'OTHER'] as const;
export const AMORTIZATION_SYSTEMS = ['PRICE', 'SAC'] as const;

export const debtSimulationSchema = z.object({
  principalCents: centsSchema.refine((v) => v > 0, 'Informe o valor'),
  /** Taxa mensal em partes por milhão (1,99% a.m. = 19900). Até 100% a.m. */
  monthlyRatePpm: z.number().int().min(0).max(1_000_000),
  system: z.enum(AMORTIZATION_SYSTEMS).default('PRICE'),
  installmentCount: z.number().int().min(1).max(600),
  firstDueDate: dateSchema,
  feesCents: centsSchema.default(0),
});

export const debtCreateSchema = debtSimulationSchema
  .extend({
    kind: z.enum(DEBT_KINDS),
    name: z.string().trim().min(1, 'Informe o nome').max(120),
    creditor: z.string().trim().max(120).nullable().optional(),
    startDate: dateSchema.optional(),
    accountId: z.string().uuid('Selecione a conta de pagamento'),
    categoryId: z.string().uuid().nullable().optional(),
    /** Parcelas já pagas antes do cadastro (não geram lançamentos). */
    paidInstallments: z.number().int().min(0).default(0),
    notes: z.string().max(1000).nullable().optional(),
  })
  .refine((v) => v.paidInstallments < v.installmentCount, {
    message: 'Ainda deve restar ao menos uma parcela',
    path: ['paidInstallments'],
  })
  .refine((v) => !v.startDate || v.startDate <= v.firstDueDate, {
    message: 'A contratação deve ser antes do primeiro vencimento',
    path: ['startDate'],
  });

export const debtUpdateSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  creditor: z.string().trim().max(120).nullable().optional(),
  notes: z.string().max(1000).nullable().optional(),
});

export const debtPrepaySchema = z.object({
  date: dateSchema,
  amountCents: centsSchema.refine((v) => v > 0, 'Informe o valor'),
  mode: z.enum(['REDUCE_TERM', 'REDUCE_INSTALLMENT']),
  accountId: z.string().uuid().optional(),
});

export const debtPayoffSchema = z.object({ date: dateSchema, accountId: z.string().uuid().optional() });

// ───────────── Planejamento ─────────────
export const monthSchema = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/, 'Mês deve estar no formato AAAA-MM');

export const budgetUpsertSchema = z.object({
  categoryId: z.string().uuid('Selecione a categoria'),
  limitCents: centsSchema.refine((v) => v > 0, 'Informe o limite'),
  alertThresholdBps: z.number().int().min(1000).max(10000).default(8000),
});

export const reserveSettingsSchema = z.object({
  targetMonths: z.number().int().min(1).max(24),
  accountIds: z.array(z.string().uuid()).max(50),
});

// ───────────── Cofrinhos e lista de desejos ─────────────
export const YIELD_KINDS = ['CDI_PERCENT', 'SELIC_PERCENT', 'PREFIXED', 'MANUAL', 'NONE'] as const;
export const LIQUIDITIES = ['DAILY', 'D_PLUS', 'AT_MATURITY'] as const;
export const TAXATIONS = ['REGRESSIVE', 'EXEMPT', 'STOCKS'] as const;

const piggyFields = {
  kind: z.enum(['RESERVE', 'WISH', 'GOAL']),
  name: z.string().trim().min(1, 'Dê um nome ao cofrinho').max(80),
  institution: z.string().trim().max(80).nullable(),
  color: z.string().max(20).nullable(),
  icon: z.string().max(40),
  /** Só http(s): o app abre o link do produto, então esquemas como javascript: são recusados. */
  link: z
    .string()
    .trim()
    .max(500)
    .regex(/^https?:\/\/[^\s]+$/i, 'Use um link começando com http:// ou https://')
    .nullable(),
  priority: z.number().int().min(1).max(5),
  goalCents: centsSchema.refine((v) => v > 0, 'Meta deve ser positiva').nullable(),
  targetDate: dateSchema.nullable(),
  yieldKind: z.enum(YIELD_KINDS),
  /** % do índice (11500 = 115% do CDI) ou taxa anual prefixada (1250 = 12,5% a.a.), em pontos-base. */
  yieldRateBps: z.number().int().min(0).max(100_000),
  liquidity: z.enum(LIQUIDITIES),
  liquidityDays: z.number().int().min(0).max(3650),
  taxation: z.enum(TAXATIONS),
};

export const piggyCreateSchema = z.object({
  ...piggyFields,
  kind: piggyFields.kind.default('GOAL'),
  institution: piggyFields.institution.optional(),
  color: piggyFields.color.optional(),
  icon: piggyFields.icon.default('savings'),
  link: piggyFields.link.optional(),
  priority: piggyFields.priority.default(3),
  goalCents: piggyFields.goalCents.optional(),
  targetDate: piggyFields.targetDate.optional(),
  yieldKind: piggyFields.yieldKind.default('NONE'),
  yieldRateBps: piggyFields.yieldRateBps.default(0),
  liquidity: piggyFields.liquidity.default('DAILY'),
  liquidityDays: piggyFields.liquidityDays.default(0),
  taxation: piggyFields.taxation.default('REGRESSIVE'),
});
export const piggyUpdateSchema = z.object(piggyFields).partial();

export const piggyMoveSchema = z.object({
  accountId: z.string().uuid('Escolha a conta'),
  amountCents: centsSchema.refine((v) => v > 0, 'Informe o valor').optional(),
  date: dateSchema,
  classification: z.enum(TRANSFER_CLASSIFICATIONS).optional(),
});
export const piggyDepositSchema = piggyMoveSchema.required({ amountCents: true });

export const piggyYieldSchema = z.object({ date: dateSchema, balanceCents: centsSchema });

export const piggyAchieveSchema = z.object({
  accountId: z.string().uuid('Escolha a conta'),
  date: dateSchema,
  /** Valor da compra: se informado, lança a despesa (a única despesa — guardar não é despesa). */
  purchaseCents: centsSchema.refine((v) => v > 0).optional(),
  description: z.string().trim().max(160).optional(),
  categoryId: z.string().uuid().nullable().optional(),
});

export const simulateQuerySchema = z.object({
  monthlyCents: z.coerce.number().int().min(0).max(MAX_CENTS),
  months: z.coerce.number().int().min(1).max(600).default(12),
});

export const manualRateSchema = z
  .object({
    index: z.enum(['CDI', 'SELIC', 'IPCA']),
    date: dateSchema,
    annualPct: z.number().min(0).max(1000).optional(),
    monthlyPct: z.number().min(-50).max(100).optional(),
  })
  .refine((v) => (v.index === 'IPCA' ? v.monthlyPct !== undefined : v.annualPct !== undefined), {
    message: 'CDI/Selic: informe a taxa anual; IPCA: a variação do mês',
  });

// ───────────── Investimentos ─────────────
export const INVESTMENT_KINDS = ['CDB', 'LCI', 'LCA', 'TESOURO', 'FUND', 'STOCK', 'ETF', 'OTHER'] as const;
export const INVESTMENT_INDEXERS = ['CDI_PERCENT', 'SELIC_PERCENT', 'PREFIXED', 'IPCA_PLUS', 'MARKET', 'MANUAL'] as const;

const movementInput = z.object({
  date: dateSchema,
  amountCents: centsSchema.refine((v) => v > 0, 'Informe o valor'),
  /** Conta de onde sai (aporte) ou para onde vai (resgate/proventos). Sem conta: posição anterior ao app. */
  accountId: z.string().uuid().nullable().optional(),
  quantity: z.number().positive().max(1e12).optional(),
});

export const investmentCreateSchema = z
  .object({
    kind: z.enum(INVESTMENT_KINDS),
    name: z.string().trim().min(1, 'Informe o produto').max(120),
    institution: z.string().trim().max(80).nullable().optional(),
    ticker: z.string().trim().max(20).nullable().optional(),
    indexer: z.enum(INVESTMENT_INDEXERS),
    rateBps: z.number().int().min(0).max(100_000).default(0),
    maturityDate: dateSchema.nullable().optional(),
    liquidity: z.enum(LIQUIDITIES).default('DAILY'),
    liquidityDays: z.number().int().min(0).max(3650).default(0),
    costsBps: z.number().int().min(0).max(10_000).default(0),
    taxation: z.enum(TAXATIONS).optional(),
    notes: z.string().max(1000).nullable().optional(),
    initial: movementInput.optional(),
  })
  .refine((v) => !['STOCK', 'ETF'].includes(v.kind) || v.indexer === 'MARKET', {
    message: 'Ações e ETFs usam cotação de mercado',
    path: ['indexer'],
  })
  .refine((v) => v.indexer !== 'MARKET' || !v.initial || !!v.initial.quantity, {
    message: 'Informe a quantidade de cotas/ações',
    path: ['initial', 'quantity'],
  });

export const investmentUpdateSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  institution: z.string().trim().max(80).nullable().optional(),
  ticker: z.string().trim().max(20).nullable().optional(),
  rateBps: z.number().int().min(0).max(100_000).optional(),
  maturityDate: dateSchema.nullable().optional(),
  liquidity: z.enum(LIQUIDITIES).optional(),
  liquidityDays: z.number().int().min(0).max(3650).optional(),
  costsBps: z.number().int().min(0).max(10_000).optional(),
  taxation: z.enum(TAXATIONS).optional(),
  notes: z.string().max(1000).nullable().optional(),
  status: z.enum(['ACTIVE', 'CLOSED']).optional(),
});

export const investmentMoveSchema = movementInput;

/** Valor atualizado do extrato (renda fixa/manual) ou preço unitário em centavos (mercado). */
export const investmentValueSchema = z.object({
  date: dateSchema,
  valueCents: centsSchema.optional(),
  unitPriceCents: z.number().positive().max(1e12).optional(),
});

// ───────────── Patrimônio ─────────────
export const patrimonyItemSchema = z.object({
  side: z.enum(['ASSET', 'LIABILITY']),
  category: z.string().trim().min(1).max(40),
  name: z.string().trim().min(1, 'Informe o nome').max(120),
  valueCents: centsSchema,
  valuedAt: dateSchema,
  notes: z.string().max(1000).nullable().optional(),
});
export const patrimonyItemUpdateSchema = patrimonyItemSchema.partial();
