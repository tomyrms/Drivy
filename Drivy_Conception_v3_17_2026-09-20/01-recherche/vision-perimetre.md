# Vision produit et périmètre de référence

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

**Drivy est centré sur la carte et le suivi pédagogique des trajets.** Sa boucle principale est **enregistrer le trajet → signaler une observation → retrouver le passage dans le replay → construire le bilan**. Agenda, dossiers et gestion de l’école soutiennent cette boucle sans envahir la leçon. Le GPS reste volontaire et facultatif : les observations temporelles et le bilan existent aussi sans localisation.

**Orientation confirmée par le porteur le 20 septembre 2026 :** une bulle de signalement inspirée du principe d’interaction Waze, avec des catégories pédagogiques rapides et des animations soignées. Il s’agit de relever les erreurs et situations de conduite, pas de partager des incidents routiers avec une communauté. L’identité « Cartographie native », le nom Drivy, Swift natif et l’exclusion du bouton photo live sont conservés. Le principe est accepté ; la taxonomie complète, les dimensions, le mouvement exact et la sécurité d’usage restent à qualifier.

## Proposition de valeur

**Drivy transforme les situations réellement rencontrées en conduite en supports d’apprentissage que l’élève et le moniteur peuvent revoir.** La carte et le replay sont au cœur de cette proposition. L’organisation des rendez-vous, des cours collectifs et des packs permet de l’utiliser dans des auto-écoles différentes.

Le produit n’est ni un GPS de navigation généraliste, ni un système permanent de suivi des salariés, ni une application uniquement administrative. Il ne promet pas de détecter les contrôles visuels, le respect des priorités ou l’aptitude à l’examen à partir d’une trace de position.

## Besoins et origine

| ID | Besoin | Origine et limite |
|---|---|---|
| B01 | Préparer la journée et la leçon sans recomposer les informations | Brief et archive ; mêmes objectifs de continuité que la V1. |
| B02 | Décrire la leçon sans perdre la saisie, puis publier volontairement | Brouillons/synchronisation observés ; fiabilité à éprouver. |
| B03 | Pour l’élève, savoir où aller, quoi travailler et quel document fournir | Rendez-vous, progression et documents ; aucune efficacité chiffrée établie. |
| B04 | Éviter les engagements incompatibles | Planning individuel et collectif, validation serveur. |
| B05 | Donner les bons accès et clore une relation proprement | Séparation des écoles, droits, archivage et protection des données. |
| B06 | Comprendre les prestations et règlements | Étendu des leçons aux achats/packs et inscriptions, sans portefeuille monétaire. |
| B07 | Revoir un trajet et une observation au bon passage | Exigence explicite du porteur : GPS central. |
| B08 | Respecter le refus de capture sans pénaliser une leçon | Exigence explicite du porteur. |
| B09 | Adapter durées, prix, packs et sites | Recherche dix écoles, non enquête représentative. |
| B10 | Voir les cours disponibles et réserver une place | Demande explicite du porteur ; exemple Luc’s communiqué par lui. |
| B11 | Informer les élèves concernés sans spam ni inscription automatique | Demande explicite complétée par des règles proposées. |

## Cœur inclus

F01–F14 conservent leurs identifiants : identité/école, dossier, formations, disponibilité, réservation individuelle par personnel, préparation, réalisation, bilans, documents, comptes, notifications, continuité, configuration, vie privée. Leur périmètre est élargi là où les nouveaux parcours en ont besoin.

**F15 : capture GPS volontaire. F16 : replay et observations situées. F17 : catalogue, packs et droits. F18 : séries collectives, inscriptions et présences. F19 : agenda d’offres et ciblage des annonces.** Chaque fonction possède règles, écrans, données et contrats ; aucune n’est seulement une promesse dans la navigation.

Le pilote de capture vise la leçon individuelle en voiture sur le téléphone ou la tablette qualifiée du moniteur. Les autres catégories peuvent exister dans le catalogue avec profil approuvé ; cela ne signifie pas que le trajet individuel de chaque membre d’un groupe moto soit capturé. La première version collective vise une série complète avec plusieurs occurrences et non les rattrapages autonomes bloc par bloc.

## Rôle et prochaine action

Le moniteur retrouve sa séance, ses objectifs et le démarrage ; il peut conserver et qualifier des observations pendant la leçon, puis les relire dans le replay et le bilan. Le besoin de thème/statut en Live Map vient du porteur ; les gestes précis restent une proposition à qualifier. L’élève retrouve le bilan et sa prochaine étape, les engagements confirmés et les offres de cours non réservées. Le personnel d’école configure et publie sans recevoir de droits pédagogiques globaux. Un formateur collectif accède à ses listes et présences, pas automatiquement aux traces de conduite des inscrits.

