# Revue UI/UX native — 4 octobre 2026

## État

Les huit lots de la [passation](reprise-revue-ui-20261004.md) sont implémentés et relus dans le code depuis `fef94bf`, sur `codex/revue-integration-20260929`. Les huit lots ont été compilés sur Apple. La campagne initiale a exécuté 241 tests Swift avec succès ; un sélecteur de test de navigation iPad a été corrigé après son échec. La source courante est `e36b0d4` : elle ajoute le logo vectoriel demandé et corrige la fenêtre de la fixture Aujourd’hui. L’IPA 0.7.0/build98 est livrée. Le porteur demande ensuite de la voir sans attendre tous les tests : les campagnes restantes sont arrêtées, avec leurs limites conservées ci-dessous. Le [suivi de qualification](STATUS.md) et la passation portent leur état courant.

La revue suit `AGENTS.md`, `COMMENCER_ICI.md`, les règles, contrats et scénarios concernés. Elle conserve l’identité de `DESIGN.md` : composants et tokens Drivy, police système, navigation native, français et peu de texte. Aucun changement OpenAPI, serveur ou déploiement homelab n’a été nécessaire. Le partage automatique des leçons réalisées et la confidentialité suivent les [décisions du 28 septembre](decisions-2026-09-28.md).

## Huit lots

| Lot | Constats et changements |
|---|---|
| **1 — Squelettes, compte, trajets** | **P2 :** ajout de `DrivySkeletonBlock/Row/Rows` et `drivySkeleton`, puis emploi pour les premières lectures du compte et des trajets. Une erreur de lecture de l’école dans Trajets propose une reprise au lieu de rester présentée comme un chargement. Galerie et harnais complétés. |
| **2 — Aujourd’hui, démarrage** | **P2 :** le panneau montre la date, la prochaine leçon même lorsqu’une précédente reste à terminer, et le nombre exact des autres leçons. Les leçons closes passent au second plan. « Horaire commencé » ne prétend pas que la capture a démarré. La localisation non demandée ou refusée propose l’action appropriée. Relecture au premier plan, au changement de jour et après modification d’une leçon, avec rejet des réponses obsolètes. Démarrage : choix et lieu conservés sur panne transitoire, commande bloquée jusqu’à contexte valide ; purge sur refus explicite. |
| **3 — Leçon en cours** | **P2 :** annulation déplacée dans « Plus d’actions », avec le formulaire de confirmation existant. Onglets maintenus ; chevron de retour uniquement dans un écran poussé. Commandes de carte séparées du panneau inférieur pour laisser MapKit placer ses mentions. Squelette initial du dossier élève. |
| **4 — GPS et replay** | **P1 :** point affiché, ordre des publications après écriture et ancres pouvaient diverger de la séquence durable. Sélection pure de mesures réelles partagée par direct, replay et aperçu ; publications ordonnées et ancres sur séquence d’origine. Relecture du replay sans effacement sur panne et pagination complète de l’aperçu. Seuils et limites ci-dessous. |
| **5 — Agenda et planification** | **P1/P2 :** contenu du contexte courant et choix valides conservés pendant une relecture ; changement d’identité ou refus d’accès retirant les projections concernées. Disponibilités distinguant chargement, erreur et absence. Conservation des choix de formation, prestation et moniteur encore valides. Limites UTF-16 alignées sur le serveur. Conflit de version des préférences traité explicitement, confirmations commerciales conservées. |
| **6 — Dossiers et progression** | **P1 :** progression conservée sur panne, retirée sur refus de la ressource, contexte protégé fermé sur perte de session. Curseur de formations conservé jusqu’au résultat confirmé : une liste partielle ne semble plus complète pendant sa relecture. **P2 :** squelettes initiaux et dossier maintenu sur panne ; anciennes leçons planifiées exclues du prochain rendez-vous proposé à l’élève. |
| **7 — Leçon, bilan, observations, préparation** | **P2 :** squelettes initiaux de fiche, observations et choix de trajet ; maintien du contenu déjà lu. Champs des observations bloqués pendant l’envoi ou une demande incertaine. Confirmation avant abandon d’un retrait d’observation modifié. Préparation occupée protégée contre une fermeture accidentelle. Reprise après erreur et sélection accessible du trajet. États du bilan et de la fin de leçon relus. |
| **8 — Invitations, entrée, profil, accueil guidé** | **P1 :** options d’invitation appliquées après lecture complète ; panne conservant les choix et bloquant la création jusqu’à un contexte valide. Purge 401/403 incluant formations, moniteurs et sélections, sans suppression d’une commande incertaine. **P2 :** squelettes initiaux. **P3 :** retrait du badge ordinaire « en attente » et d’une note routinière du profil. Entrée par lien/code et composants École relus sans changement nécessaire. |

