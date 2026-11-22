import PDFDocument from 'pdfkit';
import { SwissQRBill } from 'swissqrbill/pdf';
import type { Data } from 'swissqrbill/types';
import type { InvoiceKind } from './platform-billing-model.js';
import { billingCountry, pdfText, type PaymentMode } from './platform-invoice-qr.js';

/**
 * Rendu PDF d'une facture émise ou d'un avoir (R01-T07, #459) : A4, police standard, section de paiement en bas de page.
 * Tout vient de l'instantané figé. Le document produit est conservé : il n'est jamais rendu une seconde fois pour le même mode.
 */

export const invoicePdfGenerator = 'drivy-invoice-pdf/1';

export interface InvoicePdfLine { label: string; periodStart: string | null; periodEnd: string | null; amount: number; discount: number; net: number }
export interface InvoicePdfModel {
  kind: InvoiceKind;
  number: string;
  creditedNumber: string | null;
  issuedOn: string;
  issuedAt: string | null;
  dueOn: string | null;
  period: { startsOn: string; endsOn: string } | null;
  issuer: Record<string, string | null>;
  recipient: Record<string, string | null>;
  lines: readonly InvoicePdfLine[];
  subtotal: number;
  discountTotal: number;
  netTotal: number;
  tax: { mode: 'NONE' | 'VAT'; rateBp: number | null; pricesIncludeTax: boolean | null; amount: number } | null;
  total: number;
  /** Données de la section QR ; `null` : aucun ordre de paiement. */
  payment: Data | null;
}

const left = 50;
const right = 545;
/** Haut de la section de paiement : 105 mm avant le bas d'une page A4. */
const paymentTop = 841.89 - SwissQRBill.height;
const pageOptions = { size: 'A4' as const, margins: { top: 50, left, right: 50, bottom: 0 } };

export const pdfDay = (value: string) => { const [year, month, date] = value.split('-'); return `${date}.${month}.${year}`; };
export function pdfAmount(cents: number) {
  const whole = Math.trunc(Math.abs(cents) / 100).toString().replace(/\B(?=(\d{3})+$)/g, ' ');
  return `${cents < 0 ? '-' : ''}${whole}.${(Math.abs(cents) % 100).toString().padStart(2, '0')}`;
}
const rate = (bp: number) => `${(bp / 100).toFixed(2).replace(/\.?0+$/, '')} %`;

function addressLines(party: Record<string, string | null>, name: string | null) {
  const street = [party.street, party.buildingNumber].filter(Boolean).join(' ');
  const country = billingCountry(party.country) ?? party.country ?? '';
  return [name, party.contactName, street, `${party.postalCode ?? ''} ${party.city ?? ''}`.trim(), country]
    .filter((line): line is string => Boolean(line)).map(pdfText);
}

/** Nom du fichier joint ou téléchargé. */
export const invoiceFileName = (kind: InvoiceKind, number: string) => `${kind === 'CREDIT_NOTE' ? 'avoir' : 'facture'}-${number}.pdf`;

/** Objet et texte du courriel. Le montant et l'échéance sont ceux du document ; aucune donnée de paiement n'est répétée dans le message. */
export function invoiceMailContent(input: {
  kind: InvoiceKind; number: string; creditedNumber: string | null; total: number; dueOn: string | null; issuerName: string; mode: PaymentMode;
}) {
  const credit = input.kind === 'CREDIT_NOTE';
  const body = credit
    ? `Veuillez trouver ci-joint l’avoir ${input.number}${input.creditedNumber ? ` sur la facture ${input.creditedNumber}` : ''}. Il ne demande aucun paiement.`
    : input.mode === 'QR' && input.dueOn
      ? `Veuillez trouver ci-joint la facture ${input.number} de CHF ${pdfAmount(input.total)}, à régler jusqu’au ${pdfDay(input.dueOn)} au moyen de la section de paiement.`
      : `Veuillez trouver ci-joint la facture ${input.number} de CHF ${pdfAmount(input.total)}. Ce document ne comporte pas d’ordre de paiement.`;
  return { subject: `${credit ? 'Avoir' : 'Facture'} ${input.number}`, text: `Bonjour,\n\n${body}\n\nCordialement,\n${input.issuerName}` };
}

