import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { addDaysISO, nthOccurrence } from '../src/domain/recurrence';
import { todayISO } from '../src/lib/dates';
import { prisma } from '../src/lib/prisma';
import { generateAll, resetGenerationThrottle } from '../src/modules/recurring/recurring.service';
import { balanceOf, categoryId, createAccount, createUser, resetDb, type TestUser } from './helpers';

type Occ = { id: string; amountCents: number; status: string; competenceDate: string; recurring: { isOverride: boolean; ruleId: string } };

let u: TestUser;
let accountId: string;
let catId: string;
const today = todayISO();
const base = () => `/api/entities/${u.personalId}/recurring`;

beforeAll(async () => {
  await resetDb();
  u = await createUser();
  accountId = (await createAccount(u, u.personalId, 100000)).id;
  catId = await categoryId(u, u.personalId, 'Serviços básicos');
});
beforeEach(() => resetGenerationThrottle());

async function createEnergy(extra: object = {}) {
  const res = await u.api.post(base(), {
    type: 'EXPENSE',
    description: 'Conta de energia',
    amountCents: 25000,
    amountKind: 'VARIABLE',
    accountId,
    categoryId: catId,
    frequency: 'MONTHLY',
    startDate: today,
    ...extra,
  });
  expect(res.status).toBe(201);
  return res.body.data as { id: string; occurrences: Occ[] };
}

const rule = async (id: string) => (await u.api.get(`${base()}/${id}`)).body.data as { occurrences: Occ[]; status: string; stats: Record<string, number>; nextOccurrence: unknown };
const open = (occ: Occ[]) => occ.filter((o) => o.status === 'PLANNED' || o.status === 'PENDING');