Les états chargement, vide, erreur, contenu connu, mutation, hors ligne, demande incertaine et reprise ont été examinés. Les adaptations grand texte/iPad ont aussi été examinées sur les captures Apple. Deux défauts de grand texte ont été corrigés : panneau Aujourd’hui tronqué et glyphes débordant des commandes fixes. Le clavier, les gestes et VoiceOver physiques restent à qualifier. Aucun nouveau P0 n’a été établi.

### Présélection de formation

Le permis B n’est pas forcé. `SchoolPlanningDefaults.trainingID(in:)` prend l’unique formation active disponible ; avec plusieurs formations, la catégorie préférée n’est retenue que si elle en désigne une seule. Sinon le choix reste à faire. Le démarrage exclut aussi les formations bloquées par le serveur. Une formation unique s’affiche en ligne fixe, plusieurs en sélecteur. Une sélection encore valide est conservée lors d’une relecture.

### Chargements

Le squelette remplace seulement une première lecture dont la forme est connue. Il reprend les lignes réelles — avatar, heure ou texte — et leur empilement en grand texte, avec largeurs déterministes bornées sur iPad. Apparition différée de **150 ms** ; balayage du masque à **30 images/s**, sans déplacement du contenu ; mouvement immobile avec Réduire les animations. Augmenter le contraste renforce les formes. Un seul libellé VoiceOver représente le groupe, dont les éléments décoratifs et les gestes sont désactivés.

Une relecture conserve le contenu courant. Mutation et pagination gardent un indicateur nommé. Un refus d’accès retire les données concernées, contrairement à une panne ; il ne supprime pas la file durable.

### Navigation et carte

Changer d’onglet laisse la capture active. Aujourd’hui utilise `location.fill` et la valeur accessible « Leçon en cours ». Aucun bouton de fermeture en racine ; chevron pour revenir à une fiche poussée. La croix ne devient pas une annulation.

« Plus d’actions » dispose d’une cible de **48 pt**, avec « Voir la leçon » et « Annuler la leçon ». Motif et confirmation d’annulation restent requis. Les identifiants `capture-more` et `capture-cancel-lesson` sont repris dans les tests UI. Le harnais live utilise les vrais onglets.

Les commandes de carte sont en superposition avant l’insertion du panneau inférieur. Les mentions Apple Plans sont visibles au bord inférieur de la carte dans les captures utilisables. Le contrôle sur iPhone physique reste requis. En grand texte, une page défilante permet de conserver les contenus ; seuls les symboles des commandes de taille fixe sont bornés, les textes restent adaptatifs.

## GPS : choix explicites et limites

Collecte, stockage chiffré et transfert conservent les mesures brutes. `SchoolCaptureDisplayRoute` sélectionne uniquement des mesures réelles : aucune interpolation, aucun lissage de coordonnées, aucun recalage routier.

