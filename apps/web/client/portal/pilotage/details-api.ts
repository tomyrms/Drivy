import { z } from 'zod';
import { RequestFailure } from '../../protocol';
import { readSchool } from '../../school-api';
import { exportFileName } from './detail-model';
import { filterQuery, type MetricFilters } from './metrics-api';
import { detailsSchema, type DetailsAnswer } from './metrics-schemas';

export type { DetailLineRecord, DetailsAnswer } from './metrics-schemas';

/**
 * Lignes d'une mesure et export CSV (#373, T07 #380). Le web montre ce que le serveur liste et renvoie les valeurs lues sur la carte
 * pour qu'un écart soit signalé ; il ne recompte rien et ne fabrique aucun fichier : le CSV est celui du serveur, octet pour octet.
 */

export interface DetailRequest extends MetricFilters { measure: string; part?: 'a' | 'b' | undefined; from: string; toExclusive: string }
export interface ExpectedFromCard { lineCount?: number; amountCents?: number }

/** Une page de lignes. Le curseur est lié par le serveur à la personne, à la mesure, à la période et aux filtres. */
export async function readDetails(schoolId: string, request: DetailRequest, cursor: string | null, expected: ExpectedFromCard): Promise<DetailsAnswer> {
  const answer = await readSchool(schoolId, 'metrics/details', detailsSchema, {
    measure: request.measure, from: request.from, toExclusive: request.toExclusive, limit: '50', ...filterQuery(request),
    ...(request.part ? { part: request.part } : {}),
    ...(cursor ? { cursor } : {}),
    ...(expected.lineCount === undefined ? {} : { expectedLineCount: String(expected.lineCount) }),
    ...(expected.amountCents === undefined ? {} : { expectedAmountCents: String(expected.amountCents) }),
  });
  if (answer.schoolId !== schoolId || answer.measure !== request.measure || answer.period.from !== request.from || answer.period.toExclusive !== request.toExclusive) {
    throw new RequestFailure('INVALID_RESPONSE');
  }
  return answer;
}

/** Corps de l'export : la même sélection que le détail affiché, jamais seulement la page vue. */
export function exportBody(request: DetailRequest, expected: ExpectedFromCard) {
  return {
    measure: request.measure, from: request.from, toExclusive: request.toExclusive,
    ...(request.part ? { part: request.part } : {}),
    ...(request.instructor ? { instructorMembershipId: request.instructor } : {}),
    ...(request.category ? { categoryCode: request.category } : {}),
    ...(request.product ? { productKey: request.product } : {}),
    ...(expected.lineCount === undefined ? {} : { expectedLineCount: expected.lineCount }),
    ...(expected.amountCents === undefined ? {} : { expectedAmountCents: expected.amountCents }),
  };
}

export type ExportOutcome = { ok: true; drift: boolean; fileName: string } | { ok: false; code: string };

/**
 * Télécharge le CSV du serveur. Les octets sont conservés tels quels (BOM compris) : le fichier est lu comme blob, jamais décodé puis réencodé.
 * Une réponse en erreur ne produit aucun fichier ; l'export synchrone n'est ni conservé ni accessible par une adresse réutilisable.
 */
export async function exportMeasure(schoolId: string, csrf: string, request: DetailRequest, expected: ExpectedFromCard): Promise<ExportOutcome> {
  let response: Response;
  try {
    response = await fetch(new URL(`/app/bff/schools/${schoolId}/metrics/exports`, window.location.origin), {
      method: 'POST', credentials: 'same-origin', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer',
      signal: AbortSignal.timeout(60_000),
      headers: { Accept: 'text/csv', 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
      body: JSON.stringify(exportBody(request, expected)),
    });
  } catch { return { ok: false, code: 'NETWORK_UNAVAILABLE' }; }
  if (!response.ok) {
    let code = response.status >= 500 ? 'SERVICE_UNAVAILABLE' : 'REQUEST_FAILED';
    try {
      const problem = z.object({ code: z.string().regex(/^[A-Z0-9_]{1,80}$/) }).safeParse(await response.json());
      if (problem.success) code = problem.data.code;
    } catch { /* La réponse n'est pas du JSON : le code générique reste. */ }
    return { ok: false, code };
  }
  if (response.headers.get('content-type')?.split(';')[0]?.trim() !== 'text/csv') return { ok: false, code: 'INVALID_RESPONSE' };
  const blob = await response.blob();
  const fileName = exportFileName(request.measure, request.part, request.from, request.toExclusive);
  const link = document.createElement('a');
  const url = URL.createObjectURL(blob);
  link.href = url; link.download = fileName; link.rel = 'noopener'; link.hidden = true;
  document.body.append(link); link.click(); link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
  return { ok: true, drift: response.headers.get('x-metrics-drift') === 'true', fileName };
}
