/**
 * Pure rules of the management commands, shared by the React console and the unit tests.
 * No DOM, no network, no relative import: this file is type-checked for the browser and for Node.
 *
 * A command keeps one operationId (sent as Idempotency-Key) from its first emission until the
 * school confirms it — by a verified response or by an AP72 receipt. Nothing is shown as
 * succeeded before that. Mirrors apps/ios/Drivy/SchoolConfigurationAPI/SchoolCommandOutbox.swift.
 */

export type CommandKind =
  | 'updateSchool' | 'saveSetup' | 'activate' | 'saveDataPolicy'
  | 'createInvitation' | 'resendInvitation' | 'revokeInvitation'
  | 'createProfilePolicy' | 'publishProfilePolicy'
  | 'createOffering' | 'createCurriculum' | 'createCatalogPolicy' | 'updateMember'
  | 'createCommercialTerms' | 'createServiceProduct';
export type CommandMethod = 'POST' | 'PATCH' | 'PUT';

interface CommandSpec {
  readonly operationType: string;
  readonly resourceType: string;
  /** Which identifier the AP72 receipt must carry: the school, the targeted resource, or a new one. */
  readonly target: 'school' | 'resource' | 'created';
  readonly method: CommandMethod;
  readonly expectedStatus: 200 | 201;
  readonly label: string;
}

export const commandSpecs: Readonly<Record<CommandKind, CommandSpec>> = {
  updateSchool: { operationType: 'UPDATE_SCHOOL', resourceType: 'School', target: 'school', method: 'PATCH', expectedStatus: 200, label: 'Modification des coordonnées' },
  saveSetup: { operationType: 'SAVE_SCHOOL_SETUP', resourceType: 'SchoolSetup', target: 'school', method: 'PATCH', expectedStatus: 200, label: 'Enregistrement de l’avancement' },
  activate: { operationType: 'ACTIVATE_SCHOOL', resourceType: 'School', target: 'school', method: 'POST', expectedStatus: 200, label: 'Activation de l’école' },
  saveDataPolicy: { operationType: 'ADOPT_SCHOOL_DATA_POLICY', resourceType: 'SchoolDataPolicy', target: 'school', method: 'PUT', expectedStatus: 200, label: 'Adoption des textes d’information' },
  createInvitation: { operationType: 'CREATE_INVITATION', resourceType: 'Invitation', target: 'created', method: 'POST', expectedStatus: 201, label: 'Envoi d’une invitation' },
  resendInvitation: { operationType: 'RESEND_INVITATION', resourceType: 'Invitation', target: 'resource', method: 'POST', expectedStatus: 200, label: 'Renvoi d’une invitation' },
  revokeInvitation: { operationType: 'REVOKE_INVITATION', resourceType: 'Invitation', target: 'resource', method: 'POST', expectedStatus: 200, label: 'Révocation d’une invitation' },
  createProfilePolicy: { operationType: 'CREATE_PROFILE_FIELD_POLICY', resourceType: 'ProfileFieldPolicy', target: 'created', method: 'POST', expectedStatus: 201, label: 'Création d’une version des champs du profil' },
  publishProfilePolicy: { operationType: 'PUBLISH_PROFILE_FIELD_POLICY', resourceType: 'ProfileFieldPolicy', target: 'resource', method: 'POST', expectedStatus: 200, label: 'Publication des champs du profil' },
  createOffering: { operationType: 'CREATE_OFFERING_VERSION', resourceType: 'Offering', target: 'created', method: 'POST', expectedStatus: 201, label: 'Création d’une version d’offre' },
  createCurriculum: { operationType: 'CREATE_CURRICULUM_VERSION', resourceType: 'Curriculum', target: 'created', method: 'POST', expectedStatus: 201, label: 'Création d’une révision de référentiel' },
  createCatalogPolicy: { operationType: 'CREATE_SCHOOL_POLICY', resourceType: 'SchoolPolicy', target: 'created', method: 'POST', expectedStatus: 201, label: 'Création d’une version de procédure' },
  updateMember: { operationType: 'UPDATE_MEMBER', resourceType: 'Member', target: 'resource', method: 'PATCH', expectedStatus: 200, label: 'Modification des accès d’un membre' },
  createCommercialTerms: { operationType: 'CREATE_COMMERCIAL_TERMS', resourceType: 'CommercialTermsVersion', target: 'created', method: 'POST', expectedStatus: 201, label: 'Création de conditions commerciales' },
  createServiceProduct: { operationType: 'CREATE_SERVICE_PRODUCT', resourceType: 'ServiceProductVersion', target: 'created', method: 'POST', expectedStatus: 201, label: 'Création d’une prestation' },
};

