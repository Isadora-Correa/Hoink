-- CreateEnum
CREATE TYPE "ContactKind" AS ENUM ('CLIENT', 'SUPPLIER', 'BOTH');

-- AlterTable
ALTER TABLE "recurring_rules" ADD COLUMN     "contact_id" UUID;

-- AlterTable
ALTER TABLE "transactions" ADD COLUMN     "contact_id" UUID;

-- CreateTable
CREATE TABLE "transaction_settlements" (
    "id" UUID NOT NULL,
    "transaction_id" UUID NOT NULL,
    "amount_cents" BIGINT NOT NULL,
    "date" DATE NOT NULL,
    "created_by" UUID NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "transaction_settlements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "contacts" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "kind" "ContactKind" NOT NULL,
    "name" TEXT NOT NULL,
    "document" TEXT,
    "email" TEXT,
    "phone" TEXT,
    "notes" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,
    "archived_at" TIMESTAMPTZ,

    CONSTRAINT "contacts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "transaction_settlements_transaction_id_idx" ON "transaction_settlements"("transaction_id");

-- CreateIndex
CREATE INDEX "transaction_settlements_date_idx" ON "transaction_settlements"("date");

-- CreateIndex
CREATE INDEX "contacts_entity_id_kind_idx" ON "contacts"("entity_id", "kind");

-- CreateIndex
CREATE INDEX "transactions_contact_id_idx" ON "transactions"("contact_id");

-- AddForeignKey
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "contacts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "transaction_settlements" ADD CONSTRAINT "transaction_settlements_transaction_id_fkey" FOREIGN KEY ("transaction_id") REFERENCES "transactions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "contacts" ADD CONSTRAINT "contacts_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_rules" ADD CONSTRAINT "recurring_rules_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "contacts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "transaction_settlements"
  ADD CONSTRAINT "transaction_settlements_amount_positive" CHECK ("amount_cents" > 0);

-- Backfill: cada lançamento já liquidado ganha um registro de liquidação com o valor e a data atuais.
INSERT INTO "transaction_settlements" ("id", "transaction_id", "amount_cents", "date", "created_by", "created_at")
SELECT gen_random_uuid(), t."id", t."settled_amount_cents", t."settled_date", t."created_by", t."updated_at"
FROM "transactions" t
WHERE t."settled_amount_cents" > 0 AND t."settled_date" IS NOT NULL;
