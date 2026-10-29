# hoink.

> **Seu dinheiro, do seu jeito.** Gestão financeira pessoal e profissional (PF/PJ), com visão consolidada.

[![CI](https://github.com/Isadora-Correa/Hoink/actions/workflows/ci.yml/badge.svg)](https://github.com/Isadora-Correa/Hoink/actions/workflows/ci.yml)
[![CD](https://github.com/Isadora-Correa/Hoink/actions/workflows/cd.yml/badge.svg)](https://github.com/Isadora-Correa/Hoink/actions/workflows/cd.yml)

Projeto final da disciplina de **DevOps (FATEC)**. A hoink. resolve um problema comum de autônomos e
pequenos empreendedores: misturar o dinheiro da pessoa física com o da empresa. O app separa os ambientes
**Pessoal**, **Profissional** e **Consolidado (Total)**, calcula saldos a partir das movimentações e nunca
conta transferências internas como receita ou despesa.

## Funcionalidades

| Área | O que já funciona |
|---|---|
| Autenticação | Cadastro, login, logout, recuperação de senha por código, troca de senha, gestão de sessões |
| Ambientes | Pessoal e Profissional criados no cadastro, isolamento por usuário/ambiente, visão Consolidada com participação societária |
| Contas | CRUD, arquivamento, extrato com saldo acumulado, conciliação com ajuste rastreável |
| Lançamentos | Receitas, despesas, reembolsos e ajustes; status previsto/pendente/parcial/liquidado/atrasado; filtros, busca, paginação |
| Transferências | Entre contas próprias e entre PF ↔ PJ com classificação gerencial (pró-labore, aporte, retirada…) |
| Dashboard | Saldo, entradas/saídas realizadas, contas a pagar, evolução de 6 meses, gastos por categoria, próximos vencimentos |
| Categorias | Padrões por tipo de ambiente + personalizadas |
| Perfil | Foto de perfil, conta profissional (PJ) opcional, ativável e desativável sem perder dados |
| Recorrências (Fase 2) | Diária, semanal, quinzenal, mensal, anual e personalizada; valor fixo, variável ou estimado; edição de uma ocorrência, desta em diante ou da série (histórico preservado); pausa, reativação e cancelamento; geração automática sem duplicatas |
| Clientes e fornecedores (Fase 2) | Cadastro com CPF/CNPJ, faturado × recebido, em aberto, inadimplência e histórico financeiro |
| Contas a pagar e receber (Fase 2) | Itens em aberto e em atraso, próximos 7 dias, faturas de cartão a pagar, recebimentos e pagamentos parciais com histórico por data |
| Cartões de crédito (Fase 2) | Limite usado e disponível, compras à vista e parceladas (até 48x), faturas por mês com fechamento e vencimento, pagamento total ou parcial da fatura **sem duplicar a despesa** (RN08) |
| Dívidas (Fase 2) | Financiamentos e empréstimos PRICE ou SAC com principal, juros e encargos separados; parcelas em contas a pagar; multa e mora no pagamento; amortização extraordinária (reduz prazo ou parcela); simulação e registro de quitação antecipada |
| Planejamento (Fase 2) | Fluxo de caixa projetado para 30/60/90 dias separando **confirmado** de **previsto**, alerta de saldo negativo, orçamentos por categoria com alertas e reserva de emergência |
| Cofrinhos e lista de desejos (Fase 3) | Reservas, metas e desejos (PS5, drone, carro…) com preço, link e prioridade; guardar e resgatar como transferência do saldo; rendimento por % do CDI/Selic ou prefixado separando principal, rendimento confirmado, estimado, saldo bruto e líquido estimado (IR/IOF); simulação até a meta; "Comprei!" lança a compra uma única vez |
| Gamificação (Fase 3) | Níveis de porquinho, pontos por marcos (25/50/75/100% da meta, desejo realizado, R$ 1 mil e 10 mil guardados), sequência semanal de depósitos e comemoração ao desbloquear conquistas |
| Investimentos (Fase 3) | CDB, LCI, LCA, Tesouro, fundos, ações, ETFs e outros, com motor por produto (% CDI/Selic, prefixado, IPCA+, cotas × preço, valor manual); aportes, resgates, proventos, custos, vencimentos, IR regressivo/isenção estimados, evolução e comparação |
| Índices de mercado (Fase 3) | CDI, Selic e IPCA do Banco Central (SGS, API pública), sincronizados a cada 12 h; dados ausentes ficam sinalizados como desatualizados — nada é inventado |
| Patrimônio (Fase 3) | Ativos (contas, cofrinhos, investimentos, bens) − passivos (dívidas, cartões, outras obrigações), sem dupla contagem, com fotografia mensal e histórico |
| Privacidade | Olhinho no topo de todas as telas esconde todos os valores, inclusive gastos e gráficos |

Costelinha IA e relatórios aparecem no app como **"Em construção"** (Fase 4), sem dados simulados.

## Arquitetura

```
apps/app   Front-end Flutter (Web, Android, iOS) ─┐ HTTPS + Bearer token
apps/api   Back-end Node.js/Express (TypeScript) ◀┘ ── Prisma ──▶ PostgreSQL 16
e2e/       Testes E2E (Playwright)    perf/  Testes de carga (k6)
```

- **Front-end:** Flutter 3.47 (Riverpod, go_router, fl_chart), design system dos protótipos (`docs/DESIGN.md`).
- **Back-end:** Express 5, Zod (validação), Prisma 6, argon2id, pino (logs), prom-client (métricas).
- **Middlewares:** autenticação por sessão, autorização por ambiente, idempotência, rate limit, tratamento de erros, métricas.
- **Banco:** PostgreSQL com migrations, valores em centavos (`BIGINT`), restrições `CHECK` e trilha de auditoria.

Detalhes em [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Como executar

### Opção 1 — tudo em contêineres (recomendado para demonstração)

```bash
cp .env.example .env
docker compose --profile full up -d --build
# Front-end: http://localhost:8080   API: http://localhost:3333
# Se a porta 8080 estiver ocupada: WEB_PORT=8081 docker compose --profile full up -d
```

Dados de demonstração (opcional — o banco do Compose fica exposto em `localhost:5433`):

```bash
pnpm install && pnpm db:seed   # cria miguel@hoink.dev / hoink1234
```

### Opção 2 — desenvolvimento local

Pré-requisitos: Node 24, pnpm 10, Flutter 3.47, Docker.

```bash
cp .env.example .env
pnpm install
pnpm db:up            # PostgreSQL em localhost:5433 (+ banco hoink_test)
pnpm db:migrate       # aplica as migrations
pnpm db:seed          # dados de demonstração
pnpm dev              # API em http://localhost:3333

cd apps/app
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3333
```

## Testes

| Tipo | Ferramenta | Comando | Quantidade |
|---|---|---|---|
| Unitários (regras de domínio, recorrências, faturas, amortização, projeção, dinheiro) | Vitest | `pnpm --filter @hoink/api test` | 38 |
| Integração (API + PostgreSQL real) | Vitest + Supertest | `pnpm --filter @hoink/api test` | 65 |
| Unitários e de widget (app) | flutter_test | `cd apps/app && flutter test` | 37 |
| E2E (desktop e mobile) | Playwright | `pnpm test:e2e` | 12 |
| Performance | k6 | `k6 run perf/load.js` | p95 < 500 ms, erros < 1% |

Cobertura da API: ~95% das linhas (mínimo exigido no CI: 75%). Como rodar cada tipo e onde ficam as
evidências: [docs/TESTING.md](docs/TESTING.md).

## CI/CD

- **CI** (`.github/workflows/ci.yml`), em todo push e PR: validação da estrutura → lint/typecheck → testes
  unitários e de integração com cobertura → análise e testes do Flutter → build → E2E → carga com k6 →
  auditoria de dependências e varredura Trivy (vulnerabilidades e segredos) → build das imagens Docker.
- **CD** (`.github/workflows/cd.yml`), após o CI verde na `main` ou em tags `v*`: publica as imagens no
  GitHub Container Registry com a versão e o commit, dispara o deploy e verifica a versão publicada.

Processo completo: [docs/DEPLOY.md](docs/DEPLOY.md).

## Monitoramento

| Endpoint | Para quê |
|---|---|
| `GET /health` | Disponibilidade (inclui verificação do banco) — usado pelos health checks do Docker e do deploy |
| `GET /version` | Versão e commit publicados |
| `GET /metrics` | Métricas Prometheus: requisições, latência (histograma), erros 5xx, eventos de negócio |
| `GET /version.json` (front) | Versão e commit do front-end |

Logs estruturados em JSON (pino), com eventos como `auth.login`, `auth.login_failed`, `transaction.created`
e `transfer.created`. Senhas e tokens são omitidos dos logs.

## Configuração e segurança

- Toda configuração vem de variáveis de ambiente (`.env.example` documenta todas, sem credenciais reais).
- Senhas com argon2id; tokens de sessão guardados apenas como hash SHA-256; sessões revogáveis.
- Rate limit em autenticação, Helmet, CORS restrito, validação de entrada no servidor.
- Pipelines com permissões mínimas (`contents: read`; `packages: write` só no job que publica imagens).
- Dependabot, `pnpm audit` e Trivy no CI.

## Colaboração

Fluxo de branches, padrão de commits e Pull Requests: [CONTRIBUTING.md](CONTRIBUTING.md).

## Estrutura

```
apps/api/          API (src/modules, src/domain, prisma/, tests/)
apps/app/          App Flutter (lib/app, lib/core, lib/data, lib/state, lib/ui)
e2e/               Testes E2E Playwright
perf/              Testes de carga k6
docs/              Arquitetura, deploy, testes, design system, protótipos e marca
.github/           Workflows, templates de PR/issue, Dependabot
```
