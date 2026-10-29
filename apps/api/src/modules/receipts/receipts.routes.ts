import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { membershipOf, parse } from '../../lib/http';
import { previewReceipt } from './receipts.service';

/** Leitura de nota fiscal (prévia). Limitada por IP: cada leitura consulta serviços externos. */
export const receiptsRouter = Router({ mergeParams: true });
const limiter = rateLimit({ windowMs: 60_000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false });

receiptsRouter.post('/preview', limiter, async (req, res) => {
  const { qr } = parse(z.object({ qr: z.string().trim().min(10, 'Leia o QR Code ou digite a chave').max(2000) }), req.body);
  res.json({ data: await previewReceipt(membershipOf(req).entityId, qr) });
});
