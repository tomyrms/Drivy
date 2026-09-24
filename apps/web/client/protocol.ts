import { z } from 'zod';

const identifier = z.string().uuid();
const text = z.string().min(1).max(20_000);
export const roleSchema = z.enum(['ADMIN', 'INSTRUCTOR', 'LEARNER']);
const roles = z.array(roleSchema).min(1).max(3);
export const sessionSchema = z.object({
  authenticated: z.boolean(),
  csrfToken: z.string().min(1).max(512),
  invitationPending: z.boolean(),
  user: z.object({
    displayName: z.string().max(300),
    email: z.string().max(254).optional(),
    emailVerified: z.boolean(),
  }).optional(),
});
export const memberSchema = z.object({
  membershipId: identifier,
  schoolId: identifier,
  schoolName: text,
  roles,
  grants: z.array(z.string().max(100)).max(100),
  accessEpoch: z.number().int().positive(),
});
export const meSchema = z.object({ data: z.object({
  personId: identifier,
  displayName: z.string().max(300),
  version: z.number().int().positive(),
  memberships: z.array(memberSchema).max(500),
}) });
export const previewSchema = z.object({ confirmation: z.string().min(1).max(512), data: z.object({
  invitationId: identifier,
  schoolId: identifier,
  schoolName: text,
  roles,
  maskedEmail: text,
  expiresAt: z.string().datetime({ offset: true }),
  notice: z.object({
    version: z.number().int().positive(),
    noticeText: text,
    retentionText: text,
    contactEmail: z.string().email().max(254),
  }),
}) });
export const acceptedSchema = z.object({ data: memberSchema });
export const okSchema = z.object({ ok: z.literal(true) });
export const loginSchema = z.object({ url: z.string().url() });

export type Session = z.infer<typeof sessionSchema>;
export type Me = z.infer<typeof meSchema>['data'];
export type InvitationPreview = z.infer<typeof previewSchema>['data'];
export type Member = z.infer<typeof memberSchema>;
export type Role = z.infer<typeof roleSchema>;

export class RequestFailure extends Error {
  constructor(readonly code: string, readonly status = 0) {
    super(code);
    this.name = 'RequestFailure';
  }
}

// The BFF owns the OAuth credentials and invitation operation. This client
// only sends same-origin requests with its CSRF value held in memory.
export async function request<T>(path: string, schema: z.ZodType<T>, options?: {
  csrf: string;
  body: Record<string, unknown>;
}): Promise<T> {
  const url = new URL(`/app/bff/${path}`, window.location.origin);
  let response: Response;
  try {
    response = await fetch(url, {
      method: options ? 'POST' : 'GET',
      credentials: 'same-origin',
      cache: 'no-store',
      redirect: 'error',
      referrerPolicy: 'no-referrer',
      signal: AbortSignal.timeout(25_000),
      headers: {
        Accept: 'application/json, application/problem+json',
        ...(options ? { 'Content-Type': 'application/json', 'X-CSRF-Token': options.csrf } : {}),
      },
      ...(options ? { body: JSON.stringify(options.body) } : {}),
    });
  } catch { throw new RequestFailure('NETWORK_UNAVAILABLE'); }
  if (response.url !== url.href) throw new RequestFailure('INVALID_RESPONSE');
  const contentType = response.headers.get('content-type')?.split(';')[0]?.trim();
  if (contentType !== 'application/json' && contentType !== 'application/problem+json') {
    throw new RequestFailure('INVALID_RESPONSE', response.status);
  }
  let value: unknown;
  try { value = await response.json(); }
  catch { throw new RequestFailure('INVALID_RESPONSE', response.status); }
  if (!response.ok) {
    const problem = z.object({ code: z.string().max(100) }).safeParse(value);
    throw new RequestFailure(problem.success ? problem.data.code : 'REQUEST_FAILED', response.status);
  }
  if (contentType !== 'application/json') throw new RequestFailure('INVALID_RESPONSE');
  const parsed = schema.safeParse(value);
  if (!parsed.success) throw new RequestFailure('INVALID_RESPONSE');
  return parsed.data;
}

export function errorMessage(error: unknown): string {
  if (!(error instanceof RequestFailure)) return 'La demande n’a pas pu être vérifiée. Réessayez dans un instant.';
  const messages: Record<string, string> = {
    NETWORK_UNAVAILABLE: 'La connexion a été interrompue. Vérifiez votre réseau puis réessayez.',
    INVALID_RESPONSE: 'La réponse reçue ne permet pas de confirmer le résultat. Réessayez dans un instant.',
    INVITATION_EXPIRED: 'Cette invitation a expiré. Demandez à votre école de vous envoyer un nouveau lien.',
    INVITATION_REVOKED: 'Cette invitation n’est plus disponible. Contactez votre école pour obtenir un nouveau lien.',
    INVITATION_INVALID: 'Ce lien d’invitation n’est pas disponible. Ouvrez le lien le plus récent envoyé par votre école.',
    INVITATION_NOT_FOUND: 'Ce lien d’invitation n’est pas disponible. Ouvrez le lien le plus récent envoyé par votre école.',
    INVITATION_USED: 'Cette invitation a déjà été utilisée. Actualisez vos écoles pour vérifier votre accès.',
    INVITATION_IDENTITY_MISMATCH: 'Cette invitation est destinée à une autre adresse. Connectez-vous avec le compte invité.',
    EMAIL_NOT_VERIFIED: 'Vérifiez votre adresse auprès du service de connexion, puis reconnectez-vous pour continuer.',
    IDENTITY_EMAIL_NOT_VERIFIED: 'Vérifiez votre adresse auprès du service de connexion, puis reconnectez-vous pour continuer.',
    ALREADY_MEMBER: 'Votre compte est déjà rattaché à cette école. Actualisez vos écoles pour retrouver votre accès.',
    INVITATION_REQUIRED: 'Ouvrez le lien d’invitation envoyé par votre école pour continuer.',
    INVITATION_CHANGED: 'Une autre invitation a été ouverte. Relisez le lien de l’école que vous souhaitez rejoindre.',
    INVITATION_PREVIEW_CHANGED: 'L’invitation ou les informations de l’école ont changé. Actualisez puis relisez-les avant de confirmer à nouveau.',
    INVITATION_IN_PROGRESS: 'Une acceptation est déjà en cours. Attendez sa confirmation avant d’ouvrir une autre invitation.',
    INVITATION_RESULT_UNKNOWN: 'Le résultat d’une acceptation doit encore être vérifié avant de fermer ou remplacer cette invitation.',
    CSRF_INVALID: 'La session de cette page a changé. Actualisez-la avant de réessayer.',
    CSRF_REQUIRED: 'La session de cette page a changé. Actualisez-la avant de réessayer.',
    CSRF_REJECTED: 'La session de cette page a changé. Actualisez-la avant de réessayer.',
    SCHOOL_NOT_ACTIVE: 'Cette école n’est pas encore prête à vous accueillir. Contactez son administration.',
  };
  const knownMessage = messages[error.code];
  if (knownMessage) return knownMessage;
  if (error.status === 401) return 'Votre connexion a expiré. Reconnectez-vous pour continuer.';
  if (error.status === 403) return 'Cette action n’est pas disponible avec vos accès actuels.';
  if (error.status === 429) return 'Trop de demandes ont été envoyées. Patientez un instant avant de réessayer.';
  return 'La demande n’a pas pu être confirmée. Réessayez ou contactez votre école si le problème persiste.';
}

export function roleLabel(role: Role): string {
  return { ADMIN: 'Administration', INSTRUCTOR: 'Moniteur', LEARNER: 'Élève' }[role];
}
