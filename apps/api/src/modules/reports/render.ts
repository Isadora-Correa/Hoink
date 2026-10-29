import { existsSync } from 'node:fs';
import { join } from 'node:path';
import ExcelJS from 'exceljs';
import PDFDocument from 'pdfkit';
import { formatCell, type Column, type Report } from './report.model';

const PINE = '#103E37';
const IVORY = '#FFF9F1';
const PINK = '#F3A9B8';
const MUTED = '#5E6B66';

/** Evita injeção de fórmulas ao abrir CSV/XLSX em planilhas (=, +, -, @ no início do texto). */
function safeText(v: string): string {
  return /^[=+\-@\t\r]/.test(v) ? `'${v}` : v;
}

/** CSV no padrão brasileiro: separador ";", vírgula decimal e BOM para o Excel reconhecer UTF-8. */
export function toCsv(r: Report): Buffer {
  const esc = (s: string) => (/[;"\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s);
  const csvCell = (c: Column, v: unknown) => {
    if (v === null || v === undefined || v === '') return '';
    if (c.type === 'money') return (Number(v) / 100).toFixed(2).replace('.', ',');
    if (c.type === 'percent') return (Number(v) / 100).toFixed(2).replace('.', ',');
    return esc(safeText(formatCell(c.type, v as string)));
  };
  const lines: string[] = [esc(`${r.title} — ${r.scope}`), esc(r.period.label), ''];
  for (const s of r.sections) {
    lines.push(esc(s.title));
    lines.push(s.columns.map((c) => esc(c.label)).join(';'));
    for (const row of s.rows) lines.push(s.columns.map((c) => csvCell(c, row[c.key])).join(';'));
    if (s.totals) lines.push(s.columns.map((c) => csvCell(c, s.totals![c.key])).join(';'));
    if (s.note) lines.push(esc(s.note));
    lines.push('');
  }
  for (const n of r.notes) lines.push(esc(n));
  return Buffer.from(`\uFEFF${lines.join('\r\n')}`, 'utf8');
}

export async function toXlsx(r: Report): Promise<Buffer> {
  const wb = new ExcelJS.Workbook();
  wb.creator = 'hoink.';
  wb.created = new Date(r.generatedAt);
  const used = new Set<string>();
  for (const s of r.sections) {
    let name = s.title.replace(/[\\/?*[\]:]/g, ' ').slice(0, 31);
    for (let i = 2; used.has(name); i++) name = `${s.title.slice(0, 28)} ${i}`;
    used.add(name);
    const ws = wb.addWorksheet(name);
    ws.addRow([`${r.title} — ${r.scope}`]).font = { bold: true, size: 14, color: { argb: 'FF103E37' } };
    ws.addRow([r.period.label]).font = { color: { argb: 'FF5E6B66' } };
    ws.addRow([]);
    const header = ws.addRow(s.columns.map((c) => c.label));
    header.eachCell((cell) => {
      cell.font = { bold: true, color: { argb: 'FFFFF9F1' } };
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF103E37' } };
    });
    const value = (c: Column, v: unknown) => {
      if (v === null || v === undefined || v === '') return null;
      if (c.type === 'money') return Number(v) / 100;
      if (c.type === 'percent') return Number(v) / 10000;
      if (c.type === 'number') return Number(v);
      if (c.type === 'date') return formatCell('date', v as string);
      return safeText(String(v));
    };
    for (const row of s.rows) ws.addRow(s.columns.map((c) => value(c, row[c.key])));
    if (s.totals) ws.addRow(s.columns.map((c) => value(c, s.totals![c.key]))).font = { bold: true };
    s.columns.forEach((c, i) => {
      const col = ws.getColumn(i + 1);
      col.width = Math.max(12, Math.min(40, c.label.length + 4));
      if (c.type === 'money') col.numFmt = '"R$" #,##0.00;[Red]-"R$" #,##0.00';
      if (c.type === 'percent') col.numFmt = '0.0%';
    });
    ws.getColumn(1).width = Math.max(ws.getColumn(1).width ?? 12, 28);
    if (s.note) ws.addRow([]).getCell(1);
    if (s.note) ws.addRow([s.note]).font = { italic: true, color: { argb: 'FF5E6B66' } };
  }
  const info = wb.addWorksheet('Sobre');
  for (const n of r.notes) info.addRow([n]);
  return Buffer.from(await wb.xlsx.writeBuffer());
}

/** PDF A4 com a identidade da hoink. (Sora, verde-pinho) e tabelas paginadas. */
export function toPdf(r: Report): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    // Tabelas largas (muitas colunas) ficam melhor na página deitada.
    const wide = r.sections.some((s) => s.columns.length > 7);
    const doc = new PDFDocument({
      size: 'A4',
      layout: wide ? 'landscape' : 'portrait',
      margin: 40,
      bufferPages: true,
      info: { Title: `${r.title} — ${r.scope}`, Author: 'hoink.' },
    });
    const chunks: Buffer[] = [];
    doc.on('data', (c: Buffer) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const fonts = join(process.cwd(), 'assets/fonts');
    const regular = existsSync(join(fonts, 'Sora-400.ttf')) ? join(fonts, 'Sora-400.ttf') : 'Helvetica';
    const bold = existsSync(join(fonts, 'Sora-600.ttf')) ? join(fonts, 'Sora-600.ttf') : 'Helvetica-Bold';
    const left = doc.page.margins.left;
    const width = doc.page.width - left - doc.page.margins.right;
    const bottom = () => doc.page.height - doc.page.margins.bottom - 30;

    // Cabeçalho
    doc.font(bold).fontSize(22).fillColor(PINE).text('hoink', left, 40, { continued: true }).fillColor(PINK).text('.');
    doc.font(regular).fontSize(9).fillColor(MUTED).text('Seu dinheiro, do seu jeito.');
    doc.moveDown(1);
    doc.font(bold).fontSize(16).fillColor(PINE).text(r.title);
    doc.font(regular).fontSize(10).fillColor(MUTED).text(`${r.scope} • ${r.period.label}`);
    doc.moveDown(1);

    for (const s of r.sections) {
      if (doc.y > bottom() - 60) doc.addPage();
      doc.font(bold).fontSize(12).fillColor(PINE).text(s.title, left);
      doc.moveDown(0.4);
      // Larguras medidas pelo conteúdo: números e datas nunca quebram; o texto absorve a sobra (ou a falta).
      let fontSize = s.columns.length > 9 ? 7.5 : 8.5;
      const allRows = [...s.rows, ...(s.totals ? [s.totals] : [])];
      const measure = () => {
        doc.font(bold).fontSize(fontSize);
        return s.columns.map((c) => {
          const headerWord = Math.max(...c.label.split(' ').map((w) => doc.widthOfString(w)));
          const cells = allRows.map((row) => doc.widthOfString(formatCell(c.type, row[c.key] ?? null)));
          const content = c.type === 'text' ? Math.min(160, Math.max(0, ...cells)) : Math.max(0, ...cells);
          return Math.max(headerWord, content) + 8;
        });
      };
      let widths = measure();
      while (widths.reduce((a, b) => a + b, 0) > width && fontSize > 6) {
        fontSize -= 0.5;
        widths = measure();
      }
      const natural = widths.reduce((a, b) => a + b, 0);
      const textCols = s.columns.map((c, i) => (c.type === 'text' ? i : -1)).filter((i) => i >= 0);
      const extra = width - natural;
      if (textCols.length) textCols.forEach((i) => (widths[i]! += extra / textCols.length));
      else widths = widths.map((w) => w + extra / widths.length);
      const drawRow = (cells: string[], opts: { header?: boolean; bold?: boolean; shade?: boolean }) => {
        doc.font(opts.header || opts.bold ? bold : regular).fontSize(fontSize);
        const heights = cells.map((c, i) => doc.heightOfString(c, { width: widths[i]! - 6 }));
        const h = Math.max(...heights) + 6;
        if (doc.y + h > bottom()) {
          doc.addPage();
        }
        const y = doc.y;
        if (opts.header) doc.rect(left, y, width, h).fill(PINE);
        else if (opts.shade) doc.rect(left, y, width, h).fill('#F2F7F4');
        let x = left;
        cells.forEach((c, i) => {
          const col = s.columns[i]!;
          const align = col.type === 'text' || col.type === 'date' ? 'left' : 'right';
          doc
            .fillColor(opts.header ? IVORY : '#1D2925')
            .text(c, x + 3, y + 3, { width: widths[i]! - 6, align, lineBreak: true });
          x += widths[i]!;
        });
        doc.y = y + h;
      };
      drawRow(s.columns.map((c) => c.label), { header: true });
      if (s.rows.length === 0) {
        doc.font(regular).fontSize(9).fillColor(MUTED).text('Sem dados no período.', left + 3, doc.y + 4);
        doc.moveDown(0.5);
      }
      s.rows.forEach((row, i) => drawRow(s.columns.map((c) => formatCell(c.type, row[c.key] ?? null)), { shade: i % 2 === 1 }));
      if (s.totals) drawRow(s.columns.map((c) => formatCell(c.type, s.totals![c.key] ?? null)), { bold: true });
      if (s.note) {
        doc.moveDown(0.3);
        doc.font(regular).fontSize(8).fillColor(MUTED).text(s.note, left, doc.y, { width });
      }
      doc.moveDown(1.2);
    }

    // Rodapé em todas as páginas
    const range = doc.bufferedPageRange();
    for (let i = range.start; i < range.start + range.count; i++) {
      doc.switchToPage(i);
      // Sem margem inferior durante o rodapé: senão o PDFKit cria uma página nova ao escrever abaixo dela.
      const margin = doc.page.margins.bottom;
      doc.page.margins.bottom = 0;
      doc
        .font(regular)
        .fontSize(7.5)
        .fillColor(MUTED)
        .text(`${r.notes.join(' ')}   Página ${i + 1} de ${range.count}`, left, doc.page.height - 32, { width, align: 'center', lineBreak: false });
      doc.page.margins.bottom = margin;
    }
    doc.end();
  });
}
