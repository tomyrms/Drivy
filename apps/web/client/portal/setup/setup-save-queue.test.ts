import { describe, expect, test, vi } from 'vitest';
import { setupContentSchema, type SetupContent, type SetupStep } from '../../setup-model';
import { SetupSaveQueue, saveOutcome, type SetupSaveOutcome, type SetupSaveSend } from './setup-save-queue';

const content = (name = 'École synthétique', contactEmail = 'ecole@example.invalid'): SetupContent => setupContentSchema.parse({
  selectedSections: ['IDENTITY', 'PRIVACY', 'PROFILE'],
  identity: { name, contactEmail, contactPhone: null, timeZone: 'Europe/Zurich' },
  privacy: { noticeText: 'Texte propre à l’école.', retentionText: 'Conservation propre.', contactEmail: 'donnees@example.invalid', templateId: null, templateVersion: null },
  profile: { fields: [], effectiveFrom: null }, formations: [],
});
const draft = (value: SetupContent, currentStep: SetupStep = 'FORMATIONS') => ({ currentStep, content: value });
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
const deferred = <T,>() => { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; };

/** École synthétique : la version ne change que si `If-Match` correspond, comme le serveur. */
function harness() {
  const state = { version: 1, content: content(), step: 'IDENTITY' as SetupStep };
  const send = vi.fn<SetupSaveSend>(async request => {
    if (request.ifMatch !== state.version) return { status: 'conflict' };
    state.version += 1;
    state.content = request.body.content;
    state.step = request.body.currentStep;
    return { status: 'confirmed', version: state.version, body: request.body } satisfies SetupSaveOutcome;
  });
  const queue = new SetupSaveQueue({ send });
  queue.adopt(state.version, { currentStep: state.step, content: state.content });
  return { queue, send, state };
}

