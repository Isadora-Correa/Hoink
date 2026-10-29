-- CreateEnum
CREATE TYPE "DebtKind" AS ENUM ('FINANCING', 'LOAN', 'OVERDRAFT', 'OTHER');

-- CreateEnum
CREATE TYPE "AmortizationSystem" AS ENUM ('PRICE', 'SAC');

-- CreateEnum
CREATE TYPE "DebtStatus" AS ENUM ('ACTIVE', 'PAID_OFF', 'CANCELED');

-- CreateEnum
CREATE TYPE "DebtPaymentKind" AS ENUM ('REGULAR', 'EXTRA', 'PAYOFF');

-- AlterEnum
ALTER TYPE "AccountType" ADD VALUE 'CREDIT_CARD';

-- AlterTable
ALTER TABLE "accounts" ADD COLUMN     "is_emergency_reserve" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "transactions" ADD COLUMN     "installment_number" INTEGER,
ADD COLUMN     "invoice_id" UUID,
ADD COLUMN     "purchase_id" UUID;

-- CreateTable
CREATE TABLE "credit_cards" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "brand" TEXT,
    "limit_cents" BIGINT NOT NULL,
    "closing_day" INTEGER NOT NULL,
    "due_day" INTEGER NOT NULL,
    "payment_account_id" UUID,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "credit_cards_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "card_invoices" (
    "id" UUID NOT NULL,
    "card_id" UUID NOT NULL,
    "month" DATE NOT NULL,
    "closing_date" DATE NOT NULL,
    "due_date" DATE NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "card_invoices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "card_purchases" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "card_id" UUID NOT NULL,
    "description" TEXT NOT NULL,
    "category_id" UUID,
    "total_cents" BIGINT NOT NULL,
    "installment_count" INTEGER NOT NULL,
    "purchase_date" DATE NOT NULL,
    "created_by" UUID NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ,

    CONSTRAINT "card_purchases_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "debts" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "kind" "DebtKind" NOT NULL,
    "name" TEXT NOT NULL,
    "creditor" TEXT,
    "principal_cents" BIGINT NOT NULL,
    "monthly_rate_ppm" INTEGER NOT NULL,
    "system" "AmortizationSystem" NOT NULL,
    "installment_count" INTEGER NOT NULL,
    "start_date" DATE NOT NULL,
    "first_due_date" DATE NOT NULL,
    "fees_cents" BIGINT NOT NULL DEFAULT 0,
    "account_id" UUID NOT NULL,
    "category_id" UUID,
    "status" "DebtStatus" NOT NULL DEFAULT 'ACTIVE',
    "notes" TEXT,
    "created_by" UUID NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "debts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "debt_installments" (
    "id" UUID NOT NULL,
    "debt_id" UUID NOT NULL,
    "kind" "DebtPaymentKind" NOT NULL DEFAULT 'REGULAR',
    "number" INTEGER,
    "due_date" DATE NOT NULL,
    "principal_cents" BIGINT NOT NULL,
    "interest_cents" BIGINT NOT NULL,
    "fees_cents" BIGINT NOT NULL DEFAULT 0,
    "balance_after_cents" BIGINT NOT NULL,
    "paid_before_app" BOOLEAN NOT NULL DEFAULT false,
    "transaction_id" UUID,
    "replaced_at" TIMESTAMPTZ,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "debt_installments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "budgets" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "category_id" UUID NOT NULL,
    "limit_cents" BIGINT NOT NULL,
    "alert_threshold_bps" INTEGER NOT NULL DEFAULT 8000,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "budgets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "planning_settings" (
    "entity_id" UUID NOT NULL,
    "emergency_target_months" INTEGER NOT NULL DEFAULT 6,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "planning_settings_pkey" PRIMARY KEY ("entity_id")
);

-- CreateIndex
CREATE INDEX "credit_cards_entity_id_idx" ON "credit_cards"("entity_id");

-- CreateIndex
CREATE UNIQUE INDEX "card_invoices_card_id_month_key" ON "card_invoices"("card_id", "month");

-- CreateIndex
CREATE INDEX "card_purchases_card_id_idx" ON "card_purchases"("card_id");

