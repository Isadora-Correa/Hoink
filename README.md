<div align="center">

# hoink.

**Seu dinheiro, do seu jeito.**
Gestão financeira pessoal e profissional (PF/PJ), com visão consolidada.

[![CI](https://github.com/Isadora-Correa/Hoink/actions/workflows/ci.yml/badge.svg)](https://github.com/Isadora-Correa/Hoink/actions/workflows/ci.yml)
[![CD](https://github.com/Isadora-Correa/Hoink/actions/workflows/cd.yml/badge.svg)](https://github.com/Isadora-Correa/Hoink/actions/workflows/cd.yml)


</div>

> Projeto final da disciplina de **DevOps — FATEC**.

---

## Sumário

1. [Sobre o projeto](#1-sobre-o-projeto)
2. [Funcionalidades](#2-funcionalidades)
3. [Requisitos](#3-requisitos)
4. [Tecnologias utilizadas](#4-tecnologias-utilizadas)
5. [Arquitetura e modelagem (UML)](#5-arquitetura-e-modelagem-uml)
   - [Casos de uso](#52-diagrama-de-casos-de-uso) · [Classes](#53-diagrama-de-classes) · [Sequência](#54-diagramas-de-sequência)
6. [Estrutura de pastas](#6-estrutura-de-pastas)
7. [Pré-requisitos](#7-pré-requisitos)
8. [Instalação e execução](#8-instalação-e-execução)
9. [Configuração e variáveis de ambiente](#9-configuração-e-variáveis-de-ambiente)
10. [Banco de dados](#10-banco-de-dados)
11. [API](#11-api)
12. [Testes](#12-testes)
   - [Automatizados](#122-testes-automatizados-realizados) · [Exploratórios](#128-testes-exploratórios-realizados-pela-equipe)
13. [Processo DevOps](#13-processo-devops)
14. [Deploy](#14-deploy)
15. [Monitoramento](#15-monitoramento)
16. [Segurança](#16-segurança)
17. [Solução de problemas](#17-solução-de-problemas)
18. [Como contribuir](#18-como-contribuir)
19. [Documentação complementar](#19-documentação-complementar)
20. [Equipe e licença](#20-equipe-e-licença)

---

## 1. Sobre o projeto

### Objetivo

Oferecer um aplicativo (Web, Android e iOS) para controlar as finanças pessoais e profissionais em um só lugar,
mantendo cada ambiente separado, mas com uma **visão consolidada** do patrimônio total.

### Problema que resolve

Autônomos e pequenos empreendedores costumam **misturar o dinheiro da pessoa física com o da empresa**. Isso
atrapalha o controle de caixa, esconde despesas reais, gera dupla contagem (por exemplo, transferir da conta PJ
para a PF e contar como receita) e dificulta o planejamento.

A hoink. separa os ambientes **Pessoal**, **Profissional** e **Consolidado (Total)**, calcula os saldos a partir
das movimentações e **nunca conta transferências internas como receita ou despesa**.

### Escopo

| Dentro do escopo | Fora do escopo |
|---|---|
| Controle de contas, lançamentos, transferências e recorrências | Integração bancária automática (Open Finance) |
| Cartões de crédito, dívidas, planejamento e orçamentos | Emissão de notas fiscais e obrigações fiscais |
| Cofrinhos, metas, investimentos e patrimônio | Execução de ordens de compra/venda de investimentos |
| Relatórios em PDF, XLSX e CSV | Uso comercial em produção (projeto acadêmico) |
| Assistente financeiro (Costelinha), sem IA paga | Atendimento multi-idioma (somente português do Brasil) |

---

## 2. Funcionalidades

| Área | O que já funciona |
|---|---|
| **Autenticação** | Cadastro, login, logout, recuperação de senha por código, troca de senha, gestão de sessões |
| **Ambientes** | Pessoal e Profissional criados no cadastro, isolamento por usuário/ambiente, visão Consolidada com participação societária |
| **Contas** | CRUD, arquivamento, extrato com saldo acumulado, conciliação com ajuste rastreável |
| **Lançamentos** | Receitas, despesas, reembolsos e ajustes; status previsto/pendente/parcial/liquidado/atrasado; filtros, busca e paginação |
| **Transferências** | Entre contas próprias e entre PF ↔ PJ, com classificação gerencial (pró-labore, aporte, retirada…) |
| **Dashboard** | Saldo, entradas/saídas realizadas, contas a pagar, evolução de 6 meses, gastos por categoria, próximos vencimentos |
| **Categorias** | Padrões por tipo de ambiente + personalizadas |
| **Perfil** | Foto de perfil e conta profissional (PJ) opcional, ativável e desativável sem perder dados |
| **Recorrências** | Diária, semanal, quinzenal, mensal, anual e personalizada; valor fixo, variável ou estimado; edição de uma ocorrência, desta em diante ou da série; pausa, reativação e cancelamento; geração automática sem duplicatas |
| **Clientes e fornecedores** | Cadastro com CPF/CNPJ, faturado × recebido, em aberto, inadimplência e histórico financeiro |
| **Contas a pagar e receber** | Itens em aberto e em atraso, próximos 7 dias, faturas de cartão, pagamentos e recebimentos parciais |
| **Cartões de crédito** | Limite usado/disponível, compras à vista e parceladas (até 48x), faturas por mês, pagamento total ou parcial **sem duplicar a despesa** |
| **Dívidas** | Financiamentos e empréstimos PRICE ou SAC, juros e encargos separados, multa e mora, amortização extraordinária, simulação e quitação antecipada |
| **Planejamento** | Fluxo de caixa projetado (30/60/90 dias) separando *confirmado* de *previsto*, orçamentos por categoria com alertas, reserva de emergência |
| **Cofrinhos e desejos** | Reservas e metas com rendimento (% do CDI/Selic ou prefixado), simulação até a meta e "Comprei!" lançando a compra uma única vez |
| **Gamificação** | Níveis de porquinho, pontos por marcos, sequência semanal de depósitos e conquistas |
| **Investimentos** | CDB, LCI, LCA, Tesouro, fundos, ações, ETFs e outros, com motor de cálculo por produto, aportes, resgates, proventos, IR estimado e comparação |
| **Índices de mercado** | CDI, Selic e IPCA do Banco Central (SGS), sincronizados a cada 12 h; dado ausente é sinalizado como desatualizado |
| **Patrimônio** | Ativos − passivos sem dupla contagem, com fotografia mensal e histórico |
| **Nota fiscal (NFC-e)** | Lê o QR Code (câmera ou link/chave), consulta a Sefaz (somente domínios `gov.br`) e preenche o lançamento; a mesma nota não é lançada duas vezes |
| **Privacidade** | Botão "olhinho" que esconde todos os valores das telas |
| **Relatórios** | 11 relatórios (mensal, trimestral, anual ou personalizado) em **PDF, XLSX e CSV**, com os mesmos números da tela |
| **Costelinha** | Assistente que responde perguntas sobre os seus dados (ex.: "Quanto posso investir?") com números calculados, fontes e datas — gratuito, sem IA paga |
| **Notificações e insights** | Contas e faturas vencendo, atrasadas, orçamento estourado e saldo negativo previsto, sem avisos repetidos |

---

## 3. Requisitos

### 3.1 Requisitos funcionais (principais)

| ID | Requisito |
|---|---|
| RF01 | O usuário deve poder se cadastrar, autenticar, recuperar e trocar a senha e gerenciar suas sessões |
| RF02 | O sistema deve manter ambientes separados (Pessoal e Profissional) e uma visão Consolidada |
| RF03 | O usuário deve gerenciar contas, categorias e lançamentos (receitas, despesas, reembolsos e ajustes) |
| RF04 | O sistema deve registrar liquidações parciais e totais e calcular os saldos a partir delas |
| RF05 | O usuário deve realizar transferências entre contas, inclusive entre PF e PJ, com classificação gerencial |
| RF06 | O sistema deve gerar e gerir lançamentos recorrentes sem duplicidade |
| RF07 | O usuário deve gerenciar cartões de crédito, compras parceladas e faturas |
| RF08 | O usuário deve gerenciar dívidas (PRICE/SAC), amortizações e quitação |
| RF09 | O sistema deve projetar o fluxo de caixa e controlar orçamentos e reserva de emergência |
| RF10 | O usuário deve gerenciar cofrinhos, metas, investimentos e patrimônio |
| RF11 | O sistema deve ler notas fiscais (NFC-e) por QR Code e preencher o lançamento |
| RF12 | O sistema deve gerar relatórios em PDF, XLSX e CSV |
| RF13 | O sistema deve responder perguntas financeiras (Costelinha) e emitir notificações |

### 3.2 Requisitos não funcionais

| ID | Categoria | Requisito |
|---|---|---|
| RNF01 | Precisão | Valores monetários sempre em **centavos inteiros** (`BIGINT` no banco, `int` no app), nunca em ponto flutuante |
| RNF02 | Segurança | Senhas com argon2id; tokens de sessão guardados apenas como hash SHA-256; rate limit; Helmet; CORS restrito |
| RNF03 | Isolamento | Um usuário nunca acessa dados de outro; ambiente alheio responde `404` |
| RNF04 | Desempenho | p95 de latência < 500 ms (dashboard < 800 ms) e menos de 1% de erros sob 20 usuários simultâneos |
| RNF05 | Rastreabilidade | Toda alteração financeira gera registro de auditoria; exclusões são lógicas |
| RNF06 | Confiabilidade | Operações críticas aceitam `Idempotency-Key`; transferências e pagamentos são atômicos |
| RNF07 | Portabilidade | Mesmo código Flutter para Web, Android e iOS |
| RNF08 | Reprodutibilidade | Ambiente completo sobe com Docker Compose; imagens versionadas por commit |
| RNF09 | Observabilidade | Logs estruturados (JSON), endpoints `/health`, `/version` e `/metrics` (Prometheus) |
| RNF10 | Qualidade | Lint, checagem de tipos e cobertura mínima de 75% das linhas da API exigidos no CI |
| RNF11 | Acessibilidade | O app Web expõe a árvore de acessibilidade (usada pelos testes E2E) |

### 3.3 Principais regras de negócio

| ID | Regra |
|---|---|
| RN01 | Transferências entre contas próprias **não** são receita nem despesa |
| RN05 | Recorrências geram ocorrências até 90 dias à frente, de forma idempotente |
| RN06 | Valor **previsto** é diferente de valor **realizado** (liquidações com data própria) |
| RN07 | Rendimento estimado é calculado na hora e nunca gravado; apenas o confirmado vira receita |
| RN08 | Pagar a fatura do cartão é uma transferência: a despesa é reconhecida uma única vez |
| RN09 | Transferência entre Pessoal e Profissional exige classificação gerencial |
| RN10 | No Consolidado, as transferências entre ambientes se anulam |
| RN11 | Isolamento por usuário e por ambiente, com papéis (`VIEWER` só lê) |
| RN13 | Dashboard e relatórios usam a mesma regra de classificação de fluxos |
| RN14 | Toda criação/alteração/exclusão financeira é auditada na mesma transação |
| RN15 | O saldo é **derivado** do histórico, não existe coluna de saldo que possa divergir |

---

## 4. Tecnologias utilizadas

### Stack

| Camada | Tecnologias |
|---|---|
| **Front-end** | Flutter 3.47 (Dart 3.13) · Riverpod · go_router · fl_chart · mobile_scanner |
| **Back-end** | Node.js 24 · Express 5 · TypeScript 5.9 · Zod · Prisma 6 |
| **Banco de dados** | PostgreSQL 16 |
| **Segurança** | argon2id (`@node-rs/argon2`) · Helmet · express-rate-limit |
| **Relatórios** | pdfkit · exceljs |
| **Observabilidade** | pino (logs) · prom-client (métricas Prometheus) |
| **Testes** | Vitest · Supertest · flutter_test · Playwright · k6 |
| **DevOps** | Docker · Docker Compose · GitHub Actions · GitHub Container Registry · Dependabot · Trivy |
| **Gerenciador de pacotes** | pnpm 10 (monorepo com workspaces) |

### Versões de referência

| Ferramenta | Versão |
|---|---|
| Node.js | 24 (arquivo `.nvmrc`; mínimo aceito: 20) |
| pnpm | 10.18.0 (campo `packageManager`) |
| Flutter | 3.47.8 (fixada no `Dockerfile` e no CI) |
| PostgreSQL | 16 (imagem `postgres:16-alpine`) |

---

## 5. Arquitetura e modelagem (UML)

### 5.1 Visão geral

```mermaid
flowchart LR
  subgraph Cliente
    W[Flutter Web<br/>nginx]
    M[Flutter Android/iOS]
  end
  subgraph API[API Node.js / Express]
    MW[Middlewares<br/>helmet · CORS · métricas · auth · ambiente · idempotência · rate limit]
    R[Rotas REST /api]
    S[Serviços de módulo]
    D[Domínio puro<br/>regras financeiras]
  end
  DB[(PostgreSQL 16)]
  P[Prometheus]
  BCB[(Banco Central — SGS)]
  SEF[(Sefaz — NFC-e)]

  W -- HTTPS + Bearer --> MW
  M -- HTTPS + Bearer --> MW
  MW --> R --> S --> D
  S -- Prisma --> DB
  P -. GET /metrics .-> API
  S -. CDI/Selic/IPCA .-> BCB
  S -. consulta da nota .-> SEF
```

#### Componentes

| Camada | Pasta | Responsabilidade |
|---|---|---|
| Telas | `apps/app/lib/ui` | Telas e widgets; **nenhum cálculo financeiro** |
| Estado | `apps/app/lib/state` | Riverpod: sessão, escopo (Pessoal/Pro/Total), mês, consultas |
| Cliente HTTP | `apps/app/lib/core/api_client.dart` | Bearer token, idempotência, tradução de erros |
| Middlewares | `apps/api/src/middleware` | Autenticação, autorização por ambiente, idempotência, erros |
| Módulos | `apps/api/src/modules/*` | Rotas + serviços por contexto, com transações atômicas e auditoria |
| Domínio | `apps/api/src/domain` | Funções puras e testáveis (regras financeiras) |
| Contratos | `apps/api/src/contracts` | Schemas Zod e enums compartilhados |
| Persistência | `apps/api/prisma` | Schema, migrations e seed |

#### Decisões de arquitetura

- **Cálculos financeiros ficam no backend.** O app apenas exibe.
- **Dinheiro em centavos inteiros**, evitando erros de arredondamento.
- **Saldo derivado**: `saldo = saldo inicial + Σ entradas liquidadas − Σ saídas liquidadas`.
- **Cartões e cofrinhos** usam uma conta-razão própria; pagar fatura ou guardar dinheiro são transferências.
- **Autenticação por token opaco (Bearer)**, igual em Web, Android e iOS, sem necessidade de proteção CSRF.

Detalhes completos (modelo de dados, regras e roadmap) em [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

### 5.2 Diagrama de casos de uso

Cada caso de uso corresponde a um requisito funcional (RF01 a RF13, da [seção 3](#3-requisitos)).

![Diagrama de casos de uso do hoink.](docs/diagramas/caso-de-uso.jpg)

**Atores**

| Ator | Papel |
|---|---|
| **Usuário** | Pessoa que usa o app (papéis `OWNER`, `ADMIN` e `MEMBER` escrevem; `VIEWER` apenas consulta) |
| **Agendador (Cron)** | Rotinas automáticas da API: geração de recorrências (a cada 6 h) e atualização de índices (a cada 12 h), ou `GET /cron/daily` em hospedagem serverless |
| **Banco Central (SGS)** | Fonte oficial de CDI, Selic e IPCA, usada nos rendimentos e investimentos |
| **Sefaz (NFC-e)** | Fonte da nota fiscal eletrônica lida pelo QR Code |

**Casos de uso**

| Caso de uso | Resumo | Regras relacionadas |
|---|---|---|
| RF01 – Gestão de acesso | Cadastro, login, recuperar/trocar senha e sessões | RNF02 |
| RF02 – Gerenciar ambientes | Pessoal, Profissional e visão Consolidada | RN10 · RN11 |
| RF03 – Gestão de lançamentos | Contas, categorias, receitas, despesas, reembolsos e ajustes | RN06 · RN15 |
| RF04 – Liquidar lançamento | Liquidação parcial ou total e cálculo de saldos (estende RF03) | RN06 |
| RF05 – Realizar transferência | Entre contas e PF ↔ PJ, com classificação gerencial | RN01 · RN09 · RN10 |
| RF06 – Gerenciar recorrências | Gerar e gerir lançamentos recorrentes sem duplicidade (acionado também pelo Agendador) | RN05 |
| RF07 – Gerenciar cartões de crédito | Compras parceladas, faturas e pagamento (usa a transferência de RF05) | RN08 |
| RF08 – Gerenciar dívidas | PRICE/SAC, amortização e quitação | — |
| RF09 – Planejamento financeiro | Fluxo de caixa projetado, orçamentos e reserva | — |
| RF10 – Cofrinhos, investimentos e patrimônio | Metas, aportes, resgates, ativos − passivos (consulta o Banco Central) | RN07 |
| RF11 – Ler nota fiscal (NFC-e) | QR Code preenche o lançamento (consulta a Sefaz) | — |
| RF12 – Emitir relatórios | PDF, XLSX e CSV | RN13 |
| RF13 – Costelinha e notificações | Respostas financeiras e avisos | — |

### 5.3 Diagrama de classes

O diagrama de classes representa o modelo de domínio do sistema, com os principais atributos e operações. Os
valores monetários (`*Centavos`) são sempre inteiros em centavos (`BigInt`). As **composições** (losango preenchido)
indicam que a parte não existe sem o todo, por exemplo `Liquidacao` em `Lancamento` e `Fatura` em `CartaoCredito`.

![Diagrama de classes do hoink.](docs/diagramas/diagrama-de-classes.jpg)

**Correspondência com o banco de dados** ([`schema.prisma`](apps/api/prisma/schema.prisma)):

| Classe (diagrama) | Modelo Prisma / tabela | | Classe (diagrama) | Modelo Prisma / tabela |
|---|---|---|---|---|
| `Usuario` | `User` | | `CartaoCredito` | `CreditCard` |
| `Sessao` | `Session` | | `Fatura` | `CardInvoice` |
| `Ambiente` | `FinancialEntity` | | `Divida` | `Debt` |
| `Conta` | `Account` | | `ParcelaDivida` | `DebtInstallment` |
| `Categoria` | `Category` | | `Cofrinho` | `PiggyBank` |
| `Lancamento` | `Transaction` | | `Investimento` | `Investment` |
| `Liquidacao` | `Settlement` | | `IndiceMercado` | `MarketRate` |
| `Transferencia` | `Transfer` | | `Orcamento` | `Budget` |
| `Recorrencia` | `RecurringRule` | | `Notificacao` | `Notification` |

As enumerações `TipoLancamento` (receita, despesa, transferência, reembolso, ajuste), `StatusLancamento`
(previsto, pendente, parcial, liquidado, cancelado) e `Classificacao` (interna, pró-labore, aporte, retirada) são
simplificações das enumerações do banco (por exemplo, `TransactionType` e `TransferClassification` têm mais valores,
como aporte e resgate de investimentos e distribuição de lucros).

### 5.4 Diagramas de sequência

Os diagramas descrevem as interações entre o app, a API (rota → serviço), o banco e os sistemas externos nos fluxos mais importantes.

#### SD01 – Realizar login (RF01 · RNF02)

![SD01 – Realizar login](docs/diagramas/sd01-login.jpg)

- O limitador de tentativas (`authLimiter`) e a validação Zod rodam antes do serviço.
- A senha é verificada com **argon2id**; credenciais inválidas retornam `401`, sem revelar se o e-mail existe.
- Só o **hash SHA-256** do token é gravado na sessão. O app guarda o token no `TokenStorage`.

#### SD02 – Registrar lançamento (RF03, RF04 · RNF03, RNF05, RNF06)

![SD02 – Registrar lançamento](docs/diagramas/sd02-registrar-lancamento.png)

- Os middlewares validam a **sessão**, o **acesso ao ambiente** (RN11) e a **idempotência** da requisição.
- O serviço cria o lançamento em **transação atômica** (`$transaction`), registra a liquidação (se liquidado) e a **auditoria**.
- O app recarrega o saldo, que é calculado pelo backend.

#### SD03 – Transferência entre ambientes PF ↔ PJ (RF05 · RNF06)

![SD03 – Transferência entre ambientes PF ↔ PJ](docs/diagramas/sd03-transferencia-pf-pj.png)

- Entre ambientes diferentes, a classificação `INTERNAL` é recusada (`422 CLASSIFICATION_REQUIRED`): o usuário precisa informar pró-labore, aporte etc. (RN09).
- Uma transferência gera **duas pernas** (saída e entrada) com liquidações, tudo na mesma transação, e a auditoria é registrada por ambiente envolvido.

#### SD04 – Pagar fatura do cartão de crédito (RF07, RF05 · RN08)

![SD04 – Pagar fatura do cartão de crédito](docs/diagramas/sd04-pagar-fatura.png)

- O serviço calcula `restante = total − pago` e recusa fatura já paga ou valor maior que o restante (`422`).
- O pagamento é uma **transferência** da conta para a conta-razão do cartão; por isso a **despesa não é duplicada**.

#### SD05 – Ler nota fiscal (NFC-e) pelo QR Code (RF11)

![SD05 – Ler nota fiscal NFC-e pelo QR Code](docs/diagramas/sd05-nfce-qrcode.png)

- A chave de acesso é validada (dígito verificador); QR Code inválido retorna `422 INVALID_RECEIPT`.
- A consulta à Sefaz só é feita em domínios `*.gov.br` (proteção contra SSRF).
- O serviço sugere a categoria e informa se a nota **já foi lançada**; ao confirmar, o app envia `POST /transactions` com a `receiptKey` (fluxo do SD02).

### 5.5 Estrutura em camadas do back-end

Cada módulo segue o mesmo padrão: **rota → serviço → domínio puro**, com os middlewares na entrada.

```mermaid
classDiagram
  direction LR
  class Router {
    <<modules/*/*.routes.ts>>
    +valida entrada (Zod)
    +chama o serviço
  }
  class Service {
    <<modules/*/*.service.ts>>
    +transação atômica (Prisma)
    +registra auditoria
    +emite eventos e métricas
  }
  class Domain {
    <<domain/*.ts · funções puras>>
    +resolveDirection()
    +normalizeSettlement()
    +flowTotals()
    +cronograma PRICE/SAC
    +rendimentos e IR
  }
  class Middleware {
    <<middleware/*.ts>>
    +requireAuth()
    +requireEntityAccess()
    +idempotency()
    +errorHandler()
  }
  class Contracts {
    <<contracts/*.ts>>
    +schemas Zod
    +enums
  }
  class PrismaClient {
    <<ORM>>
  }
  class PostgreSQL {
    <<banco>>
  }

  Middleware --> Router : protege
  Router --> Contracts : valida com
  Router --> Service : delega
  Service --> Domain : aplica regras
  Service --> PrismaClient : persiste
  PrismaClient --> PostgreSQL
```

### 5.6 Rotinas automáticas: recorrências e índices de mercado (RF06 e RF10)

```mermaid
sequenceDiagram
  autonumber
  participant AG as Agendador<br/>(setInterval ou Vercel Cron)
  participant API as API
  participant REC as recurring.service
  participant MKT as market.service
  participant BCB as Banco Central (SGS)
  participant DB as PostgreSQL

  Note over AG,API: Servidor contínuo: a cada 6 h (recorrências) e 12 h (índices).<br/>Serverless: GET /cron/daily com Bearer CRON_SECRET.
  AG->>API: dispara a rotina
  API->>REC: generateAll()
  REC->>DB: lê regras ativas
  REC->>DB: INSERT ocorrências previstas até 90 dias à frente<br/>(índice único regra+data evita duplicatas)
  API->>MKT: syncMarketRates()
  MKT->>BCB: consulta CDI, Selic e IPCA
  alt resposta ok
    BCB-->>MKT: séries do índice
    MKT->>DB: upsert em market_rates (fonte oficial)
  else falha ou MARKET_DATA_SYNC=false
    MKT-->>API: erro registrado em log — dados ficam marcados como desatualizados
  end
  API-->>AG: { recurring: "ok", market: "ok|error" }
```

---

## 6. Estrutura de pastas

```text
Hoink/
├── apps/
│   ├── api/                      # Back-end (Node.js + Express + Prisma)
│   │   ├── prisma/
│   │   │   ├── migrations/       #   Migrations versionadas do banco
│   │   │   ├── schema.prisma     #   Modelo de dados
│   │   │   └── seed.ts           #   Dados de demonstração
│   │   ├── src/
│   │   │   ├── config/           #   Leitura e validação das variáveis de ambiente
│   │   │   ├── contracts/        #   Schemas Zod e enums
│   │   │   ├── domain/           #   Regras financeiras puras (+ testes unitários)
│   │   │   ├── lib/              #   Utilitários (logger, métricas, erros, datas, dinheiro)
│   │   │   ├── middleware/       #   auth, acesso ao ambiente, idempotência, erros
│   │   │   ├── modules/          #   Um módulo por contexto (rotas + serviço)
│   │   │   ├── app.ts            #   Montagem do Express
│   │   │   └── server.ts         #   Ponto de entrada
│   │   ├── tests/                #   Testes de integração (Vitest + Supertest)
│   │   ├── Dockerfile
│   │   └── vercel.json           #   Alternativa de deploy serverless
│   └── app/                      # Front-end (Flutter)
│       ├── lib/
│       │   ├── app/              #   Rotas (go_router) e tema
│       │   ├── core/             #   Cliente HTTP, config, dinheiro, datas
│       │   ├── data/             #   Modelos e repositório
│       │   ├── state/            #   Providers (Riverpod)
│       │   └── ui/               #   Telas, shell e widgets
│       ├── android/ ios/ macos/  #   Projetos nativos
│       ├── test/                 #   Testes unitários e de widget
│       ├── Dockerfile            #   Build web + nginx
│       └── nginx.conf
├── e2e/                          # Testes ponta a ponta (Playwright)
├── perf/                         # Testes de carga (k6)
├── infra/postgres/init/          # Script que cria o banco de testes (hoink_test)
├── docs/                         # Arquitetura, deploy, testes, segurança, design e marca
│   └── diagrams/                 #   Diagramas UML (caso de uso, classes e sequência)
├── scripts/validate-structure.sh # Validação da estrutura do repositório (usada no CI)
├── .github/
│   ├── workflows/                # ci.yml e cd.yml
│   ├── ISSUE_TEMPLATE/           # Templates de bug e funcionalidade
│   ├── pull_request_template.md
│   └── dependabot.yml
├── docker-compose.yml
├── .env.example                  # Modelo das variáveis de ambiente (sem segredos)
├── CONTRIBUTING.md
├── package.json                  # Scripts da raiz
└── pnpm-workspace.yaml
```

---

## 7. Pré-requisitos

Escolha o caminho conforme o que você quer fazer.

| Ferramenta | Execução com Docker | Desenvolvimento local | Para que serve |
|---|:---:|:---:|---|
| [Git](https://git-scm.com/) | ✅ | ✅ | Clonar o repositório |
| [Docker](https://docs.docker.com/get-docker/) + Compose v2 | ✅ | ✅ | Subir o PostgreSQL (e, no modo completo, a API e o front) |
| [Node.js](https://nodejs.org/) 24 | — | ✅ | Rodar a API |
| [pnpm](https://pnpm.io/) 10 | ⚠️ opcional* | ✅ | Instalar dependências e rodar scripts |
| [Flutter](https://docs.flutter.dev/get-started/install) 3.47 | — | ✅ | Rodar/compilar o app |
| [k6](https://k6.io/docs/get-started/installation/) | — | opcional | Teste de carga |

\* Necessário apenas para popular o banco com dados de demonstração (`pnpm db:seed`).

> 💡 Com `nvm`, basta executar `nvm use` na raiz do projeto (o `.nvmrc` indica a versão). Para o pnpm:
> `corepack enable`.

---

## 8. Instalação e execução

### 8.1 Clonar o repositório

```bash
git clone https://github.com/Isadora-Correa/Hoink.git
cd Hoink
```

### 8.2 Opção 1 — Tudo em contêineres (recomendado para demonstração)

Não exige Node nem Flutter instalados.

```bash
# 1. Criar o arquivo de configuração
cp .env.example .env

# 2. Construir e subir banco + API + front-end
docker compose --profile full up -d --build
```

| Serviço | Endereço |
|---|---|
| Front-end (Flutter Web) | <http://localhost:8080> |
| API | <http://localhost:3333> |
| PostgreSQL (acesso externo) | `localhost:5433` |

> Se a porta 8080 estiver ocupada: `WEB_PORT=8081 docker compose --profile full up -d --build`

**Dados de demonstração (opcional):**

```bash
corepack enable
pnpm install
pnpm db:seed
```

Cria o usuário de demonstração `miguel@hoink.dev` com a senha `hoink1234`.
⚠️ Credencial **apenas para desenvolvimento/demonstração** — nunca use em ambiente publicado.

**Parar o ambiente:**

```bash
docker compose --profile full down        # mantém os dados
docker compose --profile full down -v     # apaga também o volume do banco
```

### 8.3 Opção 2 — Desenvolvimento local

```bash
# 1. Configuração
cp .env.example .env

# 2. Dependências (gera também o Prisma Client)
pnpm install

# 3. Banco de dados (PostgreSQL em localhost:5433, já com o banco hoink_test)
pnpm db:up

# 4. Migrations
pnpm db:migrate

# 5. Dados de demonstração (opcional)
pnpm db:seed

# 6. API em modo desenvolvimento (recarrega ao salvar) → http://localhost:3333
pnpm dev
```

Em **outro terminal**, rode o app:

```bash
cd apps/app
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3333
```

| Alvo | Como apontar para a API |
|---|---|
| Chrome (Web) | `--dart-define=API_BASE_URL=http://localhost:3333` |
| Emulador Android | `--dart-define=API_BASE_URL=http://10.0.2.2:3333` |
| Dispositivo físico | `--dart-define=API_BASE_URL=http://<IP-da-sua-máquina>:3333` |

### 8.4 Validar se o ambiente está funcionando

```bash
curl http://localhost:3333/health     # → status ok (inclui verificação do banco)
curl http://localhost:3333/version    # → versão e commit
```

No navegador, abra <http://localhost:8080> (Docker) ou a janela aberta pelo `flutter run`, faça login com o
usuário de demonstração e confira se o **Dashboard** carrega.

Se algo falhar, consulte [Solução de problemas](#17-solução-de-problemas).

### 8.5 Scripts úteis (raiz do projeto)

| Comando | O que faz |
|---|---|
| `pnpm dev` | Inicia a API em modo desenvolvimento |
| `pnpm build` | Compila todos os pacotes |
| `pnpm typecheck` | Checagem de tipos TypeScript |
| `pnpm test` | Executa os testes dos pacotes |
| `pnpm db:up` | Sobe o PostgreSQL via Docker Compose |
| `pnpm db:migrate` | Aplica as migrations (modo desenvolvimento) |
| `pnpm db:seed` | Popula o banco com dados de demonstração |
| `pnpm test:e2e` | Executa os testes E2E (Playwright) |
| `pnpm --filter @hoink/api lint` | Lint da API |

---

## 9. Configuração e variáveis de ambiente

Toda a configuração vem de variáveis de ambiente. O arquivo [`.env.example`](.env.example) documenta todas e
**não contém credenciais reais**. Copie-o para `.env` (que é ignorado pelo Git).

```bash
cp .env.example .env
```

| Variável | Obrigatória | Padrão | Descrição |
|---|:---:|---|---|
| `DATABASE_URL` | ✅ | — | Conexão PostgreSQL. Em dev: `postgresql://hoink:hoink@localhost:5433/hoink` (credencial local do Compose) |
| `NODE_ENV` | ✅ em produção | `development` | `development`, `test` ou `production` |
| `PORT` | — | `3333` | Porta HTTP da API |
| `CORS_ORIGINS` | ✅ em produção | vazio | URL(s) pública(s) do front, separadas por vírgula. Em dev, qualquer `localhost` é aceito |
| `SESSION_TTL_DAYS` | — | `30` | Validade da sessão (1 a 90 dias) |
| `APP_TIMEZONE` | — | `America/Sao_Paulo` | Fuso usado para "hoje", vencimentos e atrasos |
| `LOG_LEVEL` | — | `info` | `fatal`, `error`, `warn`, `info`, `debug`, `trace` ou `silent` |
| `APP_VERSION` | — | `0.1.0` | Versão exposta em `/version` |
| `GIT_SHA` | — | `dev` | Commit publicado (injetado no build da imagem) |
| `AUTH_RATE_LIMIT` | — | `20` | Tentativas de autenticação por IP a cada 15 minutos |
| `METRICS_TOKEN` | recomendada em produção | — | Protege `GET /metrics` com `Authorization: Bearer <token>` |
| `ADMIN_TOKEN` | — | — | (mín. 16 caracteres) Permite lançar índices manualmente via `PUT /api/market-rates` |
| `CRON_SECRET` | — | — | (mín. 16 caracteres) Protege `GET /cron/daily` (tarefas agendadas) |
| `MARKET_DATA_SYNC` | — | `true` | Busca CDI, Selic e IPCA no Banco Central. `false` = só taxas manuais |
| `RECEIPT_LOOKUP` | — | `true` | Consulta NFC-e na Sefaz e a loja na BrasilAPI. `false` = só dados do QR Code |
| `WEB_PORT` | — | `8080` | Porta do front-end no Docker Compose |

**Variáveis de build do front-end** (passadas com `--dart-define`):

| Variável | Padrão | Descrição |
|---|---|---|
| `API_BASE_URL` | `http://localhost:3333` | URL da API embutida no app |
| `APP_VERSION` | `0.1.0` | Versão exibida em Configurações |
| `GIT_SHA` | `dev` | Commit exibido em Configurações |

> 🔒 **Nunca** versione o arquivo `.env`, senhas, tokens ou chaves. O CI falha se um `.env` real for
> encontrado no repositório.

---

## 10. Banco de dados

- **SGBD:** PostgreSQL 16, acessado via **Prisma 6**.
- **Schema:** [`apps/api/prisma/schema.prisma`](apps/api/prisma/schema.prisma)
- **Migrations:** [`apps/api/prisma/migrations`](apps/api/prisma/migrations) — versionadas; aplicadas automaticamente
  na inicialização do contêiner da API (`prisma migrate deploy`).
- **Seed:** [`apps/api/prisma/seed.ts`](apps/api/prisma/seed.ts) (`pnpm db:seed`).
- **Bancos criados pelo Compose:** `hoink` (aplicação) e `hoink_test` (testes de integração), via
  [`infra/postgres/init`](infra/postgres/init).
- **Integridade:** restrições `CHECK` (valores positivos, coerência entre status e valor liquidado, tipo `TRANSFER`).

Principais tabelas:

```mermaid
erDiagram
  users ||--o{ sessions : possui
  users ||--o{ entity_members : participa
  financial_entities ||--o{ entity_members : tem
  financial_entities ||--o{ accounts : tem
  financial_entities ||--o{ transactions : tem
  accounts ||--o{ transactions : movimenta
  categories ||--o{ transactions : classifica
  transfers ||--|{ transactions : "2 pernas"
  transactions ||--o{ transaction_settlements : pagamentos
  recurring_rules ||--o{ transactions : ocorrências
  contacts ||--o{ transactions : "cliente/fornecedor"
  credit_cards ||--o{ card_invoices : faturas
  debts ||--|{ debt_installments : cronograma
  financial_entities ||--o{ investments : tem
  financial_entities ||--o{ net_worth_snapshots : histórico
```

Tabelas auxiliares: `password_reset_tokens`, `idempotency_keys`, `audit_logs`, `planning_settings`,
`market_rates`. O diagrama completo está em [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

**Comandos úteis:**

```bash
pnpm db:migrate                                   # cria/aplica migrations (dev)
pnpm --filter @hoink/api prisma:deploy            # aplica migrations pendentes (sem prompt)
pnpm --filter @hoink/api exec prisma studio       # interface visual do banco
```

---

## 11. API

- **URL base:** `http://localhost:3333`
- **Prefixo das rotas de negócio:** `/api`
- **Autenticação:** `Authorization: Bearer <token>` (obtido em `POST /api/auth/login`)
- **Formato:** JSON; valores monetários em **centavos**
- **Idempotência:** `POST` de lançamentos, liquidações, transferências e compras aceitam o cabeçalho `Idempotency-Key`
- **Erros:** respostas padronizadas pelo middleware de erro; validação de entrada com Zod

### Rotas públicas / operacionais

| Método | Rota | Descrição |
|---|---|---|
| GET | `/health` | Disponibilidade (inclui banco) |
| GET | `/version` | Versão e commit publicados |
| GET | `/metrics` | Métricas Prometheus (protegida por `METRICS_TOKEN`, se definido) |
| GET | `/cron/daily` | Tarefas diárias agendadas (protegida por `CRON_SECRET`) |

### Rotas autenticadas

| Grupo | Prefixo | Principais operações |
|---|---|---|
| Autenticação | `/api/auth` | `signup`, `login`, `logout`, `forgot-password`, `reset-password`, `change-password`, `me`, `me/avatar`, `sessions` |
| Ambientes | `/api/entities` | Listar, criar, criar ambiente profissional, editar, arquivar |
| Transferências | `/api/transfers` | Criar e excluir |
| Consolidado | `/api/consolidated` (+ `/planning`, `/patrimony`, `/reports`) | Visão total ponderada pela participação |
| Mercado | `/api/market-rates` | Consultar índices; lançar manualmente (`X-Admin-Token`) |
| Assistente | `/api/assistant` | `ask`, `insights`, `compare-investments` |
| Notificações | `/api/notifications` | Listar, marcar como lida |
| Gamificação | `/api/gamification` | Conquistas e níveis |

### Rotas por ambiente — `/api/entities/:entityId/...`

| Recurso | Rota | Operações |
|---|---|---|
| Contas | `/accounts` | CRUD, arquivar, `statement` (extrato), `reconcile` (conciliação) |
| Categorias | `/categories` | CRUD |
| Lançamentos | `/transactions` | CRUD, `settle` (liquidação parcial/total) |
| Dashboard | `/dashboard` | Indicadores do período |
| Recorrências | `/recurring` | CRUD, `pause`, `resume`, `cancel` |
| Clientes/fornecedores | `/contacts` | CRUD, arquivar |
| Contas a pagar/receber | `/payables` | Itens em aberto e em atraso |
| Cartões | `/cards` | CRUD, `invoice`, `invoices/:id/pay`, `purchases` |
| Dívidas | `/debts` | `simulate`, CRUD, `prepay`, `payoff`, `cancel` |
| Planejamento | `/planning` | `budgets`, `cashflow`, `reserve` |
| Cofrinhos | `/piggy-banks` | CRUD, `deposit`, `withdraw`, `yield`, `achieve`, `simulate` |
| Investimentos | `/investments` | CRUD, `value`, movimentações |
| Patrimônio | `/patrimony` | Consulta e bens/passivos (`items`) |
| Nota fiscal | `/receipts` | `preview` (leitura do QR Code / chave) |
| Relatórios | `/reports` | `GET /:type` em JSON, CSV, XLSX ou PDF |
| Costelinha | `/assistant` | `ask`, `insights` |

**Exemplo — login:**

```bash
curl -X POST http://localhost:3333/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"miguel@hoink.dev","password":"hoink1234"}'
```

> A lista acima é um resumo. A fonte da verdade são os arquivos `*.routes.ts` em
> `apps/api/src/modules/*` e os schemas em `apps/api/src/contracts/schemas.ts`.

---

## 12. Testes

A estratégia segue a **pirâmide de testes**: muitos testes rápidos de regras de negócio, testes de integração
com banco real, poucos E2E para os fluxos principais e um teste de carga. Todos rodam **automaticamente no CI**
a cada push e Pull Request; o merge na `main` só é liberado com o CI verde.

```mermaid
flowchart TB
  subgraph PIR["Pirâmide de testes do hoink."]
    direction TB
    P["⚡ Performance — k6<br/>20 usuários virtuais · p95 &lt; 500 ms"]
    E["🖥️ E2E — Playwright<br/>10 fluxos × 2 dispositivos (desktop e mobile)"]
    I["🔗 Integração — Vitest + Supertest + PostgreSQL real<br/>API completa, isolamento, auditoria, idempotência"]
    W["📱 App — flutter_test<br/>unitários e de widget"]
    U["🧪 Unitários — Vitest<br/>regras de domínio puras (rápidos)"]
  end
  P --- E --- I --- W --- U
```

### 12.1 Resumo dos tipos de teste

| Tipo | Ferramenta | Onde ficam | Comando | Roda no CI |
|---|---|---|---|:---:|
| Unitários (API) | Vitest | `apps/api/src/domain/*.test.ts`, `apps/api/tests/money.test.ts` | `pnpm --filter @hoink/api test` | ✅ job **API** |
| Integração (API + PostgreSQL real) | Vitest + Supertest | `apps/api/tests/*.test.ts` | `pnpm --filter @hoink/api test` | ✅ job **API** |
| Unitários e de widget (app) | flutter_test | `apps/app/test` | `cd apps/app && flutter test` | ✅ job **App Flutter** |
| E2E (desktop e mobile) | Playwright | `e2e/tests` | `pnpm test:e2e` | ✅ job **E2E** |
| Performance | k6 | `perf/load.js` | `k6 run -e API_URL=http://localhost:3333 perf/load.js` | ✅ job **Performance** |
| Qualidade estática | ESLint · `tsc` · `flutter analyze` · `dart format` | `apps/api`, `apps/app` | ver [seção 18](#18-como-contribuir) | ✅ jobs **API** e **App** |
| Segurança | `pnpm audit` · Trivy (vulnerabilidades e segredos) | repositório | executado pelo CI | ✅ job **Segurança** |
| Estrutura do repositório | `scripts/validate-structure.sh` | raiz | `bash scripts/validate-structure.sh` | ✅ job **Estrutura** |

### 12.2 Testes automatizados realizados

#### Unitários da API — regras de domínio (`apps/api/src/domain`)

| Arquivo | O que é verificado |
|---|---|
| `domain.test.ts` | Sentido do lançamento (entrada/saída); liquidação total e parcial (RN06); status "atrasado" derivado; transferências, aportes e resgates **não** são receita nem despesa (RN01–RN03); consolidação ponderada pela participação |
| `recurrence.test.ts` | Datas de recorrência: mensal no dia 31, anual em 29/02, diária/semanal/quinzenal/personalizada; janela com data final e limite de ocorrências; próxima ocorrência |
| `phase2.test.ts` | **Cartões:** fechamento × vencimento, ajuste de dias inexistentes, compra antes/depois do fechamento, parcelas que somam o total exato, situação da fatura. **Dívidas:** PRICE, SAC, juros zero, prazo restante, quitação antecipada com juros pro rata. **Planejamento:** projeção confirmado × previsto e situação de orçamentos |
| `phase3.test.ts` | **Rendimentos:** % do CDI por dia útil, prefixado, IPCA+, custos; sem índice não estima. **Tributação:** IR regressivo, IOF, isenção de LCI/LCA, lotes FIFO. **Simulações** de aporte e meta. **Gamificação:** níveis, marcos e sequência semanal. **Comparador** de investimentos |
| `nfce.test.ts` | Chave de acesso (dígito verificador módulo 11), QR Code online/offline, bloqueio de **SSRF** (só `gov.br`), leitura do layout da Sefaz e página desconhecida sem inventar dados |
| `tests/money.test.ts` | Conversão de reais para centavos e formatação em reais |

#### Integração da API — aplicação Express + PostgreSQL real (`apps/api/tests`)

| Arquivo | O que é verificado |
|---|---|
| `auth.test.ts` | Cadastro com ambientes Pessoal/Profissional; e-mail duplicado e senha fraca; login correto/incorreto; rotas protegidas; logout revoga sessão; troca de senha revoga as outras sessões; listar/revogar sessões; recuperação de senha por código de uso único |
| `profile.test.ts` | Conta profissional opcional (ativar, desativar e reativar sem perder dados); foto de perfil (tipo detectado pelos bytes e limite de tamanho) |
| `accounts.test.ts` | Saldo derivado (RN15); edição/exclusão recalcula saldo e gera auditoria; liquidação anterior à data de referência recusada; extrato com saldo acumulado; conciliação com ajuste rastreável; arquivar exige saldo zero; **idempotência** evita lançamento duplicado |
| `transactions.test.ts` | Paginação, ordenação e filtros (tipo, busca, tag, período); status "Atrasado"; validação de entrada; dashboard separando realizado de previsto (RN06) |
| `transfers.test.ts` | Transferência entre contas próprias (RN01); PF ↔ PJ exige classificação (RN09) e não duplica no consolidado (RN10); participação societária |
| `isolation.test.ts` | Um usuário não acessa ambientes, contas ou lançamentos de outro; Pessoal e Profissional isolados (RN11) |
| `recurring.test.ts` | Geração sem duplicar; valor variável; editar só uma, desta em diante ou toda a série (RN05); cancelar ocorrência; pausar e reativar; cancelar a série; mudar o calendário |
| `contacts.test.ts` | Validação de CPF/CNPJ e e-mail; recebimento parcial em meses diferentes; inadimplência; histórico de fornecedor; arquivar sem perder histórico |
| `cards.test.ts` | Compra parcelada consome limite sem mexer no caixa; **pagar fatura não duplica a despesa (RN08)**; bloqueio acima do limite; excluir compra devolve limite; faturas pendentes e arquivamento |
| `debts.test.ts` | Simulação sem gravar; cadastro com parcelas; amortização extraordinária (reduz prazo ou parcela); quitação antecipada; cancelamento |
| `planning.test.ts` | Orçamentos com alertas; fluxo de caixa projetado (confirmado × previsto); alerta de saldo negativo; reserva de emergência |
| `piggy.test.ts` | Guardar/retirar como transferência; desejo realizado lança a compra uma vez e dá conquista; rendimento estimado × confirmado; sem índice não estima; só a administração lança taxa manual |
| `investments.test.ts` | Motores por produto (CDB, LCI, prefixado, ações); aporte não é despesa; sem inventar cotação; patrimônio sem dupla contagem com histórico mensal |
| `receipts.test.ts` | NFC-e com QR offline; consulta simulada da Sefaz; **redirecionamento para fora de `gov.br` bloqueado**; mesma nota não pode ser lançada duas vezes |
| `reports.test.ts` | Relatórios batem com o dashboard (RN13) em JSON, CSV, XLSX e PDF; proteção contra injeção de fórmulas; todos os tipos e formatos; validação de período |
| `assistant.test.ts` | Costelinha: reconhece perguntas sem IA, "quanto posso investir" (reserva não conta como sobra), contas da semana, respostas prontas; comparador com índice ausente; notificações sem repetição |
| `health.test.ts` | `/health`, `/version` (commit publicado) e `/metrics` (Prometheus) |

#### App Flutter — unitários e de widget (`apps/app/test`)

| Arquivo | O que é verificado |
|---|---|
| `api_client_test.dart` | Envio de Bearer e `Idempotency-Key`; erros da API; 401 dispara logout; falha de rede amigável; resposta não-JSON |
| `money_test.dart` · `money_input_test.dart` | Leitura/formatação de reais; campo de valor com máscara em centavos |
| `router_test.dart` | Deep link preservado; login e retorno ao destino; **proteção contra open redirect**; rotas públicas e privadas |
| `widgets_test.dart` | Login e validação; dashboard desktop e mobile; criar despesa enviando centavos; seletor Pessoal/Pro/Total; recorrências; clientes; contas a pagar; cartões com compra parcelada; dívidas; planejamento; "olhinho"; cofrinhos e gamificação; patrimônio; nota fiscal; relatórios; Costelinha; notificações; extrato |

#### E2E — Playwright (`e2e/tests`)

Usam o **app Flutter Web compilado** e a **API real**, em dois dispositivos: `desktop` (1440×1000) e `mobile` (Pixel 7).

| Arquivo | Cenário |
|---|---|
| `fase1.spec.ts` | Rota protegida exige login e preserva o destino · Registrar despesa pela interface e conferir o saldo na API · Buscar na lista de lançamentos · Criar conta recorrente e gerar as próximas ocorrências |
| `fase2.spec.ts` | Compra parcelada e pagamento de fatura sem duplicar a despesa (RN08) · Projeção de caixa 30/60/90 dias |
| `fase3.spec.ts` | Guardar no cofrinho tira do saldo, não vira despesa e desbloqueia conquista · Patrimônio = ativos − passivos |
| `fase4.spec.ts` | Costelinha responde "quanto posso investir" com números da API · Relatório com prévia na tela e PDF baixado |

#### Performance — k6 (`perf/load.js`)

Sobe gradualmente até **20 usuários virtuais** por cerca de 50 s, chamando dashboard, extrato, criação de lançamento
e health check. A execução **falha** se:

| Critério | Limite |
|---|---|
| Requisições com erro | < 1% |
| p95 de latência | < 500 ms (dashboard < 800 ms) |
| Checks aprovados | ≥ 99% |

### 12.3 Rastreabilidade: regras de negócio × testes

| Regra | Onde é testada |
|---|---|
| RN01 · transferência não é receita/despesa | `domain.test.ts`, `transfers.test.ts` |
| RN05 · recorrências | `recurrence.test.ts`, `recurring.test.ts`, E2E `fase1` |
| RN06 · previsto × realizado | `domain.test.ts`, `transactions.test.ts`, `contacts.test.ts` |
| RN07 · rendimento estimado não é gravado | `phase3.test.ts`, `piggy.test.ts` |
| RN08 · fatura sem duplicar despesa | `cards.test.ts`, E2E `fase2` |
| RN09 / RN10 · PF ↔ PJ e consolidado | `transfers.test.ts` |
| RN11 · isolamento por usuário e ambiente | `isolation.test.ts`, `cards.test.ts`, `recurring.test.ts`, `reports.test.ts` |
| RN13 · relatório = dashboard | `reports.test.ts`, E2E `fase4` |
| RN14 · auditoria | `accounts.test.ts` |
| RN15 · saldo derivado | `accounts.test.ts` |

### 12.4 Como executar

**API (unitários + integração)** — exige o PostgreSQL de testes no ar:

```bash
pnpm db:up                                 # cria os bancos hoink e hoink_test
pnpm --filter @hoink/api test              # executa todos os testes da API
pnpm --filter @hoink/api test:coverage     # com cobertura → apps/api/coverage/index.html
pnpm --filter @hoink/api test:watch        # modo observação durante o desenvolvimento
```

> O banco de testes usa por padrão `postgresql://hoink:hoink@localhost:5433/hoink_test`
> (sobrescreva com `TEST_DATABASE_URL`). As migrations são aplicadas automaticamente antes da execução.
> Os testes desligam as consultas externas (`MARKET_DATA_SYNC=false`, `RECEIPT_LOOKUP=false`), então **não dependem
> de internet**. O CI exige no mínimo **75% de linhas** cobertas (e 65% de ramos).

**App Flutter:**

```bash
cd apps/app
flutter test --coverage
```

**E2E (Playwright)** — usa o app Flutter Web compilado e a API real:

```bash
# 1. API rodando em :3333 (use AUTH_RATE_LIMIT alto para os cadastros de teste)
# 2. Compilar e servir o front
cd apps/app && flutter build web --dart-define=API_BASE_URL=http://localhost:3333 && cd ../..
node e2e/serve.mjs apps/app/build/web 8080 &

# 3. Instalar o navegador e executar
pnpm --filter @hoink/e2e exec playwright install chromium
pnpm test:e2e

# Contra a stack Docker:
E2E_WEB_URL=http://localhost:8081 pnpm test:e2e
```

**Performance (k6):**

```bash
k6 run -e API_URL=http://localhost:3333 perf/load.js
# ou, sem instalar o k6:
docker run --rm -i --network host -e API_URL=http://localhost:3333 grafana/k6 run - < perf/load.js
```

### 12.5 Testes no pipeline de CI

```mermaid
flowchart LR
  PUSH([push / Pull Request]) --> EST[Estrutura e<br/>configuração]
  PUSH --> API[API: lint · typecheck ·<br/>unitários + integração · cobertura · build]
  PUSH --> APP[App Flutter: format · analyze ·<br/>unit + widget · cobertura · build web]
  PUSH --> SEC[Segurança:<br/>pnpm audit + Trivy]
  API --> E2E[E2E Playwright<br/>desktop + mobile]
  APP --> E2E
  API --> PERF[Performance k6]
  APP --> APK[Build do APK Android]
  EST --> DOCK[Build das imagens Docker]
  E2E --> OK{{CI verde}}
  PERF --> OK
  SEC --> OK
  APK --> OK
  DOCK --> OK
  OK --> MERGE([merge liberado → CD])
```

### 12.6 Evidências geradas

Cada execução do workflow **CI** publica artefatos para consulta (aba *Actions* → execução → *Artifacts*):

| Artefato | Conteúdo |
|---|---|
| `api-coverage` | Relatório HTML/LCOV da cobertura da API (resumo também no *Summary* do job) |
| `app-coverage` | `lcov.info` do Flutter |
| `e2e-report` | Relatório HTML do Playwright, traces/screenshots de falhas e log da API |
| `performance-report` | Resumo do k6 (`k6-summary.json`) e métricas Prometheus após a carga |
| `hoink-android-apk` | APK Android compilado |

Estratégia completa em [`docs/TESTING.md`](docs/TESTING.md).

### 12.7 Resultado da última execução

> Preencha com os números do último CI verde (aba *Actions* → resumo do job **API**) para a apresentação.

| Suíte | Total de testes | Aprovados | Cobertura de linhas |
|---|---|---|---|
| API (unitários + integração) | *(preencher)* | *(preencher)* | *(preencher)* |
| App Flutter | *(preencher)* | *(preencher)* | *(preencher)* |
| E2E | *(preencher)* | *(preencher)* | — |
| Performance (p95 / erros) | — | — | *(preencher)* |

### 12.8 Testes exploratórios realizados pela equipe

Além dos testes automatizados, a equipe executou uma rodada de **testes exploratórios** na versão publicada,
conferindo cada valor à mão.

| Item | Detalhe |
|---|---|
| **Data** | 17/11/2026 |
| **Ambiente** | `hoink-app.vercel.app`, Chrome desktop (1150 × 631 px), ambiente Pessoal |
| **Método** | Teste exploratório com dados fictícios prefixados `TESTE`, conferindo cada valor manualmente |
| **Fora do escopo** | Tela de celular, exportação PDF/XLSX/CSV, troca de senha, leitura de nota fiscal, reserva de emergência, comparar investimentos e antecipar fatura |

**Resumo:** os cálculos financeiros estão corretos em todos os módulos testados. Foram encontrados **10 bugs**
(1 crítico, 2 altos, 5 médios, 2 baixos) e **13 problemas de interface**.

#### Bugs encontrados

| # | Severidade | Módulo | Problema | Como reproduzir |
|---|---|---|---|---|
| B1 | 🔴 Crítico | Lançamentos | Tela cinza (crash) ao abrir uma despesa ou receita para editar. Console: `Bad state: No element`. Intermitente: parece acontecer quando os dados ainda não carregaram | Recarregar `/lancamentos` (F5) e clicar logo em um lançamento. Reproduzido 1 de 2 vezes |
| B2 | 🟠 Alto | Busca do topo | Apagar o texto da busca não remove o filtro; a lista mostra "0 lançamentos" e a busca interna aparece vazia | Buscar "mercado" no topo, apagar e dar Enter; trocar de tela e voltar. Só um reload limpa |
| B5 | 🟠 Alto | Cartões / Início | Dados desatualizados após compra no cartão: lista de Cartões segue com "Usado R$ 0,00" e o Início com despesas R$ 0,00 | Registrar compra de R$ 1.000 em 3x e abrir Cartões e Início |
| B6 | 🟡 Médio | Dívidas | Simular quitação cobra R$ 46,31 de juros proporcionais no dia do cadastro (conta desde 10/11, um mês antes do 1º vencimento). O formulário não pede data do contrato | Empréstimo de R$ 10.000 a 2% a.m., 1º venc. 10/12, simular quitação em 17/11 |
| B7 | 🟡 Médio | Cofrinhos | Guarda dinheiro de conta com saldo R$ 0,00 sem aviso; a conta fica em −R$ 100 | Conta zerada → Cofrinho → Guardar R$ 100 |
| B9 | 🟡 Médio | Lançamentos / Investimentos | Exclusão sem confirmação de transferência e de movimentação de investimento (os demais itens pedem confirmação) | Abrir uma transferência e clicar Excluir; abrir investimento e clicar na lixeira do aporte |
| B3 | 🟡 Médio | Formulários | Mensagem de erro de validação não some após corrigir o campo | Nova conta: salvar vazio e preencher Nome ("Informe o nome" fica) |
| B4 | 🟡 Médio | Costelinha | Enter apaga a pergunta sem enviar | Digitar uma pergunta e pressionar Enter; só o botão Enviar funciona |
| B10 | 🟢 Baixo | Investimentos | CDI, SELIC e IPCA aparecem "sem dados" e nenhuma requisição ao Banco Central sai; CDB a 100% do CDI fica com rendimento 0% | Abrir Investimentos e cadastrar um CDB pós-fixado |
| B11 | 🟢 Baixo | Contas / Investimentos | Não há como excluir conta nem investimento (só arquivar ou zerar) | Procurar a opção Excluir no menu da conta e no detalhe do investimento |

#### Problemas de interface e experiência

| # | Tela | Problema |
|---|---|---|
| U1 | Início | Valores cortados nos cards ("R$ 1.5…") e título quebrando letra a letra a 1150 px |
| U2 | Planejamento | Tela não pôde ser capturada em várias tentativas; sugere renderização pesada |
| U3 | Geral | Salvar dívida, recorrência e cofrinho leva 5–6 s, sem indicação clara além do botão desabilitado |
| U4 | Novo lançamento | Ao trocar de Despesa para Receita, o campo de valor perde o "R$" e o foco |
| U5 | Pagar e Receber | "Nova cobrança" abre com status "Recebido" por padrão; o esperado seria "Pendente" |
| U6 | Editar receita | Botão diz "Registrar pagamento"; o certo seria "Registrar recebimento" |
| U7 | Recorrência | "Após N vezes" começa em 1 e mostra "1 vezes" |
| U8 | Compra no cartão | Não mostra o valor de cada parcela antes de registrar |
| U9 | Novo cartão | Validação aparece como aviso no rodapé, enquanto os outros formulários marcam o campo |
| U10 | Dívidas | A simulação aparece abaixo da dobra sem rolar a tela até ela |
| U11 | Navegação | Menu "Contas fixas" abre a página "Recorrências"; Extrato não tem título |
| U12 | Gráficos | Eixo do Planejamento mostra "R$ -50" (padrão: "-R$ 50"); gráfico do Início sem valores no eixo Y |
| U13 | Novo lançamento | Categoria não é obrigatória para despesa; confirmar se é intencional |

#### Resultado por módulo

| Módulo | O que foi testado | Resultado |
|---|---|---|
| Início | Cards, ocultar valores, troca de mês, gráficos, últimos lançamentos | ✅ Cálculos OK · ⚠️ valores cortados; dados desatualizados após compra no cartão |
| Lançamentos | Despesa, receita, transferência, edição, exclusão, busca, filtros | ✅ Cálculos OK · ❌ crash após reload (B1); filtro preso (B2) |
| Minhas Contas | Criar, editar, arquivar, reativar, saldo inicial | ✅ OK · só permite arquivar e exige saldo zero |
| Cartões | Criar cartão, compra 3x, faturas | ✅ Parcelas corretas (333,34 + 333,33 + 333,33) · ⚠️ lista não atualiza (B5) |
| Cofrinhos | Criar desejo, guardar, conquistas | ✅ OK (16,7% de R$ 600) · ⚠️ guarda com saldo zero (B7) |
| Dívidas | Empréstimo PRICE, simulação, quitação | ✅ PRICE correto (R$ 945,60 × 12) · ⚠️ juros de quitação no dia do cadastro (B6) |
| Contas fixas | Recorrência mensal 3x, prevista | ✅ Gera ocorrências e aparece em A pagar |
| Pagar e Receber | A pagar, a receber, pagamento parcial | ✅ OK (parcial de R$ 50 deixa R$ 100 em aberto) |
| Notificações | Vencimento e projeção de saldo negativo | ✅ Projeção −R$ 4.386,80 bate com as saídas previstas |
| Planejamento | Orçamento por categoria | ✅ Salvou · ⚠️ renderização pesada (U2) |
| Investimentos | CDB 100% do CDI | ✅ Salvou · ⚠️ índices "sem dados", rendimento 0% (B10) |
| Patrimônio | Ativos × passivos | ✅ OK (R$ 450 − R$ 11.000 = −R$ 10.550) |
| Relatórios | Ver na tela, mês | ✅ OK · exportação não testada |
| Costelinha | Perguntas rápidas e livres | ✅ Respostas prontas OK · ⚠️ Enter não envia (B4); não responde perguntas livres |

#### O que funcionou bem

- **Cálculos:** saldos, totais do mês, parcelas de cartão com arredondamento, PRICE, pagamento parcial, patrimônio líquido e extrato com saldo corrido.
- **Notificações:** aviso de vencimento e projeção de saldo negativo (−R$ 4.386,80 em 10/02/2027, valor conferido).
- **Proteções:** confirmação ao excluir lançamentos, compras e dívidas; não deixa arquivar conta com saldo; transferência não oferece a própria conta como destino.
- Máscara de moeda, ocultar valores, troca de mês e gamificação dos cofrinhos.

#### Dados de teste

Todos os registros criados levavam o prefixo `TESTE` e foram excluídos, cancelados ou arquivados ao final.
Só o investimento "TESTE CDB" (R$ 0,00) ficou visível, porque não há como excluí-lo (B11).

#### Próximos passos

1. **B1:** proteger o editor de lançamento contra listas vazias (trocar `.first`/`firstWhere` por versões seguras ou esperar contas e categorias carregarem).
2. **B2 e B5:** limpar o filtro global ao apagar a busca e invalidar o cache de cartões e do Início após cada gravação.
3. Decidir as regras de negócio de **B6** (data do contrato na dívida) e **B7** (bloquear ou avisar saldo insuficiente).
4. Padronizar confirmação de exclusão (**B9**) e validação inline (**B3**, **U9**).
5. Investigar a falha ao buscar índices do Banco Central (**B10**) e o desempenho do Planejamento (**U2**).
6. Rodar uma segunda rodada em celular e nas exportações de relatório.

<!--
  TODO (equipe): quando novos testes automatizados forem adicionados, atualizar as tabelas da seção 12.2
  (arquivo + o que é verificado), a rastreabilidade (12.3) e os resultados (12.7).
-->

---

## 13. Processo DevOps

### 13.1 Fluxo de trabalho (Git + Pull Request)

1. **Issue primeiro.** Toda alteração nasce de uma issue (templates *Funcionalidade* e *Bug*), com critérios de aceite.
2. **Branch a partir da `main`**, nomeada por tipo e issue: `feat/12-recorrencias`, `fix/27-saldo-negativo`,
   `chore/ci-cache`, `docs/readme-deploy`.
3. **Commits pequenos** no padrão [Conventional Commits](https://www.conventionalcommits.org/pt-br/):
   `feat(api): permite liquidação parcial de lançamentos`.
4. **Pull Request** para a `main` usando o template, referenciando a issue (`Closes #12`).
5. **Revisão:** pelo menos **1 aprovação** de outro integrante e **CI verde** antes do merge.
6. **Merge por squash**, mantendo um commit por PR na `main`; a branch é apagada após o merge.

Detalhes em [`CONTRIBUTING.md`](CONTRIBUTING.md).

### 13.2 Pipeline de CI (`.github/workflows/ci.yml`)

Executado em todo push e Pull Request:

```mermaid
flowchart LR
  EST[Estrutura e<br/>configuração] --> DOCK[Build das<br/>imagens Docker]
  API[API: lint, testes,<br/>build] --> E2E[E2E<br/>Playwright]
  API --> PERF[Performance<br/>k6]
  APP[App Flutter: análise,<br/>testes, build web] --> E2E
  APP --> APK[Build do APK<br/>Android]
  SEC[Segurança:<br/>audit + Trivy]
```

Os jobs sem seta de entrada rodam em paralelo; os demais aguardam os jobs dos quais dependem (`needs:` no `ci.yml`).

| Job | O que valida |
|---|---|
| Estrutura e configuração | Arquivos obrigatórios, `docker-compose.yml`, ausência de `.env` versionado, migrations |
| API | Lint, typecheck, testes unitários e de integração com cobertura, build |
| App Flutter | Formatação, análise estática, testes de unidade/widget com cobertura, build web |
| App Android | Compila o APK e publica como artefato |
| E2E | Testes Playwright contra a API e o front reais |
| Performance | Teste de carga k6 com limites de latência e erros |
| Segurança | Auditoria de dependências e varredura Trivy (vulnerabilidades e segredos) |
| Docker | Build das imagens da API e do front-end |

### 13.3 Pipeline de CD (`.github/workflows/cd.yml`)

Executado após o CI verde na `main` ou em tags `v*`:

1. **publish** — constrói e publica `hoink-api` e `hoink-web` no GitHub Container Registry (tags: commit curto e `latest`).
2. **deploy** — dispara os webhooks de deploy do provedor.
3. **verify** — consulta `GET /version` até o commit publicado coincidir e confere `/health` e `version.json`.

---

## 14. Deploy

O pipeline independe do provedor: qualquer serviço que rode uma imagem Docker e ofereça webhook de deploy
(ou que puxe a tag `latest` do GHCR) funciona.

### 14.1 Configuração no GitHub (*Settings → Secrets and variables → Actions*)

| Tipo | Nome | Exemplo | Uso |
|---|---|---|---|
| Variável | `DEPLOY_ENABLED` | `true` | Liga os jobs de deploy e verificação |
| Variável | `API_PUBLIC_URL` | `https://hoink-api.exemplo.app` | URL da API (embutida no build do front e usada na verificação) |
| Variável | `WEB_PUBLIC_URL` | `https://hoink.exemplo.app` | URL do front (verificação) |
| Secret | `API_DEPLOY_HOOK` | *(URL do webhook)* | Dispara o redeploy da API |
| Secret | `WEB_DEPLOY_HOOK` | *(URL do webhook)* | Dispara o redeploy do front |

### 14.2 Variáveis da API em produção

Mínimo: `DATABASE_URL`, `NODE_ENV=production` e `CORS_ORIGINS`. Recomendado: `METRICS_TOKEN`.
Lista completa na [seção 9](#9-configuração-e-variáveis-de-ambiente). Use os *secrets* do provedor — **nunca**
versione valores reais.

### 14.3 Reproduzir o ambiente publicado (sem provedor)

```bash
export SHA=<commit>        # ou latest
export API_IMAGE=ghcr.io/isadora-correa/hoink-api:$SHA
export WEB_IMAGE=ghcr.io/isadora-correa/hoink-web:$SHA
docker compose --profile full up -d --no-build
curl http://localhost:3333/version      # confere o commit
```

### 14.4 Hospedagem e releases

- Sugestão gratuita (Render + Neon) e alternativas, passo a passo: [`docs/HOSPEDAGEM.md`](docs/HOSPEDAGEM.md).
- A API também possui configuração para Vercel (`apps/api/vercel.json`) com tarefa agendada diária.
- Nova versão: `git tag v0.1.0 && git push --tags` publica a versão `0.1.0`.
- Processo completo: [`docs/DEPLOY.md`](docs/DEPLOY.md). App mobile: [`docs/MOBILE.md`](docs/MOBILE.md).

---

## 15. Monitoramento

| Endpoint | Para quê |
|---|---|
| `GET /health` | Disponibilidade (verifica o banco) — usado pelos health checks do Docker e do deploy |
| `GET /version` | Versão e commit publicados |
| `GET /metrics` | Métricas Prometheus: requisições, latência (histograma), erros 5xx e eventos de negócio |
| `GET /version.json` (front) | Versão e commit do front-end |
| `GET /healthz` (front) | Health check do nginx |

Os logs são estruturados em JSON (pino), com eventos como `auth.login`, `auth.login_failed`,
`transaction.created` e `transfer.created`. **Senhas e tokens são omitidos dos logs.**

---

## 16. Segurança

Boas práticas aplicadas (revisão completa em [`docs/SECURITY.md`](docs/SECURITY.md)):

- Senhas com **argon2id**; tokens de sessão guardados apenas como **hash SHA-256**, com expiração e revogação.
- **Rate limit** em autenticação, leitura de nota fiscal e assistente; **Helmet**; **CORS** restrito.
- Validação de entrada no servidor com **Zod** e restrições `CHECK` no banco.
- Proteção contra **SSRF** na leitura de nota fiscal (somente domínios `gov.br`, limite de tempo e tamanho).
- Proteção contra **injeção de fórmulas** em CSV/XLSX.
- Contêineres executados como **usuário não-root**.
- Pipelines com **permissões mínimas**; **Dependabot**, `pnpm audit` e **Trivy** no CI.

### O que NÃO deve ser colocado no repositório nem na documentação

- Senhas, chaves de API, tokens e `secrets` reais.
- Arquivos `.env` (use apenas o `.env.example`).
- Dados pessoais ou confidenciais de clientes.
- Detalhes de infraestrutura que facilitem acessos indevidos.

> As credenciais `hoink/hoink` (banco) e `miguel@hoink.dev` (usuário de demonstração) existem **somente** para
> uso local e demonstração.

Encontrou uma vulnerabilidade? Não abra uma issue pública: avise a equipe diretamente (contato na
[seção 20](#20-equipe-e-licença)).

---

## 17. Solução de problemas

| Sintoma | Causa provável | Solução |
|---|---|---|
| `Variáveis de ambiente inválidas` ao iniciar a API | `.env` ausente ou `DATABASE_URL` inválida | `cp .env.example .env` e confira a `DATABASE_URL` |
| `port is already allocated` (8080) | Porta em uso | `WEB_PORT=8081 docker compose --profile full up -d` |
| `port is already allocated` (5433 ou 3333) | Outro serviço usando a porta | Pare o serviço ou ajuste o mapeamento no `docker-compose.yml` |
| API não conecta no banco | Contêiner `db` não está saudável | `docker compose ps` e `docker compose logs db` |
| `database "hoink_test" does not exist` | O volume do banco foi criado antes do script de init | `docker compose down -v && pnpm db:up` (apaga os dados locais) |
| Front mostra erro de rede / não carrega dados | `API_BASE_URL` errada ou CORS | Confira `API_BASE_URL` e `CORS_ORIGINS` |
| Emulador Android não acha a API | `localhost` aponta para o próprio emulador | Use `http://10.0.2.2:3333` |
| `429` ao criar muitas contas (E2E) | Rate limit de autenticação | Aumente `AUTH_RATE_LIMIT` ao rodar a API para os testes |
| Erro do Prisma Client | Client não gerado | `pnpm install` ou `pnpm --filter @hoink/api prisma:generate` |
| Índices (CDI/Selic/IPCA) desatualizados | Sem acesso ao Banco Central | Verifique a rede ou use `MARKET_DATA_SYNC=false` e lance taxas manualmente |

Logs úteis: `docker compose logs -f api` · `docker compose logs -f web`.

---

## 18. Como contribuir

1. Abra uma **issue** descrevendo a mudança (templates de *Bug* e *Funcionalidade*).
2. Crie uma **branch** a partir da `main` (`feat/…`, `fix/…`, `docs/…`).
3. Antes de abrir o PR, rode as verificações locais:

```bash
pnpm --filter @hoink/api lint && pnpm --filter @hoink/api typecheck && pnpm --filter @hoink/api test
cd apps/app && dart format lib test && flutter analyze && flutter test
```

4. Abra o **Pull Request** com o template e aguarde a revisão e o CI verde.

**Regras do projeto:**

- Cálculos financeiros ficam no backend (`apps/api/src/domain`), com testes. O app só exibe.
- Valores monetários sempre em centavos inteiros.
- Nada de credenciais no repositório.
- Mudou o banco? Crie e versione uma migration (`pnpm db:migrate`).

Guia completo: [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## 19. Documentação complementar

| Documento | Conteúdo |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Arquitetura, decisões, modelo de dados e roadmap |
| [`docs/TESTING.md`](docs/TESTING.md) | Estratégia de testes e evidências |
| [`docs/DEPLOY.md`](docs/DEPLOY.md) | Entrega contínua, deploy e variáveis de produção |
| [`docs/HOSPEDAGEM.md`](docs/HOSPEDAGEM.md) | Hospedagem gratuita passo a passo |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Revisão de segurança |
| [`docs/MOBILE.md`](docs/MOBILE.md) | Build e publicação Android/iOS |
| [`docs/DESIGN.md`](docs/DESIGN.md) | Design system, protótipos e marca |
| [`perf/README.md`](perf/README.md) | Testes de carga |

---

## 20. Equipe e licença

**Equipe**

| Nome | GitHub |
|---|---|
| Isadora Correa | [@Isadora-Correa](https://github.com/Isadora-Correa) |
| Maria Júlia Loureiro | [@mariajloureiro](https://github.com/mariajloureiro) |
| Rafaela Riganti | [@rafaelariganti](https://github.com/rafaelariganti) |
| Ronaldo Araujo | [@elronyjunior](https://github.com/elronyjunior) |
| Sophia Marcelino | [@Sophia-Araujo](https://github.com/Sophia-Araujo) |

**Contexto acadêmico:** projeto final da disciplina de DevOps — FATEC.