export interface SchoolCommand {
  readonly operationId: string;
  readonly schoolId: string;
  readonly kind: CommandKind;
  /** Path below /schools/{schoolId}, without leading slash ('' for the school itself). */
  readonly path: string;
  readonly body: Readonly<Record<string, unknown>> & { readonly operationId: string };
  /** Strong version sent as If-Match, when the route requires one. */
  readonly ifMatch?: number;
  /** Targeted resource (member, invitation, policy); absent for a creation. */
  readonly resourceId?: string;
  /** Version the command starts from; 0 for a creation. The receipt must be strictly newer. */
  readonly resourceVersion: number;
  readonly createdAt: number;
}

/** What survives a page reload: identifiers only, never the typed content. */
export interface CommandMetadata {
  readonly operationId: string;
  readonly schoolId: string;
  readonly kind: CommandKind;
  readonly resourceId?: string;
  readonly resourceVersion: number;
  readonly createdAt: number;
}

export interface OperationReceipt {
  readonly operationId: string;
  readonly commandType: string;
  readonly resourceType: string;
  readonly resourceId: string;
  readonly committedAt: string;
  readonly resourceVersion: number;
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUUID = (value: unknown): value is string => typeof value === 'string' && uuid.test(value);

export function newOperationId(): string {
  return globalThis.crypto.randomUUID();
}

export function createCommand(input: {
  schoolId: string; kind: CommandKind; path: string; body: Record<string, unknown>;
  ifMatch?: number; resourceId?: string; resourceVersion: number; operationId?: string; now?: number;
}): SchoolCommand {
  const operationId = input.operationId ?? newOperationId();
  if (!isUUID(operationId) || !isUUID(input.schoolId)) throw new Error('Identifiant de commande invalide.');
  if (input.resourceId !== undefined && !isUUID(input.resourceId)) throw new Error('Ressource invalide.');
  if (!Number.isSafeInteger(input.resourceVersion) || input.resourceVersion < 0) throw new Error('Version invalide.');
  if (input.ifMatch !== undefined && (!Number.isSafeInteger(input.ifMatch) || input.ifMatch < 1)) throw new Error('Version invalide.');
  if (!/^[a-z0-9/-]*$/.test(input.path)) throw new Error('Chemin invalide.');
  const spec = commandSpecs[input.kind];
  if (spec.target === 'resource' && !input.resourceId) throw new Error('Ressource requise.');
  if (spec.target === 'created' && (input.resourceId || input.resourceVersion !== 0)) throw new Error('Une création part de zéro.');
  return {
    operationId, schoolId: input.schoolId, kind: input.kind, path: input.path,
    body: Object.freeze({ ...input.body, operationId }),
    ...(input.ifMatch !== undefined ? { ifMatch: input.ifMatch } : {}),
    ...(input.resourceId ? { resourceId: input.resourceId } : {}),
    resourceVersion: input.resourceVersion, createdAt: input.now ?? Date.now(),
  };
}

/** Headers of one emission. A resend reuses exactly the same values. */
export function commandHeaders(command: SchoolCommand, csrf: string): Record<string, string> {
  return {
    'Content-Type': 'application/json', 'X-CSRF-Token': csrf, 'Idempotency-Key': command.operationId,
    ...(command.ifMatch !== undefined ? { 'If-Match': `"${command.ifMatch}"` } : {}),
  };
}

export function receiptMatches(command: CommandMetadata, receipt: OperationReceipt): boolean {
  const spec = commandSpecs[command.kind];
  const expected = spec.target === 'school' ? command.schoolId : spec.target === 'resource' ? command.resourceId : undefined;
  return receipt.operationId.toLowerCase() === command.operationId.toLowerCase()
    && receipt.commandType === spec.operationType && receipt.resourceType === spec.resourceType
    && Number.isSafeInteger(receipt.resourceVersion) && receipt.resourceVersion > command.resourceVersion
    && (expected === undefined || receipt.resourceId.toLowerCase() === expected.toLowerCase());
}

/**
 * Codes that the API returns only after refusing the command before any effect.
 * A fresh first emission refused with one of them may be released for correction.
 */
const businessRefusals = new Set([
  'INVALID_REQUEST', 'VERSION_CONFLICT', 'PRECONDITION_REQUIRED', 'REAUTH_REQUIRED', 'PAYLOAD_TOO_LARGE',
  'SETUP_INCOMPLETE', 'CONFIG_IMPACT_REVIEW_REQUIRED', 'MODULE_NOT_READY', 'POLICY_REVIEW_REQUIRED',
  'SCHOOL_ALREADY_ACTIVE', 'SCHOOL_ARCHIVED', 'SETUP_NOT_INITIALIZED', 'INVALID_TIME_ZONE', 'SCHOOL_NOT_ACTIVE',
  'LAST_ADMIN', 'MEMBER_RELATIONS_REQUIRE_REVIEW', 'OFFERING_NOT_READY', 'OFFERING_CATEGORY_CHANGED',
  'ALREADY_MEMBER', 'INVITATION_ALREADY_PENDING', 'INVITATION_USED', 'INVITATION_REVOKED', 'INVITATION_ROLE_FORBIDDEN',
  'PROFILE_POLICY_RULE_INVALID', 'PROFILE_POLICY_ALREADY_PUBLISHED', 'PROFILE_POLICY_DATE_CONFLICT',
  'INVALID_INTERVAL', 'INVALID_SERVICE_PRODUCT', 'COMMERCIAL_TERMS_NOT_APPROVED', 'SITE_SETUP_REQUIRED',
]);

export type CommandOutcome =
  /** Refused before any effect on a fresh first emission: release it, reload, let the person correct. */
  | { readonly type: 'rejected'; readonly code: string }
  /** Result unknown (lost response, 5xx, session lost): keep the same request, verify or resend it. */
  | { readonly type: 'uncertain'; readonly code: string; readonly needsLogin: boolean }
  /** A refusal that does not disprove a previous emission: keep it, verify with AP72 only. */
  | { readonly type: 'review'; readonly code: string };

export function classifyFailure(status: number, code: string, firstAttempt: boolean): CommandOutcome {
  if (status === 0 || status === 429 || status >= 500) return { type: 'uncertain', code, needsLogin: false };
  if (status === 401 && code !== 'REAUTH_REQUIRED') return { type: 'uncertain', code, needsLogin: true };
  // Rejected by the BFF itself, before the API: the same request can be sent again after refresh.
  if (code === 'CSRF_REJECTED') return { type: 'uncertain', code, needsLogin: false };
  if (businessRefusals.has(code)) return firstAttempt ? { type: 'rejected', code } : { type: 'review', code };
  return { type: 'review', code };
}

export function commandMessage(code: string): string {
  const messages: Record<string, string> = {
    NETWORK_UNAVAILABLE: 'La réponse n’a pas été reçue. Vérifiez le résultat auprès de l’école avant de continuer.',
    SERVICE_UNAVAILABLE: 'La réponse n’a pas été reçue. Vérifiez le résultat auprès de l’école avant de continuer.',
    API_UNAVAILABLE: 'L’école est momentanément inaccessible. Votre demande reste conservée jusqu’à vérification.',
    INVALID_RESPONSE: 'La réponse de l’école n’a pas pu être vérifiée. La modification n’est pas confirmée.',
    SESSION_EXPIRED: 'Votre connexion a expiré. Reconnectez-vous, puis vérifiez le résultat de la demande.',
    CSRF_REJECTED: 'La session de cette page a changé. La demande n’a pas été transmise : renvoyez la même demande.',
    REAUTH_REQUIRED: 'Reconnectez-vous avec le même compte pour confirmer ce changement d’accès. Rien n’a été modifié.',
    INVALID_REQUEST: 'L’école a refusé ces informations. Vérifiez la saisie avant de confirmer à nouveau.',
    PAYLOAD_TOO_LARGE: 'Le contenu dépasse la taille acceptée. Raccourcissez les textes avant de confirmer.',
    VERSION_CONFLICT: 'Les informations ont changé entre-temps. Rechargez et relisez avant de confirmer à nouveau.',
    PRECONDITION_REQUIRED: 'La version affichée est requise. Rechargez les informations avant de confirmer.',
    IDEMPOTENCY_MISMATCH: 'Cette référence de demande a déjà servi pour un autre contenu. Vérifiez son résultat auprès de l’école.',
    SETUP_INCOMPLETE: 'L’école n’est pas encore prête. Vérifiez les éléments à compléter.',
    CONFIG_IMPACT_REVIEW_REQUIRED: 'Cette modification demande une analyse d’impact dédiée (par exemple un changement de fuseau).',
    MODULE_NOT_READY: 'Ce changement n’est pas encore disponible.',
    POLICY_REVIEW_REQUIRED: 'Adoptez d’abord les textes d’information et de conservation de l’école.',
    SCHOOL_ALREADY_ACTIVE: 'Cette école est déjà active.',
    SCHOOL_ARCHIVED: 'Cette école est archivée et ne peut plus être modifiée.',
    SETUP_NOT_INITIALIZED: 'Le provisionnement de cette école doit d’abord être complété.',
    INVALID_TIME_ZONE: 'Le fuseau horaire de l’école est invalide.',
    SCHOOL_NOT_ACTIVE: 'Cette école doit être active avant cette modification.',
    LAST_ADMIN: 'L’école doit conserver au moins un membre de l’administration.',
    MEMBER_RELATIONS_REQUIRE_REVIEW: 'Les affectations ou le dossier de cette personne doivent être traités avant de retirer ce rôle.',
    OFFERING_NOT_READY: 'Le référentiel et la procédure de cette catégorie doivent être approuvés pour activer l’offre.',
    OFFERING_CATEGORY_CHANGED: 'Une offre conserve sa catégorie. Utilisez une nouvelle référence pour une autre catégorie.',
    ALREADY_MEMBER: 'Cette adresse correspond déjà à un membre de l’école.',
    INVITATION_ALREADY_PENDING: 'Une invitation est déjà en attente pour cette adresse.',
    INVITATION_USED: 'Cette invitation a déjà été utilisée.',
    INVITATION_REVOKED: 'Cette invitation a déjà été révoquée.',
    INVITATION_ROLE_FORBIDDEN: 'Vos accès ne permettent pas d’inviter avec ce rôle.',
    INVITATION_DELIVERY_UNAVAILABLE: 'L’envoi des invitations n’est pas disponible. Le résultat reste à vérifier : ne créez pas de seconde invitation.',
    PROFILE_POLICY_RULE_INVALID: 'Vérifiez les champs, leur utilité et le moment où ils sont demandés.',
    PROFILE_POLICY_ALREADY_PUBLISHED: 'Cette version est déjà publiée.',
    PROFILE_POLICY_DATE_CONFLICT: 'Une version publiée utilise déjà cette date d’effet.',
    INVALID_INTERVAL: 'La période indiquée n’est pas valide : la fin précède le début.',
    INVALID_SERVICE_PRODUCT: 'Une leçon individuelle exige une catégorie et une durée.',
    COMMERCIAL_TERMS_NOT_APPROVED: 'Choisissez des conditions commerciales approuvées pour activer cette prestation.',
    SITE_SETUP_REQUIRED: 'Les prestations par site ne sont pas encore disponibles.',
    SETUP_ACCESS_REQUIRED: 'Vos accès ne permettent plus cette opération dans l’école.',
    ACCESS_DENIED: 'Vos accès ne permettent plus cette opération dans l’école.',
    FORBIDDEN: 'Vos accès ne permettent plus cette opération dans l’école.',
    NOT_FOUND: 'Cette information n’est plus disponible avec vos accès actuels.',
  };
  return messages[code] ?? 'La demande n’a pas pu être confirmée. Vérifiez son résultat auprès de l’école avant de continuer.';
}

export function toMetadata(command: SchoolCommand): CommandMetadata {
  return { operationId: command.operationId, schoolId: command.schoolId, kind: command.kind,
    ...(command.resourceId ? { resourceId: command.resourceId } : {}), resourceVersion: command.resourceVersion, createdAt: command.createdAt };
}

export function parseMetadata(value: unknown): CommandMetadata | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null;
  const item = value as Record<string, unknown>;
  const keys = Object.keys(item);
  if (keys.some(key => !['operationId', 'schoolId', 'kind', 'resourceId', 'resourceVersion', 'createdAt'].includes(key))) return null;
  if (!isUUID(item.operationId) || !isUUID(item.schoolId) || typeof item.kind !== 'string' || !(item.kind in commandSpecs)) return null;
  if (item.resourceId !== undefined && !isUUID(item.resourceId)) return null;
  if (!Number.isSafeInteger(item.resourceVersion) || (item.resourceVersion as number) < 0) return null;
  if (!Number.isSafeInteger(item.createdAt) || (item.createdAt as number) <= 0) return null;
  const kind = item.kind as CommandKind;
  const target = commandSpecs[kind].target;
  if (target === 'resource' && item.resourceId === undefined) return null;
  return { operationId: item.operationId, schoolId: item.schoolId, kind,
    ...(item.resourceId ? { resourceId: item.resourceId as string } : {}),
    resourceVersion: item.resourceVersion as number, createdAt: item.createdAt as number };
}