/** Rend le document en mémoire. Le résultat est un PDF complet ou une erreur : jamais un fichier partiel. */
export function renderInvoicePdf(model: InvoicePdfModel): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const credit = model.kind === 'CREDIT_NOTE';
    const title = `${credit ? 'Avoir' : 'Facture'} ${model.number}`;
    const doc = new PDFDocument({
      ...pageOptions, autoFirstPage: true, compress: true,
      info: {
        Title: pdfText(title), Author: pdfText(model.issuer.legalName ?? ''), Creator: 'Drivy', Producer: 'Drivy',
        ...(model.issuedAt ? { CreationDate: new Date(model.issuedAt) } : {}),
      },
    });
    const chunks: Buffer[] = [];
    doc.on('data', (chunk: Buffer) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
    try {
      draw(doc, model, title, credit);
      doc.end();
    } catch (error) {
      reject(error instanceof Error ? error : new Error('Rendu PDF impossible.'));
    }
  });
}

function draw(doc: PDFKit.PDFDocument, model: InvoicePdfModel, title: string, credit: boolean) {
  const limit = model.payment ? paymentTop - 12 : 800;
  const ensure = (needed: number, y: number) => {
    if (y + needed <= limit) return y;
    doc.addPage(pageOptions);
    return 50;
  };

  // Émetteur.
  doc.fillColor('#111111').font('Helvetica-Bold').fontSize(12).text(pdfText(model.issuer.legalName ?? ''), left, 50, { width: 260 });
  doc.font('Helvetica').fontSize(9);
  const issuerLines = addressLines({ ...model.issuer, contactName: null }, null);
  if (model.issuer.email) issuerLines.push(pdfText(model.issuer.email));
  if (model.issuer.vatNumber) issuerLines.push(pdfText(model.issuer.vatNumber));
  doc.text(issuerLines.join('\n'), left, doc.y + 2, { width: 260, lineGap: 1 });

  // Destinataire, à la place d'une fenêtre d'enveloppe à droite.
  doc.font('Helvetica-Bold').fontSize(10).text(pdfText(model.recipient.name ?? ''), 330, 120, { width: 215 });
  doc.font('Helvetica').fontSize(10).text(addressLines(model.recipient, null).slice(1).join('\n'), 330, doc.y + 1, { width: 215, lineGap: 1 });

  // Titre et dates.
  let y = Math.max(doc.y, 200) + 18;
  doc.font('Helvetica-Bold').fontSize(16).text(pdfText(title), left, y, { width: right - left });
  y = doc.y + 8;
  const facts: [string, string][] = [['Date', pdfDay(model.issuedOn)]];
  if (model.creditedNumber) facts.push(['Facture créditée', pdfText(model.creditedNumber)]);
  if (model.period) facts.push(['Période', `${pdfDay(model.period.startsOn)} au ${pdfDay(model.period.endsOn)}`]);
  if (!credit && model.dueOn) facts.push(['Échéance', pdfDay(model.dueOn)]);
  const factWidth = (right - left) / Math.max(facts.length, 3);
  facts.forEach(([label, value], index) => {
    const x = left + index * factWidth;
    doc.font('Helvetica').fontSize(8).fillColor('#555555').text(label, x, y, { width: factWidth - 6 });
    doc.font('Helvetica-Bold').fontSize(9.5).fillColor('#111111').text(value, x, y + 11, { width: factWidth - 6 });
  });
  y += 36;

  // Lignes.
  const columns = { label: left, amount: 345, discount: 415, net: 485 };
  const header = (top: number) => {
    doc.font('Helvetica-Bold').fontSize(8.5).fillColor('#111111');
    doc.text('Désignation', columns.label, top, { width: 285 });
    doc.text('Montant', columns.amount, top, { width: 60, align: 'right' });
    doc.text('Remise', columns.discount, top, { width: 60, align: 'right' });
    doc.text('Net CHF', columns.net, top, { width: 60, align: 'right' });
    doc.moveTo(left, top + 13).lineTo(right, top + 13).lineWidth(0.6).strokeColor('#111111').stroke();
    return top + 19;
  };
  y = header(y);
  for (const line of model.lines) {
    const label = pdfText(line.label);
    const dates = line.periodStart && line.periodEnd ? `${pdfDay(line.periodStart)} au ${pdfDay(line.periodEnd)}` : null;
    doc.font('Helvetica').fontSize(9.5);
    const height = doc.heightOfString(label, { width: 285 }) + (dates ? 11 : 0) + 6;
    const top = ensure(height, y);
    y = top === y ? y : header(top);
    doc.fillColor('#111111').text(label, columns.label, y, { width: 285 });
    if (dates) doc.fontSize(8).fillColor('#555555').text(dates, columns.label, doc.y, { width: 285 });
    doc.fontSize(9.5).fillColor('#111111');
    doc.text(pdfAmount(line.amount), columns.amount, y, { width: 60, align: 'right' });
    doc.text(line.discount ? `-${pdfAmount(line.discount)}` : '', columns.discount, y, { width: 60, align: 'right' });
    doc.text(pdfAmount(line.net), columns.net, y, { width: 60, align: 'right' });
    y += height;
  }

  // Totaux.
  const totals: [string, string][] = [];
  if (model.discountTotal > 0) {
    totals.push(['Sous-total', pdfAmount(model.subtotal)], ['Remises', `-${pdfAmount(model.discountTotal)}`]);
  }
  if (model.tax?.mode === 'VAT' && model.tax.rateBp !== null) {
    totals.push(['Total net', pdfAmount(model.netTotal)]);
    totals.push([`TVA ${rate(model.tax.rateBp)}${model.tax.pricesIncludeTax ? ' (incluse)' : ''}`, pdfAmount(model.tax.amount)]);
  }
  y = ensure(totals.length * 14 + 28, y + 4);
  doc.moveTo(330, y).lineTo(right, y).lineWidth(0.6).strokeColor('#111111').stroke();
  y += 6;
  for (const [label, value] of totals) {
    doc.font('Helvetica').fontSize(9.5).fillColor('#111111').text(label, 330, y, { width: 130 });
    doc.text(value, 460, y, { width: 85, align: 'right' });
    y += 14;
  }
  doc.font('Helvetica-Bold').fontSize(11).text(credit ? 'Total de l’avoir CHF' : 'Total CHF', 330, y + 2, { width: 130 });
  doc.text(pdfAmount(model.total), 460, y + 2, { width: 85, align: 'right' });
  y += 26;

  // Mentions.
  const notes: string[] = [];
  if (model.issuer.taxNote) notes.push(pdfText(model.issuer.taxNote));
  if (model.payment && model.dueOn) notes.push(`À payer jusqu’au ${pdfDay(model.dueOn)} au moyen de la section de paiement.`);
  if (!model.payment) notes.push('Ce document ne comporte pas d’ordre de paiement.');
  const noteText = notes.join('\n');
  doc.font('Helvetica').fontSize(9);
  y = ensure(doc.heightOfString(noteText, { width: right - left, lineGap: 1 }) + 4, y);
  doc.fillColor('#111111').text(noteText, left, y, { width: right - left, lineGap: 1 });

  if (model.payment) {
    if (doc.y > paymentTop - 2) doc.addPage(pageOptions);
    new SwissQRBill(model.payment, { language: 'FR' }).attachTo(doc);
  }
}
