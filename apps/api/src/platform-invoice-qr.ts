import { SwissQRBill } from 'swissqrbill/pdf';
import type { Data } from 'swissqrbill/types';
import { calculateQRReferenceChecksum, calculateSCORReferenceChecksum, isIBANValid, isQRIBAN } from 'swissqrbill/utils';

/**
 * Section de paiement QR suisse d'une facture émise (R01-T07, #459). Module pur, miroir des contrôles de la migration 20261119.
 * Règles : directives SIX QR-facture v2.4 (adresses structurées, compte CH/LI, couple QR-IBAN/QRR ou IBAN/SCOR, montant identique à la facture).
 * Tout vient de l'instantané figé à l'émission ; rien n'est relu des paramètres courants.
 */

export const paymentModes = ['QR', 'NONE'] as const;
export type PaymentMode = (typeof paymentModes)[number];
export const referenceTypes = ['QRR', 'SCOR'] as const;
export type ReferenceType = (typeof referenceTypes)[number];
export type QrProblemCode = 'PAYMENT_ACCOUNT' | 'ISSUER_ADDRESS' | 'RECIPIENT_ADDRESS' | 'AMOUNT';
export interface QrProblem { code: QrProblemCode; message: string }

const fixedAfterIssue = 'Cette facture est déjà émise : émettez un avoir, corrigez, puis émettez une nouvelle facture.';
const problemMessages: Record<QrProblemCode, string> = {
  PAYMENT_ACCOUNT: `L’IBAN de cette facture n’est pas un compte suisse ou liechtensteinois valide. ${fixedAfterIssue}`,
  ISSUER_ADDRESS: `L’adresse ou le titulaire de l’émetteur ne respecte pas le format de la QR-facture. ${fixedAfterIssue}`,
  RECIPIENT_ADDRESS: `L’adresse de l’école ne respecte pas le format de la QR-facture. ${fixedAfterIssue}`,
  AMOUNT: 'Le montant de cette facture ne permet pas un ordre de paiement.',
};
const problem = (code: QrProblemCode): QrProblem => ({ code, message: problemMessages[code] });

// --- Texte -----------------------------------------------------------------------------------------------------------------------

/** Remplace la typographie courante par son équivalent autorisé, replie les blancs. Même règle que `drivy.platform_qr_text`. */
export function qrText(value: string): string {
  return value.normalize('NFC').replace(/[\u2019\u2018]/g, '\'').replace(/[\u201C\u201D]/g, '"').replace(/[\u2013\u2014]/g, '-')
    .replace(/\u00A0/g, ' ').replace(/\s+/g, ' ').trim();
}
/** Intersection du jeu des directives et de WinAnsi, seul codage de la police PDF standard. */
const allowed = /^[\u0020-\u007E\u00A0-\u00FF\u0152\u0153\u0160\u0161\u0178\u017D\u017E\u20AC]*$/;
export const qrFieldOk = (value: string | null | undefined, max: number): value is string =>
  typeof value === 'string' && value.length >= 1 && value.length <= max && allowed.test(value);
const textOk = (value: string | null | undefined, max: number) => typeof value === 'string' && qrFieldOk(qrText(value), max);
/** Le NPA s'écrit sans préfixe de pays. */
const postalOk = (value: string | null | undefined) => typeof value === 'string' && textOk(value, 16) && !/^[A-Za-z]{1,2}-/.test(qrText(value));
/** Hors du jeu de la police : remplacé plutôt que de produire un PDF illisible (documents sans ordre de paiement uniquement). */
export const pdfText = (value: string) => [...qrText(value)].map(char => (allowed.test(char) ? char : '?')).join('');

// --- Pays ------------------------------------------------------------------------------------------------------------------------

const isoCountries = new Set('AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW'.split(' '));
const countryNames: Record<string, string> = {
  suisse: 'CH', schweiz: 'CH', svizzera: 'CH', svizra: 'CH', switzerland: 'CH', liechtenstein: 'LI', france: 'FR',
  allemagne: 'DE', deutschland: 'DE', germany: 'DE', italie: 'IT', italia: 'IT', italy: 'IT', autriche: 'AT', 'österreich': 'AT', austria: 'AT',
};
/** Pays d'une adresse (texte libre sur la fiche) : code ISO ou nom courant. `null` si inconnu, jamais deviné. Même règle que `drivy.platform_billing_country`. */
export function billingCountry(value: string | null | undefined): string | null {
  const text = (value ?? '').trim();
  if (isoCountries.has(text.toUpperCase())) return text.toUpperCase();
  return countryNames[text.toLowerCase()] ?? null;
}

// --- Compte et référence ---------------------------------------------------------------------------------------------------------

export const qrAccountOk = (iban: string | null | undefined): iban is string =>
  typeof iban === 'string' && /^(CH|LI)[0-9]{7}[A-Z0-9]{12}$/.test(iban) && isIBANValid(iban);

