# Synthèse : Drivy, une refonte orientée leçon

> Référence de conception **3.17 · 20 septembre 2026**. [Index](README.md) · [Commencer](COMMENCER_ICI.md).

**Drivy** est centré sur la carte et le suivi pédagogique des trajets. Sa boucle principale est **enregistrer le trajet → signaler une observation → retrouver le passage dans le replay → construire le bilan**. Agenda, dossiers et gestion de l’école soutiennent cette boucle sans envahir la leçon. Le GPS reste volontaire et facultatif : les observations temporelles et le bilan existent aussi sans localisation.

**Orientation confirmée par le porteur le 20 septembre 2026 :** une bulle de signalement inspirée du principe d’interaction Waze, avec des catégories pédagogiques rapides et des animations soignées. Il s’agit de relever les erreurs et situations de conduite, pas de partager des incidents routiers avec une communauté. L’identité « Cartographie native », le nom Drivy, Swift natif et l’exclusion du bouton photo live sont conservés. Le principe est accepté ; la taxonomie complète, les dimensions, le mouvement exact et la sécurité d’usage restent à qualifier.

## Référence active et portée

La V3.17 étend le style apprécié aux parcours hors carte et unifie leur fabrication. [APPLICATION.html](DESIGN/APPLICATION.html) propose 16 compositions supplémentaires ; les quatre vues de carte sont conservées. Les 20 compositions correspondent à 17 écrans existants, non à 20 fonctions ajoutées. [LECON.html](DESIGN/LECON.html) ouvre directement le parcours GPS, depuis les mêmes sources. Les primitives communes et leurs usages sont recensés pour les 49 écrans ; 26 restent sans rendu. Les détails visuels restent à valider.

La refonte autorise une nouvelle architecture, navigation et esthétique détaillée. Elle n’autorise pas la suppression implicite des besoins utiles. La [transition du code](05-realisation/migration.md#transition-code) distingue réutilisation à qualifier, remplacement et migration de données. Aucun code de l’application n’est modifié dans ce ZIP.

## Préparer, vivre, revoir, progresser

Le moniteur prépare une leçon, conserve ses observations, formule un bilan et prépare la suivante. L’élève consulte ses engagements, documents et publications autorisées. L’école gère personnes, offres, cours, disponibilités, droits et activités selon les permissions, sur un même système.

La saisie en direct est un besoin connu du porteur. Le [parcours proposé](03-fonctionnel/gps-replay.md#saisie-pendant-lecon) sépare repère rapide privé, observation avec thème/statut à l’arrêt et évaluation publiée. Les statuts d’événement ne sont pas des niveaux de compétence. Aucune observation n’est publiée ni transformée en note sans action explicite. Sans GPS, le texte et la qualification restent possibles sans créer de position. Un bouton simple n’est pas une preuve de sécurité et l’interaction en circulation n’est pas validée.

## Premier incrément et produit cible

La [roadmap](05-realisation/roadmap-backlog.md) est structurée par G0–G5 et GA0, non par compléments de versions. G0 qualifie les bases ; G1 ouvre l’identité, l’école, les formations et le planning ; G2 réunit leçon, observations, bilan, capture facultative et décompte. Ces tranches internes sur données fictives ne sont pas un lancement public. Les cours, packs composites, gestion, confidentialité et exploitation du périmètre cible restent nécessaires à leurs jalons.

Le [registre de périmètre](05-realisation/perimetre-premiere-livraison.md) justifie les objets logiques et leur première tranche. Il ne transforme ni 101 entrées de documentation en 101 tables SQL, ni l’accord de refonte en validation de toute complexité proposée. Le chiffrage doit être établi par lots après décomposition et calibration, pas déduit du nombre d’entités.

## Design et couverture

[L’application unifiée](DESIGN/APPLICATION.html) propose **20 compositions couvrant 17 écrans métier**, dont 16 compositions hors carte. La [galerie complémentaire](DESIGN/MAQUETTES.html) conserve les variantes non encore reprises : **23 des 49 écrans ont au moins une illustration, 26 restent sans rendu**. La correspondance de composants couvre les 49 fiches mais ne vaut pas illustration de tous leurs états. Clair, sombre, grand texte et fenêtres iPad sont présents. La capture active et le bilan terminé utilisent des fixtures séparées ; aucun GPS, serveur ou stockage applicatif durable n’est disponible.

## Ce qui est spécifié, ce qui reste à valider

La référence contient 23 fonctions, 29 parcours, 112 règles, 49 écrans, 201 opérations et 376 schémas. Les **434 scénarios métier et 68 mobiles** restent NOT_EXECUTED. Les contrôles documentaires et navigateur ne remplacent pas ces essais.

**DM06** : les routes de suppression globale sont spécifiées ; responsabilités, délais, rétentions, dernier administrateur et essais restent un **blocage de publication**. **DM07** : les budgets de performance, autonomie, synchronisation, restauration et accessibilité doivent être approuvés puis mesurés ; sans cela, ils restent `NOT_QUALIFIED`. La recherche utilisateur, les hypothèses commerciales, l’internationalisation, les mineurs et représentants légaux font l’objet d’un [plan explicite](01-recherche/vision-perimetre.md#validation-produit), sans résultats inventés. Les appareils et builds natifs restent à qualifier.

[Rapport de revue](06-gouvernance/audit-corrections-v3-14.md) · [Fonctions prévues](01-fonctionnalites-prevues.md) · [Décisions](06-gouvernance/glossaire-decisions-questions.md).
