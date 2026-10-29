import ExcelJS from 'exceljs';
import { beforeEach, describe, expect, it } from 'vitest';
import { REPORT_TYPES } from '../src/modules/reports/report.model';
import { resolvePeriod } from '../src/modules/reports/reports.service';
import { todayISO } from '../src/lib/dates';
import { app, categoryId, createAccount, createUser, resetDb, type TestUser } from './helpers';
import request from 'supertest';

let u: TestUser;
let base: string;
const today = todayISO();
const month = today.slice(0, 7);

beforeEach(async () => {
  await resetDb();
  u = await createUser();
  base = `/api/entities/${u.personalId}`;
  const acc = await createAccount(u, u.personalId, 500_000);
  const mercado = await categoryId(u, u.personalId, 'Mercado');
  const salario = await categoryId(u, u.personalId, 'Salário');
  await u.api.post(`${base}/transactions`, { type: 'INCOME', description: 'Salário', amountCents: 800_000, accountId: acc.id, categoryId: salario, competenceDate: today });
  await u.api.post(`${base}/transactions`, { type: 'EXPENSE', description: '=HYPERLINK("http://x")', amountCents: 123_456, accountId: acc.id, categoryId: mercado, competenceDate: today });
});

const binary = (r: request.Response) => r.body as Buffer;
const getFile = (url: string) =>
  request(app)
    .get(url)
    .set('Authorization', `Bearer ${u.token}`)
    .buffer(true)
    .parse((res, cb) => {
      const chunks: Buffer[] = [];
      res.on('data', (c: Buffer) => chunks.push(c));
      res.on('end', () => cb(null, Buffer.concat(chunks)));
    });

describe('relatórios', () => {
  it('receitas e despesas batem com o dashboard (RN13) em JSON, CSV, XLSX e PDF', async () => {
    const dash = (await u.api.get(`${base}/dashboard?month=${month}`)).body.data;
    const json = (await u.api.get(`${base}/reports/receitas-despesas?period=month&ref=${month}`)).body.data;
    const resumo = json.sections[0].rows;
    expect(resumo.find((r: { item: string }) => r.item === 'Receitas').valor).toBe(dash.realized.incomeCents);
    expect(resumo.find((r: { item: string }) => r.item.startsWith('Despesas')).valor).toBe(dash.realized.expenseCents);
    expect(json.sections[1].rows).toEqual(expect.arrayContaining([{ tipo: 'Despesa', categoria: 'Mercado', valor: 123_456 }]));

    const csv = await getFile(`${base}/reports/receitas-despesas?format=csv`);
    expect(csv.status).toBe(200);
    expect(csv.headers['content-type']).toContain('text/csv');
    expect(csv.headers['content-disposition']).toMatch(/attachment; filename="hoink-receitas-despesas-/);
    const text = binary(csv).toString('utf8');
    expect(text.charCodeAt(0)).toBe(0xfeff);
    expect(text).toContain('Receitas;8000,00');
    expect(text).toContain('Mercado;1234,56');

    const xlsx = await getFile(`${base}/reports/receitas-despesas?format=xlsx`);
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(binary(xlsx) as unknown as ArrayBuffer);
    const sheet = wb.getWorksheet('Resumo')!;
    const values = sheet.getSheetValues().flat().filter((v) => typeof v === 'number');
    expect(values).toEqual(expect.arrayContaining([8000, 1234.56]));

    const pdf = await getFile(`${base}/reports/receitas-despesas?format=pdf`);
    expect(pdf.headers['content-type']).toBe('application/pdf');
    expect(binary(pdf).subarray(0, 5).toString()).toBe('%PDF-');
    // Uma página só (o rodapé não pode gerar páginas em branco).
    expect(binary(pdf).toString('latin1').match(/\/Type \/Page[^s]/g)).toHaveLength(1);
  });

  it('protege contra injeção de fórmulas ao abrir em planilhas', async () => {
    const acc = (await u.api.get(`${base}/accounts`)).body.data[0];
    await u.api.post(`${base}/transactions`, {
      type: 'EXPENSE',
      description: '=HYPERLINK("http://malicioso")',
      amountCents: 1000,
      accountId: acc.id,
      status: 'PENDING',
      competenceDate: today,
      dueDate: today,
    });
    const csv = binary(await getFile(`${base}/reports/contas-a-pagar?format=csv&period=year`)).toString('utf8');
    expect(csv).toContain(`"'=HYPERLINK(""http://malicioso"")"`);
    expect(csv).not.toMatch(/;=HYPERLINK/);
    const xlsx = await getFile(`${base}/reports/contas-a-pagar?format=xlsx&period=year`);
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(binary(xlsx) as unknown as ArrayBuffer);
    const cells = wb.worksheets[0]!.getSheetValues().flat().map(String);
    expect(cells).toContain(`'=HYPERLINK("http://malicioso")`);
  });

  it('todos os tipos geram em todos os formatos, no ambiente e no consolidado', async () => {
    const types = (await u.api.get('/api/reports')).body.data.map((t: { type: string }) => t.type);
    expect(types).toEqual(Object.keys(REPORT_TYPES));
    for (const t of types) {
      const res = await u.api.get(`${base}/reports/${t}?period=quarter`);
      expect(res.status, t).toBe(200);
      expect(res.body.data.sections.length, t).toBeGreaterThan(0);
      expect((await getFile(`${base}/reports/${t}?format=pdf&period=year`)).status, t).toBe(200);
    }
    const consolidated = (await u.api.get('/api/consolidated/reports/receitas-despesas')).body.data;
    expect(consolidated.scope).toBe('Consolidado (Total)');
    expect(consolidated.sections[0].rows[0].valor).toBe(800_000);
  });

  it('valida período e isola ambientes', async () => {
    expect((await u.api.get(`${base}/reports/inexistente`)).status).toBe(404);
    expect((await u.api.get(`${base}/reports/receitas-despesas?period=custom&from=2026-02-01&to=2026-01-01`)).body.error.code).toBe('INVALID_PERIOD');
    expect((await u.api.get(`${base}/reports/receitas-despesas?period=custom&from=2000-01-01&to=2026-01-01`)).body.error.code).toBe('PERIOD_TOO_LONG');
    const other = await createUser('Outra');
    expect((await other.api.get(`${base}/reports/receitas-despesas`)).status).toBe(404);
    expect(resolvePeriod({ period: 'quarter', ref: '2026-05' })).toEqual({ from: '2026-04-01', to: '2026-06-30', label: '2º trimestre de 2026' });
    expect(resolvePeriod({ period: 'year', ref: '2026-05' }).to).toBe('2026-12-31');
  });
});
