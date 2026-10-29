import express, { Router, type Request } from 'express';
import rateLimit from 'express-rate-limit';
import { env } from '../../config/env';
import {
  changePasswordSchema,
  forgotPasswordSchema,
  loginSchema,
  resetPasswordSchema,
  signupSchema,
  updateProfileSchema,
} from '../../contracts';
import { authOf, param, parse } from '../../lib/http';
import { requireAuth } from '../../middleware/auth';
import * as auth from './auth.service';

const client = (req: Request) => ({ userAgent: req.get('user-agent'), ip: req.ip });

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: env.NODE_ENV === 'test' ? 10_000 : env.AUTH_RATE_LIMIT,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: { code: 'RATE_LIMITED', message: 'Muitas tentativas. Tente novamente mais tarde.' } },
});

export const authRouter = Router();

authRouter.post('/signup', authLimiter, async (req, res) => {
  res.status(201).json({ data: await auth.signup(parse(signupSchema, req.body), client(req)) });
});

authRouter.post('/login', authLimiter, async (req, res) => {
  res.json({ data: await auth.login(parse(loginSchema, req.body), client(req)) });
});

authRouter.post('/forgot-password', authLimiter, async (req, res) => {
  await auth.requestPasswordReset(parse(forgotPasswordSchema, req.body).email);
  res.json({ data: { message: 'Se o e-mail estiver cadastrado, você receberá um código de redefinição.' } });
});

authRouter.post('/reset-password', authLimiter, async (req, res) => {
  const body = parse(resetPasswordSchema, req.body);
  await auth.resetPassword(body.token, body.password);
  res.json({ data: { ok: true } });
});

authRouter.use(requireAuth);

authRouter.post('/logout', async (req, res) => {
  await auth.logout(authOf(req).sessionId);
  res.status(204).end();
});

authRouter.get('/me', async (req, res) => {
  res.json({ data: await auth.me(authOf(req).userId) });
});

authRouter.patch('/me', async (req, res) => {
  res.json({ data: await auth.updateProfile(authOf(req).userId, parse(updateProfileSchema, req.body)) });
});

// Foto de perfil: corpo binário da imagem (image/png, image/jpeg ou image/webp), até 2 MB.
authRouter.put('/me/avatar', express.raw({ type: () => true, limit: '2mb' }), async (req, res) => {
  const body = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
  res.json({ data: await auth.setAvatar(authOf(req).userId, body) });
});

authRouter.get('/me/avatar', async (req, res) => {
  const avatar = await auth.getAvatar(authOf(req).userId);
  res.set({ 'Content-Type': avatar.mimeType, 'Cache-Control': 'private, max-age=300' });
  res.send(Buffer.from(avatar.data));
});

authRouter.delete('/me/avatar', async (req, res) => {
  res.json({ data: await auth.removeAvatar(authOf(req).userId) });
});

authRouter.post('/change-password', async (req, res) => {
  const { userId, sessionId } = authOf(req);
  const body = parse(changePasswordSchema, req.body);
  await auth.changePassword(userId, sessionId, body.currentPassword, body.newPassword);
  res.json({ data: { ok: true } });
});

authRouter.get('/sessions', async (req, res) => {
  const { userId, sessionId } = authOf(req);
  res.json({ data: await auth.listSessions(userId, sessionId) });
});

authRouter.delete('/sessions/:id', async (req, res) => {
  await auth.revokeSession(authOf(req).userId, param(req, 'id'));
  res.status(204).end();
});
