import { describe, expect, it } from 'vitest';
import { SwissQRBill } from 'swissqrbill/pdf';
import { isQRReferenceValid, isSCORReferenceValid } from 'swissqrbill/utils';
import { invoiceFileName, invoiceMailContent, pdfAmount, renderInvoicePdf, type InvoicePdfModel } from '../src/platform-invoice-pdf.js';
import {
  billingCountry, documentMode, invoiceReference, paymentPlan, pdfText, qrAccountOk, qrFieldOk, qrText, type PaymentSnapshot, type QrProblemCode,
} from '../src/platform-invoice-qr.js';

/**
 * R01-T07 (#459) : section de paiement et document, sans base. Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic).
 * Identités synthétiques ; comptes et références : exemples publiés. Le décodage du QR imprimé reste à qualifier sur un vrai lecteur.
 */
const iban = 'CH9300762011623852957';
const qrIban = 'CH4431999123000889012';
const issuer: Record<string, string | null> = {
  legalName: 'Drivy Exemple Sàrl', accountHolder: null, street: 'Rue de l’Exemple', buildingNumber: '1', postalCode: '1000', city: 'Lausanne', country: 'CH', iban,
};
const recipient: Record<string, string | null> = { name: 'Auto-école des Lilas', street: 'Rue des Lilas 2', postalCode: '1200', city: 'Genève', country: 'CH' };
const snapshot = (patch: Partial<PaymentSnapshot> = {}): PaymentSnapshot => ({ number: 'F-2026-00001', total: 40_000, issuer, recipient, ...patch });
const codes = (input: PaymentSnapshot): QrProblemCode[] => {
  const result = paymentPlan(input);
  return result.ok ? [] : result.problems.map(item => item.code);
};
function planOf(input: PaymentSnapshot) {
  const result = paymentPlan(input);
  if (!result.ok) throw new Error(result.problems.map(item => item.code).join(','));
  return result.plan;
}

describe('texte et pays', () => {
  it('ramène la typographie courante au jeu autorisé et replie les blancs', () => {
    const space = String.fromCodePoint(0xA0);
    expect(qrText(`  Rue de l’Exemple${space} – 1  `)).toBe('Rue de l\'Exemple - 1');
    expect(pdfText('Auto-école 東京')).toBe('Auto-école ??');
  });

  it('borne chaque champ et refuse ce que la police ne sait pas imprimer', () => {
    expect(qrFieldOk('Genève', 35)).toBe(true);
    expect(qrFieldOk('', 35)).toBe(false);
    expect(qrFieldOk('x'.repeat(36), 35)).toBe(false);
    expect(qrFieldOk('東京', 35)).toBe(false);
    expect(qrFieldOk(null, 35)).toBe(false);
  });

  it('un pays se lit en code ou nom courant, jamais deviné', () => {
    expect(billingCountry('ch')).toBe('CH');
    expect(billingCountry(' Suisse ')).toBe('CH');
    expect(billingCountry('Liechtenstein')).toBe('LI');
    expect(billingCountry('Narnia')).toBeNull();
    expect(billingCountry(null)).toBeNull();
  });
});

describe('compte et référence', () => {
  it('seul un compte CH ou LI à la clé valide est accepté', () => {
    expect(qrAccountOk(iban)).toBe(true);
    expect(qrAccountOk(qrIban)).toBe(true);
    expect(qrAccountOk('CH9300762011623852958')).toBe(false);
    expect(qrAccountOk('DE89370400440532013000')).toBe(false);
    expect(qrAccountOk('CH93 0076 2011 6238 5295 7')).toBe(false);
    expect(qrAccountOk(null)).toBe(false);
  });

  it('les exemples publiés servent de repère aux contrôles de référence', () => {
    expect(isQRReferenceValid('210000000003139471430009017')).toBe(true);
    expect(isSCORReferenceValid('RF18539007547034')).toBe(true);
  });

  it('IBAN ordinaire : SCOR ; QR-IBAN : QRR ; la référence est stable et dérivée du numéro', () => {
    const scor = invoiceReference(iban, 'F-2026-00001');
    expect(scor?.type).toBe('SCOR');
    expect(scor?.value.endsWith('F202600001')).toBe(true);
    expect(isSCORReferenceValid(scor!.value)).toBe(true);
    expect(invoiceReference(iban, 'F-2026-00001')).toEqual(scor);

    const qrr = invoiceReference(qrIban, 'F-2026-00001');
    expect(qrr?.type).toBe('QRR');
    expect(qrr?.value).toHaveLength(27);
    expect(isQRReferenceValid(qrr!.value)).toBe(true);
    expect(invoiceReference(qrIban, 'F-2026-00002')?.value).not.toBe(qrr?.value);
  });

  it('un numéro inutilisable ne produit aucune référence', () => {
    expect(invoiceReference(qrIban, 'SANS-CHIFFRE')).toBeNull();
    expect(invoiceReference(qrIban, '1'.repeat(27))).toBeNull();
    expect(invoiceReference(iban, 'a-b')).toBeNull();
    expect(invoiceReference(iban, 'A'.repeat(22))).toBeNull();
  });

  it('la section refuse un couple compte et référence incohérent', () => {
    const { data } = planOf(snapshot());
    expect(() => new SwissQRBill({ ...data, creditor: { ...data.creditor, account: qrIban } })).toThrow();
    expect(() => new SwissQRBill({ ...data, reference: '210000000003139471430009017' })).toThrow();
  });
});

