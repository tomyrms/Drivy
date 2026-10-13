# Portail Studio — couverture des pages et contrôles

État de travail du 14 octobre 2026, après abandon de la direction Registre et validation de la référence Mercury par le porteur. Ce document distingue la lecture du code, les interactions réellement exécutées dans Edge et la qualification visuelle encore en cours. Il complète l’[inventaire fonctionnel du 13 octobre](web-redesign-inventory-20261013.md), sans répéter ses règles ni transformer une capture synthétique en recette métier.

## Sources et niveau de preuve

- **Code** : `apps/web/client/main.tsx`, `console/sections.ts`, `console/navigation.ts`, composants des pages ci-dessous, `choice-field.tsx` et CSS locaux. Les 18 clés de section demeurent ; les audiences d’invitations et les étapes du guide constituent des variantes de ces pages.
- **Conception** : `COMMENCER_ICI.md`, R09–R11 pour disponibilités/concurrence, règles scolaires R86–R98 et J19 pour la configuration, contrat canonique OpenAPI 3.11.0. Les décisions d’implémentation récentes restent prioritaires sur les anciennes formulations de publication.
- **Référence observée** : démo Mercury examinée par l’agent principal ; provenance et mesures dans [le benchmark Studio](web-studio-benchmark-20261014.md). L’inventaire ci-dessous n’ajoute aucune prétendue observation directe de cette démo.
- **Avant** : captures synthétiques protégées sur `1b7d204808cb892c05293b33f9e5e8c7220b9ddc`, manifeste `artifacts/web-studio-20261014/before/baseline-manifest.json`. Les rapports séparent captures de pages et 12 états de contrôles ouverts.
- **Après** : essais des choix et des routes effectivement exécutés par l’agent de vérification, rapports relus pour cet inventaire. Ils utilisent Edge 155.0.4283.45 et les vrais composants React, avec BFF synthétique en mémoire. Ils ne qualifient ni OIDC, ni PostgreSQL, ni un lecteur d’écran physique.

La typographie constatée dans `styles.css` pendant cette passe est Manrope embarquée ; les choix de palette sont portés par les tokens partagés. Ces constats de code ne mesurent pas à eux seuls les contrastes ou le confort de lecture.

## Pages couvertes

Les chemins de la console restent `/app/gestion/:schoolId/:section`. « Relu » signifie code examiné ; « recomposé » signifie structure ou contrôles modifiés dans cette passe. La colonne preuve ne vaut pas validation esthétique de toute la page.

