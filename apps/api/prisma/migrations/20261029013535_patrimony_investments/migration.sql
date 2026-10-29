-- CreateEnum
CREATE TYPE "MarketIndex" AS ENUM ('CDI', 'SELIC', 'IPCA');

-- CreateEnum
CREATE TYPE "MarketRateSource" AS ENUM ('BCB', 'MANUAL');

-- CreateEnum
CREATE TYPE "YieldKind" AS ENUM ('CDI_PERCENT', 'SELIC_PERCENT', 'PREFIXED', 'MANUAL', 'NONE');

-- CreateEnum
CREATE TYPE "Liquidity" AS ENUM ('DAILY', 'D_PLUS', 'AT_MATURITY');

-- CreateEnum
CREATE TYPE "Taxation" AS ENUM ('REGRESSIVE', 'EXEMPT', 'STOCKS');

-- CreateEnum
CREATE TYPE "InvestmentKind" AS ENUM ('CDB', 'LCI', 'LCA', 'TESOURO', 'FUND', 'STOCK', 'ETF', 'OTHER');

-- CreateEnum
CREATE TYPE "InvestmentIndexer" AS ENUM ('CDI_PERCENT', 'SELIC_PERCENT', 'PREFIXED', 'IPCA_PLUS', 'MARKET', 'MANUAL');

-- CreateEnum
CREATE TYPE "InvestmentStatus" AS ENUM ('ACTIVE', 'CLOSED');

-- CreateEnum
CREATE TYPE "InvestmentMovementKind" AS ENUM ('CONTRIBUTION', 'REDEMPTION', 'VALUE_UPDATE', 'INCOME');

-- CreateEnum
CREATE TYPE "PatrimonySide" AS ENUM ('ASSET', 'LIABILITY');

-- AlterEnum
ALTER TYPE "AccountType" ADD VALUE 'PIGGY_BANK';

-- CreateTable
CREATE TABLE "market_rates" (
    "id" UUID NOT NULL,
    "index" "MarketIndex" NOT NULL,
    "date" DATE NOT NULL,
    "rate_pct" DECIMAL(14,8) NOT NULL,
    "source" "MarketRateSource" NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "market_rates_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "piggy_banks" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "goal_cents" BIGINT,
    "target_date" DATE,
    "yield_kind" "YieldKind" NOT NULL DEFAULT 'NONE',
    "yield_rate_bps" INTEGER NOT NULL DEFAULT 0,
    "liquidity" "Liquidity" NOT NULL DEFAULT 'DAILY',
    "liquidity_days" INTEGER NOT NULL DEFAULT 0,
    "taxation" "Taxation" NOT NULL DEFAULT 'REGRESSIVE',
    "icon" TEXT NOT NULL DEFAULT 'savings',
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "piggy_banks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "investments" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "kind" "InvestmentKind" NOT NULL,
    "name" TEXT NOT NULL,
    "institution" TEXT,
    "ticker" TEXT,
    "indexer" "InvestmentIndexer" NOT NULL,
    "rate_bps" INTEGER NOT NULL DEFAULT 0,
    "maturity_date" DATE,
    "liquidity" "Liquidity" NOT NULL DEFAULT 'DAILY',
    "liquidity_days" INTEGER NOT NULL DEFAULT 0,
    "costs_bps" INTEGER NOT NULL DEFAULT 0,
    "taxation" "Taxation" NOT NULL,
    "status" "InvestmentStatus" NOT NULL DEFAULT 'ACTIVE',
    "notes" TEXT,
    "created_by" UUID NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "investments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "investment_movements" (
    "id" UUID NOT NULL,
    "investment_id" UUID NOT NULL,
    "kind" "InvestmentMovementKind" NOT NULL,
    "date" DATE NOT NULL,
    "amount_cents" BIGINT NOT NULL,
    "quantity" DECIMAL(20,8),
    "unit_price" DECIMAL(20,8),
    "account_id" UUID,
    "transaction_id" UUID,
    "created_by" UUID NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ,

    CONSTRAINT "investment_movements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "patrimony_items" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "side" "PatrimonySide" NOT NULL,
    "category" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "value_cents" BIGINT NOT NULL,
    "valued_at" DATE NOT NULL,
    "notes" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,
    "deleted_at" TIMESTAMPTZ,

    CONSTRAINT "patrimony_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "net_worth_snapshots" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "month" DATE NOT NULL,
    "assets_cents" BIGINT NOT NULL,
    "liabilities_cents" BIGINT NOT NULL,
    "breakdown" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "net_worth_snapshots_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "market_rates_index_date_key" ON "market_rates"("index", "date");

-- CreateIndex
CREATE INDEX "piggy_banks_entity_id_idx" ON "piggy_banks"("entity_id");

-- CreateIndex
CREATE INDEX "investments_entity_id_status_idx" ON "investments"("entity_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "investment_movements_transaction_id_key" ON "investment_movements"("transaction_id");

-- CreateIndex
CREATE INDEX "investment_movements_investment_id_date_idx" ON "investment_movements"("investment_id", "date");

-- CreateIndex
CREATE INDEX "patrimony_items_entity_id_idx" ON "patrimony_items"("entity_id");

-- CreateIndex
CREATE UNIQUE INDEX "net_worth_snapshots_entity_id_month_key" ON "net_worth_snapshots"("entity_id", "month");

-- AddForeignKey
ALTER TABLE "piggy_banks" ADD CONSTRAINT "piggy_banks_id_fkey" FOREIGN KEY ("id") REFERENCES "accounts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "investments" ADD CONSTRAINT "investments_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "investment_movements" ADD CONSTRAINT "investment_movements_investment_id_fkey" FOREIGN KEY ("investment_id") REFERENCES "investments"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "investment_movements" ADD CONSTRAINT "investment_movements_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "accounts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "investment_movements" ADD CONSTRAINT "investment_movements_transaction_id_fkey" FOREIGN KEY ("transaction_id") REFERENCES "transactions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "patrimony_items" ADD CONSTRAINT "patrimony_items_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "net_worth_snapshots" ADD CONSTRAINT "net_worth_snapshots_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Integridade de cofrinhos, investimentos e patrimônio.
ALTER TABLE "piggy_banks"
  ADD CONSTRAINT "piggy_banks_goal_positive" CHECK ("goal_cents" IS NULL OR "goal_cents" > 0),
  ADD CONSTRAINT "piggy_banks_rate_non_negative" CHECK ("yield_rate_bps" >= 0 AND "liquidity_days" >= 0);
ALTER TABLE "investments"
  ADD CONSTRAINT "investments_rates_non_negative" CHECK ("rate_bps" >= 0 AND "costs_bps" >= 0 AND "liquidity_days" >= 0);
ALTER TABLE "investment_movements"
  ADD CONSTRAINT "investment_movements_amount_non_negative" CHECK ("amount_cents" >= 0),
  ADD CONSTRAINT "investment_movements_quantity_positive" CHECK ("quantity" IS NULL OR "quantity" > 0);
ALTER TABLE "patrimony_items"
  ADD CONSTRAINT "patrimony_items_value_non_negative" CHECK ("value_cents" >= 0);
