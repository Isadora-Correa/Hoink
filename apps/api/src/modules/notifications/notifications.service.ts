import { notFound } from '../../lib/errors';
import { prisma } from '../../lib/prisma';
import { insights, type Scope } from '../assistant/assistant.service';

/** Última geração por usuário: evita recalcular a cada abertura do sino. */
const lastRun = new Map<string, number>();
const MIN_INTERVAL_MS = 10 * 60 * 1000;

async function scopeOf(userId: string): Promise<Scope> {
  const memberships = await prisma.entityMember.findMany({ where: { userId, entity: { archivedAt: null } }, include: { entity: true } });
  return {
    label: 'Consolidado',
    entities: memberships.map((m) => ({ id: m.entityId, name: m.entity.name, kind: m.entity.kind, shareBps: 10000 })),
  };
}

/** Transforma os insights atuais em notificações novas (cada aviso só aparece uma vez). */
export async function generate(userId: string, force = false) {
  const now = Date.now();
  if (!force && now - (lastRun.get(userId) ?? 0) < MIN_INTERVAL_MS) return 0;
  lastRun.set(userId, now);
  const scope = await scopeOf(userId);
  if (scope.entities.length === 0) return 0;
  const list = await insights(scope);
  const result = await prisma.notification.createMany({
    skipDuplicates: true,
    data: list.map((i) => ({ userId, severity: i.severity, title: i.title, body: i.body, link: i.link, dedupeKey: i.key })),
  });
  return result.count;
}

export async function list(userId: string) {
  await generate(userId);
  const [items, unread] = await Promise.all([
    prisma.notification.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, take: 50 }),
    prisma.notification.count({ where: { userId, readAt: null } }),
  ]);
  return {
    unread,
    items: items.map((n) => ({
      id: n.id,
      severity: n.severity,
      title: n.title,
      body: n.body,
      link: n.link,
      createdAt: n.createdAt,
      read: n.readAt !== null,
    })),
  };
}

export async function markRead(userId: string, id: string) {
  const n = await prisma.notification.findFirst({ where: { id, userId } });
  if (!n) throw notFound('Notificação não encontrada');
  await prisma.notification.update({ where: { id }, data: { readAt: n.readAt ?? new Date() } });
}

export async function markAllRead(userId: string) {
  await prisma.notification.updateMany({ where: { userId, readAt: null }, data: { readAt: new Date() } });
}

/** Para os testes: zera o controle de frequência. */
export function resetThrottle() {
  lastRun.clear();
}
