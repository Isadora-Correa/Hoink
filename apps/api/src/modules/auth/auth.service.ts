import { hash, verify } from '@node-rs/argon2';
import { env } from '../../config/env';
import { generateToken, sha256 } from '../../lib/crypto';
import { AppError, conflict, notFound, unauthorized } from '../../lib/errors';
import { recordEvent } from '../../lib/events';
import { mailer } from '../../lib/mailer';
import { prisma } from '../../lib/prisma';
import { createDefaultEntities } from '../entities/entities.service';

const RESET_TTL_MS = 60 * 60 * 1000;
// Parâmetros argon2id recomendados pela OWASP (m=19 MiB, t=2, p=1).
const ARGON = { memoryCost: 19456, timeCost: 2, parallelism: 1 };
// Hash fixo usado para equalizar o tempo de resposta quando o e-mail não existe.
const DUMMY_HASH_PROMISE = hash('hoink-dummy-password', ARGON);

export interface ClientInfo {
  userAgent?: string;
  ip?: string;
}

const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
const withAvatar = { avatar: { select: { updatedAt: true } } } as const;

function publicUser(u: { id: string; email: string; name: string; createdAt: Date; avatar?: { updatedAt: Date } | null }) {
  // avatarUpdatedAt permite ao app saber se há foto e invalidar o cache quando ela muda.
  return { id: u.id, email: u.email, name: u.name, createdAt: u.createdAt, avatarUpdatedAt: u.avatar?.updatedAt ?? null };
}

/** Detecta o formato pelos bytes iniciais (não confia no Content-Type enviado pelo cliente). */
export function detectImageType(buf: Buffer): 'image/png' | 'image/jpeg' | 'image/webp' | null {
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  return null;
}

export async function setAvatar(userId: string, data: Buffer) {
  if (data.length === 0) throw new AppError(400, 'EMPTY_FILE', 'Envie uma imagem');
  if (data.length > AVATAR_MAX_BYTES) throw new AppError(413, 'FILE_TOO_LARGE', 'A imagem deve ter no máximo 2 MB');
  const mimeType = detectImageType(data);
  if (!mimeType) throw new AppError(415, 'UNSUPPORTED_IMAGE', 'Formato não suportado. Use PNG, JPEG ou WebP');
  const bytes = new Uint8Array(data);
  await prisma.userAvatar.upsert({ where: { userId }, create: { userId, mimeType, data: bytes }, update: { mimeType, data: bytes } });
  recordEvent('profile.avatar_updated', { userId });
  return me(userId);
}

export async function getAvatar(userId: string) {
  const avatar = await prisma.userAvatar.findUnique({ where: { userId } });
  if (!avatar) throw notFound('Sem foto de perfil');
  return avatar;
}

export async function removeAvatar(userId: string) {
  await prisma.userAvatar.deleteMany({ where: { userId } });
  return me(userId);
}

async function createSession(userId: string, client: ClientInfo) {
  const token = generateToken();
  const expiresAt = new Date(Date.now() + env.SESSION_TTL_DAYS * 24 * 60 * 60 * 1000);
  await prisma.session.create({
    data: { userId, tokenHash: sha256(token), userAgent: client.userAgent?.slice(0, 300), ip: client.ip, expiresAt },
  });
  return { token, expiresAt };
}

export async function signup(
  input: { name: string; email: string; password: string; withBusiness?: boolean },
  client: ClientInfo,
) {
  const existing = await prisma.user.findUnique({ where: { email: input.email } });
  if (existing) throw conflict('Já existe uma conta com este e-mail');
  const passwordHash = await hash(input.password, ARGON);
  const user = await prisma.$transaction(async (tx) => {
    const u = await tx.user.create({ data: { name: input.name, email: input.email, passwordHash } });
    await createDefaultEntities(tx, u.id, input.withBusiness ?? false);
    return u;
  });
  recordEvent('auth.signup', { userId: user.id });
  const session = await createSession(user.id, client);
  return { user: publicUser(user), ...session };
}

