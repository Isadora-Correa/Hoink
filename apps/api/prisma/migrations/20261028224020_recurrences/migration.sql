-- CreateEnum
CREATE TYPE "RecurrenceFrequency" AS ENUM ('DAILY', 'WEEKLY', 'BIWEEKLY', 'MONTHLY', 'YEARLY', 'CUSTOM');

-- CreateEnum
CREATE TYPE "IntervalUnit" AS ENUM ('DAY', 'WEEK', 'MONTH', 'YEAR');

-- CreateEnum
CREATE TYPE "AmountKind" AS ENUM ('FIXED', 'VARIABLE', 'ESTIMATED');

-- CreateEnum
CREATE TYPE "RecurrenceStatus" AS ENUM ('ACTIVE', 'PAUSED', 'CANCELED');

-- AlterTable
ALTER TABLE "transactions" ADD COLUMN     "is_override" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "occurrence_date" DATE,
ADD COLUMN     "recurring_rule_id" UUID;

-- CreateTable
CREATE TABLE "recurring_rules" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "type" "TransactionType" NOT NULL,
    "description" TEXT NOT NULL,
    "amount_cents" BIGINT NOT NULL,
    "amount_kind" "AmountKind" NOT NULL DEFAULT 'FIXED',
    "account_id" UUID NOT NULL,
    "category_id" UUID,
    "counterparty" TEXT,
    "notes" TEXT,
    "frequency" "RecurrenceFrequency" NOT NULL,
    "interval_count" INTEGER NOT NULL DEFAULT 1,
    "interval_unit" "IntervalUnit",
    "start_date" DATE NOT NULL,
    "end_date" DATE,
    "max_occurrences" INTEGER,
    "active_since" DATE NOT NULL,
    "status" "RecurrenceStatus" NOT NULL DEFAULT 'ACTIVE',
    "previous_rule_id" UUID,
    "created_by" UUID NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "recurring_rules_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "recurring_rules_entity_id_status_idx" ON "recurring_rules"("entity_id", "status");

-- CreateIndex
CREATE INDEX "transactions_recurring_rule_id_occurrence_date_idx" ON "transactions"("recurring_rule_id", "occurrence_date");

-- AddForeignKey
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_recurring_rule_id_fkey" FOREIGN KEY ("recurring_rule_id") REFERENCES "recurring_rules"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_rules" ADD CONSTRAINT "recurring_rules_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_rules" ADD CONSTRAINT "recurring_rules_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "accounts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_rules" ADD CONSTRAINT "recurring_rules_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Nunca gerar duas ocorrências ativas da mesma regra na mesma data (idempotência da geração).
CREATE UNIQUE INDEX "transactions_rule_occurrence_unique"
  ON "transactions" ("recurring_rule_id", "occurrence_date")
  WHERE "recurring_rule_id" IS NOT NULL AND "deleted_at" IS NULL;

ALTER TABLE "recurring_rules"
  ADD CONSTRAINT "recurring_rules_amount_positive" CHECK ("amount_cents" > 0),
  ADD CONSTRAINT "recurring_rules_interval_positive" CHECK ("interval_count" >= 1),
  ADD CONSTRAINT "recurring_rules_type" CHECK ("type" IN ('INCOME', 'EXPENSE')),
  ADD CONSTRAINT "recurring_rules_dates" CHECK ("end_date" IS NULL OR "end_date" >= "start_date");

ALTER TABLE "transactions"
  ADD CONSTRAINT "transactions_occurrence_consistency" CHECK (("recurring_rule_id" IS NULL) = ("occurrence_date" IS NULL));
