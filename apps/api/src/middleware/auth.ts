import type { NextFunction, Request, Response } from 'express';
import { sha256 } from '../lib/crypto';
import { unauthorized } from '../lib/errors';
import { prisma } from '../lib/prisma';

const TOUCH_INTERVAL_MS = 5 * 60 * 1000;

export function bearerToken(req: Request): string | null {
  const header = req.get('authorization');
  if (!header?.startsWith('Bearer ')) return null;
  const token = header.slice(7).trim();
  return token.length >= 20 ? token : null;
}

/**
 * Autenticação por token de sessão opaco no cabeçalho Authorization (Bearer).
 * O banco guarda apenas o hash SHA-256 do token; sessões podem ser revogadas individualmente.
 */
export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  const token = bearerToken(req);
  if (!token) throw unauthorized();

  const session = await prisma.session.findUnique({ where: { tokenHash: sha256(token) } });
  const now = new Date();
  if (!session || session.revokedAt || session.expiresAt <= now) throw unauthorized('Sessão expirada');

  if (now.getTime() - session.lastUsedAt.getTime() > TOUCH_INTERVAL_MS) {
    await prisma.session.update({ where: { id: session.id }, data: { lastUsedAt: now } });
  }
  req.auth = { userId: session.userId, sessionId: session.id };
  next();
}
