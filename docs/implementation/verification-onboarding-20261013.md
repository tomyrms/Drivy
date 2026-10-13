# Vérification complémentaire de l’onboarding

La demande est de vérifier les parcours, l’interface et leur fluidité, puis de corriger les défauts prouvés. Point de départ : `2c396ae`, PR 31, plan des six lots déjà approuvé. Le tour précédent avait produit des preuves et un bilan ; cette passe réexamine le code et les écrans actuels au lieu de déduire l’absence de défaut des suites vertes.

## Défauts reproduits et corrections

| Parcours | Défaut vérifié | Correction |
| --- | --- | --- |
| Étapes du guide | À 390 px, le titre de l’étape suivante reçoit le focus mais reste 314 px au-dessus du viewport après Continuer. | Fermer le menu mobile puis afficher le début de l’étape et focaliser son titre. Le retour vers une erreur garde ensuite la priorité. |
| Informations des élèves | Une explication Téléphone vide produit `profile.fields` ; cliquer l’erreur ouvre l’explication Prénom valide. | Le serveur indique l’index exact ; l’interface ouvre le détail du champ correspondant, le centre et lui donne le focus. |
| Formations et tarifs | Une deuxième compétence vide cible le premier champ du programme ; une annulation vide peut pointer vers le déroulement valide. | Conserver les chemins précis de chaque erreur du serveur, sans message parasite sur un champ valide. |
| Erreurs du guide | Après le retour depuis la revue, le champ reçoit le focus sans afficher ni associer son message d’erreur. | Réutiliser les erreurs des contrôles partagés et leur description accessible ; retirer une erreur quand la valeur concernée change. |
| Création de l’école | Un fuseau « Zurich » produit un refus connu 400 présenté comme une réponse incertaine, sans champ ciblé. | Validation avant envoi, erreur associée au champ et ouverture du détail Fuseau horaire. Le serveur garde sa validation indépendante. |
| Écran d’ouverture | Les champs hors `.console-shell` ne reçoivent pas les styles des contrôles partagés ; une classe de masquage inexistante affiche la légende technique. | Étendre les règles des contrôles à `.opening-shell`, réutiliser `visually-hidden`, disposer l’identité du compte sur toute la largeur utile sur mobile. |
| Première leçon | Une école globalement prête peut encore manquer des disponibilités du moniteur affecté ou d’un tarif pour le permis de cet élève ; le lien renvoyait au dossier au lieu du réglage concerné. | Cibler les disponibilités du moniteur exact ou le guide d’ajout de tarif pour l’offre exacte, selon les contrôles serveur. |
| Entrée native avec plusieurs rôles | ADMIN + LEARNER ouvre l’espace élève mais cherchait son dossier dans les cinquante premiers dossiers administratifs. | Lecture personnelle filtrée au serveur, indépendante de la pagination administrative et incluant les dossiers archivés. [Contrat et limites](native-personal-learner-20261013.md). |

## Vérification exécutée localement

- 228 tests web, typecheck web/API et build web réussis après les corrections de saisie et de styles. Aucun résultat PostgreSQL ou Swift nouveau n’est déduit de ces contrôles Windows.
- Neuf contrôles clavier du guide : avancer, revenir et cibler l’erreur exacte à 320, 390 et 1440 px. Les captures avant/après ont été examinées.
- Quatre contrôles de récupération d’une réponse de sauvegarde perdue : reçu retrouvé, bonne étape, saisie conservée et aucune nouvelle commande. Activation puis ajout de formation après activation vérifiés dans le harness de rendu à 320 px.
- Les six étapes ont été examinées sans débordement à 320/390/640 px. Agrandissement CSS 200 % contrôlé ; le zoom natif du navigateur n’est pas qualifié par ce substitut.
- Ouverture : six rendus à 320/390/1440 px, clair/sombre ; champs de 44 px minimum, taille de texte 16 px sur mobile, pas de débordement. La saisie d’un fuseau invalide n’envoie aucune création et focalise le champ identifié comme invalide. Trois captures représentatives examinées, six rendus mesurés. Réponses BFF synthétiques : ces contrôles ne prouvent pas la persistance.
- Erreurs associées : huit rendus à 390/1440 px pour le téléphone, la deuxième compétence, la troisième description et l’annulation. Focus, détail ouvert, message visible et lié, disparition après édition vérifiés. Quatre contrôles supplémentaires conservent les erreurs des autres champs et empêchent leur transfert à un autre élément après retrait d’une compétence ou d’un champ demandé.

Les captures et résultats locaux figurent sous `artifacts/onboarding-review/` : `audit-transition-after-*`, `audit-profile-error-after-*`, `opening-final-*` et `opening-validation-audit.*`.

## Preuves intégrées sur cette révision

La recette `scripts/dev/check-school-opening.ts` ajoute les contrôles réels du fuseau avant création, de l’explication Téléphone depuis la revue et de la transition mobile depuis le bas d’une étape. Les trois erreurs de compétences/annulation sont ensuite corrigées depuis la revue, avec vérification du champ focalisé, du message associé et de sa disparition après correction. Elle conserve les parcours OIDC, SMTP, ouverture, reprise AP72, activation, catalogue, navigation et invitation déjà exécutés sur `75e79f9`.

