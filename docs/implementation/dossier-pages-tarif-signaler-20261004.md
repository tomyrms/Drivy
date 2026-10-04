# Dossier par pages, tarif affiché et palette Signaler — 4 octobre 2026

## Retour du porteur

Après build102, le tarif ouvre une fenêtre qui répète le montant déjà visible ; la palette Signaler demande un petit défilement inutile ; le dossier doit commencer par la fiche de l’élève puis donner accès à des pages distinctes pour ses leçons et sa progression.

## Réalisation

Le montant convenu et le solde réellement lu sont du texte dans la fiche de leçon, sans chevron, bouton ni feuille tarifaire. Le solde n’est pas remplacé par zéro lorsque sa lecture n’est pas disponible.

La palette Signaler compacte passe de 480 à 520 pt ; le mode feuille utilise le même budget fixe. Les colonnes de catégories peuvent mesurer 100 pt pour conserver trois colonnes sur un iPhone de 375 pt. Le popover iPad reste à 480 × 560 pt. Défilement et grande feuille restent disponibles pour les petits espaces, les erreurs et les tailles de texte importantes. Aucun retour au dimensionnement mesuré ou aux gestes personnalisés rejetés sur build99.

Le dossier commence désormais par une carte unique : identité, coordonnées, date de naissance et adresse lorsqu’autorisées, catégories de permis en formation. Modifier ouvre l’éditeur réel avec le même modèle ; fermeture et actualisation relisent les données enregistrées. Les changements non enregistrés ne sont jamais présentés comme confirmés dans la carte.

Deux entrées sous la carte poussent les pages Leçons et Progression, avec retour natif au Dossier. Avec plusieurs formations, chaque catégorie a ses deux entrées. Les filtres, bilans, évaluations, pagination et modèles de formation existants sont conservés. Démarrer et Planifier restent en bas du dossier. Le changement d’élève, de compte ou de droits réinitialise le chemin et invalide les lectures de profil obsolètes. Chargements initiaux, erreurs avec reprise, absence de formation et demandes non confirmées restent visibles.

La lecture administrative utilise AP175 et sa projection serveur existante : un moniteur affecté reçoit identité et contacts ; date de naissance et adresse sont réservées à ADMIN ou au profil propre. Les champs omis pour une raison de droit ne deviennent pas des mentions « non renseigné ». Aucun droit n’est élargi. Le suivi samaritains/sensibilisation n’est pas encore implémenté ; aucun accomplissement de cours ni statut de permis contrôlé n’est déduit de la catégorie de formation. Ce besoin reste ouvert pour une tranche métier dédiée.

La relecture a découvert un cas de reprise transversal : un écran générique pouvait rapprocher une création d’observation alors qu’une intention durable de retrait était attachée. Le rapprochement commun refuse désormais cette intention composée ; seul le client d’observations peut rapprocher CREATE puis REMOVE. Le profil indique le retour à la leçon et ne propose plus une vérification inadaptée pour ce retrait.

## Références appliquées

AGENTS.md, COMMENCER_ICI, F02/F03 et contrat AP175/AP176 restent les références fonctionnelles. Aucune modification du dossier de conception, du contrat canonique ou du serveur.

Impeccable : `layout` et `operate` pour l’ordre identité → pages ; `craft-floor` pour les actions réelles, états explicites et absence de modal de lecture superflu ; `harden` pour les erreurs et la projection des droits. SwiftUI UI Patterns : NavigationStack et navigation typée, état hors des branches conditionnelles, conservation du contenu pendant une relecture. Typographie, tokens, contrastes et composants Drivy existants sont conservés. Les actions de contact et de modification ont une cible d’au moins 44 pt ; les lignes passent en pile avec le grand texte.

## Vérification et livraison

Relecture des fichiers complets et revue croisée effectuées. `git diff --check` propre. Détecteur Impeccable layout sans résultat ; son analyse source ne qualifie pas le rendu SwiftUI. Les fixtures synthétiques lisent le profil via transport isolé et outbox en mémoire, sans données de production. Les assertions de capture et le test de navigation existants suivent la nouvelle racine et les allers-retours ; les tests de reprise du retrait sont complétés.

Compilation Release Apple et livraison IPA rapide prévues après push. À la demande du porteur, aucune campagne Apple de tests ou de captures. Les nouvelles assertions ne sont pas déclarées exécutées. Dimensions réelles, gestes de navigation iPhone/iPad, grand texte et VoiceOver restent à vérifier sur appareil. Aucun résultat physique GPS ou batterie n’est revendiqué.