describe('Enregistrement coalescé du brouillon (#123)', () => {
  test('un seul PUT en vol ; la dernière saisie part après la réponse avec la version qu’elle renvoie', async () => {
    const h = harness();
    const waiting = deferred<SetupSaveOutcome>();
    h.send.mockImplementationOnce(() => waiting.promise);
    const first = content('École A');
    const second = content('École B');

    h.queue.enqueue(draft(first));
    h.queue.enqueue(draft(second, 'PRICING'));
    h.queue.enqueue(draft(second, 'PRICING'));

    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.send.mock.calls[0]![0]).toMatchObject({ ifMatch: 1 });
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'saving', saving: true, synced: false });

    h.state.version = 2; h.state.content = first;
    waiting.resolve({ status: 'confirmed', version: 2, body: draft(first) });
    await flush();

    expect(h.send).toHaveBeenCalledTimes(2);
    expect(h.send.mock.calls[1]![0]).toMatchObject({ ifMatch: 2 });
    expect(h.send.mock.calls[1]![0].body.content.identity.name).toBe('École B');
    expect(h.state.version).toBe(3);
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'idle', synced: true, heldVersion: 3 });
  });

  test('aucune requête pour une saisie identique à celle que l’école détient déjà', async () => {
    const h = harness();
    h.queue.enqueue(draft(content(), 'IDENTITY'));
    await flush();
    expect(h.send).not.toHaveBeenCalled();
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'idle', synced: true });

    // Seule l'étape a changé : la saisie est la même, rien ne part.
    h.queue.enqueue(draft(content(), 'FORMATIONS'));
    await flush();
    expect(h.send).not.toHaveBeenCalled();

    h.queue.enqueue(draft(content('École A')));
    await flush();
    expect(h.send).toHaveBeenCalledTimes(1);
    h.queue.enqueue(draft(content('École A')));
    h.queue.enqueue(draft(content('École A'), 'PRICING'));
    await flush();
    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.queue.getSnapshot().synced).toBe(true);
  });

  test('un refus garde la saisie et « Réessayer » renvoie exactement le même brouillon', async () => {
    const h = harness();
    h.send.mockResolvedValueOnce({ status: 'refused', message: 'La préparation n’a pas pu être enregistrée.' });
    const typed = content('École A');
    h.queue.enqueue(draft(typed));
    await flush();

    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'refused', synced: false, heldVersion: 1 });
    expect(h.queue.getSnapshot().message).toBe('La préparation n’a pas pu être enregistrée.');

    h.queue.retry();
    await flush();
    expect(h.send).toHaveBeenCalledTimes(2);
    expect(h.send.mock.calls[1]![0]).toEqual(h.send.mock.calls[0]![0]);
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'idle', synced: true, heldVersion: 2 });
  });

  test('un résultat non établi ne se rejoue pas tout seul, et un reçu le tranche par une relecture', async () => {
    const h = harness();
    h.send.mockResolvedValueOnce({ status: 'unknown', message: 'Enregistrement non confirmé.' });
    const typed = content('École A');
    h.queue.enqueue(draft(typed));
    await flush();
    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'unknown', synced: false });

    // Le reçu confirme et la relecture montre le brouillon envoyé : plus rien à vérifier.
    h.state.version = 2; h.state.content = typed;
    h.queue.adopt(2, { currentStep: 'FORMATIONS', content: typed });
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'idle', synced: true, heldVersion: 2 });
    expect(h.send).toHaveBeenCalledTimes(1);
  });

  test('un résultat non établi que la relecture ne confirme pas reste à réessayer explicitement', async () => {
    const h = harness();
    h.send.mockResolvedValueOnce({ status: 'unknown', message: 'Enregistrement non confirmé.' });
    h.queue.enqueue(draft(content('École A')));
    await flush();
    h.queue.adopt(2, { currentStep: 'REVIEW', content: content('École C') });
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'unknown', synced: false });

    h.state.version = 2; h.state.content = content('École C');
    h.queue.retry();
    await flush();
    expect(h.send).toHaveBeenCalledTimes(2);
    expect(h.send.mock.calls[1]![0]).toMatchObject({ ifMatch: 2 });
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'idle', synced: true });
  });

  test('un conflit garde la saisie, relit l’école et marque l’étape « à relire »', async () => {
    const h = harness();
    const typed = content('École A');
    h.state.version = 5; // un autre administrateur a enregistré entre-temps
    h.queue.enqueue(draft(typed));
    await flush();

    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'conflict', conflictStep: 'FORMATIONS', synced: false, heldVersion: 1 });
    expect(h.queue.getSnapshot().held?.content.identity.name).toBe('École synthétique');

    h.queue.adopt(5, { currentStep: 'REVIEW', content: content('École C') });
    expect(h.queue.getSnapshot()).toMatchObject({ heldVersion: 5, conflictStep: 'FORMATIONS', synced: false });
    expect(h.send).toHaveBeenCalledTimes(1); // rien n'est rejoué tout seul

    h.queue.enqueue(draft(typed));
    await flush();
    expect(h.send).toHaveBeenCalledTimes(2);
    expect(h.send.mock.calls[1]![0]).toMatchObject({ ifMatch: 5 });
    expect(h.send.mock.calls[1]![0].body.content.identity.name).toBe('École A');
    expect(h.state.version).toBe(6);
  });

  test('une lecture plus ancienne que la version détenue ne ramène pas l’école en arrière', async () => {
    const h = harness();
    h.queue.enqueue(draft(content('École A')));
    await flush();
    expect(h.queue.getSnapshot().heldVersion).toBe(2);
    h.queue.adopt(1, { currentStep: 'IDENTITY', content: content() });
    expect(h.queue.getSnapshot()).toMatchObject({ heldVersion: 2, synced: true });
  });

  test('« Enregistrer et quitter » attend l’envoi en vol au lieu de le doubler', async () => {
    const h = harness();
    const waiting = deferred<SetupSaveOutcome>();
    h.send.mockImplementationOnce(() => waiting.promise);
    const typed = content('École A');
    h.queue.enqueue(draft(typed));
    const explicit = h.queue.flush(draft(typed));
    await flush();
    expect(h.send).toHaveBeenCalledTimes(1);

    h.state.version = 2; h.state.content = typed;
    waiting.resolve({ status: 'confirmed', version: 2, body: draft(typed) });
    const settled = await explicit;
    expect(h.send).toHaveBeenCalledTimes(1);
    expect(settled).toMatchObject({ phase: 'idle', synced: true });
    expect(settled.held?.content.identity.name).toBe('École A');
  });

  test('« Enregistrer et quitter » envoie la saisie plus récente après la réponse en vol', async () => {
    const h = harness();
    const waiting = deferred<SetupSaveOutcome>();
    h.send.mockImplementationOnce(() => waiting.promise);
    h.queue.enqueue(draft(content('École A'), 'FORMATIONS'));
    const explicit = h.queue.flush(draft(content('École B'), 'PRICING'));
    await flush();
    expect(h.send).toHaveBeenCalledTimes(1);

    h.state.version = 2; h.state.content = content('École A');
    waiting.resolve({ status: 'confirmed', version: 2, body: draft(content('École A')) });
    const settled = await explicit;
    expect(h.send).toHaveBeenCalledTimes(2);
    expect(h.send.mock.calls[1]![0]).toMatchObject({ ifMatch: 2 });
    expect(settled).toMatchObject({ phase: 'idle', synced: true });
    expect(settled.held?.content.identity.name).toBe('École B');
  });

  test('un changement de portée abandonne l’envoi : la réponse tardive n’est ni crue ni rejouée', async () => {
    const h = harness();
    const waiting = deferred<SetupSaveOutcome>();
    h.send.mockImplementationOnce(() => waiting.promise);
    const typed = content('École A');
    h.queue.enqueue(draft(typed));
    expect(h.queue.getSnapshot().phase).toBe('saving');

    h.queue.dispose();
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'idle', held: null, heldVersion: null, synced: false });

    waiting.resolve({ status: 'confirmed', version: 2, body: draft(typed) });
    await flush();
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'idle', held: null });
    expect(h.send).toHaveBeenCalledTimes(1);

    h.queue.enqueue(draft(typed));
    await flush();
    expect(h.send).toHaveBeenCalledTimes(1); // rien n'est rejoué dans la nouvelle portée
  });

  test('sauvegarde perdue, rechargement puis reçu : la file repart synchronisée sur le brouillon relu', async () => {
    const h = harness();
    const waiting = deferred<SetupSaveOutcome>();
    h.send.mockImplementationOnce(() => waiting.promise);
    const typed = content('École A');
    // « Enregistrer et revenir au résumé » : la réponse est perdue, le magasin garde la demande au résultat inconnu.
    h.queue.enqueue(draft(typed, 'REVIEW'));
    expect(h.queue.getSnapshot().phase).toBe('saving');

    // Rechargement de la page : la portée précédente est abandonnée, une file neuve relit le brouillon que le PUT a écrit.
    h.queue.dispose();
    const reloaded = new SetupSaveQueue({ send: h.send });
    reloaded.adopt(2, { currentStep: 'REVIEW', content: typed });
    reloaded.track({ currentStep: 'REVIEW', content: typed });
    expect(reloaded.getSnapshot()).toMatchObject({ phase: 'idle', synced: true, heldVersion: 2, conflictStep: null });

    // Reçu AP72 : il confirme l'opération sans contenu, la relecture du brouillon garde la même version et la même saisie.
    reloaded.adopt(2, { currentStep: 'REVIEW', content: typed });
    expect(reloaded.getSnapshot()).toMatchObject({ phase: 'idle', synced: true, heldVersion: 2 });

    // La réponse tardive de la page précédente n'atteint jamais la nouvelle portée.
    waiting.resolve({ status: 'confirmed', version: 2, body: draft(typed, 'REVIEW') });
    await flush();
    expect(reloaded.getSnapshot()).toMatchObject({ phase: 'idle', synced: true, heldVersion: 2 });
    expect(h.send).toHaveBeenCalledTimes(1);
  });

  test('une réponse perdue n’est pas un refus : la sortie attend la vérification au lieu d’abandonner la commande', async () => {
    const h = harness();
    h.send.mockResolvedValueOnce({ status: 'unknown', message: 'Enregistrement non confirmé. Vérifiez son résultat.' });
    const typed = content('École A');
    // Dialogue de sortie : « Enregistrer et quitter ».
    const settled = await h.queue.flush(draft(typed, 'PROFILE'));

    expect(settled).toMatchObject({ phase: 'unknown', synced: false });
    expect(saveOutcome(settled, draft(typed, 'PROFILE'))).toBe('pending');
    // La saisie reste retenue et la commande reste suivie : rien n'est abandonné, rien n'est renvoyé.
    expect(h.queue.getSnapshot().held?.content.identity.name).toBe('École synthétique');
    expect(h.send).toHaveBeenCalledTimes(1);
  });

  test('la sortie ne se fait que sur le brouillon exactement détenu par l’école', async () => {
    const h = harness();
    const typed = content('École A');
    const settled = await h.queue.flush(draft(typed, 'PROFILE'));
    expect(settled).toMatchObject({ phase: 'idle', synced: true });
    expect(saveOutcome(settled, draft(typed, 'PROFILE'))).toBe('confirmed');
    // Même contenu, autre étape : l'école détient bien la saisie.
    expect(saveOutcome(settled, draft(typed, 'REVIEW'))).toBe('confirmed');
    // Une saisie plus récente n'est pas ce que l'école détient : pas de sortie.
    expect(saveOutcome(settled, draft(content('École B'), 'PROFILE'))).toBe('failed');

    h.send.mockResolvedValueOnce({ status: 'refused', message: 'La préparation n’a pas été enregistrée.' });
    const refused = await h.queue.flush(draft(content('École B'), 'PROFILE'));
    expect(refused).toMatchObject({ phase: 'refused' });
    expect(saveOutcome(refused, draft(content('École B'), 'PROFILE'))).toBe('failed');
  });

  test('une normalisation serveur sur un champ non retouché est reprise par l’intention suivante', async () => {
    const h = harness();
    const waiting = deferred<SetupSaveOutcome>();
    h.send.mockImplementationOnce(() => waiting.promise);
    const first = content('École A');
    const second = content('École B');
    h.queue.enqueue(draft(first));
    h.queue.enqueue(draft(second, 'PRICING'));

    const confirmedFirst = content('École A');
    confirmedFirst.identity = { ...confirmedFirst.identity, contactEmail: 'normalise@example.invalid' };
    h.state.version = 2; h.state.content = confirmedFirst;
    waiting.resolve({ status: 'confirmed', version: 2, body: draft(confirmedFirst) });
    await flush();

    expect(h.send).toHaveBeenCalledTimes(2);
    const next = h.send.mock.calls[1]![0];
    // Le nom vient de la saisie postérieure, l'e-mail normalisé par l'école n'est pas écrasé par l'ancien brouillon.
    expect(next.body.content.identity.name).toBe('École B');
    expect(next.body.content.identity.contactEmail).toBe('normalise@example.invalid');
  });

  test('un même champ changé localement et normalisé par l’école reste à relire sans second envoi', async () => {
    const h = harness();
    const waiting = deferred<SetupSaveOutcome>();
    h.send.mockImplementationOnce(() => waiting.promise);
    const first = content('École A');
    const second = content('École B', 'local@example.invalid');
    h.queue.enqueue(draft(first));
    h.queue.enqueue(draft(second, 'PRICING'));

    const confirmedFirst = content('École A', 'normalise@example.invalid');
    h.state.version = 2; h.state.content = confirmedFirst;
    waiting.resolve({ status: 'confirmed', version: 2, body: draft(confirmedFirst) });
    await flush();

    // Même champ des deux côtés : aucune intention locale n'est renvoyée en silence sur la valeur normalisée.
    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.queue.getSnapshot()).toMatchObject({ phase: 'conflict', conflictStep: 'PRICING', synced: false, heldVersion: 2 });
    expect(h.queue.getSnapshot().held?.content.identity.contactEmail).toBe('normalise@example.invalid');
  });
});
