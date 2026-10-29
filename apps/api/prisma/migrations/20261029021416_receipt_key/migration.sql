-- AlterTable
ALTER TABLE "transactions" ADD COLUMN     "receipt_key" TEXT;

-- A mesma nota fiscal não pode gerar dois lançamentos ativos no mesmo ambiente.
CREATE UNIQUE INDEX "transactions_receipt_key_unique"
  ON "transactions" ("entity_id", "receipt_key")
  WHERE "receipt_key" IS NOT NULL AND "deleted_at" IS NULL;
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_receipt_key_format" CHECK ("receipt_key" IS NULL OR "receipt_key" ~ '^[0-9]{44}$');
