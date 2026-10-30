# EPIC #280 — candidat de refonte du portail

28 octobre 2026, branche `codex/epic-280-web`. Le code est intégré dans un worktree distinct du travail natif et de #253. La base qualifiée `origin/master` (`c94ec2bb`) est fusionnée intégralement dans `52fe0320`. Ce reçu décrit la réalisation avant essai personnel ; il ne clôture ni l'épic ni ses critères de qualification.

## Ordre et périmètre

Inventaire W01 puis socle W02–W07 ; lots planning/cours, catalogue/réglages et accès/dossiers réalisés en parallèle avec propriété de fichiers disjointe. Intégration W28–W30, contrôles minimum et préparation homelab. W31/#309 et #84 sont préparés, **différés après essai et validation du porteur à sa demande**. Aucune validation intermédiaire n'est requise. La seule confirmation demandée avant publication concerne le candidat et le plan de production final.

La composition reprend la hiérarchie Untitled UI avec les composants officiels shadcn/ui Base UI et les tokens Drivy. Le portail responsive reste le bureau de l'école ; l'application Swift et ses parcours terrain restent ceux de la base fusionnée. Aucun kit payant ou troisième moteur de composants n'est embarqué.

## Réalisation par sous-issue

`IMPLEMENTED_UNQUALIFIED` signifie que le code de la tranche est présent et relu, sans prétendre que toute sa matrice d'acceptation a été exécutée. Les preuves ciblées ci-dessous n'équivalent pas à W31. Les issues restent ouvertes jusqu'à leurs critères réels.

| Tranche | Réalisation et preuve de code | État avant essai |
| --- | --- | --- |
| W01 #281 | [110 sous-vues, rôles, actions, états et sources](epic-280-inventory.json), captures avant/après synthétiques dans `proofs/epic-280` | Inventaire réalisé ; matrice complète différée |
| W02 #282 | Tokens, Manrope locale, clair/Soft Charcoal, rythme et contraste dans DESIGN.md et `styles.css` | IMPLEMENTED_UNQUALIFIED |
| W03 #283 | Primitives shadcn Base UI, Tailwind sans preflight, alias et dépendances verrouillées ; [fondation](epic-280-foundation.md) | IMPLEMENTED_UNQUALIFIED |
| W04 #284 | Un arbre de navigation desktop/mobile, contexte scolaire, liens réels et garde de saisie ; `Console.tsx`, `portal-shell.css` | IMPLEMENTED_UNQUALIFIED |
| W05 #285 | Listes de personnes et tarifs, recherche/pagination/tri, détail pleine page, métadonnées lisibles sur mobile | IMPLEMENTED_UNQUALIFIED |
| W06 #286 | Champs/Select/Combobox/dialogues partagés ; tâches longues en page, confirmations contextualisées | IMPLEMENTED_UNQUALIFIED |
| W07 #287 | `LoadState`, avis et suivi des commandes existant, états distincts ; aucun second store | IMPLEMENTED_UNQUALIFIED |
| W08 #288 | Connexion, codes, inscription, invitations et récupération : composition commune `access.css`, saisie et contrôleurs conservés | IMPLEMENTED_UNQUALIFIED |
| W09 #289 | Ouverture d'école et opérateur ; révocation contextualisée, création durable et suites inchangées | IMPLEMENTED_UNQUALIFIED |
| W10 #247 | Accueil actif vers agenda, prochaine action réelle, préparation volontaire ; [planning](epic-280-planning.md) | IMPLEMENTED_UNQUALIFIED |
| W11 #255 | Guide unique en trois étapes, présentation compacte mobile et synthèse complète, personnalisation historique préservée | IMPLEMENTED_UNQUALIFIED |
| W12 #290 | Agenda jour/semaine, filtres mobiles repliables, leçons/cours/occurrences et retour daté | IMPLEMENTED_UNQUALIFIED |
| W13 #291 | Planification/fiche en page, participants/horaires/tarif, revue et accords de déplacement préservés | IMPLEMENTED_UNQUALIFIED |
| W14 #292 | Horaires et absences en cartes ; éditions versionnées, périodes et confirmations | IMPLEMENTED_UNQUALIFIED |
| W15 #293 | Annuaire d'élèves responsive avec recherche/tri et données administratives accessibles | IMPLEMENTED_UNQUALIFIED |
| W16 #294 | Dossier séparé en suivi pédagogique/gestion, champs et formulaires gardés montés, prérequis #253 conservés | IMPLEMENTED_UNQUALIFIED |
| W17 #295 | Équipe : accès lisibles avant modification, rôles/grants/retrait conservés et contrôlés | IMPLEMENTED_UNQUALIFIED |
| W18 #296 | Invitations en page, email/code/renvoi/révocation, portée et résultat durable inchangés | IMPLEMENTED_UNQUALIFIED |
| W19 #297 | Catalogue et programmes, rubriques mobiles, versions historiques ; [inventaire](epic-280-inventory.md) | IMPLEMENTED_UNQUALIFIED |
| W20 #298 | Tarifs en page, conditions communes/spécifiques et revue collective sans réécriture des anciennes conditions | IMPLEMENTED_UNQUALIFIED |
| W21 #299 | Cours en page, fiche par rubriques, séances et publication, report et annulation contextualisés | IMPLEMENTED_UNQUALIFIED |
| W22 #300 | Appel par occurrence, liste mobile des participants, règlements/validation/attente conservés | IMPLEMENTED_UNQUALIFIED |
| W23 #301 | Trajets avec élève/moniteur/date/durée et retour dossier ; aucun replay web inventé | IMPLEMENTED_UNQUALIFIED |
| W24 #302 | Coordonnées, fuseau, demandes de profil, aperçu et publication existante | IMPLEMENTED_UNQUALIFIED |
| W25 #303 | Textes/impact/confidentialité/GPS scolaire, lecture intégrale disponible et accords distincts | IMPLEMENTED_UNQUALIFIED |
| W26 #304 | Signalements, ordre/visibilité et aperçu ; alternatives clavier Monter/Descendre conservées | IMPLEMENTED_UNQUALIFIED |
| W27 #305 | Préférences personnelles, apparence, portée des notifications et aide à la demande | IMPLEMENTED_UNQUALIFIED |
| W28 #306 | Zones sûres/dvh, navigation mobile, reprise avec relecture d'accès et conservation du brouillon autorisé | IMPLEMENTED_UNQUALIFIED ; appareils physiques différés |
| W29 #307 | Audits dépendances, sécurité ciblée, [tailles](epic-280-foundation.md) et [mesures synthétiques](epic-280-performance.md) | Contrôles ciblés ; qualification exhaustive différée |
| W30 #308 | Routes conservées, 404 explicite, récupération de chunk, CSS obsolète retiré, [retour arrière](epic-280-delivery.md) | Candidat intégré ; bascule NOT_EXECUTED |
| W31 #309 | Manifeste, fixtures, preuves et recette préparés ; campagne #309/#84 après validation personnelle | DEFERRED_USER_TRIAL |

