/**
 * Dados de demonstração baseados nos protótipos (usuário "Miguel").
 * Usa os mesmos serviços de domínio da API, então todas as regras de negócio se aplicam.
 * Login: miguel@hoink.dev / hoink1234
 */
import type { z } from 'zod';
import { transactionCreateSchema } from '../src/contracts';
import { formatDate, parseDate, shiftMonth, todayISO } from '../src/lib/dates';
import { prisma } from '../src/lib/prisma';
import { addDaysISO } from '../src/domain/recurrence';
import { createAccount } from '../src/modules/accounts/accounts.service';
import { createCard, createPurchase, getCard, payInvoice } from '../src/modules/cards/cards.service';
import { createDebt } from '../src/modules/debts/debts.service';
import { updateReserve, upsertBudget } from '../src/modules/planning/planning.service';
import { signup } from '../src/modules/auth/auth.service';
import { listEntities } from '../src/modules/entities/entities.service';
import { createContact } from '../src/modules/contacts/contacts.service';
import { createRule } from '../src/modules/recurring/recurring.service';
import { createTransaction, settleTransaction } from '../src/modules/transactions/transactions.service';
import { createTransfer } from '../src/modules/transfers/transfers.service';

const EMAIL = 'miguel@hoink.dev';

/** Remove apenas os dados do usuário de demonstração (uso: pnpm seed --reset). */
async function resetDemo() {
  const user = await prisma.user.findUnique({ where: { email: EMAIL }, include: { memberships: true } });
  if (!user) return;
  const entityIds = user.memberships.map((m) => m.entityId);
  await prisma.$transaction(async (tx) => {
    const transferIds = (
      await tx.transaction.findMany({ where: { entityId: { in: entityIds }, transferId: { not: null } }, select: { transferId: true } })
    ).map((t) => t.transferId!);
    await tx.debtInstallment.deleteMany({ where: { debt: { entityId: { in: entityIds } } } });
    await tx.transaction.deleteMany({ where: { entityId: { in: entityIds } } });
    await tx.cardPurchase.deleteMany({ where: { entityId: { in: entityIds } } });
    await tx.cardInvoice.deleteMany({ where: { card: { entityId: { in: entityIds } } } });
    await tx.creditCard.deleteMany({ where: { entityId: { in: entityIds } } });
    await tx.debt.deleteMany({ where: { entityId: { in: entityIds } } });
    await tx.recurringRule.deleteMany({ where: { entityId: { in: entityIds } } });
    await tx.contact.deleteMany({ where: { entityId: { in: entityIds } } });
    await tx.transfer.deleteMany({ where: { id: { in: transferIds } } });
    await tx.account.deleteMany({ where: { entityId: { in: entityIds } } });
    await tx.auditLog.deleteMany({ where: { OR: [{ userId: user.id }, { entityId: { in: entityIds } }] } });
    await tx.idempotencyKey.deleteMany({ where: { userId: user.id } });
    await tx.financialEntity.deleteMany({ where: { id: { in: entityIds } } });
    await tx.user.delete({ where: { id: user.id } });
  });
  console.log('Dados de demonstração removidos.');
}