describe('plan de paiement', () => {
  it('reprend exactement le montant, la référence et les adresses de l’instantané', () => {
    const plan = planOf(snapshot({ total: 12_345 }));
    expect(plan).toMatchObject({ referenceType: 'SCOR', amount: 12_345 });
    expect(plan.data).toMatchObject({
      amount: 123.45, currency: 'CHF', reference: plan.reference, message: 'Facture F-2026-00001',
      creditor: { account: iban, name: 'Drivy Exemple Sàrl', address: 'Rue de l\'Exemple', buildingNumber: '1', zip: '1000', city: 'Lausanne', country: 'CH' },
      debtor: { name: 'Auto-école des Lilas', address: 'Rue des Lilas 2', zip: '1200', city: 'Genève', country: 'CH' },
    });
  });

  it('le créancier est le titulaire du compte, s’il est distinct', () => {
    expect(planOf(snapshot({ issuer: { ...issuer, accountHolder: 'Camille Exemple' } })).data.creditor.name).toBe('Camille Exemple');
  });

  it('un QR-IBAN donne une référence QRR, sans autre réglage', () => {
    const plan = planOf(snapshot({ issuer: { ...issuer, iban: qrIban } }));
    expect(plan.referenceType).toBe('QRR');
    expect(isQRReferenceValid(plan.reference)).toBe(true);
  });

  it.each<[string, Partial<PaymentSnapshot>, QrProblemCode]>([
    ['sans compte', { issuer: { ...issuer, iban: null } }, 'PAYMENT_ACCOUNT'],
    ['clé fausse', { issuer: { ...issuer, iban: 'CH9300762011623852958' } }, 'PAYMENT_ACCOUNT'],
    ['compte étranger', { issuer: { ...issuer, iban: 'DE89370400440532013000' } }, 'PAYMENT_ACCOUNT'],
    ['NPA émetteur préfixé', { issuer: { ...issuer, postalCode: 'CH-1000' } }, 'ISSUER_ADDRESS'],
    ['titulaire trop long', { issuer: { ...issuer, accountHolder: 'x'.repeat(71) } }, 'ISSUER_ADDRESS'],
    ['numéro trop long', { issuer: { ...issuer, buildingNumber: '1'.repeat(17) } }, 'ISSUER_ADDRESS'],
    ['pays émetteur inconnu', { issuer: { ...issuer, country: 'Narnia' } }, 'ISSUER_ADDRESS'],
    ['destinataire absent', { recipient: null }, 'RECIPIENT_ADDRESS'],
    ['NPA école préfixé', { recipient: { ...recipient, postalCode: 'CH-1200' } }, 'RECIPIENT_ADDRESS'],
    ['ville hors du jeu', { recipient: { ...recipient, city: '東京' } }, 'RECIPIENT_ADDRESS'],
    ['pays école inconnu', { recipient: { ...recipient, country: 'Narnia' } }, 'RECIPIENT_ADDRESS'],
    ['montant nul', { total: 0 }, 'AMOUNT'],
    ['montant absent', { total: null }, 'AMOUNT'],
    ['montant trop élevé', { total: 100_000_000_000 }, 'AMOUNT'],
    ['sans numéro', { number: null }, 'AMOUNT'],
  ])('refuse : %s', (_label, patch, code) => {
    expect(codes(snapshot(patch))).toContain(code);
  });
});

