import type { MemberRole } from '@prisma/client';

declare global {
  namespace Express {
    interface Request {
      auth?: { userId: string; sessionId: string };
      membership?: { entityId: string; role: MemberRole; ownershipShareBps: number };
    }
  }
}

export {};