## Principes qui arbitrent

La collecte est facultative, mais la fiabilité du parcours ne l’est pas. Les états d’inscription, présence, paiement et accomplissement restent séparés. Le serveur tranche la dernière place et le solde de droits ; un agenda en cache ne promet rien. Les options scolaires sont bornées : une école peut désactiver un module, pas la séparation des données ou le refus de suivi.

La simplicité visuelle ne doit pas masquer la durée contractuelle d’une leçon ou les dates d’un cours. Une confirmation de cours montre toute la série. L’app n’exige aucune saisie pendant le déplacement. Une erreur GPS doit être visible sans culpabiliser l’élève ni empêcher le bilan.

<a id="validation-produit"></a>
## Validation produit et hypothèse commerciale

**État : aucun entretien ni observation d’usage n’a été réalisé pour cette conception.** Les sites publics d’écoles éclairent l’offre, pas l’utilité réelle du replay ou l’effort de saisie. Le choix produit du porteur reste une direction à éprouver ; aucune statistique de demande ni willingness-to-pay n’est inventée.

| Hypothèse | Vérification proposée | Décision à prendre après observation |
|---|---|---|
| Noter au fil de la leçon réduit la reconstruction de mémoire | Faire comparer saisie d’un repère, thème/statut à l’arrêt et relecture finale sur une même séance fictive ; observer oublis, interruptions et effort | Choisir gestes et vocabulaire, conserver/simplifier les niveaux de saisie ; aucun geste en mouvement déclaré validé par défaut |
| Le replay aide à expliquer un événement | Faire retrouver et expliquer une observation avec trace, puis sans trace ; observer les erreurs de compréhension | Ajuster rôle du replay et priorité des observations, pas maximiser les kilomètres enregistrés |
| Le parcours sans GPS est réellement équivalent | Faire préparer, observer et publier une leçon sans permission GPS | Supprimer toute dépendance injustifiée à la capture |
| Les cours et packs correspondent à l’exploitation | Demander de reconstruire une offre réelle anonymisée, ses droits et une annulation | Qualifier les variantes nécessaires et différer les mécanismes non utilisés |
| La tablette apporte un avantage en situation de travail | Tester iPad et iPhone aux moments de préparation/bilan, avec grande taille de texte | Ajuster panneau, densité et continuité, sans copier un écran agrandi |

Commencer par deux écoles consentantes est un **recrutement exploratoire**, pas une validation du marché suisse. Inclure moniteur, personne administrative et élève lorsque pertinent, et des usages divergents (indépendant, multi-moniteurs, avec/sans packs). Utiliser des données fictives et un environnement sûr pour les interactions. Ne pas enregistrer de trajet ou de données d’un élève réel pour l’étude sans cadre approuvé. Consigner protocole, contexte, observations brutes, limites et décisions ; aucun résultat prérempli.

### Fiche de preuve pour chaque session de recherche

Une session ne ferme pas une hypothèse par impression générale. Conserver, sans données personnelles inutiles : identifiant de session, rôle et type de structure, scénario testé, appareil/contexte, observations factuelles, difficultés, citations courtes autorisées, comportement attendu/non attendu, hypothèse concernée, décision prise ou `INCONCLUSIVE`, responsable et date de revue. Séparer **ce qui a été observé** de **l’interprétation** et de **la décision produit**.

Pour la saisie pendant la leçon, noter au minimum : moment où le besoin d’annotation apparaît, possibilité réelle de reporter l’action, nombre d’éléments oubliés au bilan, erreurs de thème/statut, interruptions de conduite et préférence entre repère rapide, qualification à l’arrêt et saisie après séance. Ne pas demander aux participants de manipuler l’application pendant une situation de conduite dangereuse pour « tester » le concept.


### Vente et coûts : hypothèses à examiner

**Hypothèse de travail non validée :** l’école ou le moniteur indépendant paie pour l’organisation, la continuité pédagogique et les bilans ; l’élève n’a pas d’abonnement imposé par défaut. Comparer une facturation par moniteur actif et une formule par école avec utilisateurs inclus, sans fixer de prix ici. Le paiement de l’abonnement peut rester manuel pendant un pilote autorisé ; cela ne supprime pas le besoin d’accord commercial.