describe('mode du document', () => {
  const invoice = { kind: 'INITIAL', total: 40_000, credit_note: null, settlement: { allocated: 0 } };

  it('une facture à payer porte un QR', () => { expect(documentMode(invoice, [])).toBe('QR'); });
  it('un avoir, une facture à zéro ou créditée n’en portent pas', () => {
    expect(documentMode({ ...invoice, kind: 'CREDIT_NOTE', settlement: null }, [])).toBe('NONE');
    expect(documentMode({ ...invoice, total: 0 }, [])).toBe('NONE');
    expect(documentMode({ ...invoice, credit_note: { id: 'avoir' } }, [{ payment_mode: 'QR' }])).toBe('NONE');
  });
  it('un règlement affecté interdit un nouveau QR au montant total, le QR déjà rendu reste le document', () => {
    expect(documentMode({ ...invoice, settlement: { allocated: 100 } }, [])).toBe('NONE');
    expect(documentMode({ ...invoice, settlement: { allocated: 100 } }, [{ payment_mode: 'QR' }])).toBe('QR');
  });
});

describe('document et courriel', () => {
  const model = (patch: Partial<InvoicePdfModel> = {}): InvoicePdfModel => ({
    kind: 'INITIAL', number: 'F-2026-00001', creditedNumber: null, issuedOn: '2026-11-19', issuedAt: '2026-11-19T10:00:00.000Z', dueOn: '2026-12-19', period: null,
    issuer, recipient, lines: [{ label: 'Montant initial', periodStart: null, periodEnd: null, amount: 50_000, discount: 10_000, net: 40_000 }],
    subtotal: 50_000, discountTotal: 10_000, netTotal: 40_000, tax: { mode: 'NONE', rateBp: null, pricesIncludeTax: null, amount: 0 }, total: 40_000, payment: null, ...patch,
  });
  const pages = (pdf: Buffer) => pdf.toString('latin1').match(/\/Type \/Page\b/g)?.length ?? 0;

  it('formate les montants et nomme le fichier', () => {
    expect(pdfAmount(1_234_567)).toBe('12 345.67');
    expect(pdfAmount(-5)).toBe('-0.05');
    expect(invoiceFileName('INITIAL', 'F-2026-00001')).toBe('facture-F-2026-00001.pdf');
    expect(invoiceFileName('CREDIT_NOTE', 'AV-2026-00001')).toBe('avoir-AV-2026-00001.pdf');
  });

  it('le courriel ne répète aucune donnée de paiement et ne demande rien sur un avoir', () => {
    const invoiceMail = invoiceMailContent({ kind: 'INITIAL', number: 'F-2026-00001', creditedNumber: null, total: 40_000, dueOn: '2026-12-19', issuerName: 'Drivy Exemple Sàrl', mode: 'QR' });
    expect(invoiceMail.subject).toBe('Facture F-2026-00001');
    expect(invoiceMail.text).toContain('CHF 400.00');
    expect(invoiceMail.text).toContain('19.12.2026');
    expect(invoiceMail.text).not.toContain(iban);
    const creditMail = invoiceMailContent({ kind: 'CREDIT_NOTE', number: 'AV-2026-00001', creditedNumber: 'F-2026-00001', total: 40_000, dueOn: null, issuerName: 'Drivy Exemple Sàrl', mode: 'NONE' });
    expect(creditMail.subject).toBe('Avoir AV-2026-00001');
    expect(creditMail.text).toContain('aucun paiement');
  });

  it('produit un PDF avec ou sans section de paiement', async () => {
    const plain = await renderInvoicePdf(model());
    const withQr = await renderInvoicePdf(model({ payment: planOf(snapshot()).data }));
    expect(plain.subarray(0, 5).toString()).toBe('%PDF-');
    expect(withQr.subarray(0, 5).toString()).toBe('%PDF-');
    expect(withQr.byteLength).toBeGreaterThan(plain.byteLength);
  });

  it('une longue facture passe à la page suivante au lieu de chevaucher la section', async () => {
    const line = { label: 'Période', periodStart: '2026-11-01', periodEnd: '2026-11-30', amount: 100, discount: 0, net: 100 };
    const pdf = await renderInvoicePdf(model({ lines: Array.from({ length: 60 }, () => line), payment: planOf(snapshot()).data }));
    expect(pages(pdf)).toBeGreaterThan(1);
  });
});
