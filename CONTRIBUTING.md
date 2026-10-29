# Como contribuir

## Fluxo de trabalho

1. **Issue primeiro.** Toda alteração nasce de uma issue (templates *Funcionalidade* e *Bug*), com critérios de aceite.
2. **Branch a partir da `main`**, nomeada pelo tipo e pela issue:
   - `feat/12-recorrencias`, `fix/27-saldo-negativo`, `chore/ci-cache`, `docs/readme-deploy`
3. **Commits pequenos e descritivos** no padrão [Conventional Commits](https://www.conventionalcommits.org/pt-br/):
   - `feat(api): permite liquidação parcial de lançamentos`
   - `fix(app): mantém o deep link após o login`
   - `test(e2e): cobre busca na listagem de lançamentos`
   - `ci: adiciona teste de carga com k6`
4. **Pull Request** para a `main` usando o template, referenciando a issue (`Closes #12`). O PR liga a tarefa à
   alteração e fecha a issue no merge.
5. **Revisão de código:** pelo menos **1 aprovação de outro integrante** e **CI verde** antes do merge.
6. **Merge por squash**, mantendo um commit por PR na `main`. A branch é apagada após o merge.

## Proteção da `main` (configurar em *Settings → Branches*)

- Exigir Pull Request antes do merge, com 1 aprovação
- Exigir status checks: `Estrutura e configuração`, `API — lint, testes e build`,
  `App Flutter — análise, testes e build web`, `Testes E2E (Playwright)`, `Segurança — dependências e segredos`
- Bloquear push direto e force push

## Antes de abrir o PR

```bash
pnpm --filter @hoink/api lint && pnpm --filter @hoink/api typecheck && pnpm --filter @hoink/api test
cd apps/app && dart format lib test && flutter analyze && flutter test
```

## Regras do projeto

- Cálculos financeiros ficam no backend (`apps/api/src/domain`), com testes. O app só exibe.
- Valores monetários sempre em centavos inteiros.
- Nada de credenciais no repositório: use `.env` (ignorado) e secrets do GitHub.
- Mudou o banco? Crie uma migration (`pnpm db:migrate`) e versione-a.
