# Planification des leçons sur le web — 26 octobre 2026

Issue suivie : [#51](https://github.com/tomyrms/Drivy/issues/51). Références relues : F04/F05, R06/R08–R14, AP39–AP43/AP72 et T017–T020 de la conception conservée ; API `lessons.ts`, extensions déjà utilisées par l’app et décision #61 sur les annulations. Aucun fichier de la livraison de conception modifié.

## Réalisation

L’administration peut créer une leçon depuis Ajouter → Leçon, ouvrir la fiche depuis une ligne de l’agenda, modifier une leçon non commencée ou l’annuler avec un motif explicite. La fiche conserve un accès au dossier élève. Semaine, filtre moniteur, recherche et sélection restent dans l’agenda ; une création hors de la semaine ne déplace pas silencieusement le planning. La préparation de la première leçon ouvre maintenant ce formulaire.

Le formulaire lit élèves, formations actives, affectations, moniteurs, offres, procédures et versions commerciales autorisés. La liste élève est recherchable et distingue les homonymes. Les formations affichent leur nom métier avec une référence courte en cas de doublon, jamais `offeringKey` : la projection API expose le `label` déjà en base (extension documentée dans `apps/api/contracts/offering-label.json`, sans migration ni changement des droits). Aucun prix de démonstration n’est choisi : seuls les produits courants, actifs, de la bonne catégorie, compatibles avec la durée, la date et les conditions approuvées sont proposés. La marge après la leçon est séparée de sa durée et du prix. Une lecture tronquée bloque la confirmation au lieu de prétendre être complète.

La disponibilité est demandée à `GET lessons/availability`, qui vérifie ouvertures, fermetures et occupation commune aux leçons et aux cours. Le web n’ajoute pas de moteur de disponibilités. La commande finale revérifie les règles en transaction ; la vérification préalable ne réserve rien. Le récapitulatif montre élève, formation, moniteur, début/fin dans le fuseau de l’école, rendez-vous, prix et textes applicables. Une heure locale inexistante est refusée ; une heure répétée exige le choix explicite du passage.

Un déplacement conserve par défaut la durée, la marge, le prix et les conditions de la leçon. Changer la durée ou le tarif est un choix séparé qui impose une nouvelle prestation et un motif ; `commercialChange` est absent autrement. L’accord de l’élève et du moniteur est recueilli explicitement. La version relue par le formulaire reste figée malgré une revalidation en arrière-plan. Un conflit 412 garde la proposition et permet une relecture explicite de la version actuelle ; l’accord doit être reconfirmé.

Les écritures utilisent le même magasin de commandes que les autres rubriques : operationId stable, Idempotency-Key, If-Match pour déplacer/annuler, suivi AP72 si le résultat est inconnu. Elles partagent le domaine de conflit planning. Aucun rendez-vous optimiste n’est annoncé comme confirmé. Les champs sont bloqués pendant une vérification ou une demande incertaine, et les refus corrigibles gardent les valeurs. Le formulaire intact ferme directement ; les changements et le motif d’annulation sont protégés. Les données saisies restent en mémoire : seuls les identifiants de l’opération sont conservés par le mécanisme de reprise du bureau.

Le BFF autorise explicitement les quatre chemins nécessaires (availability/create/move/cancel), avec paramètres bornés et If-Match. Aucune route de démarrage, fin de séance, capture GPS ou proxy arbitraire n’est ajoutée.

## Vérifications exécutées

- PostgreSQL réel sur la base de recette isolée : `apps/api` → `TEST_DATABASE_URL=… npm run test -- test/catalogue.integration.test.ts test/lessons.integration.test.ts --no-file-parallelism`, **10/10**. Création, refus de droits, conflits de créneau/tampon, ouverture/fermeture, déplacement versionné avec accord, annulation, réponse idempotente, AP72, retrait d’affectation et libellé métier de formation. Le seul changement API est le libellé additif décrit plus haut.
- Web : `npm run test -- test/lesson-planning.test.ts test/school-bff.test.ts test/command-core.test.ts test/command-store-code.test.ts test/agenda-model.test.ts test/console-route.test.ts`, **113/113**. Dont heure inexistante/répétée, contrat préservé, changement commercial explicite, tarifs invalides, affectation couvrante, libellé sans clé technique, barrière de version BFF et reprise des trois commandes sans seconde mutation après réponse perdue.
- `npm run typecheck` et `npm run build` : **passent**. Avertissement existant sur le script classique `theme-init.js` lors du build.
- Recette navigateur locale synthétique `test/visual.html?page=agenda&agenda=lesson-planning&shell=1` : création à 100 CHF, modification du lieu en conservant les 95 CHF d’origine, annulation explicite et affichage dans la même semaine ; fermeture avec saisie → retour → saisie conservée. Les captures sont dans `proofs/planning-web-20261026/` et ne contiennent que des données fictives.
- Variantes navigateur `state=mutation-error` et `state=response-lost` : le refus SLOT_CONFLICT garde le lieu saisi ; la réponse perdue expose le panneau AP72, sans annoncer l’annulation, puis « Vérifier auprès de l’école » retrouve le reçu et l’état Annulée sans deuxième mutation. Cette recette a identifié puis corrigé un dialogue modal qui empêchait d’atteindre le panneau de reprise : un résultat incertain ferme seulement le récapitulatif, le formulaire reste verrouillé et la même demande reste suivie.
- Revue indépendante du modèle/éditeur et comparaison à l’API par l’agent du socle web : pas de défaut bloquant identifié.

## Limites maintenues

La console conserve sa frontière actuelle **ADMIN** conformément au mandat « app terrain, web administration ». L’API autorise déjà le moniteur affecté et les règles du nouveau formulaire en tiennent compte, mais l’ouverture d’un bureau restreint aux moniteurs n’est pas livrée ici. **#51 n’est donc pas déclaré intégralement clôturable.**

L’interface du bureau ne propose ni modification ni annulation après `actualStart`. L’API conserve la décision plus récente #61, qui permet à un personnel habilité d’annuler une séance commencée mais non terminée depuis les parcours existants : ce lot ne prétend pas introduire un refus serveur contraire à cette décision.

La recette navigateur utilise un transport synthétique, distinct de la suite API avec PostgreSQL réel. Le parcours navigateur complet BFF + API + OIDC réel, les petits écrans et lecteurs d’écran restent à qualifier. Aucun résultat VoiceOver physique ni fonctionnement GPS n’est revendiqué. Aucun déploiement effectué.
