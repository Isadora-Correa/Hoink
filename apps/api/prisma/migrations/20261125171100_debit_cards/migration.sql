-- CreateTable
CREATE TABLE "debit_cards" (
    "id" UUID NOT NULL,
    "entity_id" UUID NOT NULL,
    "account_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "institution" TEXT,
    "brand" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,
    "archived_at" TIMESTAMPTZ,

    CONSTRAINT "debit_cards_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "debit_cards_entity_id_idx" ON "debit_cards"("entity_id");

-- AddForeignKey
ALTER TABLE "debit_cards" ADD CONSTRAINT "debit_cards_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "debit_cards" ADD CONSTRAINT "debit_cards_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "accounts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