/* ---------- Input rules shared with the Apple client ---------- */

export const characters = (value: string): number => [...value].length;
export const filled = (value: string, maximum: number): boolean => value.trim().length > 0 && characters(value) <= maximum;

export function isEmail(value: string): boolean {
  const pieces = value.split('@');
  return pieces.length === 2 && pieces.every(piece => piece.length > 0) && characters(value) <= 254 && !/\s/.test(value)
    && /\.[^.]+$/.test(pieces[1]!);
}

/** CHF amount typed as « 95 », « 95.50 » or « 95,5 » → cents; anything else is refused. */
export function parseCents(text: string): number | null {
  const value = text.trim().replace(',', '.');
  const match = /^(\d{1,13})(?:\.(\d{1,2}))?$/.exec(value);
  if (!match) return null;
  const cents = Number(match[1]) * 100 + Number((match[2] ?? '').padEnd(2, '0') || '0');
  return Number.isSafeInteger(cents) ? cents : null;
}

export function formatCents(cents: number): string {
  return new Intl.NumberFormat('fr-CH', { style: 'currency', currency: 'CHF' }).format(cents / 100);
}

export function centsToInput(cents: number): string {
  return cents % 100 === 0 ? String(cents / 100) : (cents / 100).toFixed(2);
}

export function isCivilDate(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  return date.getUTCFullYear() === Number(match[1]) && date.getUTCMonth() === Number(match[2]) - 1 && date.getUTCDate() === Number(match[3]);
}