Pour chaque modèle candidat, renseigner revenu mensuel net par école, utilisateurs actifs, stockage de traces/documents, trafic, frais de communications, fournisseurs, sauvegardes et temps de support. **Contribution mensuelle par école = revenu net − coûts variables attribuables.** Les coûts fixes d’exploitation/développement restent séparés. Chaque entrée doit avoir date, source ou hypothèse ; aucun prix fournisseur, volume ou marge non mesuré ne devient un fait. La tarification des prestations de l’auto-école (F17) est distincte de celle du logiciel Drivy.

### Langues de lancement et internationalisation

**Proposition :** première expérimentation francophone, architecture de contenus localisables dès la première tranche ; FR/DE/IT restent des langues à sélectionner/qualifier avant disponibilité annoncée. L’échantillon d’écoles nationales ne prouve pas un lancement multilingue déjà décidé. preferred_locale est une préférence de personne, pas la langue d’enseignement d’un cours ni le fuseau de l’école.

Le client Swift utilise des clés/localisations natives et des pluriels, sans concaténer des phrases traduites. Le serveur renvoie des codes d’erreur stables et paramètres, pas un unique message français utilisé comme contrat. Web et notifications utilisent le même lexique validé ; contenu libre d’école non traduit automatiquement. Règle proposée de résolution : préférence prise en charge → langue de l’appareil prise en charge → langue de secours explicitement configurée. Dates selon locale, heures selon le fuseau métier affiché, montants en unités mineures et devise explicite. Tester troncature, grand texte, pluriels, offres dans une autre langue et préférence inconnue. Les traductions allemandes/italiennes ne sont pas déclarées faites par ce dossier.

### Mineurs et représentant légal

Le parcours mineur n’est pas retiré du produit ni traité comme cas exceptionnel. **Avant son ouverture réelle**, faire qualifier qui peut créer le compte et engager quelles prestations, quelle information reçoit l’élève, quand l’intervention d’un représentant légal est nécessaire et comment elle est prouvée/révoquée. Distinguer compte logiciel, contrat de formation, règlement, information GPS et accès aux données ; ne pas fusionner ces consentements.

La présente révision ne crée pas automatiquement un compte parent, un accès aux trajets ou une collecte de coordonnées parentales pour tous. Les règles d’accès nécessitent une habilitation précise et une finalité approuvée. Tester au minimum élève mineur, passage à la majorité, représentant contesté/changé, retrait GPS et demande de suppression. Toute capacité dépendant d’une règle non qualifiée reste bloquée à l’ouverture concernée, avec motif lisible et décision tracée ; pas de droit inventé à partir d’une simple date de naissance. [Questions Q06 et DM06](../06-gouvernance/glossaire-decisions-questions.md#q06).

## Validation du positionnement

Tester avec une école indépendante, une école sans forfaits et une structure à plusieurs moniteurs, sans présumer leur accord. Observer si le trajet rend le bilan plus concret, si les objectifs servent à la séance suivante, si la publication d’un cours réduit réellement les échanges nécessaires et si les élèves distinguent « disponible » et « inscrit ». Les refus GPS ne sont pas une métrique d’échec.

Pas d’objectif de kilomètres enregistrés, de couverture GPS forcée ou de taux de réussite inventé. Les [gates](../05-realisation/roadmap-backlog.md) distinguent prototype, implémentation, tests et disponibilité réelle.

## Besoins V3 et élargissement cohérent

| ID | Besoin | Origine et limite |
|---|---|---|
| B12 | Gérer en détail élèves, paramètres, archivage et activité au bureau | Demande explicite ; workspace connecté, même autorisation. |
| B13 | Enseigner et revoir sur tablette, avec confort au-delà du GPS | Demande explicite ; fréquence d’usage en Suisse non mesurée. |
| B14 | Accueillir progressivement élèves et personnel sur app/web | Demande explicite ; collecte conditionnelle et photo facultative sont des choix cohérents proposés. |
| B15 | Comprendre les chiffres sans double comptage ni surveillance | Déduction de conception pour répondre aux statistiques demandées. |

**F20** ajoute la configuration guidée de l’école. **F21** couvre les onboardings personnels et la reprise. **F22** spécialise les outils de gestion web et le cycle de vie contrôlé des dossiers. **F23** définit les indicateurs réellement calculables. Ils s’appuient sur F01–F19, non sur un second modèle. Le support tablette est transversal à toutes les fonctions, pas une option après le mobile.

Le produit vise un pilote iPhone/iPad + web de gestion et accès élève web, avec Android téléphone/tablette à qualifier avant disponibilité annoncée. Cette séquence est recommandée sous hypothèse de ressources limitées. Elle ne change ni la proposition de valeur GPS ni la liberté de ne pas enregistrer. Les tâches administratives soutiennent le parcours pédagogique au lieu de le remplacer.
