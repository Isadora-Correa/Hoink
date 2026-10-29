import { Router, type Request } from 'express';
import { z } from 'zod';
import { contactCreateSchema, contactUpdateSchema, payablesQuerySchema } from '../../contracts';
import { authOf, membershipOf, param, parse } from '../../lib/http';
import { ensureGenerated } from '../recurring/recurring.service';
import * as svc from './contacts.service';

export const contactsRouter = Router({ mergeParams: true });
const ctx = (req: Request) => ({ userId: authOf(req).userId, entityId: membershipOf(req).entityId, ip: req.ip });

contactsRouter.get('/', async (req, res) => {
  const q = parse(
    z.object({
      kind: z.enum(['CLIENT', 'SUPPLIER']).optional(),
      q: z.string().trim().max(100).optional(),
      includeArchived: z.enum(['true', 'false']).optional(),
    }),
    req.query,
  );
  res.json({ data: await svc.listContacts(membershipOf(req).entityId, { ...q, includeArchived: q.includeArchived === 'true' }) });
});

contactsRouter.post('/', async (req, res) => {
  res.status(201).json({ data: await svc.createContact(ctx(req), parse(contactCreateSchema, req.body)) });
});

contactsRouter.get('/:contactId', async (req, res) => {
  res.json({ data: await svc.getContact(membershipOf(req).entityId, param(req, 'contactId')) });
});

contactsRouter.patch('/:contactId', async (req, res) => {
  res.json({ data: await svc.updateContact(ctx(req), param(req, 'contactId'), parse(contactUpdateSchema, req.body)) });
});

contactsRouter.post('/:contactId/archive', async (req, res) => {
  res.json({ data: await svc.setContactArchived(ctx(req), param(req, 'contactId'), true) });
});

contactsRouter.post('/:contactId/unarchive', async (req, res) => {
  res.json({ data: await svc.setContactArchived(ctx(req), param(req, 'contactId'), false) });
});

/** Contas a receber / a pagar do ambiente. */
export const payablesRouter = Router({ mergeParams: true });
payablesRouter.get('/', async (req, res) => {
  const entityId = membershipOf(req).entityId;
  await ensureGenerated([entityId]);
  res.json(await svc.payables([entityId], parse(payablesQuerySchema, req.query)));
});
