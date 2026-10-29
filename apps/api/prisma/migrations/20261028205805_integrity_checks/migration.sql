-- Restrições de integridade financeira que o schema Prisma não expressa.
ALTER TABLE "transactions"
  ADD CONSTRAINT "transactions_amount_positive" CHECK ("amount_cents" > 0),
  ADD CONSTRAINT "transactions_settled_range" CHECK ("settled_amount_cents" >= 0 AND "settled_amount_cents" <= "amount_cents"),
  ADD CONSTRAINT "transactions_settled_consistency" CHECK (
    ("status" = 'SETTLED' AND "settled_amount_cents" = "amount_cents" AND "settled_date" IS NOT NULL)
    OR ("status" = 'PARTIAL' AND "settled_amount_cents" > 0 AND "settled_amount_cents" < "amount_cents" AND "settled_date" IS NOT NULL)
    OR ("status" IN ('PLANNED', 'PENDING', 'CANCELED') AND "settled_amount_cents" = 0)
  ),
  ADD CONSTRAINT "transactions_transfer_type" CHECK (("type" = 'TRANSFER') = ("transfer_id" IS NOT NULL));

ALTER TABLE "transfers"
  ADD CONSTRAINT "transfers_amount_positive" CHECK ("amount_cents" > 0);

ALTER TABLE "entity_members"
  ADD CONSTRAINT "entity_members_share_range" CHECK ("ownership_share_bps" BETWEEN 0 AND 10000);

-- Índice para busca textual frequente por descrição.
CREATE INDEX "transactions_entity_deleted_idx" ON "transactions" ("entity_id") WHERE "deleted_at" IS NULL;
