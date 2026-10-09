# Stabilité de la console web — 9 octobre 2026

Passe sur `apps/web`, sans refonte, nouvelle rubrique, déploiement ou écriture sur les données de l’école. Références relues : `COMMENCER_ICI.md`, R11–R15, R86/R95, API AP29/AP30/AP39/AP72, scénario T232, décisions de séparation app/administration web et tranches d’implémentation existantes. La documentation de conception reste intacte.

## Défauts corrigés

| Problème constaté dans le code | Correction |
|---|---|
| L’agenda ne lisait pas `actualStart` et ne distinguait pas la leçon passée non commencée d’une leçon réalisée. | Lecture du démarrage durable, fourni par l’API : sans démarrage, la leçon reste « En attente » après l’horaire prévu ; avec démarrage, « En cours », puis « À terminer » après la fin prévue. Une réalisation est indiquée « Terminée ». Aucune mutation automatique n’est déclenchée par l’heure. |
| Changer de semaine, moniteur, page de trajets ou ressource pouvait afficher les anciennes données sous la nouvelle sélection, y compris après échec de la nouvelle lecture. | `useLoad` associe les données à un périmètre explicite. Le précédent est masqué dès le changement de périmètre ; seule une relecture du même périmètre conserve ses données. La protection contre les réponses tardives est conservée. |
| L’annuaire de l’agenda excluait les dossiers archivés, malgré la présence de leurs leçons historiques. Un filtre visant un moniteur inactif pouvait aussi perdre sa commande d’effacement. | Lecture des élèves avec `status=ALL`. Annuaire et semaine sont chargés séparément ; le filtre conserve sa valeur et « Tous les moniteurs » même si la personne n’est plus active. |
| La console interceptait silencieusement un refus de déconnexion puis effaçait le suivi et redirigeait, alors que le serveur pouvait toujours détenir une session active. La page du compte effaçait aussi son état avant confirmation. | Fonction de déconnexion commune : CSRF relu, fermeture serveur attendue, état et suivi effacés après confirmation seulement. Une erreur reste visible et la demande peut être réessayée. Une session déjà fermée est reconnue sans second POST. |
| Après une mutation de ses propres droits, seule l’école était relue ; les anciennes rubriques et habilitations locales pouvaient rester visibles. Le retour depuis le cache du navigateur ne relisait pas les droits de la console. | `/me` est relu après une commande confirmée et au retour `pageshow.persisted`. Retirer ADMIN ferme les rubriques de gestion ; une variation de l’époque d’accès renouvelle le périmètre des brouillons. Un lecteur monotone empêche une ancienne réponse d’annuler un refus récent. Un refus 401/403/404 retire les anciennes données de gestion. L’API reste l’autorité pour chaque opération. |
| Les dialogues de permis, transition de formation, archivage et accès se fermaient après tout résultat, y compris un refus. Rouvrir un permis réinitialisait la saisie malgré le message « Votre saisie est conservée ». | Le refus garde le dialogue et ses champs. Son erreur s’affiche dans le dialogue actif. Une réponse confirmée ou incertaine ferme le dialogue, ce dernier cas étant repris par le panneau commun de suivi. Changer de dossier ferme également les intentions du dossier précédent. |
| Le tableau filtré des trajets annonçait encore « Trajets de l’école » aux technologies d’assistance. | Son intitulé suit le filtre élève réellement appliqué. |

Le démarrage et la fin d’une leçon restent dans l’app native. L’agenda web conserve sa fonction administrative en lecture seule. Les états « En cours » et « À terminer » n’apparaissent qu’à partir du démarrage enregistré ; un simple retard ne crée ni réalisation, ni annulation.

## Nettoyage et documentation

