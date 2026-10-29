-- CreateEnum
CREATE TYPE "PiggyKind" AS ENUM ('RESERVE', 'WISH', 'GOAL');

-- AlterTable
ALTER TABLE "piggy_banks" ADD COLUMN     "achieved_at" DATE,
ADD COLUMN     "kind" "PiggyKind" NOT NULL DEFAULT 'GOAL',
ADD COLUMN     "link" TEXT,
ADD COLUMN     "priority" INTEGER NOT NULL DEFAULT 3;

-- CreateTable
CREATE TABLE "achievements" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "piggy_id" UUID,
    "unlocked_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "achievements_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
-- Conquistas sem cofrinho (piggy_id nulo) também não podem se repetir.
CREATE UNIQUE INDEX "achievements_user_id_code_piggy_id_key" ON "achievements"("user_id", "code", "piggy_id") NULLS NOT DISTINCT;

-- AddForeignKey
ALTER TABLE "achievements" ADD CONSTRAINT "achievements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "piggy_banks" ADD CONSTRAINT "piggy_banks_priority" CHECK ("priority" BETWEEN 1 AND 5);
