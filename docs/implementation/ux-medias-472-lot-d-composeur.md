# Épic UX médias #472 — lot D : composeur (#475)

Branche `tomyrms/ux-medias-475-composeur`, partie de l'intégration `tomyrms/ux-medias-472-integration` (lots A #473 et B #474). Le protocole UI gelé `MessagingMediaRuntime` n'est pas modifié.

## Règle texte / légende

Le champ de texte principal ne disparaît plus pendant le choix d'une pièce. Tant qu'une pièce est choisie, il sert de légende (placeholder « Légende ») et **est** le brouillon : une seule valeur (`MessagingComposerModel.draft`), donc :

- choisir une pièce ne vide ni ne déplace le texte déjà saisi ;
- remplacer la pièce garde la légende ; un remplacement refusé garde l'ancienne pièce et la légende ;
- retirer la pièce laisse le texte tel quel dans le champ (le « retrait qui restitue le brouillon ») ;
- l'envoi de la pièce transmet la légende (rognée, `nil` si vide) puis ne vide le champ que si son contenu est inchangé depuis l'envoi (une frappe pendant la mise en file reste) ;
- la légende est enregistrée comme n'importe quel brouillon (stockage protégé, `persistDraft`), jamais le média ;
- aucun texte n'est envoyé à l'insu de l'utilisateur : le champ envoyé est le champ affiché.

## Interfaces (internes)

- `MessagingCaptionChannel { read: @MainActor () -> String; write: @MainActor (String) -> Void }` ; `MessagingMediaComposerModel.draftChannel` (installé par `MessagingThreadComposer.onAppear`). Sans raccord, la légende est locale (tests, compositions minimales).
- `MessagingMediaComposerModel.caption` : calculée (raccord ou local). Nouveautés : `selectionError: String?`, `selectionRevision: UUID`, `static selectionLabel(_:)`. `select` ne vide plus la légende ; `removeSelection` non plus ; `suspend` ne touche pas au brouillon du composeur.
- `MessagingComposerAttachmentChip` (carte/miniature, retrait), `MessagingComposerThumbnail`, `MessagingComposerSelectionSection`, `MessagingComposerAttachmentText.accessibilityLabel(name:mime:byteSize:)`.
- Panneau média : la sélection est déléguée à `MessagingComposerSelectionSection` ; le bouton « Envoyer la pièce » et le champ de légende du panneau sont retirés, l'envoi est la flèche du composeur.

## Erreurs de choix

Annulation du sélecteur : aucune erreur. Format/taille refusés : messages existants. Import interrompu (iCloud, fournisseur de fichiers indisponible, toute erreur hors contrat) : « Fichier indisponible. Vérifier la connexion, puis le choisir à nouveau. » Affichées sous la pièce (`messaging.media.error`) ; `error` reste renseigné pour le reste du panneau, qui n'affiche pas deux fois le même texte.

## Accessibilité

Libellés : « Photo, nom », « Document PDF, nom, taille », « Retirer la pièce jointe », champ « Légende de la pièce jointe », envoi « Envoyer la pièce jointe » / « Envoi en cours ». Identifiants conservés : `messaging.media.selection.open`, `.remove`, `messaging.media.caption` (désormais le champ principal), `messaging.media.send` (désormais la flèche), `messaging.media.preparing`, `messaging.media.error`. Retirés : aucun. Cibles ≥ 44 pt ; nom jusqu'à 4 lignes en tailles d'accessibilité, troncature au milieu.

## Bouton d'envoi

Pendant la préparation, la flèche de texte est désactivée (pas d'envoi de texte alors qu'une pièce arrive). Pièce choisie : flèche média, désactivée tant que le brouillon n'est pas chargé, occupée (indicateur) pendant la mise en file, jamais deux envois (`canSend` faux dès `sending`).

## Test UI adapté / ajouté

`MessagingMediaUITests` : parcours existants inchangés (identifiants conservés) ; ajout de `testCaptionIsTheDraftAndSurvivesRemoval`.

## Non couvert / reste

- La sélection (octets) n'est jamais persistée : un redémarrage de l'app perd la pièce choisie mais garde la légende comme brouillon texte. Persister le média en clair est exclu ; le chiffrer exigerait une capacité du runtime non prévue ici.
- Remplacement : via le menu « + » (Photo/Fichier) ; pas de bouton « Remplacer » dédié. Pendant la préparation d'un remplacement, la pièce précédente est masquée et « Retirer » retire tout.
- Mentions : la légende reste du texte simple, les mentions `@` ne sont pas transmises avec une pièce (comportement antérieur inchangé).
- Intentions déjà en file, états et reprises : lot C (#476).
- Non essayé : rendu réel, clavier ouvert, petit iPhone, grande taille de texte, iPad étroit, VoiceOver, appareil physique.
