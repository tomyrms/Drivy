# #311 / R12 #323 — horaires et absences des moniteurs

Branche `claude/311-planning`, base `d9c85479`. Périmètre de ce lot : `apps/web/client/portal/availability/*`, la famille d'aperçu `portal/preview/families/planning.ts` et deux lignes dans `portal/pages.tsx` (sections `disponibilites` et `absences`). Aucun backend, contrat, migration, ancien rendu, Swift ou CI modifié. Aucun résultat ci-dessous ne vaut validation du porteur ni ne ferme #323.

## Sous-vues reconstruites

- **Lecture des horaires** : « Semaine type » (sept jours, plages en texte, barre proportionnelle seulement à partir de 768 px, `aria-hidden`), puis « Horaires en vigueur », « À venir » et un groupe replié « Horaires terminés (n) ». La semaine type ne montre que les horaires en vigueur le jour même ; un jour sans plage reste « Aucune plage » et n'est jamais présenté comme une disponibilité.
- **Ajout et modification d'un horaire** : une page (pas une modale), en deux temps. Saisie (jours en ToggleGroup, début, fin, validité, fin de validité facultative), puis « Relire avant d'enregistrer ». En modification, chaque ligne changée affiche l'ancienne valeur barrée. « Relire » reste inactif tant que rien n'a changé.
- **Retrait d'un horaire** : dialogue de confirmation (jours, heures, période) ; le texte rappelle que les rendez-vous prévus ne sont pas déplacés.
- **Lecture des absences** : absences à venir ou en cours, dans le fuseau de l'école, motif affiché s'il existe.
- **Ajout d'une absence** : début et fin en `datetime-local` libellés avec le fuseau, motif facultatif (1 000 caractères), relecture, puis commande. Retrait par dialogue de confirmation.
- **Contexte** : choix du moniteur (Select ou Combobox au-delà de six), mémorisé dans la mémoire de liste de l'école et dans l'URL (`instructor`) ; « Voir l'agenda » avec ce moniteur ; « Retour au membre » quand l'arrivée vient d'Équipe. États : chargement (squelette), erreur de lecture avec reprise, lecture partielle (écritures bloquées), école inactive, aucun moniteur, aucun horaire, aucune absence.

## Décisions

- **Contrat respecté** : champ de fin de validité (`validUntil`, nullable) et motif d'absence (`reason`, 1 000 caractères) existent dans l'API ; ils sont donc proposés. Aucune édition d'absence n'est offerte : l'API n'expose que création et retrait. Le motif du retrait est le texte fixe existant (« Retirée depuis la gestion web. »).
- **Une action ne déplace jamais un rendez-vous** : l'API refuse (`EXISTING_BOOKINGS`) ; le refus s'affiche près des boutons avec « Voir l'agenda de {moniteur} ». `INVALID_INTERVAL` s'affiche sous le champ de fin. Le chevauchement entre deux horaires est calculé localement (`overlappingHours`, la règle éditée est exclue) et affiché sous les champs, relié par `aria-describedby`.
- **Aucun succès avant reçu durable** : commandes uniquement par `createCommand` et `useCommandRunner` (If-Match, version de la ligne lue, `operationId`). Refus : saisie conservée et retour à la saisie. Conflit de version : « Relire, garder ma saisie » relit les lignes sans toucher au brouillon (la version envoyée suit la relecture). Réponse perdue : le panneau d'attente du coordinateur porte la vérification, l'éditeur est verrouillé.
- **Brouillon protégé** : `useUnsavedChanges` ; changement de moniteur, d'onglet ou départ passent par `confirmNavigation`. L'éditeur est monté avec une clé `moniteur:horaire` : un brouillon ne s'applique jamais à une autre cible.
- **Écritures sur lecture complète seulement** : lecture partielle ou école inactive désactivent ajout, modification et retrait (un chevauchement caché fausserait la relecture).
- **Logique pure** : `schedule-model.ts` (jours, périodes, groupes, semaine, problèmes de saisie, corps des commandes, absences) est testé ; `use-schedule*.ts` portent lecture et commandes ; `*-panel.tsx` et `schedule-page.tsx` ne contiennent que de la présentation. Aucun import de l'ancien rendu (la compilation d'aperçu l'impose).
- Les composants `ReadFeedback` et `CommandFeedback` de l'Agenda sont réutilisés ; `useHeadingFocus` (Agenda) donne le focus au titre après le cadre.

## Vérifications exécutées (dans `apps/web`)

- `node node_modules/typescript/bin/tsc --noEmit` : sortie vide, code 0.
- `node node_modules/vitest/vitest.mjs run client/portal/agenda client/portal/availability` : 2 fichiers, 12 tests réussis (4 de `calendar-layout`, 8 de `schedule-model`).
- `node node_modules/vite/bin/vite.js build --config vite.preview-311.config.ts` : réussi (garde des imports hérités sans erreur).
- Navigateur headless (Chromium via Playwright), 1440×900 clair et 390×844 sombre, aperçu servi sur le port 5192, données fictives : lecture des horaires de Luc et de Marie ; modification refusée par `EXISTING_BOOKINGS` (la fin à 11:00 laisse une leçon de 11:00 hors horaire) ; chevauchement ; ajout confirmé ; retrait confirmé ; retrait refusé dans le dialogue ; absence refusée (leçon prévue demain) puis confirmée ; abandon de brouillon ; garde de départ vers l'autre onglet avec brouillon conservé ; scénarios « Refus », « Conflit de version » et « Réponse perdue ». Aucun débordement horizontal (`scrollWidth - innerWidth = 0`) ni erreur console sur tous les écrans captés.

## Reste à qualifier

Recette au clavier et au doigt réels, lecteur d'écran (annonce du chevauchement et des refus), saisie `datetime-local` sur appareils mobiles, changement d'heure (le modèle refuse une heure inexistante ; le choix d'une heure répétée n'est pas proposé pour les absences), très longs motifs, école avec de nombreux moniteurs, raccord authentifié réel. Aucune campagne étendue API ou native lancée.

## Demandes au socle

- Variante « pressée » du ToggleGroup outline : l'état `aria-pressed` du kit est à peine visible ; contourné dans `availability.css` (`.schedule-days-toggle`).
- Sélecteur de date/heure : champs natifs utilisés (date, heure, `datetime-local`) ; aucun composant du socle ne couvre l'heure.
- Alignement optique d'un bouton ghost « Retour » en début de page : contourné par une marge négative locale.
