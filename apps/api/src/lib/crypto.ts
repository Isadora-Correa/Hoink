import { createHash, randomBytes } from 'node:crypto';

export function generateToken(bytes = 32): string {
  return randomBytes(bytes).toString('base64url');
}

/** Tokens de sessão/redefinição são armazenados apenas como hash. */
export function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}