| Règle | Seuil et effet |
|---|---|
| Précision | Coordonnées finies et légales, précision horizontale de **0 à 35 m** ; sinon point écarté et fragment interrompu. |
| Saut | Distance diminuée des incertitudes des deux positions, divisée par le temps écoulé, au plus **55 m/s**. Un saut isolé est écarté sans fabriquer de position intermédiaire. |
| Arrêt | Dernière mesure retenue maintenue dans un rayon adaptatif de **2 à 8 m**, issu de la précision. Un déplacement cumulé peut quitter ce rayon ; aucune vitesse minimale ne supprime un virage lent. |
| Ordre et lacunes | Séquences durables d’origine et temps croissants. Une séquence manquante ou plus de **15 s** sans point retenu coupe le fragment ; la reprise après absence de signal ne relie pas artificiellement les deux côtés. |
| Ancre live | Dernier point retenu seulement s’il est réellement le dernier point brut et âgé d’au plus **15 s**. Aucun signalement n’est déplacé vers le voisin d’un point écarté. |

Marqueur, cap, caméra, vue d’ensemble et ancres utilisent la même sélection. Sans point retenu, la caméra attend une mesure utilisable. Les callbacks après écriture durable sont publiés dans l’ordre. Le replay fusionne les lots par segment avant sélection, conserve l’horloge d’origine et les lacunes, puis recalcule la projection via `contentRevision` après relecture. L’aperçu lit la pagination complète, valide publication et qualité, puis déduplique ; limites de protection : **1 000 pages, 100 000 points**.

Onze tests Swift sont ajoutés : neuf dans `SchoolMapCourseTests`, un dans `SchoolCaptureLifecycleTests`, un dans `SchoolCaptureInteropTests`. Cas couverts : départ imprécis, saut, dérive à l’arrêt, giratoire lent, tunnel/lacune, lots en désordre, segments séparés, ancre sur point écarté. Ces onze tests font partie des 241 tests Swift réussis dans la première campagne Apple.

Ces seuils sont des choix techniques non calibrés sur une trace réelle du porteur. La lecture du code identifie les mécanismes possibles ; elle ne prouve pas à elle seule la cause du trajet qu’il a observé. Le filtre peut raccourcir la trace ou produire des lacunes visibles, sans revendiquer une meilleure précision des mesures.

## Relectures croisées

### Évaluateur A : quatre constats corrigés

Relecture indépendante des diffs Aujourd’hui, démarrage, agenda, planification/préférences, composants Agenda/Séance, live, onglets, squelettes et harnais depuis `fef94bf`.

| Priorité | Constat et correction |
|---|---|
| **P1** | Démarrage conservant noms, formations et lieu après refus. Purge dans `load/select` sur 401/403 ou identité non liée ; refus de l’historique facultatif désormais propagé. Test de quatre lectures — préférences, élèves, formations, historique — en 401 et 403. Commit `e243551`. |
| **P2** | Disponibilités vidées sans nouvelle lecture lorsque l’identifiant moniteur ne changeait pas. Relecture explicite après chargement du contexte. Commit `10ba55e`. |
| **P2** | Préférences saisies conservées mais version silencieusement remplacée, permettant d’écraser une modification concurrente. Conflit explicite bloquant l’enregistrement, puis action « Utiliser les préférences actualisées » ; test de version différente. Commit `10ba55e`. |
| **P2** | Simplification de la confirmation retirant aussi les explications d’erreurs. Messages ciblés rétablis pour horaire passé, motif commercial absent et limites de longueur. Commit `10ba55e`. |

Aucun autre P0–P2 établi sur ces diffs par A ; conclusion limitée au code.

### Évaluateur B et détecteur

B a terminé sa relecture indépendante et signalé un **P2** supplémentaire : les disponibilités déjà connues disparaissaient pendant leur relecture. Correction implémentée et transmise à l’intégrateur : maintien des disponibilités et fermetures pour le même moniteur pendant la relecture ou une panne, indicateur d’actualisation distinct du squelette initial, purge au changement de moniteur ou au refus d’accès. Trois tests ajoutés couvrent relecture suspendue puis 503 et récupération, changement de moniteur avec réponse tardive, et purge 403. Ces trois tests, ajoutés après la première campagne, ne sont pas déclarés qualifiés : le porteur a demandé d’arrêter l’attente des campagnes finales pour recevoir l’IPA.

