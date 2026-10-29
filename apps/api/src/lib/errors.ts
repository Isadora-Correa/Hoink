export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
  }
}

export const badRequest = (message: string, details?: unknown) => new AppError(400, 'BAD_REQUEST', message, details);
export const unauthorized = (message = 'Não autenticado') => new AppError(401, 'UNAUTHORIZED', message);
export const forbidden = (message = 'Acesso negado') => new AppError(403, 'FORBIDDEN', message);
export const notFound = (message = 'Recurso não encontrado') => new AppError(404, 'NOT_FOUND', message);
export const conflict = (message: string) => new AppError(409, 'CONFLICT', message);
export const unprocessable = (code: string, message: string) => new AppError(422, code, message);
