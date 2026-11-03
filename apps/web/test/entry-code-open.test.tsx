import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { PortalEntryPage } from '../client/portal/entry/entry-page';
import { SchoolsPending } from '../client/portal/entry/schools-view';
import type { EntrySessionState } from '../client/portal/entry/use-entry-session';
import { codeFieldError, singleFlight } from '../client/portal/entry/entry-model';

/** Rendu du premier affichage : aucune lecture de /me ni de la liste des écoles n'a encore répondu (effets non lancés). */
const firstPaint = renderToStaticMarkup(<PortalEntryPage invitationLink={{ token: null, error: false }} page="account" />);

describe('« J’ai un code » avant la réponse de /me et de la liste des écoles (#120)', () => {
  it('propose « J’ai un code » actif dès le premier affichage, sans attendre la session', () => {
    const button = /<button[^>]*>(?:(?!<\/button>).)*J’ai un code<\/button>/s.exec(firstPaint)?.[0];
    expect(button).toBeDefined();
    expect(button).not.toMatch(/disabled/);
  });

  it('n’affiche aucun état authentifié ni école avant la preuve du serveur', () => {
    expect(firstPaint).not.toContain('Vos écoles');
    expect(firstPaint).not.toContain('Ouvrir l’école');
    expect(firstPaint).not.toContain('entry-account');
  });

  it('remplace le formulaire de connexion par un repère de chargement tant que la session est inconnue', () => {
    expect(firstPaint).not.toContain('type="password"');
    expect(firstPaint).toContain('aria-busy="true"');
  });
});

describe('session connue, /me et la liste des écoles en attente', () => {
  const pending = renderToStaticMarkup(<SchoolsPending state={{ typedCode: { value: 'ABCD-1234', set: () => undefined }, signedIn: () => undefined } as unknown as EntrySessionState} />);
  it('affiche le champ du code actif, avec la saisie déjà faite', () => {
    const field = /<input[^>]*name="code"[^>]*>/.exec(pending)?.[0];
    expect(field).toBeDefined();
    expect(field).toContain('value="ABCD-1234"');
    expect(field).not.toMatch(/ (readonly|disabled)(=|\s|\/)/i);
    expect(pending).toMatch(/<button[^>]*aria-disabled="false"[^>]*>Continuer<\/button>/);
  });
});

describe('erreur du code rattachée au champ', () => {
  it('montre le problème de saisie avant l’erreur du serveur', () => {
    expect(codeFieldError('Saisissez le code.', 'Ce code n’est pas valide.')).toBe('Saisissez le code.');
    expect(codeFieldError(null, 'Ce code n’est pas valide.')).toBe('Ce code n’est pas valide.');
    expect(codeFieldError(null, null)).toBeUndefined();
  });
});

describe('un seul envoi du code', () => {
  it('ignore un second envoi tant que le premier n’a pas répondu, puis accepte un nouvel envoi', async () => {
    const flight = singleFlight();
    let sent = 0;
    let release!: () => void;
    const gate = new Promise<void>(resolve => { release = resolve; });
    const first = flight(async () => { sent++; await gate; });
    const second = flight(async () => { sent++; });
    release();
    await Promise.all([first, second]);
    expect(sent).toBe(1);
    await flight(async () => { sent++; });
    expect(sent).toBe(2);
  });

  it('libère le verrou quand la réponse est perdue, sans relancer l’envoi tout seul', async () => {
    const flight = singleFlight();
    let sent = 0;
    await flight(async () => { sent++; throw new Error('NETWORK_UNAVAILABLE'); }).catch(() => undefined);
    expect(sent).toBe(1);
    await flight(async () => { sent++; });
    expect(sent).toBe(2);
  });
});
