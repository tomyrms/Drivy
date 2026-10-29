# Préférences de leçon : tarifs et conflits (#211–#213)

29 octobre 2026. Base `c94ec2bb`, branche `codex/ios-planning-invitations-20261029`.
Tickets ouverts, sans commentaire, relus via GitHub. Aucune PR ni correction dédiée retrouvée dans les branches
accessibles ; leurs trois constats sont encore présents dans `master`.

## Réalisation

- #211 : chaque tarif affiche son libellé, sa durée contractuelle et son montant CHF avec les formateurs existants.
  Un montant nul reste un prix valide. Durée manquante et produit indisponible ne reçoivent aucune valeur inventée.
  Clé de produit, éligibilité et prix des leçons engagées restent inchangés.
- #212 : changer de formation conserve un tarif admissible. Un tarif incompatible est retiré avec explication près
  du sélecteur et annonce accessible ; aucun autre tarif n’est choisi automatiquement. « Garder aucune préférence »
  acquitte explicitement cette information. Revenir à une formation antérieure ne rétablit pas un ancien choix.
- #213 : le conflit ouvre une comparaison des choix locaux non enregistrés et de la version de l’école. Annuler
  conserve la saisie. Deux décisions explicites : utiliser les valeurs de l’école, ou conserver ses choix comme
  brouillon à enregistrer. Ce dernier choix reprend la version relue pour `If-Match`, jamais une écriture forcée.
  Produit/formation retirés restent inéligibles et empêchent l’enregistrement jusqu’à correction.

La comparaison conserve le brouillon et la version examinés. Une modification locale plus récente, une nouvelle
lecture/version ou une commande en attente invalide ses boutons. Les réponses tardives de lecture/envoi ne remplacent
pas une saisie intervenue depuis leur départ. Un nouveau conflit serveur déclenche une relecture en gardant les choix.
La confirmation d’enregistrement exige toujours le reçu durable et la commande utilise l’outbox chiffrée existante.

## Références et vérification

Références : `COMMENCER_ICI.md`, F04/F05 et R08–R14 dans `03-fonctionnel/planning-lecons.md`, contrat et scénarios de
`planning-defaults-20260930.md`, `native-planning-settings-design.md`, `SchoolPlanningClient` et
`SchoolPlanningDefaultsTests`. Skills `ui-skills-root`/`swiftui-ui-patterns`, références état asynchrone et feuilles.

Exécuté : revue du diff, `git diff --check`. Six scénarios métier préparés : durée/prix nul/inconnu ; tarif conservé ou
retiré ; maintien local avec bonne version ; comparaison périmée par saisie/version récente ; produit retiré ; réponse
de lecture tardive. L’ancien scénario de conflit utilise maintenant la décision explicite de comparaison.

**NOT_EXECUTED** : tests Swift/UI, compilation Apple, rendu iPhone/iPad/Dynamic Type et VoiceOver physique. Le
coordinateur compile l’IPA groupée à la fin de la vague ; tests après essai du porteur. Aucune API, migration, web,
configuration CI ou dépendance modifiée. Aucun déploiement, push, fusion ni clôture d’issue par ce lot.