## Préservation et corrections d'intégration

- Contrats générés et OpenAPI canonique inchangés par la refonte. Les droits, OIDC/BFF, CSRF/Origin, CSP, RLS, If-Match, operationId, reçus et suivi durable existants restent les autorités. La dépendance API supplémentaire et la seule migration additive viennent de #253 déjà qualifiée, pas d'une API UI parallèle.
- Une restauration `pageshow.persisted` relit session et accès avant réaffichage. Pendant cette lecture, contenu scolaire `hidden`/`inert` et portails suspendus. Une erreur garde le masque et propose de réessayer. Même personne/école/permissions : brouillons montés conservés ; contexte changé : anciens champs purgés. Le verrou de déconnexion est réinitialisé après lecture fraîche ; le verrou d'une commande scolaire en cours ne l'est pas.
- La récupération de compte reste en nouvel onglet pour conserver la continuation d'ouverture d'école en mémoire. Les dates de retour agenda sont transmises au dossier et aux trajets. Les onglets dossier changent la visibilité sans démonter la saisie.
- Retrait du CSS `operations-studio.css` après remplacement par les styles planning/trajets ; retrait des anciennes compositions du shell, de l'entrée et des listes de personnes. Les wrappers `ui.tsx`/`choice-field.tsx` sont les adaptateurs métier vers l'unique socle shadcn, pas une seconde implémentation de contrôle. `formation-wizard.tsx` reste supprimé.
- Les rendus synthétiques ont révélé puis permis de corriger une entrée trop étroite, un agenda mobile trop haut et un conflit de grille sur les rôles à 320 px. Les contrôles de tri restent accessibles sur mobile.
- Aucun nouveau stockage scolaire navigateur, service worker, appel décoratif tiers, capture GPS, notification web ou compte de démonstration. Aucun secret ni donnée de production dans les preuves.

## Vérifications avant essai

TypeScript client, configuration et BFF ainsi que compilation de production web : PASS sous Node 24.22.1. Compilation API : PASS. Les dépendances de développement Vite/Vitest ont été corrigées aux versions exactes 8.3.5/5.0.5 ; audits racine et web sans vulnérabilité signalée au moment du contrôle. Les workflows et protections ne sont pas modifiés.

Le [contrôle court de sécurité](../../scripts/dev/check-web-280-access.mjs) passe ses six scénarios synthétiques : conservation du brouillon, masque pendant relecture, panne de session, retrait de rôle, changement de personne, commande sensible en vol et contrôles clavier associés. Ce sont des événements et réponses synthétiques Chromium ; ce n'est pas un essai de vrai bfcache ni de Safari physique. Les tests BFF ciblés et le détail exact des contrôles sont consignés dans la fondation.

Captures [reproductibles](../../scripts/dev/capture-web-280.mjs) de familles de pages à 320/390/1440 px, clair/sombre selon fichiers ; données fictives `example.test`. Les manifestes de rendu décrivent exactement les exécutions, les erreurs JS et la largeur réelle. Les fichiers `before-*` viennent de `e5166404`, les `after-*` du candidat. Chaque capture ne qualifie que son état visible, pas toutes les actions de la sous-vue.

L'API/migration intégrée est identique à la [source qualifiée #253](qualification-253-uxb-20261028.md), sauf mise à jour de Vitest de développement. Ses 796 tests PostgreSQL hérités ne sont **pas** annoncés comme une nouvelle exécution de #280. Aucun test Swift ni IPA nouveau n'est requis par ce lot web.

## Essai et livraison

Après accord final, sauvegarde fraîche, installation du SHA immuable API/web/worker, migration additive puis vérifications de publication selon le [plan homelab](epic-280-delivery.md). Aucun reset. Retour logiciel vers `a41cf64d` en conservant les écritures et la policy additive. La production actuelle est toujours `a41cf64d` avant cet accord.

À essayer personnellement : connexion et choix d'école ; agenda jour/semaine et leçon ; dossier élève ; cours et appel ; invitation ; programmes/tarifs/conditions ; coordonnées/confidentialité ; préférences et menu mobile. Les opérations utilisent les données réelles de l'école après déploiement. Les preuves synthétiques ne créent aucun compte pour cet essai.

Après publication, attendre le retour du porteur. Ensuite seulement, campagne complète #309/#84 sur le candidat, corrections des régressions, qualification des critères individuels, fusion et clôtures justifiées. **Essai du porteur, déploiement, validation finale et campagne intégrée : NOT_EXECUTED à ce stade.**