- La constante exportée `invitationCodeValidityDays` n’avait aucun usage dans le client, le serveur, les tests ou les scripts du dépôt ; elle est supprimée. L’expiration affichée et la validation serveur existantes sont conservées.
- Les quinze rubriques de `Section` ont une route et des liens de navigation principaux ou contextuels. Aucune suppression d’écran n’a été justifiée par cette revue.
- La lecture de l’annuaire a été extraite de celle de la semaine : changer la semaine ne recharge plus toute la liste des élèves et moniteurs.
- Le README web décrit désormais les rubriques effectivement présentes, l’entrée sur l’agenda, les états de lecture, la déconnexion et les limites actuelles. Ses anciennes mentions d’horaires, dossiers et formations non implémentés ont été retirées.
- Direction visuelle, tokens, espacements et composants existants conservés. Aucun défaut de disposition bloquant n’a été observé dans les vues ci-dessous ; pas de retouche CSS spéculative.

## Vérifications exécutées

Sur Windows, Node **24.6.0**, dans `apps/web` :

- `npm run typecheck` : réussi.
- `npm test` : **125/125 tests**, douze fichiers, aucun ignoré. Les vingt et un nouveaux cas couvrent cinq états/variantes de leçon, quatre cas de périmètre de lecture, cinq cas de déconnexion (confirmation, réseau, 403, 503, session déjà fermée) et sept cas de relecture des droits (réponses concurrentes inversées, invalidation lors du changement d’école, refus explicites et actualisation de l’époque d’accès).
- `npm run build` : réussi. Vite signale encore le poids du bundle principal, environ **511 kB minifié / 142 kB gzip** ; ce n’est pas une qualification de performance.
- `git diff --check -- apps/web` : réussi.

Navigateur intégré, uniquement sur `http://127.0.0.1:5173/app/test/visual.html` et ses données synthétiques :

- Agenda à **1280 × 900** et **390 × 844**, noms longs : horaires, élève, moniteur, « Terminée », « En attente », alerte de permis et commandes lisibles.
- Changement de semaine avec délai simulé de 1,5 seconde : la nouvelle semaine est affichée avec « Lecture de l’agenda… », sans les leçons de l’ancienne semaine ; la liste apparaît ensuite.
- Échec de déconnexion : erreur « Déconnexion non confirmée », compte et commande de déconnexion conservés, pas de redirection simulant un succès.
- Dossier à largeur mobile : ouverture depuis la liste, gestion de la formation, formulaire de permis. Après refus synthétique, la case et le motif restent saisis, l’erreur reste visible, les boutons Retour/Consigner restent accessibles.
- Passage dossier → trajets filtrés : nom de l’élève, moniteur, date et durée synthétiques présents ; retour au dossier proposé.

Captures relues, sans données réelles : [agenda bureau](assets/stabilite-web-20261009/agenda-desktop.jpg), [changement de semaine en cours](assets/stabilite-web-20261009/agenda-loading.jpg), [refus du permis sur petit écran](assets/stabilite-web-20261009/permit-refused-mobile.jpg). Le harnais `visual.tsx` ajoute les états `slow` et `mutation-error` pour reproduire les refus et lectures lentes ; il n’entre pas dans le build de production.

## Limites de preuve

Cette passe ne constitue pas une qualification navigateur de toutes les combinaisons d’écrans et de droits. Pas de session OIDC réelle ni d’écriture API/PostgreSQL depuis ces contrôles UI ; la persistance réelle relève des tests métier API et de la recette intégrée. Le retrait de ses propres droits et la restauration du cache de navigation sont corrigés et relus, sans recette OIDC complète de ces deux cas ici.

Non vérifiés dans cette passe : Safari/iPad physique, lecteurs d’écran, zoom 200 %, miroir RTL, thème sombre de chaque rubrique, historique de plus de 1 000 éléments, performance et fluidité sous charge. Les brouillons restent en mémoire et ne sont pas restaurés après rechargement ou reconnexion. Aucune donnée GPS, batterie ou VoiceOver physique n’est déduite de ces captures web.
