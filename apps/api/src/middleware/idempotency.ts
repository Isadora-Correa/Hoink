import { Prisma } from '@prisma/client';
import type { NextFunction, Request, Response } from 'express';
import { sha256 } from '../lib/crypto';
import { conflict } from '../lib/errors';
import { prisma } from '../lib/prisma';

/**
 * Idempotência para operações que movimentam dinheiro. Se o cliente enviar o cabeçalho
 * `Idempotency-Key`, a primeira resposta é armazenada e repetições com a mesma chave
 * devolvem a mesma resposta sem criar novo registro.
 */
export async function idempotency(req: Request, res: Response, next: NextFunction) {
  const key = req.get('idempotency-key');
  if (!key || !req.auth) return next();
  if (key.length > 200) throw conflict('Idempotency-Key muito longa');

  const userId = req.auth.userId;
  const requestHash = sha256(JSON.stringify({ path: req.originalUrl, body: req.body ?? null }));

  try {
    await prisma.idempotencyKey.create({
      data: { userId, key, method: req.method, path: req.originalUrl, requestHash },
    });
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
      const existing = await prisma.idempotencyKey.findUnique({ where: { userId_key: { userId, key } } });
      if (!existing || existing.requestHash !== requestHash) {
        throw conflict('Idempotency-Key já utilizada com outra requisição');
      }
      if (existing.statusCode === null) throw conflict('Requisição com esta Idempotency-Key ainda em processamento');
      res.setHeader('Idempotent-Replayed', 'true');
      res.status(existing.statusCode).json(existing.response);
      return;
    }
    throw err;
  }

  const originalJson = res.json.bind(res);
  res.json = (body: unknown) => {
    const statusCode = res.statusCode;
    const op =
      statusCode < 500
        ? prisma.idempotencyKey.update({
            where: { userId_key: { userId, key } },
            data: { statusCode, response: (body ?? null) as Prisma.InputJsonValue },
          })
        : prisma.idempotencyKey.delete({ where: { userId_key: { userId, key } } });
    void op.catch(() => undefined);
    return originalJson(body);
  };
  next();
}
