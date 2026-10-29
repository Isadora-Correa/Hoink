# Segurança

Revisão feita na Fase 5. Cada item aponta onde está implementado e como é verificado.

## Autenticação e sessões

| Controle | Onde | Verificação |
|---|---|---|
| Senhas com argon2id | `modules/auth` | `tests/auth.test.ts` |
| Token de sessão opaco, guardado só como hash SHA-256, com expiração e revogação | `middleware/auth`, `modules/auth` | `tests/auth.test.ts` |
| Rate limit no login/cadastro (`AUTH_RATE_LIMIT`), na leitura de nota fiscal e nas perguntas à Costelinha | `modules/auth`, `receipts.routes`, `assistant.routes` | E2E usa limite alto via variável |
| Bearer token (sem cookie): dispensa proteção CSRF | `core/api_client.dart` | — |

## Autorização e isolamento (RN11)

- Toda rota de ambiente passa por `requireEntityAccess`: ambiente de outra pessoa responde **404** (não revela que
  existe); papel `VIEWER` só lê.
- Consolidado, notificações e gamificação filtram sempre pelo usuário autenticado.
- Testes de isolamento em cada módulo (`isolation`, `cards`, `debts`, `piggy`, `investments`, `reports`,
  `assistant`).

## Entrada e saída de dados

| Risco | Proteção |
|---|---|
| Dados inválidos | Validação com Zod em todas as rotas; valores em centavos inteiros; `CHECK` no banco |
| SSRF na leitura de nota fiscal | Só domínios `*.gov.br` de Fazenda, sem credenciais na URL, portas padrão, cada redirecionamento conferido, limite de 10 s e 1 MB (`domain/nfce.ts`, `tests/receipts.test.ts`) |
| Injeção de fórmulas em CSV/XLSX | Textos iniciados por `= + - @` recebem `'` (`reports/render.ts`, `tests/reports.test.ts`) |
| Links maliciosos (lista de desejos) | Só `http(s)://` (`contracts/schemas.ts`, `tests/piggy.test.ts`) |
| Arquivos enviados (foto de perfil) | Tipo detectado pelos bytes (não pela extensão), limite de 2 MB |
| Índices de mercado compartilhados | Lançamento manual só com `ADMIN_TOKEN`; nunca sobrescreve o dado do Banco Central |
| Duplicidade | `Idempotency-Key` em pagamentos/transferências/compras; nota fiscal única por ambiente |

## Costelinha

- Não usa IA paga nem envia dados para serviços externos: as respostas são montadas no servidor com os números
  calculados e textos prontos.

## Infraestrutura

- Helmet (cabeçalhos de segurança), CORS restrito a `CORS_ORIGINS` em produção, `x-powered-by` desligado.
- Contêineres sem root (`USER node` na API, `USER 101` no nginx), imagens enxutas, health checks.
- Logs JSON com senhas, tokens e cabeçalho `authorization` omitidos.
- `/metrics` protegido por `METRICS_TOKEN` quando configurado.
- Segredos só por variáveis de ambiente / secrets do GitHub; `.env` fora do Git (`scripts/validate-structure.sh`).

## Verificação contínua (CI)

- `pnpm audit --prod` (falha em alta/crítica) e Trivy (vulnerabilidades, segredos e configurações) a cada push.
- Dependabot para npm, pub e GitHub Actions.
- Dependência transitiva corrigida por override quando necessário (ex.: `exceljs>uuid`).

## Limites conhecidos

- E-mail de recuperação de senha ainda é apenas registrado em log (sem provedor de e-mail configurado).
- Não há MFA; recomendado antes de uso com muitos usuários.
- Backups do PostgreSQL dependem do provedor de hospedagem escolhido.