export async function login(input: { email: string; password: string }, client: ClientInfo) {
  const user = await prisma.user.findUnique({ where: { email: input.email }, include: withAvatar });
  const ok = user ? await verify(user.passwordHash, input.password) : (await verify(await DUMMY_HASH_PROMISE, input.password), false);
  if (!user || !ok) {
    recordEvent('auth.login_failed', { ip: client.ip });
    throw unauthorized('E-mail ou senha incorretos');
  }
  recordEvent('auth.login', { userId: user.id });
  const session = await createSession(user.id, client);
  return { user: publicUser(user), ...session };
}

export async function logout(sessionId: string) {
  await prisma.session.updateMany({ where: { id: sessionId, revokedAt: null }, data: { revokedAt: new Date() } });
}

export async function me(userId: string) {
  const user = await prisma.user.findUniqueOrThrow({ where: { id: userId }, include: withAvatar });
  return publicUser(user);
}

export async function updateProfile(userId: string, data: { name: string }) {
  return publicUser(await prisma.user.update({ where: { id: userId }, data, include: withAvatar }));
}

/** Troca a senha e revoga todas as outras sessões do usuário. */
export async function changePassword(userId: string, sessionId: string, current: string, next: string) {
  const user = await prisma.user.findUniqueOrThrow({ where: { id: userId } });
  if (!(await verify(user.passwordHash, current))) {
    throw new AppError(400, 'INVALID_PASSWORD', 'Senha atual incorreta');
  }
  await prisma.$transaction([
    prisma.user.update({ where: { id: userId }, data: { passwordHash: await hash(next, ARGON) } }),
    prisma.session.updateMany({
      where: { userId, id: { not: sessionId }, revokedAt: null },
      data: { revokedAt: new Date() },
    }),
  ]);
}

/** Sempre responde com sucesso para não revelar se o e-mail está cadastrado. */
export async function requestPasswordReset(email: string) {
  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) return;
  const token = generateToken();
  await prisma.passwordResetToken.create({
    data: { userId: user.id, tokenHash: sha256(token), expiresAt: new Date(Date.now() + RESET_TTL_MS) },
  });
  await mailer.send({
    to: user.email,
    subject: 'hoink. — redefinição de senha',
    text: `Olá, ${user.name}! Use este código para redefinir sua senha (válido por 1 hora): ${token}`,
  });
}

export async function resetPassword(token: string, password: string) {
  const record = await prisma.passwordResetToken.findUnique({ where: { tokenHash: sha256(token) } });
  if (!record || record.usedAt || record.expiresAt <= new Date()) {
    throw new AppError(400, 'INVALID_TOKEN', 'Código inválido ou expirado');
  }
  const now = new Date();
  await prisma.$transaction([
    prisma.user.update({ where: { id: record.userId }, data: { passwordHash: await hash(password, ARGON) } }),
    prisma.passwordResetToken.update({ where: { id: record.id }, data: { usedAt: now } }),
    prisma.session.updateMany({ where: { userId: record.userId, revokedAt: null }, data: { revokedAt: now } }),
  ]);
  recordEvent('auth.password_reset', { userId: record.userId });
}

export async function listSessions(userId: string, currentSessionId: string) {
  const sessions = await prisma.session.findMany({
    where: { userId, revokedAt: null, expiresAt: { gt: new Date() } },
    orderBy: { lastUsedAt: 'desc' },
  });
  return sessions.map((s) => ({
    id: s.id,
    userAgent: s.userAgent,
    ip: s.ip,
    createdAt: s.createdAt,
    lastUsedAt: s.lastUsedAt,
    expiresAt: s.expiresAt,
    current: s.id === currentSessionId,
  }));
}

export async function revokeSession(userId: string, sessionId: string) {
  const r = await prisma.session.updateMany({
    where: { id: sessionId, userId, revokedAt: null },
    data: { revokedAt: new Date() },
  });
  if (r.count === 0) throw notFound('Sessão não encontrada');
}