/**
 * Référence d'une facture, dérivée de son numéro : stable, identique à chaque rendu. QR-IBAN : QRR (27 chiffres). IBAN ordinaire : SCOR (ISO 11649).
 * Aucun QR-IBAN n'est supposé : le type de compte saisi décide.
 */
export function invoiceReference(iban: string, number: string): { type: ReferenceType; value: string } | null {
  if (isQRIBAN(iban)) {
    const digits = number.replace(/\D/g, '');
    if (!digits || digits.length > 26) return null;
    const body = digits.padStart(26, '0');
    return { type: 'QRR', value: body + calculateQRReferenceChecksum(body) };
  }
  const body = number.replace(/[^A-Z0-9]/g, '');
  if (body.length < 1 || body.length > 21) return null;
  return { type: 'SCOR', value: `RF${calculateSCORReferenceChecksum(body)}${body}` };
}

// --- Plan de paiement ------------------------------------------------------------------------------------------------------------

/** Instantané de la facture : ce qui a été figé à l'émission. */
export interface PaymentSnapshot {
  number: string | null;
  total: number | null;
  issuer: Record<string, string | null> | null;
  recipient: Record<string, string | null> | null;
}
export interface PaymentPlan { data: Data; referenceType: ReferenceType; reference: string; amount: number }
export type PaymentPlanResult = { ok: true; plan: PaymentPlan } | { ok: false; problems: QrProblem[] };

/** Contrôle l'instantané puis bâtit les données du QR. Le constructeur de la section est la dernière barrière : il valide tout selon les directives. */
export function paymentPlan(snapshot: PaymentSnapshot): PaymentPlanResult {
  const { issuer, recipient, total, number } = snapshot;
  const problems: QrProblem[] = [];
  if (!number || total === null || !Number.isInteger(total) || total < 1 || total > 99_999_999_999) problems.push(problem('AMOUNT'));
  const iban = issuer?.iban ?? null;
  if (!qrAccountOk(iban)) problems.push(problem('PAYMENT_ACCOUNT'));
  const holder = issuer?.accountHolder ?? issuer?.legalName ?? null;
  const creditorCountry = billingCountry(issuer?.country);
  const building = issuer?.buildingNumber ?? null;
  if (!textOk(holder, 70) || !textOk(issuer?.street, 70) || (building !== null && !textOk(building, 16)) || !postalOk(issuer?.postalCode)
    || !textOk(issuer?.city, 35) || !creditorCountry) problems.push(problem('ISSUER_ADDRESS'));
  const debtorCountry = billingCountry(recipient?.country);
  if (!textOk(recipient?.name, 70) || !textOk(recipient?.street, 70) || !postalOk(recipient?.postalCode) || !textOk(recipient?.city, 35)
    || !debtorCountry) problems.push(problem('RECIPIENT_ADDRESS'));
  if (problems.length) return { ok: false, problems };

  const reference = invoiceReference(iban!, number!);
  if (!reference) return { ok: false, problems: [problem('AMOUNT')] };
  const data: Data = {
    amount: total! / 100, currency: 'CHF', reference: reference.value, message: `Facture ${number!}`,
    creditor: {
      account: iban!, name: qrText(holder!), address: qrText(issuer!.street!), zip: qrText(issuer!.postalCode!), city: qrText(issuer!.city!),
      country: creditorCountry!, ...(building ? { buildingNumber: qrText(building) } : {}),
    },
    debtor: {
      name: qrText(recipient!.name!), address: qrText(recipient!.street!), zip: qrText(recipient!.postalCode!), city: qrText(recipient!.city!), country: debtorCountry!,
    },
  };
  try {
    new SwissQRBill(data, { language: 'FR' });
  } catch {
    return { ok: false, problems: [problem('PAYMENT_ACCOUNT')] };
  }
  return { ok: true, plan: { data, referenceType: reference.type, reference: reference.value, amount: total! } };
}

/**
 * Mode du document à rendre. Un avoir, une facture à zéro ou créditée ne portent aucun ordre de paiement. Un QR déjà rendu reste le document de la
 * facture. Sinon, un règlement déjà affecté interdit un QR au montant total : il demanderait de payer deux fois.
 */
export function documentMode(row: {
  kind: string; total: number | null; credit_note: unknown; settlement: { allocated: number } | null;
}, documents: readonly { payment_mode: PaymentMode }[]): PaymentMode {
  if (row.kind === 'CREDIT_NOTE' || row.credit_note || (row.total ?? 0) === 0) return 'NONE';
  if (documents.some(item => item.payment_mode === 'QR')) return 'QR';
  return (row.settlement?.allocated ?? 0) > 0 ? 'NONE' : 'QR';
}