describe('recorrências', () => {
  it('gera as próximas ocorrências previstas, sem duplicar ao gerar de novo', async () => {
    const r = await createEnergy();
    expect(r.occurrences.length).toBeGreaterThanOrEqual(3); // horizonte de 90 dias
    expect(r.occurrences.every((o) => o.status === 'PLANNED' && o.amountCents === 25000)).toBe(true);
    const dates = r.occurrences.map((o) => o.competenceDate);
    expect(dates[0]).toBe(today);
    expect(dates[1]).toBe(nthOccurrence({ frequency: 'MONTHLY', startDate: today }, 1));

    await generateAll();
    await generateAll();
    await u.api.get(base());
    expect((await rule(r.id)).occurrences).toHaveLength(r.occurrences.length);
    // Previsto não altera saldo (RN06).
    expect(await balanceOf(u, u.personalId, accountId)).toBe(100000);
  });

  it('valor variável: paga só esta ocorrência com o valor real', async () => {
    const r = await createEnergy({ description: 'Energia variável' });
    const [first, second] = r.occurrences;
    const before = await balanceOf(u, u.personalId, accountId);
    const paid = await u.api.post(`/api/entities/${u.personalId}/transactions/${first!.id}/settle`, {
      date: today,
      finalAmountCents: 28750,
    });
    expect(paid.body.data).toMatchObject({ amountCents: 28750, status: 'SETTLED' });
    expect(paid.body.data.recurring.isOverride).toBe(true);
    const after = await rule(r.id);
    expect(after.occurrences.find((o) => o.id === second!.id)!.amountCents).toBe(25000);
    expect(await balanceOf(u, u.personalId, accountId)).toBe(before - 28750);
  });

  it('editar a série preserva realizados e ocorrências editadas individualmente (RN05)', async () => {
    const r = await createEnergy({ description: 'Internet', amountKind: 'FIXED' });
    const [paid, edited, normal] = r.occurrences;
    await u.api.post(`/api/entities/${u.personalId}/transactions/${paid!.id}/settle`, { date: today });
    await u.api.patch(`/api/entities/${u.personalId}/transactions/${edited!.id}`, { amountCents: 19990 });

    const res = await u.api.patch(`${base()}/${r.id}`, { scope: 'SERIES', changes: { amountCents: 12990 } });
    expect(res.status).toBe(200);
    const occ = (await rule(r.id)).occurrences;
    expect(occ.find((o) => o.id === paid!.id)).toMatchObject({ amountCents: 25000, status: 'SETTLED' });
    expect(occ.find((o) => o.id === edited!.id)!.amountCents).toBe(19990);
    expect(occ.find((o) => o.id === normal!.id)!.amountCents).toBe(12990);
  });

  it('alterar desta em diante divide a série sem tocar nas anteriores', async () => {
    const r = await createEnergy({ description: 'Academia', amountKind: 'FIXED', amountCents: 9900 });
    const [o1, o2, o3] = r.occurrences;
    await u.api.post(`/api/entities/${u.personalId}/transactions/${o1!.id}/settle`, { date: today });

    const res = await u.api.patch(`${base()}/${r.id}`, {
      scope: 'FROM',
      fromDate: o2!.competenceDate,
      changes: { amountCents: 11900 },
    });
    const newRule = res.body.data as { id: string; occurrences: Occ[]; previousRuleId: string };
    expect(newRule.id).not.toBe(r.id);
    expect(newRule.previousRuleId).toBe(r.id);
    expect(newRule.occurrences[0]!.competenceDate).toBe(o2!.competenceDate);
    expect(newRule.occurrences.every((o) => o.amountCents === 11900)).toBe(true);
    expect(newRule.occurrences.map((o) => o.competenceDate)).toContain(o3!.competenceDate);

    const old = await rule(r.id);
    expect(old.occurrences.map((o) => o.id)).toEqual([o1!.id]);
    expect(old.occurrences[0]).toMatchObject({ amountCents: 9900, status: 'SETTLED' });

    // Nenhuma data duplicada entre as duas regras.
    const all = await prisma.transaction.findMany({
      where: { recurringRuleId: { in: [r.id, newRule.id] }, deletedAt: null },
      select: { occurrenceDate: true },
    });
    const keys = all.map((t) => t.occurrenceDate!.toISOString());
    expect(new Set(keys).size).toBe(keys.length);
  });

  it('cancelar uma ocorrência não a recria na próxima geração', async () => {
    const r = await createEnergy({ description: 'Streaming', amountKind: 'FIXED' });
    const target = r.occurrences[1]!;
    expect((await u.api.delete(`/api/entities/${u.personalId}/transactions/${target.id}`)).status).toBe(204);
    await generateAll();
    const occ = (await rule(r.id)).occurrences.filter((o) => o.competenceDate === target.competenceDate);
    expect(occ).toHaveLength(1);
    expect(occ[0]!.status).toBe('CANCELED');
  });

  it('pausar remove as previstas futuras; reativar volta a gerar a partir de hoje', async () => {
    const r = await createEnergy({ description: 'Seguro', amountKind: 'FIXED', startDate: addDaysISO(today, 1) });
    const paused = await u.api.post(`${base()}/${r.id}/pause`);
    expect(paused.body.data.status).toBe('PAUSED');
    expect(open(paused.body.data.occurrences)).toHaveLength(0);
    await generateAll();
    expect(open((await rule(r.id)).occurrences)).toHaveLength(0);

    const resumed = await u.api.post(`${base()}/${r.id}/resume`);
    expect(resumed.body.data.status).toBe('ACTIVE');
    expect(open(resumed.body.data.occurrences).length).toBeGreaterThanOrEqual(3);
  });

  it('cancelar a série preserva o histórico e não gera mais nada', async () => {
    const r = await createEnergy({ description: 'Aluguel', amountKind: 'FIXED', amountCents: 185000 });
    await u.api.post(`/api/entities/${u.personalId}/transactions/${r.occurrences[0]!.id}/settle`, { date: today });
    const canceled = await u.api.post(`${base()}/${r.id}/cancel`);
    expect(canceled.body.data.status).toBe('CANCELED');
    const occ = canceled.body.data.occurrences as Occ[];
    expect(occ.filter((o) => o.status === 'SETTLED')).toHaveLength(1);
    expect(open(occ).filter((o) => o.competenceDate >= today)).toHaveLength(0);
    await generateAll();
    expect(open((await rule(r.id)).occurrences).filter((o) => o.competenceDate >= today)).toHaveLength(0);
    expect((await u.api.patch(`${base()}/${r.id}`, { scope: 'SERIES', changes: { amountCents: 1 } })).body.error.code).toBe(
      'RULE_CANCELED',
    );
  });

  it('mudar o calendário da série regenera as previstas e mantém as realizadas', async () => {
    const r = await createEnergy({ description: 'Faxina', amountKind: 'FIXED', amountCents: 15000 });
    await u.api.post(`/api/entities/${u.personalId}/transactions/${r.occurrences[0]!.id}/settle`, { date: today });
    const res = await u.api.patch(`${base()}/${r.id}`, { scope: 'SERIES', changes: { frequency: 'WEEKLY' } });
    const occ = res.body.data.occurrences as Occ[];
    expect(occ[0]).toMatchObject({ status: 'SETTLED', competenceDate: today });
    expect(occ.map((o) => o.competenceDate)).toContain(addDaysISO(today, 7));
    expect(occ.length).toBeGreaterThanOrEqual(13);
  });

  it('valida a regra e isola entre usuários (RN11)', async () => {
    const bad = await u.api.post(base(), {
      type: 'EXPENSE', description: 'X', amountCents: 100, accountId, frequency: 'CUSTOM', startDate: today,
    });
    expect(bad.status).toBe(400);
    const r = await createEnergy({ description: 'Privada' });
    const other = await createUser('Outra');
    expect((await other.api.get(`/api/entities/${u.personalId}/recurring/${r.id}`)).status).toBe(404);
    expect((await other.api.get(`/api/entities/${other.personalId}/recurring/${r.id}`)).status).toBe(404);
  });

  it('ocorrências previstas entram na previsão do mês e no filtro de recorrentes', async () => {
    const month = today.slice(0, 7);
    const dash = (await u.api.get(`/api/entities/${u.personalId}/dashboard?month=${month}`)).body.data;
    expect(dash.forecast.expenseCents).toBeGreaterThan(0);
    const list = await u.api.get(`/api/entities/${u.personalId}/transactions?kind=recurring&pageSize=100&from=${today}`);
    expect(list.body.data.every((t: { recurring: unknown }) => t.recurring !== null)).toBe(true);
  });
});
