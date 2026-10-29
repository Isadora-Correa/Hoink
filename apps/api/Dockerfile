# syntax=docker/dockerfile:1
# Imagem da API hoink. — build a partir da raiz do repositório:
#   docker build -f apps/api/Dockerfile -t hoink-api .

FROM node:24-bookworm-slim AS base
ENV PNPM_HOME=/pnpm PATH=/pnpm:$PATH
RUN corepack enable && apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /repo

# 1) Dependências (camada em cache enquanto o lockfile não muda)
FROM base AS deps
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/api/package.json apps/api/package.json
COPY apps/api/prisma/schema.prisma apps/api/prisma/schema.prisma
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile --filter @hoink/api...

# 2) Build (gera o Prisma Client e empacota com tsup)
FROM deps AS build
COPY apps/api apps/api
RUN pnpm --filter @hoink/api exec prisma generate && pnpm --filter @hoink/api build \
  && pnpm --filter @hoink/api deploy --prod --legacy --ignore-scripts /out \
  && cp -r apps/api/dist apps/api/prisma apps/api/assets /out/ \
  && cd /out && node node_modules/prisma/build/index.js generate

# 3) Runtime enxuto, sem ferramentas de build, rodando como usuário não-root
FROM node:24-bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*
ARG APP_VERSION=0.1.0
ARG GIT_SHA=dev
ENV NODE_ENV=production PORT=3333 APP_VERSION=$APP_VERSION GIT_SHA=$GIT_SHA
WORKDIR /app
COPY --from=build --chown=node:node /out ./
USER node
EXPOSE 3333
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
# Aplica as migrations pendentes antes de iniciar (idempotente).
CMD ["sh", "-c", "node node_modules/prisma/build/index.js migrate deploy && node dist/server.js"]
