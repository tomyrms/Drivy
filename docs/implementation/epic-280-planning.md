# EPIC #280 — accueil, préparation, planning et cours

Travail du 28 octobre 2026 sur `codex/epic-280-web`. Référence : issues W10 #247, W11 #255, W12 #290, W13 #291, W14 #292, W21 #299 et W22 #300. Les apports #253 et #278 sont intégrés au point de départ avant la recomposition.

## Mise en œuvre

| Chantier | Réalisation |
|---|---|
| W10 · Accueil | L’école active ouvre le planning existant. Les liens d’accueil conservent semaine, jour, moniteur, leçon, cours et occurrence. La prochaine action vient de `setup-draft/next-actions`, reste réductible dans la mémoire de l’école et expose l’heure de lecture. L’école archivée reste explicitement identifiée. |
| W11 · Préparation | Un seul `SchoolSetupGuide`, brouillon et commandes inchangés. Progression latérale desktop, progression compacte et dépliable mobile, espace de lecture borné, cartes de formations, synthèse modifiable. Textes complets disponibles dans la revue avant l’adoption ; le choix personnalisé expose immédiatement son nom et sa catégorie. |
| W12 · Agenda | Projection unique leçons/cours conservée. Vue jour initiale sur téléphone et semaine sur desktop ; choix manuel conservé en mémoire. Dates, filtres et ouvertures réelles de leçon/cours/occurrence dans la navigation canonique. Barre de jours abrégés, filtres repliables sur mobile avec nombre de filtres actifs, retour à l’objet et restauration de défilement. Lecture partielle et échecs conservés, aucun jour non chargé déclaré libre. |
| W13 · Leçons | Fiche et éditeur séparés du planning, retour explicite, lecture élève/horaires/moniteur/lieu/prix, annulation secondaire. Éditeur regroupé par participants, rendez-vous et tarif. Vérification du créneau, récapitulatif, accord de déplacement, changements commerciaux explicites et protection de saisie conservés. |
| W14 · Horaires | Cartes d’horaires et d’absences, jours sélectionnés et périodes de validité lisibles. Un seul éditeur, date de fin facultative, modification avec `If-Match`, motif facultatif d’absence et retrait par confirmation. Changement de moniteur et navigation protègent le brouillon. Lecture tronquée explicitée et écritures suspendues. |
| W21 · Cours | Éditeur en page, séances compactes dépliables, résumé avant publication incluant la langue. Fiche en rubriques Informations / Appel et suivi / Inscriptions. Capacité secondaire, report en formulaire de page par séance et annulation contextualisée. Dates, identité de série/occurrence, tarifs/conditions existants inchangés. |
| W22 · Participants | Sélection explicite d’une occurrence pour l’appel ; tableau desktop et liste mobile, sans matrice à défilement bidirectionnel. Recherche de participants, état non renseigné distinct, retours d’écriture liés à la personne. Modes appel/règlements/validation conservés. Annulation d’une saisie distinguée du remboursement. Inscrits annulés et file d’attente restent consultables ; sélecteur recherchable et homonymes conservés, lecture tronquée signalée. |

## Contrats et garanties

- Références relues : `COMMENCER_ICI.md`, R09–R14, R60–R69, API AP31–AP43 et contrats runtime des cours ; scénarios T013–T020. Les décisions et implémentations plus récentes concernant les cours et la liste d’attente restent applicables.
- Les composants partagés passent par le socle shadcn/ui Base UI du chantier fondation. Les contrôleurs, `createCommand`, reçus/idempotence, droits serveur, versions, fuseau scolaire et stockage existant sont conservés. Aucun endpoint, migration, autorisation ou logique de présence supplémentaire n’est créé.
- `availability-rules` PUT et `closures` POST sont des capacités serveur déjà présentes. L’interface expose ces contrats, y compris `validUntil` et le motif, sans contournement du contrôle d’occupation.
- Un cours relit sa fiche après mutation confirmée. La feuille de participants marque la génération de lecture : une lecture démarrée avant une écriture confirmée ne remplace plus son résultat plus récent. La saisie n’est pas présentée comme confirmée pendant l’incertitude.
- Filtres et préférences d’affichage restent dans la mémoire de la session scolaire. Seuls les identifiants techniques et dates de navigation autorisés entrent dans l’URL. Aucun cache local persistant, token, donnée scolaire ou contenu de commande n’est ajouté au stockage navigateur.
- Couleurs issues des tokens Drivy, y compris `accent-fill` et `on-accent` pour les boutons sélectionnés en sombre. Le retrait du CSS Agenda précédent est un remplacement, pas une nouvelle série de surcharges de l’ancienne composition.

## Vérifications effectuées et limites

- `npm run typecheck` web : réussi (TypeScript client et configuration de vérification) après intégration du socle et des changements de routes.
- `git diff --check` des fichiers du lot : réussi ; seuls avertissements de normalisation CRLF/LF de Git.
- Le coordinateur inspecte les captures synthétiques dans `proofs/epic-280/`. Une première capture Agenda 390 px a révélé trop de commandes dépliées et des noms de jours cassés ; corrigé par barre compacte et panneau Filtres.
- Les captures ne prouvent ni transactions PostgreSQL, ni navigateur physique, ni clavier logiciel, ni VoiceOver, ni validation utilisateur. Les tests métier complets et campagnes #309/#84 restent à exécuter après essai et validation du porteur, conformément à sa demande.
- Aucune intervention homelab, aucun déploiement ni commit Git exécuté par l’agent du lot.

## Entrées synthétiques pour la revue visuelle

- `/test/visual.html?shell=1&page=agenda&agenda=mixed`
- `/test/visual.html?shell=1&page=agenda&agenda=lesson-planning`
- `/test/visual.html?page=course&agenda=course-review` ; ajouter `draft=1` pour le brouillon.
- `/test/visual.html?shell=1&page=availability` et `page=absences`.
- `/test/visual.html?shell=1&page=overview&from=configuration`.
- `/test/visual.html?shell=1&page=overview&status=draft&setup=ready&step=PRICING` ; `step=REVIEW` pour la confirmation.

Ces entrées chargent exclusivement les fixtures synthétiques du serveur de développement. Elles ne sont pas des routes de production.
