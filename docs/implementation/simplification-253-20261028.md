# Épic #253 — parcours simplifié, livraison de qualification

Mandat élargi par le porteur aux autres lots de l’épic, puis autorisation de travailler avec plusieurs agents. Branche `codex/simplification-253`, issue de `2c15a061` (premier accueil, PR #278). Le checkout de messagerie de l’autre intervenant n’est pas modifié. Aucun ticket n’est fermé sur la seule existence du code. Les prototypes abandonnés de `s01-premier-usage/` ne font pas partie de cette livraison.

## Parcours retenu — S01

Web administrateur : ouvrir l’école avec ses coordonnées → choisir les permis enseignés → confirmer la durée et saisir le prix réel → répondre aux questions communes de paiement/annulation → relire le résumé → préparer le premier élève et son rendez-vous → utiliser l’agenda au quotidien. Trois étapes principales du guide : permis, prix/règles, résumé. Identité, textes et champs élèves restent modifiables depuis le résumé. Une identité manquante ou une erreur garde son éditeur accessible. Une information technique inconnue n’est pas remplacée par une réponse inventée.

App : invitation par code → connexion ou compte → informations requises à cette étape → choix GPS personnel, y compris refus ou décision reportée → agenda → élève et leçon → départ autorisé → observations → bilan et replay. L’adoption des textes par l’administration ne répond pas à la place de l’élève. Le moniteur conserve le parcours terrain existant, les protections de synchronisation et les composants Drivy. Le skill `swift-native-components`, explicitement demandé, a conduit à réutiliser les composants SwiftUI/Drivy ; aucune bibliothèque ajoutée.

Le nombre d’étapes du guide est observable dans le code ; aucun gain de temps ou résultat utilisateur n’a été mesuré. Aucun deuxième assistant ni prototype préalable supplémentaire.

## État par sujet

| Sujet | Réalisation dans cette branche | Limite / qualification restante |
|---|---|---|
| S01 #254 | Parcours ci-dessus, divulgation progressive, séparation bureau/terrain | Essai utilisateur |
| S02 #255 | Guide existant ramené à trois étapes, reprise du brouillon, résumé éditable | Adoption sur données synthétiques à vérifier |
| S03 #247 | Accueil actif sur agenda, première préparation explicite (commit 2c15a061) | Rôles et petites largeurs à essayer |
| S04 #256 | Code réévaluable, changement de code, récupération du compte sans perdre l’intention | Invitation expirée/réponse perdue à exercer |
| S05 #257 | Aperçu court du formulaire ; politiques par étape et exigences serveur conservées | Pas de nouvelle collecte générale |
| S06 #258 | Prochaine action réelle, prise en compte rendez-vous confirmé/réalisé | Premier rendez-vous complet à essayer |
| S07 #259 | Matrice versionnée et sourcée des 17 catégories/restrictions | Voir lacunes précises de la matrice ; aucune certification |
| S08 #260 | Programmes distincts, clés stables, provenance, pas de variante créée par défaut | Propositions pédagogiques `NOT_QUALIFIED`, G/M séparés de la pratique |
| S09 #261 | Comparaison, confirmation des ajouts seuls, personnalisation/historique conservés | Évolutions réglementaires complexes et transfert volontaire de dossiers hors mécanisme automatique |
| S10 #262 | Aide contextuelle datée dans dossier/permis, sources et inconnus | Pas de preuve structurée des cours ni de connexion SARI ; aucun acquis déduit |
| S11 #263 | Durée/prix réels, tarif par leçon, date scolaire proposée, pas de fin imposée | Prix null bloquant ; zéro reste un choix explicite |
| S12 #264 | Questions communes, procédure versionnée, échéance avant réservation | Migration additive préparée, non exécutée ; collectifs et leurs 24 h distincts conservés |
| S13 #265 | Une version de conditions partagée, publication groupée avec impact et conflit | Exceptions et engagements anciens conservés ; changement d’annulation exige sa procédure |
| S14 #266 | Cartographie des faits, recherche officielle, décision par traitement | **Activation GPS obligatoire réelle bloquée** : exploitant/accès/sauvegardes/durées et qualification non résolus |
| S15 #267 | Textes factuels préremplis, résumé, adoption distincte du choix personnel | Conservation inconnue explicitement à compléter, pas de promesse fictive |
| S16 #268 | Choix GPS réel dans accueil ; refuser ou reporter conserve l’accès | Appareil et compte synthétique à essayer |
| S17 #269 | Préparation sans `actualStart`, démarrage atomique par capture, serveur bloque l’ancien départ si qualifié | Activation limitée à la configuration de qualification, vide par défaut |
| S18 #270 | Choix du compte réutilisé, contrôle de version d’un nouvel accord, refus prioritaire | Multi-appareils/hors réseau à qualifier ; bail distant non instantané |
| S19 #271 | Pipeline interruptions conservé, provenance moniteur explicite, aucun mode de repli inventé | GPS obligatoire limité à B/BE en qualification ; positions moto non assimilées à l’élève |
| S20 #272 | Carte, pauses, observations, arrêt existants conservés après revue | Aucune nouvelle preuve physique GPS/batterie |
| S21 #273 | Compétences liées à la leçon d’abord, autres dépliables ; aucun niveau inféré | Revue du bilan sur appareil |
| S22 #274 | Aide native courte, contact scolaire réel, diagnostic public copié explicitement | VoiceOver/grands textes non qualifiés |
| S23 #275 | Ancien assistant `formation-wizard.tsx` supprimé, route réutilisant le guide unique, retrait du lien de variantes | API/historique anciens conservés ; LEGACY nécessaire tant que #266 bloque l’activation |
| S24 #276 | Compilation et recette décrites ci-dessous, fixtures ciblées préparées | Essai du porteur, tests ciblés et contrôles requis avant toute fusion |

Références : [matrice suisse](regles-suisses-20261028.md), [données et GPS](donnees-et-gps-253-20261028.md), [annulation individuelle](regles-annulation-individuelle-20261028.md), [accueil/bilan/aide natifs](simplification-native-accueil-bilan-aide-20261028.md), [premier accueil](accueil-premier-rendezvous-20261028.md).

## Compatibilité et contrats

OpenAPI canonique 3.11.0 inchangée. Extensions d’implémentation : `apps/api/contracts/school-setup-draft.json`, `formations.json`, `practical-start.json` et champ facultatif `cancellationRules` de la procédure, décrit dans la note S12. Le texte des règles communes est généré pour le web depuis le module API, source unique ; publication finale calculée par le serveur. Schémas, droits, revue d’impact, versions et reçus idempotents continuent de faire autorité.

Une notice valide d’ancien serveur sans `practicalStartPolicy` vaut LEGACY, conformément au contrat historique. Une panne de lecture ou une valeur inconnue ne le vaut pas. L’IPA seule ne déploie ni la politique GPS ni les changements web/API. Les anciens choix verbaux ne permettent pas un départ GPS_REQUIRED. Un nouvel accord désuet ne remplace pas un refus plus récent. Les baux, la révocation et les files chiffrées existantes restent en place.

## Vérifications effectuées avant l’IPA

### Ajout demandé : 15 corrections de l’audit UX B

Branche intégrée dans la branche de travail : `claude/replay-audit-b42-b44-20261028`, SHA `db855a853f9c64b438d521e25fbe2666f50145a5`. Son [run Apple indépendant](https://github.com/tomyrms/Drivy/actions/runs/40727684500) a réussi. Le premier run de #253 seul (40730352252) est abandonné après élargissement ; une nouvelle IPA doit compiler le commit combiné.

- Cours #221–226 : langue renseignée, prochain cours et offres visibles ensemble, confirmation de refus/sortie, échéance d’offre relue, titre/séance/contexte du cours, enregistrement d’un règlement.
- Replay #233–236 : vocabulaire et aide, observation entière, pause sur sélection, recherche/filtres cohérents dans carte/liste/chronologie/suivi. La provenance des positions ajoutée pour #253 est conservée.
- Messages #239, #242–245 : causes lisibles, erreurs de sondage contextualisées, protection de la saisie, état/portée de recherche et extrait trouvé en gras. L’accès Messages de qualification reste inclus dans le build manuel.

Ces changements supplémentaires sont uniquement natifs. Ils n’ajoutent aucune migration ou exigence de déploiement aux modifications #253 décrites ci-dessous. Tester ces trois groupes dans la même IPA ; les tests ciblés et UI de leur branche restent préparés, non exécutés, pour après l’essai du porteur. Aucun des 15 tickets fermé et aucune fusion vers `master`.

Le 28 octobre 2026, Node 24.22.1 : typage API complet **PASS**, compilation API **PASS**, typage web **PASS**, compilation web **PASS**. Avertissement Vite existant sur le script classique `theme-init.js`, compilation terminée. Générateurs des trois contrats exécutés. Aucun test PostgreSQL, Swift, navigateur ou physique exécuté pour cette tranche. La migration SQL n’a pas été exécutée. La compilation Apple est à relever dans la preuve de livraison après le run, jamais déduite de ces contrôles TypeScript.

## Recette proposée

1. Installer l’IPA non signée via iLoader ; vérifier connexion, invitation et changement de code, récupération du compte puis choix GPS dans Mon profil. Refuser/reporter doit laisser compte et rendez-vous accessibles.
2. Sur une école synthétique servie par cette version API : préparer B et A, saisir les vrais prix de l’essai, choisir les règles communes, reprendre le brouillon, confirmer. Vérifier une échéance et l’absence d’échéance sur une ancienne procédure inconnue. Un second permis identique doit renvoyer vers sa fiche.
3. Inviter un élève synthétique, fournir seulement les informations requises, ouvrir sa formation, affecter son moniteur et planifier. Revenir à l’agenda sans refaire le guide.
4. Essayer une leçon, observer puis terminer le bilan : compétences liées d’abord, autres accessibles, contenu privé toujours privé. Consulter le replay partiel et l’aide ; la copie du diagnostic n’envoie rien.
5. GPS_REQUIRED se teste seulement sur une école synthétique explicitement configurée : absence/refus de choix, permission retirée, perte réseau, réponse de départ perdue, retrait depuis l’autre compte. Ne pas réaliser de manipulation UI au volant. Aucun essai réel tant que #266 reste bloqué.

Pour le web sans production : utiliser les environnements locaux synthétiques décrits dans `apps/web/README.md` et `apps/api/README.md`, avec les migrations sur une base locale uniquement. Après leurs prérequis, Node 24 : `node --import tsx scripts/dev/run-api.ts` et `node --import tsx scripts/dev/run-web.ts` dans deux terminaux, puis `http://127.0.0.1:3002/app`. Ne pas relancer la commande Atrium d’aperçu déjà existante. La procédure est fournie ; aucun serveur de cette version n’a été annoncé comme démarré.

Après retour du porteur : corriger, exécuter les tests ciblés onboarding/règles communes/contrats/GPS et les tests Swift correspondants sur Apple, puis les contrôles requis du dépôt avant fusion. Les résultats GPS, batterie, VoiceOver et participant restent **NOT_EXECUTED** tant qu’ils ne sont pas observés.

## Déploiement éventuel — proposition non exécutée

Services concernés : API, web/BFF et schéma PostgreSQL. Authentification OIDC, messagerie, OSRM et collecte active ne nécessitent aucune reconfiguration de ce lot. `GPS_ONLY_QUALIFICATION_SCHOOL_IDS` reste vide en production ; liste d’UUID synthétiques seulement dans un environnement de qualification autorisé.

Migration `20261028_individual_cancellation_rules.sql` : une colonne JSONB nullable et sa contrainte sur `school_policy_version`. Aucun backfill, effacement ni réinterprétation d’un texte historique. Elle doit précéder la nouvelle API. Avant déploiement homelab : obtenir l’accord explicite sur ce plan, relever versions/overrides réellement en service, sauvegarder la base et vérifier sa lisibilité, qualifier la migration sur une copie synthétique, publier API puis web.

Retour arrière : remettre les versions API/web relevées avant bascule ; conserver la colonne additive et les nouvelles versions de données, que l’ancien code peut ignorer. Aucun DROP ni restauration écrasant des actes récents. Une restauration éventuelle demande un inventaire des écritures depuis sauvegarde et une décision séparée. Un rollback ne falsifie ni conditions déjà acceptées ni historique des choix GPS. **Aucun déploiement, migration homelab ou fusion exécuté pour ce lot.**