Impeccable **0.1.7**, `detect --json apps/ios/Drivy` : sortie **[]**, code **0**, **106 Swift** inclus. Les règles du détecteur ciblent HTML/CSS ; une sortie vide ne valide donc pas SwiftUI. La revue native suit `audit.native.md` et doit être complétée par captures/appareil. Aucune exclusion, configuration locale ou exemption inline n’a été ajoutée.

## Skills réellement appliqués

Le contexte Impeccable a été exécuté ; iOS a été choisi manuellement car sa détection retournait `null`. `DESIGN.md` fait autorité en mode Operate. Les lectures ont été poursuivies pendant les lots et `craft-floor.md` relu avant les éditions d’interface.

| Référence | Recommandation appliquée |
|---|---|
| Impeccable (`.claude/skills/impeccable/SKILL.md`, installation locale) : `ios.md`, `operate.md`, `critique.md`, `polish.md`, `craft-floor.md` | Conserver l’identité existante ; vérifier les états réels, espaces sûrs, retour et onglets natifs ; classer les défauts P0–P3. |
| Impeccable `harden.md`, sections erreurs/chargements | Maintenir le contenu utile sur panne et distinguer premier chargement, erreur et absence : dossiers, progression, agenda, invitations, replay. |
| Impeccable `quieter.md`, `distill.md`, `onboard.md` | Réduire le bruit sans masquer les décisions : annulation en menu, retrait de badges ordinaires et notes routinières, aide contextuelle et étapes facultatives. |
| SwiftUI UI patterns (`.claude/skills/swiftui-ui-patterns/SKILL.md`, installation locale) : `async-state`, `loading-placeholders`, `tabview` | Garder les données connues lors des relectures, reprendre l’anatomie finale dans les squelettes et porter l’état de capture au niveau de l’application. |
| Interaction design (`.claude/skills/interaction-design/SKILL.md`, installation locale), Accessible animation (`.claude/skills/accessible-animation/SKILL.md`, installation locale), Better accessibility (`.claude/skills/better-accessibility/SKILL.md`, installation locale) | Mouvement limité au masque, apparition différée, Réduire les animations, grand texte, libellé VoiceOver unique, sélection annoncée. |
| Interactive hit areas (`.claude/skills/interactive-hit-areas/SKILL.md`, installation locale) | Menu de leçon 48 pt et cibles existantes préservées pendant la simplification. |
| Balise UX writing (`.claude/skills/balise-ux-writing/SKILL.md`, installation locale), `references/interface-patterns.md` ; Better writing (`.claude/skills/better-writing/SKILL.md`, installation locale) | Libellés persistants, reprises compréhensibles, pagination nommée, consentement distinct, explications limitées aux erreurs et décisions utiles. |
| SwiftUI Liquid Glass (`.claude/skills/swiftui-liquid-glass/SKILL.md`, installation locale) | Styles natifs existants réservés aux commandes flottant sur la carte. |
| Write Swift (`.claude/skills/write-swift/SKILL.md`, installation locale) | Signatures compatibles, paramètres par défaut pour les appelants et harnais, logique pure testable et état isolé au modèle. |
| Apple design HIG (`.claude/skills/apple-design-hig/SKILL.md`, installation locale), Mobile native (`.claude/skills/mobile-native/SKILL.md`, installation locale) | Relecture clavier, toucher, continuité et grand texte du lot 8 ; recommandations web non transposées artificiellement en SwiftUI. |

Le `SKILL.md` Apple HIG distinct a été lu par l’intégrateur, mais ses références annoncées étaient absentes. Leur application n’est pas revendiquée.