-- CreateIndex
CREATE INDEX "debts_entity_id_status_idx" ON "debts"("entity_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "debt_installments_transaction_id_key" ON "debt_installments"("transaction_id");

-- CreateIndex
CREATE INDEX "debt_installments_debt_id_due_date_idx" ON "debt_installments"("debt_id", "due_date");

-- CreateIndex
CREATE UNIQUE INDEX "budgets_entity_id_category_id_key" ON "budgets"("entity_id", "category_id");

-- CreateIndex
CREATE INDEX "transactions_invoice_id_idx" ON "transactions"("invoice_id");

-- CreateIndex
CREATE INDEX "transactions_purchase_id_idx" ON "transactions"("purchase_id");

-- AddForeignKey
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "card_invoices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_purchase_id_fkey" FOREIGN KEY ("purchase_id") REFERENCES "card_purchases"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "credit_cards" ADD CONSTRAINT "credit_cards_id_fkey" FOREIGN KEY ("id") REFERENCES "accounts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "credit_cards" ADD CONSTRAINT "credit_cards_payment_account_id_fkey" FOREIGN KEY ("payment_account_id") REFERENCES "accounts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "card_invoices" ADD CONSTRAINT "card_invoices_card_id_fkey" FOREIGN KEY ("card_id") REFERENCES "credit_cards"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "card_purchases" ADD CONSTRAINT "card_purchases_card_id_fkey" FOREIGN KEY ("card_id") REFERENCES "credit_cards"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "card_purchases" ADD CONSTRAINT "card_purchases_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "debts" ADD CONSTRAINT "debts_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "debts" ADD CONSTRAINT "debts_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "accounts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "debts" ADD CONSTRAINT "debts_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "debt_installments" ADD CONSTRAINT "debt_installments_debt_id_fkey" FOREIGN KEY ("debt_id") REFERENCES "debts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "debt_installments" ADD CONSTRAINT "debt_installments_transaction_id_fkey" FOREIGN KEY ("transaction_id") REFERENCES "transactions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "budgets" ADD CONSTRAINT "budgets_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "budgets" ADD CONSTRAINT "budgets_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "categories"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "planning_settings" ADD CONSTRAINT "planning_settings_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Integridade de cartões, dívidas e orçamentos.
ALTER TABLE "credit_cards"
  ADD CONSTRAINT "credit_cards_limit_non_negative" CHECK ("limit_cents" >= 0),
  ADD CONSTRAINT "credit_cards_days" CHECK ("closing_day" BETWEEN 1 AND 31 AND "due_day" BETWEEN 1 AND 31);

ALTER TABLE "card_purchases"
  ADD CONSTRAINT "card_purchases_total_positive" CHECK ("total_cents" > 0),
  ADD CONSTRAINT "card_purchases_installments" CHECK ("installment_count" BETWEEN 1 AND 48);

ALTER TABLE "transactions"
  ADD CONSTRAINT "transactions_installment_consistency" CHECK (("purchase_id" IS NULL) = ("installment_number" IS NULL));

ALTER TABLE "debts"
  ADD CONSTRAINT "debts_principal_positive" CHECK ("principal_cents" > 0),
  ADD CONSTRAINT "debts_rate_non_negative" CHECK ("monthly_rate_ppm" >= 0),
  ADD CONSTRAINT "debts_installments" CHECK ("installment_count" BETWEEN 1 AND 600),
  ADD CONSTRAINT "debts_fees_non_negative" CHECK ("fees_cents" >= 0);

ALTER TABLE "debt_installments"
  ADD CONSTRAINT "debt_installments_values_non_negative"
    CHECK ("principal_cents" >= 0 AND "interest_cents" >= 0 AND "fees_cents" >= 0 AND "balance_after_cents" >= 0);

ALTER TABLE "budgets"
  ADD CONSTRAINT "budgets_limit_positive" CHECK ("limit_cents" > 0),
  ADD CONSTRAINT "budgets_threshold" CHECK ("alert_threshold_bps" BETWEEN 1000 AND 10000);

ALTER TABLE "planning_settings"
  ADD CONSTRAINT "planning_settings_months" CHECK ("emergency_target_months" BETWEEN 1 AND 24);
