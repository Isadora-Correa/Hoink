import type { Prisma } from '@prisma/client';
import type { Tx } from '../../lib/prisma';

export interface AuditEntry {
  userId: string;
  entityId?: string | null;
  action: 'create' | 'update' | 'delete' | 'archive' | 'unarchive' | 'settle' | 'reconcile' | string;
  resourceType: string;
  resourceId?: string | null;
  before?: unknown;
  after?: unknown;
  ip?: string;
}

/** BIGINT não é serializável em JSON; converte para string antes de gravar. */
function toJson(value: unknown): Prisma.InputJsonValue | undefined {
  if (value === undefined || value === null) return undefined;
  return JSON.parse(JSON.stringify(value, (_k, v) => (typeof v === 'bigint' ? v.toString() : v)));
}

/** Registra trilha de auditoria (RN14). Deve ser chamada dentro da mesma transação da alteração. */
export async function audit(tx: Tx, e: AuditEntry) {
  await tx.auditLog.create({
    data: {
      userId: e.userId,
      entityId: e.entityId ?? null,
      action: e.action,
      resourceType: e.resourceType,
      resourceId: e.resourceId ?? null,
      before: toJson(e.before),
      after: toJson(e.after),
      ip: e.ip,
    },
  });
}
