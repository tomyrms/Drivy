import { describe, expect, it } from 'vitest';
import { billingMailConfig, classifyDeliveryError, decryptBillingMail, encryptBillingMail, maskEmail } from '../src/billing-mail.js';

/**
 * R01-T07 (#459) : file d'envoi des factures, sans base ni SMTP. Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic).
 * Clés, adresses et contenu synthétiques.
 */
const key = 'b2'.repeat(32);
const deliveryId = '6f1f0d8a-2a55-4b53-9d0e-6a4b6f7c1a01';
const payload = {
  email: 'marie@example.invalid', subject: 'Facture F-2026-00001', text: 'Bonjour,', fileName: 'facture-F-2026-00001.pdf',
  pdf: Buffer.from('%PDF-contenu-synthétique').toString('base64'),
};

describe('chiffrement de la file', () => {
  it('rend le contenu d’origine, sans rien laisser en clair', () => {
    const encrypted = encryptBillingMail(deliveryId, payload, key);
    expect(decryptBillingMail(deliveryId, encrypted, key)).toEqual(payload);
    expect(encrypted.toString('latin1')).not.toContain('marie');
    expect(encrypted.toString('latin1')).not.toContain('F-2026-00001');
  });

  it('chaque chiffrement est différent', () => {
    expect(encryptBillingMail(deliveryId, payload, key).equals(encryptBillingMail(deliveryId, payload, key))).toBe(false);
  });

  it('refuse un autre envoi, une autre clé ou un contenu altéré', () => {
    const encrypted = encryptBillingMail(deliveryId, payload, key);
    expect(() => decryptBillingMail('6f1f0d8a-2a55-4b53-9d0e-6a4b6f7c1a02', encrypted, key)).toThrow();
    expect(() => decryptBillingMail(deliveryId, encrypted, 'c3'.repeat(32))).toThrow();
    const altered = Buffer.from(encrypted);
    altered[altered.length - 1] = altered[altered.length - 1]! ^ 1;
    expect(() => decryptBillingMail(deliveryId, altered, key)).toThrow();
  });

  it('refuse un nom de fichier qui sortirait du format attendu', () => {
    const encrypted = encryptBillingMail(deliveryId, { ...payload, fileName: '../facture.pdf' }, key);
    expect(() => decryptBillingMail(deliveryId, encrypted, key)).toThrow();
  });
});

describe('adresse affichée', () => {
  it('masque la partie locale', () => {
    expect(maskEmail('marie@example.invalid')).toBe('ma***@example.invalid');
    expect(maskEmail('m@example.invalid')).toBe('m***@example.invalid');
  });
});

describe('classement des erreurs d’envoi', () => {
  it.each([
    ['refus temporaire', { responseCode: 451 }, 'RETRY', 'SMTP_TEMPORARY'],
    ['refus définitif', { responseCode: 550 }, 'FAILED', 'SMTP_REJECTED'],
    ['DNS', { code: 'EDNS' }, 'RETRY', 'SMTP_UNREACHABLE'],
    ['TLS', { code: 'ETLS' }, 'RETRY', 'SMTP_UNREACHABLE'],
    ['authentification', { code: 'EAUTH' }, 'RETRY', 'SMTP_UNREACHABLE'],
    ['coupure de connexion', { code: 'ECONNECTION' }, 'UNCERTAIN', 'SMTP_UNCERTAIN'],
    ['socket', { code: 'ESOCKET' }, 'UNCERTAIN', 'SMTP_UNCERTAIN'],
    ['délai', { code: 'ETIMEDOUT' }, 'UNCERTAIN', 'SMTP_UNCERTAIN'],
    ['réponse inattendue', { responseCode: 354 }, 'UNCERTAIN', 'SMTP_UNCERTAIN'],
    ['erreur inconnue', new Error('inconnue'), 'UNCERTAIN', 'SMTP_UNCERTAIN'],
    ['rien', null, 'UNCERTAIN', 'SMTP_UNCERTAIN'],
  ])('%s', (_label, error, outcome, code) => {
    expect(classifyDeliveryError(error)).toEqual({ outcome, code });
  });
});

describe('configuration', () => {
  const env = { BILLING_OUTBOX_KEY: key, SMTP_HOST: '127.0.0.1', SMTP_FROM: 'factures@example.invalid' } as NodeJS.ProcessEnv;

  it('sans clé de file, aucun envoi n’est configuré', () => {
    expect(billingMailConfig({ SMTP_HOST: '127.0.0.1' } as NodeJS.ProcessEnv)).toBeUndefined();
  });

  it('lit la configuration ; TLS exigé hors boucle locale et en production', () => {
    expect(billingMailConfig(env)).toMatchObject({ encryptionKey: key, host: '127.0.0.1', port: 587, secure: false, from: 'factures@example.invalid', requireTLS: false });
    expect(billingMailConfig({ ...env, SMTP_HOST: 'smtp.example.invalid' } as NodeJS.ProcessEnv)?.requireTLS).toBe(true);
    expect(billingMailConfig({ ...env, NODE_ENV: 'production' } as NodeJS.ProcessEnv)?.requireTLS).toBe(true);
    expect(billingMailConfig({ ...env, BILLING_MAIL_FROM: 'compta@example.invalid' } as NodeJS.ProcessEnv)?.from).toBe('compta@example.invalid');
  });

  it('refuse une clé malformée ou un identifiant SMTP sans son secret', () => {
    expect(() => billingMailConfig({ ...env, BILLING_OUTBOX_KEY: 'courte' } as NodeJS.ProcessEnv)).toThrow();
    expect(() => billingMailConfig({ ...env, SMTP_USER: 'factures' } as NodeJS.ProcessEnv)).toThrow();
  });
});
