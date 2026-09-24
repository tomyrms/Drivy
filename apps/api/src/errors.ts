export class ApiError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) { super(message); }
}
export const forbidden = () => new ApiError(403, 'ACCESS_DENIED', 'Accès indisponible dans cette école.');
export const notFound = () => new ApiError(404, 'NOT_FOUND', 'Objet introuvable dans le périmètre autorisé.');
