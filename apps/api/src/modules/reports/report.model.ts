/** Modelo único de relatório: os mesmos números vão para a tela, CSV, XLSX e PDF (RN13). */

export type ColumnType = 'text' | 'money' | 'date' | 'percent' | 'number';

export interface Column {
  key: string;
  label: string;
  type: ColumnType;
}

export type Cell = string | number | null;

export interface Section {
  title: string;
  columns: Column[];
  rows: Record<string, Cell>[];
  totals?: Record<string, Cell>;
  /** Observação exibida abaixo da tabela (ex.: "valores estimados"). */
  note?: string;
}

export interface Report {
  type: string;
  title: string;
  scope: string;
  period: { from: string; to: string; label: string };
  generatedAt: string;
  sections: Section[];
  notes: string[];
}

export const REPORT_TYPES = {
  'receitas-despesas': 'Receitas e despesas',
  'fluxo-de-caixa': 'Fluxo de caixa',
  clientes: 'Clientes',
  'contas-a-receber': 'Contas a receber',
  'contas-a-pagar': 'Contas a pagar',
  dividas: 'Dívidas',
  cofrinhos: 'Cofrinhos',
  investimentos: 'Investimentos',
  rendimentos: 'Rendimentos',
  patrimonio: 'Patrimônio',
  orcamentos: 'Orçamentos',
} as const;

export type ReportType = keyof typeof REPORT_TYPES;

const pad = (n: number) => String(n).padStart(2, '0');

/** Valor em centavos → "1.234,56" (sem R$), datas AAAA-MM-DD → DD/MM/AAAA, percentuais em pontos-base. */
export function formatCell(type: ColumnType, v: Cell): string {
  if (v === null || v === undefined || v === '') return '';
  switch (type) {
    case 'money': {
      const n = Number(v) / 100;
      return n.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
    case 'date': {
      const s = String(v);
      return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s.split('-').reverse().join('/') : /^\d{4}-\d{2}$/.test(s) ? `${s.slice(5)}/${s.slice(0, 4)}` : s;
    }
    case 'percent':
      return `${(Number(v) / 100).toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`;
    case 'number':
      return Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 8 });
    default:
      return String(v);
  }
}

export function nowLabel(d = new Date()) {
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