| Page ou variante | Couverture de la passe et contraintes préservées | Preuve disponible à cette étape |
|---|---|---|
| `/app/` et invitation | Racine compte/invitation conservée dans `App.tsx` ; identité, confirmation personnelle et résultat inconnu demeurent. Hérite des primitives et tokens communs. | Code ; état connexion capturé avant. Capture finale à compléter. |
| `/app/preferences` | Composition de paramètres dans `preferences.tsx` et `settings-studio.css` ; thème personnel distinct des réglages d’école. | Code recomposé par intégration ; contrôle final à compléter. |
| `/app/ouvrir`, `/app/operateur` | Routes et rôles distincts conservés dans `school-opening.tsx` ; pas de sélecteur natif à migrer. Liens secrets, émission/révocation et adoption gardent leur logique. | Code relu pour les contrôles ; aucune émission réelle dans cette passe. |
| `agenda` | Période et flèches regroupées, recherche compacte, filtre moniteur recherché ; jours horizontaux avec décompte, statut près de l’élève. `agenda.tsx`, `agenda-studio.css`. | Interaction Edge : semaine suivante/précédente, choix du moniteur, recherche, dossier puis retour conservant semaine, moniteur et recherche. Captures finales à compléter. |
| `disponibilites` | Filtre moniteur compact, horaires sans carte englobante, contenu borné à 52 rem, formulaire à 44 rem. Jours multiples restent des cases, heures et dates restent natives. | Code recomposé ; typecheck. Largeurs et retrait réel à qualifier en navigateur. |
| `absences` | Même propriétaire `availability.tsx` ; période dans le fuseau scolaire, ajout et retrait conservés. CSS local partagé avec les disponibilités. | Code recomposé ; typecheck. Aucun effet supposé sur des engagements existants. |
| `eleves` liste | Vues Actifs/Archives/Tous, recherche compacte, filtre Profil ancré ; tri dans l’en-tête avec `aria-sort`, initiales déterministes. Les cinq colonnes, homonymes/contact, pagination et liens restent présents. | Interaction Edge : tri clavier, page réinitialisée, profil dans le menu. Captures avant présentes ; comparaison finale à compléter. |
| Dossier élève | En-tête avec initiales, coordonnées séparées ; retour au contexte, profil manquant, formations, moniteurs, permis et archivage conservés. Moniteur/offre recherchables ; décision permis en radios. | Code ; allers-retours liste/agenda exécutés. Les commandes métier de chaque sous-formulaire restent à intégrer à la recette finale. |
| Suivi de formation et bilans | `dossier.tsx` conserve son chargement progressif et les filtres année/mois ; ceux-ci héritent du menu partagé. Aucun nouveau calendrier ni calcul pédagogique. | Code relu ; pas de modification de composition nécessaire dans ce lot. |
| `trajets` global et par élève | `trips.tsx` utilise la recherche commune, une table au rythme des annuaires et une identité avec initiales. Deux colonnes conservées, forme mobile avec libellé Trajet ; pagination distincte du filtre. | Code recomposé ; typecheck. Navigation/captures finales à compléter. |
| `equipe` liste et membre | Recherche et vues séparées, tri dans l’en-tête, identité et fiche harmonisées. Les trois colonnes, rôles, grants, motif et revue restent conservés. | Interaction Edge : tri, filtre inactif, contexte conservé après ouverture du membre. |
| `invitations`, audience élèves | État dans un menu compact, moniteur dans un choix recherché ; code/copie, catégorie et révocation inchangés. | Code ; contrôles partagés testés. Recette de l’audience à compléter. |
| `invitations`, audience équipe | Même propriétaire `people.tsx`, portée et recherche mémoire distinctes ; choix de rôles par cases et capacités de messagerie conservés. | Code ; aucune émission de message réel dans cette passe. |
| `formations` | Vue par permis et destinations utiles conservées dans `formations.tsx` ; composition prise en charge avec le catalogue par l’intégration. | Code ; rendu final à qualifier. |
| `offres`, `referentiels`, `procedures` | `catalog.tsx` : listes recherchables, éditeurs complets avec retour et barre de sauvegarde ; choix référentiel/procédure recherchables. Versions, approbation, revue et garde inchangés. | Code recomposé par le lot catalogue ; contrôles communs testés, éditeurs finaux à qualifier. |
| `prestations`, `conditions` | `commerce.tsx` : listes recherchables, détail/éditeur complet ; conditions recherchables. Type à quatre libellés longs reste un menu. Prix, unités, dates de validité et activation gardent leurs règles. | Code recomposé par le lot catalogue ; contrôles communs testés, recette finale à compléter. |
| `configuration` | Lecture en lignes puis modification explicite du groupe coordonnées. `configuration.tsx`, `settings-studio.css`. | Edge : entrée/sortie sans écriture, validation, refus, conflit et relecture confirmée vérifiés dans les rapports ciblés. |
| `confidentialite` | Lecture des textes puis édition limitée au groupe ; détails contractuels conservés. Les confirmations d’impact et la publication immédiate ne changent pas. | Code recomposé par le lot paramètres ; revue finale à compléter. |
| `champs-profil` | `profile-fields.tsx` délègue à `PrivacySection(section="fields")`. Choix 2–4 en radios dans des lignes label/valeur ; explication et aperçu conservés. Aucun second éditeur ajouté. | Code relu après recomposition du lot paramètres ; contrôle clavier des radios communs exécuté. |
| `signalements` | Composition existante conservée : liste ordonnée, déplacement poignée/flèches, visibilité et aperçu, sauvegarde distincte. Pas de menu à remplacer ni de nouvelle règle de glisser-déposer. | Edge : modification puis inverse sans faux garde, vrai brouillon protégé, sauvegarde libérant la sortie. |
| `apercu` école en préparation | Guide IDENTITÉ/CONFIDENTIALITÉ/PROFIL/FORMATIONS/TARIFS/REVUE dans `school-setup.tsx`. Choix de demande en radios, formation existante recherchable. Écriture du brouillon serveur et activation conservées. | Code ; contrôle partagé, recette complète du guide à exécuter après stabilisation. |
| `apercu` école active et mode catalogue | Même état de préparation calculé au serveur ; parcours limité FORMATIONS/TARIFS/REVUE pour le catalogue. Aucune réadoption implicite des textes. | Code relu ; rendu et parcours finaux à qualifier. |