export function isHttpURL(value: string): boolean {
  try {
    const url = new URL(value);
    return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password && value.length <= 2048;
  } catch { return false; }
}

function offsetMinutes(instant: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit' }).formatToParts(new Date(instant));
  const part = (type: string) => Number(parts.find(item => item.type === type)?.value);
  const asUTC = Date.UTC(part('year'), part('month') - 1, part('day'), part('hour'), part('minute'), part('second'));
  return Math.round((asUTC - Math.floor(instant / 1000) * 1000) / 60_000);
}

/**
 * Wall-clock time of the school ('YYYY-MM-DDTHH:mm' in its IANA zone) → ISO instant.
 * Returns null for an invalid value or a local time skipped by a daylight-saving change.
 */
export function schoolTimeToInstant(local: string, timeZone: string): string | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(local);
  if (!match || !isCivilDate(local.slice(0, 10)) || Number(match[4]) > 23 || Number(match[5]) > 59) return null;
  const wall = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]));
  try {
    let instant = wall - offsetMinutes(wall, timeZone) * 60_000;
    instant = wall - offsetMinutes(instant, timeZone) * 60_000;
    if (instant + offsetMinutes(instant, timeZone) * 60_000 !== wall) return null;
    return new Date(instant).toISOString();
  } catch { return null; }
}

