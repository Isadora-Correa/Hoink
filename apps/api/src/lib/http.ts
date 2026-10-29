import type { Request } from 'express';
import { z } from 'zod';
import { AppError } from './errors';

export function parse<S extends z.ZodType>(schema: S, data: unknown): z.output<S> {
  const result = schema.safeParse(data);
  if (!result.success) {
    throw new AppError(400, 'VALIDATION_ERROR', 'Dados inválidos', z.flattenError(result.error));
  }
  return result.data;
}

export function authOf(req: Request) {
  if (!req.auth) throw new AppError(401, 'UNAUTHORIZED', 'Não autenticado');
  return req.auth;
}

export function membershipOf(req: Request) {
  if (!req.membership) throw new AppError(500, 'INTERNAL', 'Ambiente não resolvido');
  return req.membership;
}

export function param(req: Request, name: string): string {
  const v = req.params[name];
  if (typeof v !== 'string') throw new AppError(400, 'BAD_REQUEST', `Parâmetro ${name} ausente`);
  return v;
}

export function clientIp(req: Request): string | undefined {
  return req.ip ?? undefined;
}
