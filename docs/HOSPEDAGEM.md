# Hospedagem gratuita — guia para o grupo

O que precisa ficar no ar:

| Parte | O que é | Onde sugerimos |
|---|---|---|
| Banco | PostgreSQL 16 | **Neon** (plano Free) |
| API | Imagem Docker `ghcr.io/isadora-correa/hoink-api` (Node, porta 3333) | **Render** (Web Service Free) |
| Front-end | Imagem Docker `ghcr.io/isadora-correa/hoink-web` (Flutter Web + nginx, porta 8080) | **Render** (Web Service Free) |

Por que essa combinação: tudo sem custo e sem mexer no código. O CD do projeto (`.github/workflows/cd.yml`) já
publica as imagens no GitHub Container Registry, chama os *deploy hooks* e confere a versão publicada — o Render
oferece exatamente esses deploy hooks. O banco fica no Neon porque o Postgres gratuito do Render expira em 30 dias.

> Planos gratuitos mudam com frequência. Conferido em outubro/2026; revisem as páginas oficiais antes de começar.

## Limites que o grupo precisa conhecer

- **Render Free:** o serviço "dorme" depois de ~15 min sem acesso; o primeiro acesso depois disso demora cerca de
  1 minuto. **Abram o app uns 2 minutos antes da apresentação.** Sem cartão de crédito.
- **Neon Free:** 0,5 GB por projeto e 100 horas de computação por mês; o banco "dorme" sem uso e acorda sozinho.
  Não expira. Sem cartão de crédito.
- Projeto acadêmico, sem uso comercial — dentro das regras dos planos gratuitos.

## Passo a passo

### 1. Tornar as imagens públicas (uma vez)

Depois do primeiro CD na `main`, em *GitHub → perfil/organização → Packages*, abrir `hoink-api` e `hoink-web` →
*Package settings* → **Change visibility → Public**. Assim o Render consegue baixá-las sem senha.

### 2. Banco no Neon

1. Criar conta em neon.com → *New project* (Postgres 16, região **São Paulo** se disponível, senão a mais próxima).
2. Em *Connection details*, copiar a string **direta** (sem `-pooler` no host), com `?sslmode=require`.
   Ela será a `DATABASE_URL`. **Não colocar no repositório.**
3. As tabelas são criadas sozinhas: a API roda as migrations ao iniciar.

### 3. API no Render

1. render.com → *New → Web Service → Existing image* → `ghcr.io/isadora-correa/hoink-api:latest`.
2. Plano **Free**, região mais próxima.
3. *Environment variables*:

   | Variável | Valor |
   |---|---|
   | `DATABASE_URL` | string do Neon |
   | `NODE_ENV` | `production` |
   | `CORS_ORIGINS` | URL do front (passo 4), ex.: `https://hoink-web.onrender.com` |
   | `METRICS_TOKEN` | um texto aleatório longo (protege `/metrics`) |
   | `APP_TIMEZONE` | `America/Sao_Paulo` |

   O Render informa a porta pela variável `PORT`, que a API já usa.
4. *Settings → Health Check Path*: `/health`.
5. Copiar o **Deploy Hook** (*Settings → Deploy Hook*) e a URL pública (ex.: `https://hoink-api.onrender.com`).

### 4. Front-end no Render

1. *New → Web Service → Existing image* → `ghcr.io/isadora-correa/hoink-web:latest`, plano **Free**.
2. *Health Check Path*: `/healthz`.
3. Copiar o **Deploy Hook** e a URL pública.

> A URL da API é embutida no front na hora do build. Por isso a variável `API_PUBLIC_URL` (passo 5) precisa estar
> configurada **antes** do CD gerar a imagem `hoink-web`.

### 5. Ligar o CD no GitHub

Em *Settings → Secrets and variables → Actions*:

| Tipo | Nome | Valor |
|---|---|---|
| Variável | `API_PUBLIC_URL` | URL da API (passo 3) |
| Variável | `WEB_PUBLIC_URL` | URL do front (passo 4) |
| Variável | `DEPLOY_ENABLED` | `true` |
| Secret | `API_DEPLOY_HOOK` | deploy hook da API |
| Secret | `WEB_DEPLOY_HOOK` | deploy hook do front |

Depois disso, todo merge na `main` faz: CI → imagens novas no GHCR → deploy no Render → verificação automática de
que `GET {API_PUBLIC_URL}/version` mostra o commit novo.

### 6. Conferir

```bash
curl https://SUA-API.onrender.com/health    # {"status":"ok","db":"ok"}
curl https://SUA-API.onrender.com/version   # mostra o commit publicado
```

Abrir a URL do front, criar uma conta e lançar uma despesa. Para ter dados de exemplo no ambiente publicado,
rodar o seed apontando para o Neon **a partir de uma máquina do grupo** (nunca commitar a string):

```bash
DATABASE_URL="postgresql://...neon.tech/...?sslmode=require" pnpm --filter @hoink/api seed
```

## Alternativas (se o grupo preferir)

| Opção | Prós | Contras |
|---|---|---|
| **Cloudflare Pages** só para o front | Não dorme; CDN rápida; sem cartão | O build do Flutter precisa rodar no GitHub Actions e publicar com `wrangler` (exige um job novo no CD) |
| **Oracle Cloud Always Free** (VM) com `docker compose` | Nada dorme; roda tudo junto (o compose do projeto já serve) | Exige cartão; configuração de servidor (firewall, HTTPS); limites do plano ARM foram reduzidos em 2026 |
| **Google Cloud Run** para a API | Cota mensal generosa, escala a zero | Exige cartão e conta no Google Cloud |
| **Vercel Hobby** para o front | Simples para sites estáticos | Só uso não comercial; mesmo problema do build do Flutter fora do CI |

Fly.io e Koyeb deixaram de ser opções práticas sem custo para contas novas.