/** ISO instant → wall-clock 'YYYY-MM-DDTHH:mm' of the school, for a datetime-local field. */
export function instantToSchoolTime(instant: string, timeZone: string): string {
  const time = Date.parse(instant);
  const shifted = new Date(time + offsetMinutes(time, timeZone) * 60_000);
  return shifted.toISOString().slice(0, 16);
}

/* ---------- Profile field policy (same rules as the API and SchoolProfileRule.isValid) ---------- */

export const profileFields = ['firstName', 'lastName', 'birthDate', 'postalAddress', 'contactEmail', 'contactPhone', 'profilePhotoDocumentId'] as const;
export type ProfileField = typeof profileFields[number];
export type ProfileRequirement = 'REQUIRED' | 'CONDITIONAL' | 'OPTIONAL';
export type ProfileStage = 'JOIN' | 'BEFORE_LESSON' | 'BEFORE_COURSE' | 'OPTIONAL';
export type ProfilePurpose = 'IDENTIFICATION' | 'LESSON_CONTACT' | 'COURSE_ELIGIBILITY' | 'CERTIFICATE' | 'POSTAL_CONTACT' | 'PERSONALISATION';
export interface ProfileRule { field: ProfileField; requirement: ProfileRequirement; stage: ProfileStage; purposeCode: ProfilePurpose; explanation: string }