async function main() {
  if (process.argv.includes('--reset')) await resetDemo();
  const existing = await prisma.user.findUnique({ where: { email: EMAIL } });
  if (existing) {
    console.log(`Seed já aplicado (${EMAIL}). Nada a fazer.`);
    return;
  }
  const { user } = await signup({ name: 'Miguel Santos', email: EMAIL, password: 'hoink1234', withBusiness: true }, {});
  const entities = await listEntities(user.id);
  const pf = entities.find((e) => e.kind === 'PERSONAL')!.id;
  const pj = entities.find((e) => e.kind === 'BUSINESS')!.id;
  const ctxPF = { userId: user.id, entityId: pf };
  const ctxPJ = { userId: user.id, entityId: pj };

  const month = todayISO().slice(0, 7);
  const start = `${shiftMonth(month, -5)}-01`;
  const day = (m: string, d: number) => `${m}-${String(d).padStart(2, '0')}`;
  const today = todayISO();

  const nubank = await createAccount(ctxPF, { name: 'Nubank Ultravioleta', institution: 'Nubank', type: 'CHECKING', initialBalanceCents: 320000, referenceDate: start });
  const itau = await createAccount(ctxPF, { name: 'Itaú Personnalité', institution: 'Itaú', type: 'CHECKING', initialBalanceCents: 150000, referenceDate: start });
  const inter = await createAccount(ctxPJ, { name: 'Banco Inter PJ', institution: 'Inter', type: 'PAYMENT', initialBalanceCents: 500000, referenceDate: start });

  const cats = await prisma.category.findMany({ where: { entityId: { in: [pf, pj] } } });
  const cat = (entityId: string, name: string) => cats.find((c) => c.entityId === entityId && c.name === name)!.id;

  const studio = await createContact(ctxPJ, {
    kind: 'CLIENT',
    name: 'Studio Alpha',
    document: '12345678000190',
    email: 'financeiro@studioalpha.com.br',
    notes: 'Consultoria mensal de Design System',
  });
  const nexa = await createContact(ctxPJ, { kind: 'CLIENT', name: 'Nexa Tecnologia', email: 'contas@nexa.dev' });
  const grafica = await createContact(ctxPJ, { kind: 'SUPPLIER', name: 'Gráfica Rápida', phone: '(11) 4000-1234' });

  const variable = [0.92, 1.05, 0.98, 1.1, 0.95, 1];
  for (let i = 5; i >= 0; i--) {
    const m = shiftMonth(month, -i);
    const isCurrent = i === 0;
    const k = variable[5 - i]!;
    const settledIfPast = (d: string) => (d <= today ? ('SETTLED' as const) : ('PENDING' as const));

    const add = (ctx: typeof ctxPF, input: z.input<typeof transactionCreateSchema>) =>
      createTransaction(ctx, transactionCreateSchema.parse(input));
    const salaryDate = day(m, 5);
    await add(ctxPF, { type: 'INCOME', description: 'Salário Tech Co.', amountCents: 780000, accountId: itau.id, categoryId: cat(pf, 'Salário'), status: settledIfPast(salaryDate), competenceDate: salaryDate, dueDate: salaryDate });
    const rentDate = day(m, 8);
    await add(ctxPF, { type: 'EXPENSE', description: 'Aluguel & Condomínio', counterparty: 'QuintoAndar', amountCents: 185000, accountId: itau.id, categoryId: cat(pf, 'Moradia'), status: settledIfPast(rentDate), competenceDate: rentDate, dueDate: rentDate });
    for (const [d, desc, cents] of [[9, 'Supermercado Pão de Açúcar', 48000], [14, 'Carrefour Express', 7840], [21, 'Feira Orgânica', 8500]] as const) {
      const date = day(m, d);
      if (isCurrent && date > today) continue;
      await add(ctxPF, { type: 'EXPENSE', description: desc, amountCents: Math.round(cents * k), accountId: nubank.id, categoryId: cat(pf, 'Mercado'), competenceDate: date, tags: ['mercado'] });
    }
    for (const [d, desc, cents, c] of [[12, 'Uber', 4300, 'Transporte'], [16, 'Restaurante Jardins', 18500, 'Alimentação'], [18, 'Farmácia', 9200, 'Saúde'], [25, 'Cinema', 9000, 'Lazer']] as const) {
      const date = day(m, d);
      if (isCurrent && date > today) continue;
      await add(ctxPF, { type: 'EXPENSE', description: desc, amountCents: Math.round(cents * k), accountId: nubank.id, categoryId: cat(pf, c), competenceDate: date });
    }
    const subDate = day(m, 12);
    await add(ctxPF, { type: 'EXPENSE', description: 'Spotify Premium Duo + Netflix', amountCents: 6390, accountId: nubank.id, categoryId: cat(pf, 'Assinaturas'), status: settledIfPast(subDate), competenceDate: subDate, dueDate: subDate, tags: ['assinatura'] });
    const enelDate = day(m, 10);
    await add(ctxPF, { type: 'EXPENSE', description: 'Conta de Luz • Enel', amountCents: Math.round(25000 * k), accountId: itau.id, categoryId: cat(pf, 'Serviços básicos'), status: settledIfPast(enelDate), competenceDate: day(m, 1), dueDate: enelDate });

    // Profissional: recebimentos de clientes e pró-labore para o Pessoal (transferência classificada).
    const clientDate = day(m, 11);
    await add(ctxPJ, { type: 'INCOME', description: 'Consultoria Design System', contactId: studio.id, amountCents: Math.round(640000 * k), accountId: inter.id, categoryId: cat(pj, 'Serviços prestados'), status: settledIfPast(clientDate), competenceDate: clientDate, dueDate: clientDate });
    const toolsDate = day(m, 3);
    if (!(isCurrent && toolsDate > today)) {
      await add(ctxPJ, { type: 'EXPENSE', description: 'Figma + Google Workspace', amountCents: 21000, accountId: inter.id, categoryId: cat(pj, 'Software e ferramentas'), competenceDate: toolsDate });
    }
    const taxDate = day(m, 20);
    await add(ctxPJ, { type: 'EXPENSE', description: 'DAS Simples Nacional', amountCents: Math.round(38400 * k), accountId: inter.id, categoryId: cat(pj, 'Impostos'), status: settledIfPast(taxDate), competenceDate: day(m, 1), dueDate: taxDate });
    const plDate = day(m, 15);
    if (plDate <= today) {
      await createTransfer(user.id, { fromAccountId: inter.id, toAccountId: nubank.id, amountCents: 160000, date: plDate, classification: 'PRO_LABORE', description: 'Pró-labore' });
    }
  }
  // Contas a receber: projeto da Nexa com recebimento parcial e uma parcela em atraso.
  const nexaProject = await createTransaction(
    ctxPJ,
    transactionCreateSchema.parse({
      type: 'INCOME', description: 'Landing page Nexa', amountCents: 480000, accountId: inter.id,
      categoryId: cat(pj, 'Serviços prestados'), contactId: nexa.id, status: 'PENDING',
      competenceDate: `${shiftMonth(month, -1)}-15`, dueDate: `${shiftMonth(month, -1)}-25`,
    }),
  );
  await settleTransaction(ctxPJ, nexaProject.id, { date: `${shiftMonth(month, -1)}-25`, amountCents: 200000 });
  await createTransaction(
    ctxPJ,
    transactionCreateSchema.parse({
      type: 'EXPENSE', description: 'Material impresso evento', amountCents: 62000, accountId: inter.id,
      categoryId: cat(pj, 'Fornecedores'), contactId: grafica.id, status: 'PENDING',
      competenceDate: today, dueDate: `${shiftMonth(month, 1)}-05`,
    }),
  );

  // Recorrências a partir do próximo mês (os meses anteriores já foram lançados acima).
  const next = shiftMonth(month, 1);
  const rules: [typeof ctxPF, Parameters<typeof createRule>[1]][] = [
    [ctxPF, { type: 'INCOME', description: 'Salário Tech Co.', amountCents: 780000, amountKind: 'FIXED', accountId: itau.id, categoryId: cat(pf, 'Salário'), frequency: 'MONTHLY', intervalCount: 1, startDate: `${next}-05` }],
    [ctxPF, { type: 'EXPENSE', description: 'Aluguel & Condomínio', amountCents: 185000, amountKind: 'FIXED', accountId: itau.id, categoryId: cat(pf, 'Moradia'), counterparty: 'QuintoAndar', frequency: 'MONTHLY', intervalCount: 1, startDate: `${next}-08` }],
    [ctxPF, { type: 'EXPENSE', description: 'Conta de Luz • Enel', amountCents: 25000, amountKind: 'VARIABLE', accountId: itau.id, categoryId: cat(pf, 'Serviços básicos'), frequency: 'MONTHLY', intervalCount: 1, startDate: `${next}-10` }],
    [ctxPF, { type: 'EXPENSE', description: 'Spotify Premium Duo + Netflix', amountCents: 6390, amountKind: 'FIXED', accountId: nubank.id, categoryId: cat(pf, 'Assinaturas'), frequency: 'MONTHLY', intervalCount: 1, startDate: `${next}-12` }],
    [ctxPJ, { type: 'INCOME', description: 'Consultoria Design System', amountCents: 640000, amountKind: 'ESTIMATED', accountId: inter.id, categoryId: cat(pj, 'Serviços prestados'), contactId: studio.id, frequency: 'MONTHLY', intervalCount: 1, startDate: `${next}-11` }],
    [ctxPJ, { type: 'EXPENSE', description: 'DAS Simples Nacional', amountCents: 38400, amountKind: 'VARIABLE', accountId: inter.id, categoryId: cat(pj, 'Impostos'), frequency: 'MONTHLY', intervalCount: 1, startDate: `${next}-20` }],
  ];
  for (const [ctx, input] of rules) await createRule(ctx, input);

  await createTransfer(user.id, { fromAccountId: itau.id, toAccountId: nubank.id, amountCents: 50000, date: formatDate(parseDate(`${month}-01`)) <= today ? `${month}-01` : today, description: 'Reforço de saldo' });

  // Reserva de emergência numa poupança.
  const reserva = await createAccount(ctxPF, { name: 'Reserva Nubank', institution: 'Nubank', type: 'SAVINGS', initialBalanceCents: 1450000, referenceDate: start });
  await updateReserve(ctxPF, { targetMonths: 6, accountIds: [reserva.id] });

  // Cartão de crédito com compras à vista e parceladas; faturas vencidas já pagas pela conta.
  const card = await createCard(ctxPF, { name: 'Nubank Roxinho', institution: 'Nubank', brand: 'Mastercard', limitCents: 1200000, closingDay: 3, dueDay: 10, paymentAccountId: nubank.id, color: '#6C3643' });
  const purchases: [string, number, number, string, string][] = [
    ['Notebook Dell Inspiron', 420000, 10, day(shiftMonth(month, -3), 18), 'Educação'],
    ['Passagem aérea Floripa', 135000, 3, day(shiftMonth(month, -1), 22), 'Lazer'],
    ['Tênis de corrida', 59990, 2, day(shiftMonth(month, -2), 7), 'Saúde'],
    ['iFood', 8790, 1, addDaysISO(today, -2), 'Alimentação'],
    ['Posto Shell', 21000, 1, addDaysISO(today, -6), 'Transporte'],
  ];
  for (const [description, totalCents, installments, purchaseDate, c] of purchases) {
    if (purchaseDate < start) continue;
    await createPurchase(ctxPF, card.id, { description, totalCents, installments, purchaseDate, categoryId: cat(pf, c) });
  }
  for (const inv of (await getCard(pf, card.id)).pendingInvoices) {
    if (inv.dueDate < today && inv.id) {
      await payInvoice(ctxPF, card.id, inv.id, { fromAccountId: nubank.id, date: inv.dueDate });
    }
  }

  // Financiamento do carro (PRICE), cadastrado com parcelas antigas já pagas.
  const debt = await createDebt(ctxPF, {
    kind: 'FINANCING', name: 'Financiamento Onix', creditor: 'Banco Itaú', principalCents: 4800000,
    monthlyRatePpm: 14900, system: 'PRICE', installmentCount: 48, firstDueDate: day(shiftMonth(month, -12), 15),
    feesCents: 1500, accountId: itau.id, paidInstallments: 7,
  });
  for (const i of debt.installments) {
    if (i.state !== 'PAID' && i.transactionId && i.dueDate <= today) {
      await settleTransaction(ctxPF, i.transactionId, { date: i.dueDate });
    }
  }

  // Orçamentos mensais.
  for (const [c, limit] of [['Mercado', 60000], ['Alimentação', 30000], ['Lazer', 25000], ['Transporte', 12000]] as const) {
    await upsertBudget(ctxPF, { categoryId: cat(pf, c), limitCents: limit, alertThresholdBps: 8000 });
  }

  console.log(`Seed concluído. Login: ${EMAIL} / hoink1234`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