Les nouveaux scénarios PostgreSQL couvrent les mauvaises destinations de prochaine action et le dossier personnel derrière plus de cinquante élèves, y compris identité, rôles, école, archive et curseur. Les nouveaux tests Swift couvrent la requête personnelle et le choix du bon chargement selon les rôles. La méthode UI `SchoolEntryTests/testAdminLearnerFindsOwnDossierBeyondTheFirstDirectoryPage` ajoute un scénario iPhone/iPad avec cinquante autres dossiers.

**IPA exécutée à `563166b`** : [compilation Release](https://github.com/tomyrms/Drivy/actions/runs/38419088103) réussie, version 0.7.0/build 268, archive non signée arm64 et empreinte SHA-256 vérifiée après téléchargement (`3d9feb2b2b6e886d532201539ab06c21ef94dd2d5fdd16ae64ee8a697bb9c9ac`). Fichier local : `artifacts/native-personal-ipa-38419088103/Drivy.ipa`. Les sources natives n’ont pas changé dans `5d42465`. L’API étendue doit précéder l’installation de cette IPA.

**API/web à `5d42465`** : [CI réussie](https://github.com/tomyrms/Drivy/actions/runs/38420532256), 439 tests API dans 37 fichiers, 228 tests web dans 19 fichiers, types et compilations réussis. Les 13 scénarios d’onboarding, les 14 scénarios d’ouverture et la migration synthétique peuplée 030→031/032 passent. L’intégrité documentaire est vérifiée séparément.

**Navigateur à `5d42465`** : [recette intégrée réussie](https://github.com/tomyrms/Drivy/actions/runs/38420532259), 53 contrôles Chromium 153.0.8010.12 avec Keycloak, SMTP, BFF, API et PostgreSQL. Le téléphone, la deuxième compétence, la troisième description et l’annulation sont ciblés et associés à leur message, puis corrigés avant l’activation. Les réponses perdues, reçus et reprises restent vérifiés. Bilan et sept captures téléchargés dans `artifacts/onboarding-web-ci-5d42465/`.

La première suite PostgreSQL à `563166b` avait échoué dans la préparation d’une nouvelle fixture : rattachements scolaires manquants avant création des dossiers. La fixture corrigée dans `5d42465` passe avec toute la suite. Ce premier échec n’était pas présenté comme une qualification du dossier personnel.

**Unités Apple à `563166b`** : [634 tests distincts réussis](https://github.com/tomyrms/Drivy/actions/runs/38419091299), soit 631 Swift Testing dans 60 suites et 3 XCTest ; 686 passages avec les cas paramétrés, aucun échec ni test ignoré. Les trois nouveaux tests couvrent la requête personnelle, quatre combinaisons élève/administrateur avec dossier actif/archivé, et trois combinaisons moniteur conservant l’annuaire. Simulateur iPhone 17 Pro, iOS 26.4.1. Rapports téléchargés sous `artifacts/native-personal-units-38419091299/`.

**UI Apple à `563166b`** : [nouveau parcours du dossier personnel réussi](https://github.com/tomyrms/Drivy/actions/runs/38419095872), un passage iPhone 17 Pro et un passage iPad Air 11 pouces M4, iOS 26.4.1, aucun échec ni test ignoré. Les deux captures du scénario ont été examinées : identité et école attendues, Mes informations, état sans formation, onglets élève adaptés et aucun autre dossier affiché. Rapports sous `artifacts/native-personal-ui-38419095872/test-reports/`. Les campagnes antérieures restent des preuves historiques et ne remplacent pas l’exécution des derniers changements.

## Audit de couverture et qualifications restantes

| Exigence | Preuve autoritative disponible ou prévue | Limite à conserver |
| --- | --- | --- |
| Lien sans saisie opérateur, aperçu sans consommation, création unique | Tests PostgreSQL d’ouverture et recette OIDC complète à `5d42465` | Fournisseur et messagerie de la cible réelle à configurer/qualifier |
| Étapes, exemples, adoption explicite, prix réellement saisi | Parcours navigateur intégré et validation métier transactionnelle | Les pratiques et textes d’une école réelle nécessitent sa relecture |
| Sauvegarde, reprise, concurrence et résultat incertain | Tests du brouillon, reçus AP72, conflits et pertes de réponse dans la recette intégrée | Une frappe non enregistrée d’un onglet fermé n’est pas une sauvegarde serveur |
| Navigation, erreurs, clavier, dimensions | Tests de routes, rendu clavier et scénarios intégrés renforcés | Lecteur d’écran réel et zoom natif non exécutés dans cette passe |
| Activation minimale et premières actions | Tests PostgreSQL de readiness, rollback et actions propres à l’élève | La recette jusqu’à la première leçon avec un responsable réel reste à mener |
| App selon le statut et les rôles, retour du portail | Tests Swift, UI entrée existante et nouvelle lecture personnelle | Les fixtures UI ne qualifient pas à elles seules Safari/OIDC réel ni la présentation automatique de la racine |
| Écoles existantes, références commerciales et migrations | Migration peuplée 030→031/032 et suites métier à `5d42465` | Aucun déploiement de cette branche ni essai physique GPS/batterie/VoiceOver |

La vérification automatique et les rendus examinés peuvent prouver des cas précis ; ils ne constituent pas une garantie absolue d’absence de bugs. L’objectif complet reste ouvert tant que les résultats requis et la recette humaine attendue ne sont pas établis. Le module GPS scolaire, désactivé par défaut et sans commande d’activation dans ce guide, conserve la limite documentée dans le bilan des six lots.
