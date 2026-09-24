# Commencer ici : refonte de Drivy

> Référence active 3.17 · 20 septembre 2026 · Documentation de conception, pas application livrée.

## Le mandat, sans ambiguïté

**Il s’agit d’une refonte assumée, et non d’une mise à niveau incrémentale imposée à l’ancienne application.** Le porteur a demandé de reconstruire les bases, les parcours, l’architecture et l’esthétique sans reprendre automatiquement la structure ou le design existants. L’ancien code sert de source de besoins, de cas limites et de composants éventuellement réutilisables après examen. Ni sa réécriture intégrale, ni sa conservation intégrale ne sont des objectifs en soi.


**Nom produit :** **Drivy** (D-R-I-V-Y), sans variante de marque concurrente dans la référence active. Les identifiants techniques internes déjà nommés `drivy` sont cohérents avec ce nom et ne nécessitent aucune migration cosmétique.

**Décisions validées :** client Apple en **Swift natif** pour iPhone et iPad ; Android ultérieurement, distinct ; direction A « Cartographie native » ; GPS central mais facultatif ; web, tablette, onboarding et cours collectifs avec inscription volontaire conservés. L’accord pour une refonte ne valide pas automatiquement toutes les entités, propositions commerciales ou règles de procédure.

**Besoin rétabli explicitement :** le moniteur doit pouvoir conserver une observation pendant la leçon, avec thème et statut, et la retrouver au bilan. Cette capacité ne se réduit pas au replay après la séance. Le dispositif précis reste une proposition à tester ; aucune saisie obligatoire en mouvement ni bouton photo dans la Live Map.

**Drivy est centré sur la carte et le suivi pédagogique des trajets.** Sa boucle principale est **enregistrer le trajet → signaler une observation → retrouver le passage dans le replay → construire le bilan**. Agenda, dossiers et gestion de l’école soutiennent cette boucle sans envahir la leçon. Le GPS reste volontaire et facultatif : les observations temporelles et le bilan existent aussi sans localisation.

**Orientation confirmée par le porteur le 20 septembre 2026 :** une bulle de signalement inspirée du principe d’interaction Waze, avec des catégories pédagogiques rapides et des animations soignées. Il s’agit de relever les erreurs et situations de conduite, pas de partager des incidents routiers avec une communauté. L’identité « Cartographie native », le nom Drivy, Swift natif et l’exclusion du bouton photo live sont conservés. Le principe est accepté ; la taxonomie complète, les dimensions, le mouvement exact et la sécurité d’usage restent à qualifier.

## Direction visuelle retenue

Le porteur a accepté le 20 septembre 2026 la recommandation suivante : composition inspirée de Plans, geste de signalement inspiré de Waze, hiérarchie inspirée de Flighty et sobriété inspirée de Things. **Peu de texte simultanément, sans masquer les états critiques.** Ce choix valide une direction, pas tous les détails de sa réalisation.

Ouvrir **[l’application unifiée](DESIGN/APPLICATION.html)** pour Séance, Agenda, Élèves et les bilans, ou [la carte directement](DESIGN/LECON.html). Les deux entrées partagent composants et sources ; les explications de revue restent hors de l’écran simulé. La [recherche complémentaire](01-recherche/coherence-application.md) motive l’extension sans changer de direction. La [galerie complémentaire](DESIGN/MAQUETTES.html) conserve les variantes non encore reprises ; les nouvelles compositions priment lorsqu’elles couvrent le même état.

## Le premier parcours à réaliser

Le premier incrément interne est : compte/école/formation → préparer et planifier une leçon → ouvrir la séance sur iPhone/iPad → capturer ou continuer sans GPS → conserver une observation → constater la séance → relire et publier un bilan → consulter ce bilan côté élève. La persistance, les droits et les erreurs font partie du parcours, pas d’une phase de finition.



### Règle de construction