## Inventaire des contrôles de choix

`ui.tsx` réexporte `SelectField` et `SegmentField` depuis `choice-field.tsx`. La dépendance verrouillée est `@base-ui/react` **1.9.0**. Une recherche du client ne relève plus de `<select>` écrit directement dans les composants produit ; un contrôle interne de la bibliothèque pour les formulaires n’est pas un sélecteur visuel à migrer.

| Contrôle | Usage et emplacement | Décision |
|---|---|---|
| École gérée | `console/Console.tsx` | Choix recherché ; garde du changement d’école conservé. |
| Moniteur | Agenda, disponibilités, dossier, invitation élève | Recherche dans le panneau ; apparence filtre dans les barres de vue. Aucun nom saisi ne devient une valeur métier. |
| Formation | Dossier et guide | Recherche explicite, valeur par identifiant existant. |
| Référentiel/procédure/conditions | Catalogue et prestations | Recherche explicite dans des listes de versions. |
| Profil et état d’invitation | Annuaires | Menu compact ; valeur active lisible. Aucun filtre sans donnée ou fonction existante. |
| Type de prestation | `commerce.tsx` | Menu conservé : quatre options aux libellés longs. |
| Année et mois | `dossier.tsx` | Menu partagé ; recherche automatique au-delà de sept options. |
| Pays | `profile-completion.tsx` | Menu à six valeurs existantes. |
| Décision permis | `learners.tsx` | Deux radios natives, même valeur et même confirmation. |
| Exigence d’information | Confidentialité/profil et guide | Deux à quatre radios natives ; l’éventuelle règle historique `keep` reste disponible. |
| Rôles, grants et jours | Équipe, invitations et disponibilités | Cases à cocher conservées pour les choix multiples. Aucune sélection groupée d’élèves ajoutée. |
| Date, heure et date/heure | Disponibilités, absences, validités commerciales, profil | Saisie native conservée. Pas de nouvelle grille/calendrier ni de changement d’ISO civil ou de fuseau scolaire. |

Le choix simple et le choix recherché conservent label, erreur associée, état désactivé, valeur vide métier et focus. Le panneau est positionné en `fixed` ; son portail reste dans le dialogue natif lorsqu’il existe. Le fieldset parent désactivé ferme aussi le panneau. La requête de recherche n’appelle jamais `onChange` : seule une option autorisée choisie émet une valeur.

## Limites métier conservées

- L’agenda est une lecture hebdomadaire ; aucun glisser-déposer, création de leçon ou succès simulé n’est ajouté.
- Disponibilités/absences gardent leurs commandes `availability-rules` et `closures`, leurs versions `If-Match`, validation temporelle et confirmations de retrait. Le serveur continue de décider des impacts et des droits.
- La recherche globale des trajets porte sur la page réellement chargée ; son placeholder le dit. Le filtre par élève reste borné aux 1 000 derniers trajets autorisés et garde l’avertissement d’historique partiel. Rien ne prétend filtrer toute la base.
- Les recherches et curseurs restent dans `context.drafts`, en mémoire et dans le scope d’accès de l’école. Les URLs n’acquièrent aucun nom, email ou brouillon.
- Les thèmes restent versionnés via `observation-themes`. La contrainte d’au moins un thème visible, le déplacement clavier, les états conflit/refus et le garde calculé sur une vraie différence restent intacts.
- La publication des informations élèves reste explicite et immédiate, avec revue de l’impact sur la planification. La refonte ne change ni API ni règle de confidentialité.