export const fieldPurposes: Readonly<Record<ProfileField, readonly ProfilePurpose[]>> = {
  firstName: ['IDENTIFICATION'], lastName: ['IDENTIFICATION'], birthDate: ['COURSE_ELIGIBILITY', 'CERTIFICATE'],
  postalAddress: ['POSTAL_CONTACT', 'CERTIFICATE'], contactEmail: ['LESSON_CONTACT'], contactPhone: ['LESSON_CONTACT'],
  profilePhotoDocumentId: ['PERSONALISATION'],
};

export function profileRuleProblem(rule: ProfileRule): string | null {
  if (!filled(rule.explanation, 1000)) return 'Expliquez à la personne pourquoi ce champ est demandé (1 000 caractères au plus).';
  if (rule.field === 'firstName' || rule.field === 'lastName') {
    return rule.requirement === 'REQUIRED' && rule.stage === 'JOIN' && rule.purposeCode === 'IDENTIFICATION' ? null
      : 'Le prénom et le nom sont requis à l’entrée pour identifier la personne.';
  }
  if (rule.field === 'profilePhotoDocumentId') {
    return rule.requirement === 'OPTIONAL' && rule.stage === 'OPTIONAL' && rule.purposeCode === 'PERSONALISATION' ? null
      : 'La photo reste facultative et sert uniquement à personnaliser le profil.';
  }
  if (!fieldPurposes[rule.field].includes(rule.purposeCode)) return 'Cette utilité ne correspond pas à ce champ.';
  if (rule.requirement === 'OPTIONAL' && rule.stage !== 'OPTIONAL') return 'Un champ facultatif se demande sans étape obligatoire.';
  if (rule.requirement === 'CONDITIONAL' && rule.stage !== 'BEFORE_COURSE') return 'Un champ demandé selon la situation se demande avant un cours.';
  if (rule.requirement === 'REQUIRED' && rule.stage !== 'BEFORE_LESSON' && rule.stage !== 'BEFORE_COURSE') return 'Un champ requis se demande avant une leçon ou avant un cours.';
  return null;
}

export function profilePolicyProblem(rules: readonly ProfileRule[]): string | null {
  if (rules.length < 2 || rules.length > 7) return 'Choisissez entre deux et sept champs.';
  if (new Set(rules.map(rule => rule.field)).size !== rules.length) return 'Chaque champ ne peut figurer qu’une fois.';
  if (!rules.some(rule => rule.field === 'firstName') || !rules.some(rule => rule.field === 'lastName')) return 'Le prénom et le nom sont toujours demandés.';
  for (const rule of rules) { const problem = profileRuleProblem(rule); if (problem) return problem; }
  return null;
}