La documentation décrit davantage de concepts que le premier incrément ne doit en matérialiser. **Une ligne du modèle n’autorise pas à créer une table, un endpoint ou un écran par réflexe.** G1/G2 se construit en tranches verticales : une action utilisateur, ses invariants serveur, sa persistance minimale, ses états d’erreur/hors ligne et ses preuves. Les projections, DTO et sous-objets restent dérivés ou embarqués tant qu’un cycle de vie, une contrainte, une rétention ou une requête indépendante ne justifie pas leur séparation. Voir le [profil d’implémentation G1/G2](05-realisation/perimetre-premiere-livraison.md#profil-dimplementation-g1g2).

Cela ne supprime pas les cours, les packs ou le web de gestion du produit visé. La [roadmap consolidée](05-realisation/roadmap-backlog.md) distingue **incrément interne**, **périmètre du pilote complet** et **extension future**. G3/G4 restent nécessaires avant le pilote complet annoncé en G5. Un incrément interne incomplet n’est pas présenté comme un lancement prêt pour des écoles.

## Lire selon la tâche

| Travail à effectuer | Références à ouvrir |
|---|---|
| Comprendre les décisions et ce qui reste ouvert | Ce document, [synthèse](00-synthese.md), [registre](06-gouvernance/glossaire-decisions-questions.md) |
| Implémenter une tranche | [Roadmap](05-realisation/roadmap-backlog.md), [périmètre des objets](05-realisation/perimetre-premiere-livraison.md), règle et scénario de la tranche |
| Concevoir la séance et le bilan | [R46](03-fonctionnel/regles-etats.md#r46), [saisie live](03-fonctionnel/gps-replay.md#saisie-pendant-lecon), [E23](02-experience/ecrans.md#e23), [maquette de leçon](DESIGN/LECON.html) |
| Développer les contrats et la continuité | [API](04-technique/api.md), [modèle](04-technique/modele-donnees.md), [Swift](04-technique/architecture-client-swift.md), [synchronisation](04-technique/synchronisation.md) |
| Vérifier une livraison documentaire | [Reproduction](06-gouvernance/revue-coherence.md), [audit courant](06-gouvernance/audit-corrections-v3-17.md) |
| Décider du sort de l’existant | [Transition du code et des données](05-realisation/migration.md) |

L’index complet reste dans [README](README.md). Le [lecteur hors ligne](LIRE_DOSSIER.html) donne accès à la référence ; les journaux d’anciennes versions sont des historiques, pas des étapes de lecture obligatoires. Les anciens identifiants d’ancres sont conservés pour les liens, même lorsque les sections ont été regroupées.

## Ce qui n’est pas encore acquis

Les entretiens et observations terrain n’ont pas été réalisés. Les détails d’interaction live, le démarrage GPS entièrement hors ligne, les conditions commerciales, les durées de conservation, les procédures mineurs/dernier administrateur et les objectifs de performance restent à valider selon le [plan de validation](01-recherche/vision-perimetre.md#validation-produit). Les variantes de maquette ne constituent pas cette validation.

Le système de suppression de compte est déjà spécifié (R103, AP193–AP198, E49/J29). **DM06 porte sur les procédures, délais, rétentions et cas du dernier ADMIN restant à qualifier**, pas sur l’absence de bouton ou d’API. Le passage en production n’est pas autorisé par le seul succès des contrôles documentaires.

**DM07** impose la même discipline aux qualités non fonctionnelles : sans cible approuvée et mesure requise sur un environnement qualifié, le domaine concerné reste `NOT_QUALIFIED`. Le dossier ne revendique donc aucune performance, autonomie, capacité ou disponibilité simplement parce qu’un parcours documentaire fonctionne.

## Ne pas confondre les versions et les preuves

Livraison documentaire et application : **3.17**. Fixture GPS et SVG statiques : **3.16**, conservés. Fixture des autres pages et registre de composants : **3.17**. Galerie complémentaire héritée : **3.14**, avec lien vers la référence courante. Contrat OpenAPI : **3.11.0** ; tokens : **3.8**, inchangés. Leurs numéros ne sont pas des versions de build. Les rapports anciens ne prouvent pas les nouvelles compositions.

Les cas de forme JSON et tests de la galerie/du lecteur peuvent être exécutés ici. Les **434 scénarios métier et 68 scénarios mobiles restent à exécuter sur le produit**. Aucun entretien, build Swift, trajet réel, transaction PostgreSQL ou validation juridique n’est déclaré réalisé par cette livraison.