## Icônes et signalement

La demande complémentaire du porteur est intégrée : cinq propositions ImageGen pour l’application et cinq dessins vectoriels par thème, dont le marqueur neutre ; 65 propositions originales conservées. Une famille sélectionnée puis affinée remplace les anciennes images. « Signaler » utilise une grille sobre, une action de marquage distincte et trois appréciations explicites. L’icône de l’application et son image d’accueil sont identiques. Voir [choix et comparaisons](native-icon-signal-review-20261004.md). Le [skill logo-design installé à la demande du porteur](drivy-logo-skill-20261004.md) a ensuite permis une reprise vectorielle en trois pistes, avec sélection du d continu et deux passes optiques.

## Vérifications Apple et locales

| Campagne | Source | Résultat observé |
|---|---|---|
| [Vérifications générales 37208423190](https://github.com/tomyrms/Drivy/actions/runs/37208423190) | `0aec970` | Réussie : 224 tests API avec vraie PostgreSQL, 104 tests web, types, builds et contrôles documentaires. |
| [IPA 37208423174](https://github.com/tomyrms/Drivy/actions/runs/37208423174) | `0aec970` | IPA non signé construit. |
| [Première campagne native 37207341781](https://github.com/tomyrms/Drivy/actions/runs/37207341781) | `99b35bf` | Compilation réussie, 241 tests Swift/23 suites, 3 tests de présentation par appareil et 12 UI iPhone réussis. UI iPad : 11/12 ; seul échec = test cherchant `TabBar` alors qu’iPad expose des cellules d’onglet flottant. Sélecteur corrigé par libellé et type Button/Cell, sans coordonnées. |
| [Captures normales initiales 37207343731](https://github.com/tomyrms/Drivy/actions/runs/37207343731) | `99b35bf` | 44 PNG inspectés, 11 écrans sur deux appareils et deux apparences. 43 utilisables ; iPad live clair masqué en haut par une notification système. Fixture Aujourd’hui à corriger : requête de journée non filtrée. |
| [Captures AX initiales 37207345568](https://github.com/tomyrms/Drivy/actions/runs/37207345568) | `99b35bf` | 20 PNG inspectés. 18 utilisables ; iPad Aujourd’hui clair blanc, iPad live-waiting clair masqué par notification système. Today et commandes AX corrigés à partir des autres captures. |
| [Campagne finale native 37209322885](https://github.com/tomyrms/Drivy/actions/runs/37209322885) | `10f1d12` | Tests arrêtés à la demande du porteur après compilation réussie ; aucun verdict final retenu. |
| [Captures finales normales 37209324641](https://github.com/tomyrms/Drivy/actions/runs/37209324641) | `10f1d12` | Réussie, 24/24 PNG ouverts et inspectés individuellement. Commandes, 11 catégories et marqueur, 3 appréciations lisibles sur les deux appareils/apparences ; aucun nouveau P0–P2 établi. Today et ancien logo proviennent de 10f, remplacés depuis. |
| [Captures finales AX 37209326488](https://github.com/tomyrms/Drivy/actions/runs/37209326488) | `10f1d12` | Réussie, 24/24 PNG inspectés individuellement à résolution native ; aucun nouveau P0–P2 établi. Limites de champ ci-dessous. |

La matrice AX3 finale confirme Aujourd’hui, les commandes visibles du replay et les trois appréciations de Signaler. Limites : les commandes de carte live iPhone et les dernières catégories sont hors du champ initial défilant ; elles ne sont pas déclarées visuellement qualifiées par ces captures. Ces limites ne constituent pas un test VoiceOver.

Le transport synthétique Aujourd’hui filtre désormais les fenêtres from/to avec le même chevauchement strict que le serveur. Trois tests couvrent bornes, chevauchement et historique inchangé. Des attentes d’identifiants d’écran ont été ajoutées aux captures pour éviter de qualifier un lancement vide.

| Livraison complémentaire | Source | État |
|---|---|---|
| [Vérifications 37210789140](https://github.com/tomyrms/Drivy/actions/runs/37210789140) | `e36b0d4` | Réussies. |
| [IPA 37210789141](https://github.com/tomyrms/Drivy/actions/runs/37210789141) | `e36b0d4` | Réussie : IPA 0.7.0/build98, téléchargement et SHA-256 vérifiés. |
| [Tests natifs 37210798960](https://github.com/tomyrms/Drivy/actions/runs/37210798960) | `e36b0d4` | Annulée avant démarrage à la demande du porteur. Les 3 nouveaux tests de fixture ne sont pas exécutés. |
| [Aujourd’hui et logo 37210800901](https://github.com/tomyrms/Drivy/actions/runs/37210800901) | `e36b0d4` | Arrêt demandé par le porteur ; aucune qualification nouvelle déduite. |
| [Aujourd’hui et logo AX 37210802959](https://github.com/tomyrms/Drivy/actions/runs/37210802959) | `e36b0d4` | Annulées à la demande du porteur ; 2 captures AX iPhone récupérées et inspectées, limites ci-dessous. |

`git diff --check`, syntaxe Bash via Git Bash, comparaison des 12 ressources sélectionnées avec leurs imagesets et contrôle des 60 SVG candidats réalisés. Les tests Python de captures sont exécutés sous Git Bash avec Python UTF-8 ; ils simulent les commandes Apple et ne qualifient pas l’application native. Le premier essai Windows sans UTF-8 échouait sur le décodage d’une assertion française ; les commandes n’ont pas été modifiées pour masquer un résultat Apple.

Les captures finales utilisent XCUITest pour attendre l’état de l’écran. Un fichier PNG présent ou un workflow de capture réussi ne suffit pas à valider visuellement le produit. Les traces, noms et lieux du harnais sont synthétiques.

## Qualification physique restante

- Route réelle : départ imprécis, intersections, giratoire lent, tunnel, arrêt prolongé, pause/reprise, ancres et effets des seuils. Aucun résultat GPS ou batterie physique n’est déduit du simulateur.
- VoiceOver sur appareil, clavier, gestes, changement d’onglet et retour depuis la fiche ; position des mentions Apple Plans sur l’iPhone.
- Signature et installation de l’IPA par le porteur avec iLoader. Aucun déploiement homelab lié à cette revue native.

## Livraison demandée sans attente des tests

Le porteur privilégie explicitement le push et l’IPA rapide. Le code était déjà poussé ; le brouillon concernait seulement la PR. [PR5](https://github.com/tomyrms/Drivy/pull/5) retirée du brouillon, campagnes restantes interrompues sans déclarer leurs tests réussis. L’IPA Release arm64 non signée provient de `37210789141`, source `e36b0d4`, SHA-256 `2bd5a34c4073ccd49fdfb21b93ba305cf631216f24b3c7ce95fcf3bb9d0a8e2e`. Aucune nouvelle compilation nécessaire pour les dernières modifications documentaires.

Les artefacts partiels des captures complémentaires ont été récupérés après l’arrêt : aucune PNG normale et deux PNG AX iPhone portrait clair inspectées (Aujourd’hui et connexion). Aujourd’hui montre bien les quatre leçons de la journée ; aucun nouveau P0–P2 établi sur ces deux vues. Les quatorze autres vues prévues ne sont pas qualifiées. Le logo est volontairement masqué dans la connexion en AX : ces captures ne qualifient pas son intégration visuelle.

Contrôle distinct de la PR : GitGuardian annonce trois détections sur `e36b0d4` (check `111461991780`, aucune annotation). Les chemins et types ne sont pas exposés dans le résumé accessible ; seule une adresse de tableau de bord est fournie. Détections non vérifiées, aucun faux positif supposé. Ce contrôle n’est pas présenté comme réussi.