## Vérifications effectivement exécutées

1. `npm run typecheck` dans `apps/web` réussit après les primitives, l’agenda puis le lot disponibilités/trajets. `git diff --check` réussit sur les fichiers du lot ; les avertissements de conversion CRLF ne sont pas des erreurs de code.
2. `artifacts/web-studio-20261014/after/choices/interaction-filtered-results.json` : **11 contrôles réussis**, zéro échec. Clavier, option désactivée, Échap/Tab/focus, recherche sans émission, aucun résultat, valeur vide, choix retiré, désactivation de fieldset, erreurs associées et radios. Les choix simple/recherché dans un dialogue passent à **1440 et 390 px**, avec vérification que les options ne sont pas recouvertes par les actions.
3. `artifacts/web-studio-20261014/after/routes/interaction-filtered-results.json` : **6 contrôles réussis**, zéro échec. Édition explicite, garde et historique arrière/avant, faux garde des signalements, tri/filtre élèves, contexte équipe, aller-retour agenda/dossier.
4. Le rapport ciblé initial `after/interaction-filtered-results.json` conserve six succès et deux échecs de sélecteurs après changement de composition. Les deux scénarios ont ensuite été adaptés et passés dans le rapport `after/routes` ; on ne présente pas le rapport initial comme une passe entièrement verte.

Les captures finales clair/sombre, les états ouverts après stabilisation CSS, axe, le reflow et les parcours d’intégration réels restent des preuves distinctes à joindre par l’intégration. Aucun résultat CI, OIDC/PostgreSQL, appareil physique ou déploiement de cette passe n’est déduit des essais synthétiques ci-dessus.

## Relecture des primitives et dépendances

Le panneau recherché rend toujours `Combobox.Empty` comme région d’annonce. L’espace vide constaté avant la première option provenait de son padding alors que ses enfants étaient absents. `choice-field.css` retire seulement ce padding lorsque le nœud est vide, sans le masquer ni le démonter. Sous `pointer: coarse`, chaque option radio et chaque déclencheur de choix mesure au moins 44 px ; ce minimum concerne la cible, pas seulement le conteneur du groupe.

Le scan axe du menu simple relève les quatre sentinelles de focus internes Base UI (`aria-hidden` et `tabindex=0`). Le code verrouillé les produit dans `FocusGuard`, `FloatingPortal` et `SelectPopup` ; ce dernier utilise un gestionnaire non modal indépendamment de `Select.Root.modal`. La [réponse du mainteneur Base UI](https://github.com/mui/base-ui/issues/4668#issuecomment-4306200868) explique leur redirection immédiate vers un vrai contrôle ; [le suivi axe](https://github.com/dequelabs/axe-core/issues/4832) décrit la limite de son heuristique. Les constats bruts restent conservés et font l’objet d’un contrôle manuel des redirections. Aucun attribut de ces sentinelles n’est modifié et aucune règle axe n’est désactivée pour rendre le rapport vert. L’identifiant `aria-controls` doit être examiné avec l’état réel d’ouverture, le scan pouvant lui-même déplacer le focus et fermer un menu non modal.

Audit des paquets exécuté en lecture seule dans `apps/web` : `npm audit --omit=dev --json` retourne **0 vulnérabilité**. L’audit complet signale **1 high** pour `source-map-js@1.2.1`, dépendance de développement de `Vite → PostCSS`, déjà présente dans le lock du HEAD antérieur à Base UI. L’[avis GHSA-68fv-2mgg-jv7q](https://github.com/advisories/GHSA-68fv-2mgg-jv7q) décrit un blocage de la boucle d’événements lors du traitement de sourcemaps indexées malveillantes ; la version corrigée 1.2.2 est compatible avec la contrainte `^1.2.1` de PostCSS. Ce constat ne motive ni mise à niveau majeure ni modification automatique du lock dans ce lot.
