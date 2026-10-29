import type { CategoryKind, EntityKind } from '@prisma/client';

type Def = { name: string; kind: CategoryKind; icon: string; color: string };

const PERSONAL: Def[] = [
  { name: 'Alimentação', kind: 'EXPENSE', icon: 'restaurant', color: '#F3A9B8' },
  { name: 'Mercado', kind: 'EXPENSE', icon: 'shopping_cart', color: '#F3A9B8' },
  { name: 'Moradia', kind: 'EXPENSE', icon: 'home', color: '#103E37' },
  { name: 'Transporte', kind: 'EXPENSE', icon: 'directions_car', color: '#5E6B66' },
  { name: 'Saúde', kind: 'EXPENSE', icon: 'medical_services', color: '#B9E9CF' },
  { name: 'Lazer', kind: 'EXPENSE', icon: 'sports_esports', color: '#A2D0C6' },
  { name: 'Educação', kind: 'EXPENSE', icon: 'school', color: '#3B665E' },
  { name: 'Serviços básicos', kind: 'EXPENSE', icon: 'bolt', color: '#5A2734' },
  { name: 'Assinaturas', kind: 'EXPENSE', icon: 'subscriptions', color: '#6C3643' },
  { name: 'Empréstimos e financiamentos', kind: 'EXPENSE', icon: 'credit_score', color: '#5A2734' },
  { name: 'Outros', kind: 'EXPENSE', icon: 'more_horiz', color: '#717976' },
  { name: 'Salário', kind: 'INCOME', icon: 'payments', color: '#103E37' },
  { name: 'Rendimentos', kind: 'INCOME', icon: 'trending_up', color: '#B9E9CF' },
  { name: 'Renda extra', kind: 'INCOME', icon: 'work', color: '#A2D0C6' },
  { name: 'Outras receitas', kind: 'INCOME', icon: 'add_circle', color: '#717976' },
];

const BUSINESS: Def[] = [
  { name: 'Fornecedores', kind: 'EXPENSE', icon: 'inventory_2', color: '#5E6B66' },
  { name: 'Impostos', kind: 'EXPENSE', icon: 'account_balance', color: '#5A2734' },
  { name: 'Folha e pró-labore', kind: 'EXPENSE', icon: 'badge', color: '#103E37' },
  { name: 'Software e ferramentas', kind: 'EXPENSE', icon: 'computer', color: '#3B665E' },
  { name: 'Marketing', kind: 'EXPENSE', icon: 'campaign', color: '#F3A9B8' },
  { name: 'Despesas operacionais', kind: 'EXPENSE', icon: 'business_center', color: '#A2D0C6' },
  { name: 'Tarifas bancárias', kind: 'EXPENSE', icon: 'receipt', color: '#717976' },
  { name: 'Empréstimos e financiamentos', kind: 'EXPENSE', icon: 'credit_score', color: '#5A2734' },
  { name: 'Outros', kind: 'EXPENSE', icon: 'more_horiz', color: '#717976' },
  { name: 'Serviços prestados', kind: 'INCOME', icon: 'design_services', color: '#103E37' },
  { name: 'Vendas', kind: 'INCOME', icon: 'storefront', color: '#B9E9CF' },
  { name: 'Rendimentos', kind: 'INCOME', icon: 'trending_up', color: '#A2D0C6' },
  { name: 'Outras receitas', kind: 'INCOME', icon: 'add_circle', color: '#717976' },
];

export function defaultCategories(kind: EntityKind): Def[] {
  return kind === 'PERSONAL' ? PERSONAL : BUSINESS;
}
