import { describe, expect, it } from 'vitest';
import { ApiError } from '../src/errors.js';
import { ciphertextSha256, mediaBodyLimit, mediaId, mediaMaxBytes, mediaSize, mediaStates } from '../src/messaging-media.js';

const rejectsInvalidMedia = (error: unknown) => error instanceof ApiError && error.status === 400 && error.code === 'INVALID_MEDIA';

describe('contrat de validation des médias, sans contenu ni identifiant de diagnostic', () => {
  it('borne la taille d’une pièce jointe à 4 Mio et le corps de la route à 4 Mio plus une marge d’en-têtes', () => {
    expect(mediaMaxBytes).toBe(4_194_304);
    expect(mediaBodyLimit).toBe(4_194_304 + 8_192);
    expect(mediaSize(1)).toBe(1);
    expect(mediaSize(mediaMaxBytes)).toBe(mediaMaxBytes);
    expect(() => mediaSize(0)).toThrow();
    expect(() => mediaSize(mediaMaxBytes + 1)).toThrow();
    expect(() => mediaSize(1.5)).toThrow();
    expect(() => mediaSize(Number.NaN)).toThrow();
    try { mediaSize(0); } catch (error) { expect(rejectsInvalidMedia(error)).toBe(true); }
  });

  it('normalise un identifiant média et refuse tout ce qui n’est pas un UUID', () => {
    expect(mediaId('5C1F0000-0000-4000-8000-000000000001')).toBe('5c1f0000-0000-4000-8000-000000000001');
    expect(() => mediaId('5c1f')).toThrow();
    expect(() => mediaId('')).toThrow();
    try { mediaId('pas-un-uuid'); } catch (error) { expect(rejectsInvalidMedia(error)).toBe(true); }
  });

  it('calcule le SHA-256 du chiffré seulement, jamais un hash du clair', () => {
    expect(ciphertextSha256(Buffer.from('abc'))).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(ciphertextSha256(Buffer.alloc(0))).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(ciphertextSha256(Buffer.from('abc'))).toMatch(/^[0-9a-f]{64}$/);
  });

  it('n’expose que les trois états dérivés de colonnes', () => {
    expect(mediaStates).toEqual(['UPLOADED', 'ATTACHED', 'PURGED']);
  });
});
