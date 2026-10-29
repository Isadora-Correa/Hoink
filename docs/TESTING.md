# Testes

A estratégia segue a pirâmide de testes: muitos testes rápidos de regras de negócio, testes de integração com
banco real para os fluxos financeiros, poucos E2E para os fluxos principais do usuário e um teste de carga.

## 1. Unitários

**API** (`apps/api/src/domain/*.test.ts`, `apps/api/tests/money.test.ts`): sentido dos lançamentos,
liquidação total e parcial, status "atrasado", classificação de fluxos (transferências, aportes e resgates não são
receita nem despesa), consolidação por participação, conversão de valores em reais, datas de recorrência,
faturas de cartão (fechamento, vencimento, divisão de parcelas), amortização PRICE/SAC com valores de referência,
quitação antecipada, projeção de caixa (confirmado × previsto), situação de orçamentos, rendimento por % do
CDI/prefixado/IPCA+ com dias úteis e custos, IR regressivo/IOF por lote (FIFO), simulações e gamificação
(níveis, marcos, sequência semanal), leitura de NFC-e (chave, QR offline, layout da Sefaz, bloqueio de SSRF),
comparador de investimentos e reconhecimento das perguntas da Costelinha.

**App** (`apps/app/test`): formatação e leitura de valores em reais, cliente HTTP (Bearer, idempotência, erros,
falha de rede), redirecionamentos de rota (deep links, proteção contra open redirect) e widgets (logo, login,
dashboard desktop e mobile, formulário de despesa enviando centavos, recorrências, clientes, contas a pagar,
cartões com compra parcelada, simulação de dívida e planejamento).

```bash
pnpm --filter @hoink/api test
cd apps/app && flutter test --coverage
```

## 2. Integração

`apps/api/tests/*.test.ts` sobem a aplicação Express com Supertest contra um **PostgreSQL real** (`hoink_test`),
cobrindo autenticação e sessões, isolamento entre usuários e entre ambientes (RN11), cálculo de saldo,
liquidação parcial, extrato, conciliação, transferências PF↔PJ, consolidado, idempotência, auditoria,
validação de entrada, métricas, recorrências, clientes/fornecedores, cartões (pagamento de fatura sem
duplicar despesa — RN08), dívidas (amortização e quitação), planejamento (orçamentos, projeção e reserva), cofrinhos (guardar/resgatar sem
duplicar dinheiro, rendimento estimado × confirmado, desejo realizado, conquistas), investimentos (motores por
produto, posição, proventos), índices (só administração lança manualmente), patrimônio sem dupla contagem, nota
fiscal (Sefaz simulada, redirecionamento bloqueado, nota duplicada), relatórios (mesmos números do dashboard em
JSON/CSV/XLSX/PDF, injeção de fórmulas, 11 tipos), Costelinha (fatos, IA simulada com falha e recusa) e notificações.

```bash
pnpm db:up                                  # cria hoink e hoink_test
pnpm --filter @hoink/api test:coverage      # relatório em apps/api/coverage/index.html
```

## 3. E2E

`e2e/tests/fase1.spec.ts` a `fase4.spec.ts` (Playwright) usam o **app Flutter Web compilado** e a **API real**, em desktop
(1440×1000) e mobile (Pixel 7):

1. Rota protegida redireciona para o login e volta ao destino.
2. Registrar despesa pela interface; o saldo é conferido na API (R$ 1.000,00 → R$ 650,00).
3. Buscar lançamentos na listagem.
4. Criar uma conta recorrente pela interface; as próximas ocorrências são geradas.
5. Compra parcelada no cartão e pagamento da fatura pela interface: o caixa só cai no pagamento e a despesa
   do mês é a parcela, não o dobro (RN08).
6. Planejamento mostra a projeção de 30/60/90 dias.
7. Guardar no cofrinho de um desejo pela interface: sai do saldo, não vira despesa e desbloqueia conquista.
8. Patrimônio mostra ativos menos passivos.
9. Costelinha responde "quanto posso investir" com os números da API.
10. Relatório na tela e PDF baixado pela API.

```bash
# API rodando em :3333 (AUTH_RATE_LIMIT alto para os cadastros de teste) e build web servido em :8080
cd apps/app && flutter build web --dart-define=API_BASE_URL=http://localhost:3333 && cd ../..
node e2e/serve.mjs apps/app/build/web 8080 &
pnpm --filter @hoink/e2e exec playwright install chromium
pnpm test:e2e
# Contra a stack Docker: E2E_WEB_URL=http://localhost:8081 pnpm test:e2e
```

O app expõe a árvore de acessibilidade no Web, então os testes localizam elementos por papel e rótulo,
como um leitor de tela.

## 4. Performance

`perf/load.js` (k6) sobe até 20 usuários virtuais simultâneos chamando dashboard, extrato, criação de lançamento
e health check. Limites: erros < 1%, p95 < 500 ms (dashboard < 800 ms).

Execução de referência (máquina local, 28/10/2026): 4.439 requisições, **0% de erros**, p95 = 32,7 ms
(dashboard 42 ms), 88 req/s.

```bash
k6 run -e API_URL=http://localhost:3333 perf/load.js
```

## Evidências no CI

Cada execução do workflow **CI** publica artefatos:

| Artefato | Conteúdo |
|---|---|
| `api-coverage` | Relatório HTML/LCOV da cobertura da API (resumo também no Summary do job) |
| `app-coverage` | `lcov.info` do Flutter |
| `e2e-report` | Relatório HTML do Playwright, traces/screenshots de falhas, log da API |
| `performance-report` | Resumo do k6 (`k6-summary.json`) e métricas Prometheus após a carga |
