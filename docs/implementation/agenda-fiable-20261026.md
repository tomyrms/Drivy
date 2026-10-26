# Agenda : lectures fiables et chronologie commune

26 octobre 2026. Issues #144, #145, #146, #147, #172, #173 et #175, sous l'epic #132. #175 complète le critère d'ouverture de la leçon exacte demandé par #144.

## État courant

Le lot est qualifié pour intégration, suivie avec la clôture des tickets par la [PR #178](https://github.com/tomyrms/Drivy/pull/178). Le produit correspond à `23b19f30baa7225ba5d686c18a8c005a494b51cc` : 58 tests métier Apple et 62 exécutions avec paramètres réussis, IPA 381 non signée vérifiée. Les contrôles habituels ont réussi sur le dernier commit `00f0f45` : 745 tests API/PostgreSQL, 363 tests web, typages, build et intégrité documentaire. L'ouverture d'école sur `b42e5ea` et la recette Edge ciblée ont également réussi.

Le dernier commit `00f0f4595400c66838d0d17728562f1c0df79f70` ajuste uniquement les deux tests UI précédemment en échec ; produit et fixtures restent inchangés depuis `23b19f3`. Les [deux cas UI relancés](https://github.com/tomyrms/Drivy/actions/runs/40320751020) ont réussi sur iPhone 17 Pro et iPad Air 11 pouces M4 : exactement deux tests par appareil, sans échec ni saut. Avec les quatre autres cas déjà réussis sur chaque appareil dans `bee144c`, les six cas sont couverts sur chacun des deux appareils ; seuls deux ont été réexécutés sur `00f0f45`. Les [contrôles habituels de ce commit](https://github.com/tomyrms/Drivy/actions/runs/40320751047) ont également réussi.

Les 24 captures après correction et les 7 références valides ont été inspectées. Les captures après restent rattachées à `849bb27` et ne constituent pas une qualification globale de ce candidat, dont la recette UI avait révélé un défaut de reprise.

## Base et périmètre

Branche `codex/agenda-fiable-20261026`, issue de `master` `fcfdfde0408cf2a5a84ddabb54bc8bacb6693a77`, dans un worktree séparé. Les fichiers de l'agenda étaient identiques à ceux de la branche de messagerie `6bfea69` examinée au départ ; les modifications locales du dossier principal sont conservées.

Références : `COMMENCER_ICI.md`, R34/R37 (portée et révocation), R55/R64 (offres et engagements), T155/T156/T157 (calendrier et fuseau), contrat canonique AP147 OpenAPI 3.11.0. Le lot réutilise les routes API existantes `lessons` et `course-series` décrites dans `cours-collectifs-socle-80.md`, sans migration.

Le lot traite les erreurs de lecture, l'actualisation des sources, le filtre par formateur de séance, le tri commun, les repères, les compteurs et l'ouverture du rendez-vous choisi. Aucune réservation, publication, inscription ou règle de droit n'est modifiée.

## Réalisation

- Natif : lecture des cours indépendante des leçons, reprise ciblée, conservation uniquement à portée identique et purge des accès refusés. Compte, école, droits, filtre, fuseau et fenêtre participent à la portée. Les réponses dépassées sont ignorées. Tirer pour actualiser et revenir au premier plan relisent les deux sources. Les tests métier d'interruption et de refus d'accès ainsi que la reprise UI ciblée ont réussi.
- Web : le bouton Actualiser et la relecture automatique relisent leçons, répertoire et cours, sans doubler les requêtes en vol ni perdre sélection, focus ou recherche. L'heure globale est la plus ancienne des lectures réussies ; une source en erreur interdit le statut global « À jour ».
- Projection commune sur chaque support : ordre début, fin puis identité stable ; une occurrence est distincte de sa série. Brouillons et annulations restent identifiés. Le filtre porte sur le formateur de la séance, pas le responsable de la série. Repères et compteurs reprennent la projection affichée.
- Couverture : `course-series` est borné à 200 séries sans pagination. Atteindre cette borne rend la couverture potentiellement partielle ; aucune exhaustivité n'est affirmée. La recherche web par élève annonce son périmètre limité aux leçons.
- Navigation : le web conserve l'UUID de la leçon dans la route, relit le rendez-vous exact et vérifie école, élève, leçon et bilans. La liste blanche BFF autorise uniquement le `GET lessons/:id` nécessaire. Sur les deux supports, la séance sélectionnée est ciblée dans la fiche ou le formulaire existant. Une cible retirée est signalée sans choisir arbitrairement une autre séance.

## Qualification ciblée

Les transports de revue sont synthétiques, sans accès à une école réelle. Les fixtures natives mixtes contiennent un cours à 09 h, une leçon à 11 h, un cours à 14 h et un lendemain avec seulement un cours. Les variantes d'erreur provoquent une panne de première lecture ou de relecture. Les quatre scénarios de transport ajoutés après correction de l'enveloppe synthétique traversent les vrais clients et ont été exécutés dans la campagne métier `849bb27`.

L'exception temporaire de cette branche, utilisée conformément à #132/#84 pendant les push intermédiaires, est retirée avant intégration : `qualification-checks.yml` et `school-opening-e2e.yml` sont restaurés exactement à la base `master` `fcfdfde` dans `23b19f3`. Aucune protection GitHub n'a été modifiée. Les vérifications habituelles ont révélé un paramètre inutilisé dans un test API préexistant (blob identique à la base) ; `b42e5ea` le renomme `_series`, sans changer les appels ni assertions. Sous Node 24.22.1, les [vérifications après correction](https://github.com/tomyrms/Drivy/actions/runs/40318236760) sont réussies : 745 tests API sur PostgreSQL, 363 tests web, typages, build et intégrité documentaire. L'[ouverture d'école](https://github.com/tomyrms/Drivy/actions/runs/40318236608) est réussie aussi.

Le scope Apple `agenda` sélectionne les tests d'agenda, de chargement des cours et du transport synthétique. Métier, UI, captures et IPA sont exécutés séparément. Une compilation n'est pas une preuve de fonctionnement.

### Web et scripts

Sous Node 24.22.1, la [campagne finale `00f0f45`](https://github.com/tomyrms/Drivy/actions/runs/40320751047) fournit la référence complète : 363 tests web et 745 tests API/PostgreSQL réussis, avec les typages client/tests/serveur et les builds. Les contrôles ciblés antérieurs de projection, route, dossier et BFF ont également réussi ; ils ne sont pas additionnés à ces totaux. Les sources web et API sont inchangées depuis `b42e5ea`.

La recette Edge utilise les vraies vues React avec transport synthétique :

- Trois défauts reproduits sur la référence : ordre 09 h / 14 h / 11 h, cours masqués par le filtre moniteur et cours non actualisés.
- Après correction : 19 contrôles réussis, aucun échec, dont erreurs 503/403, purge, reprise, couverture partielle, cours seuls, vrai vide, réponse tardive, sélection, recherche et focus. Huit captures avant/après inspectées en clair/sombre à 1440 et 390 px, sans débordement horizontal ni régression visuelle bloquante relevée. [Résultats](proofs/agenda-20261026/web/results.json), [captures](proofs/agenda-20261026/web/captures-results.json).
- Navigation exacte : 10 scénarios supplémentaires réussis, couvrant deux leçons du même élève, retour navigateur, lien direct, rechargement, leçon hors pagination, refus 403/404, identités et bilan incohérents, occurrences distinctes et occurrence retirée. La recette agenda précédente a aussi été rejouée avec succès. [Résultats](proofs/agenda-20261026/web/lesson-context-results.json), [leçon exacte](proofs/agenda-20261026/web/selected-lesson-context.png), [occurrence ciblée](proofs/agenda-20261026/web/selected-course-occurrence.png).

Scripts : 17 tests de sélection Apple et 11 tests du script de captures réussis. La revue indépendante web a conduit aux gardes d'identité des bilans et des séries, incluses dans les preuves de navigation.

### Apple : résultats par candidat

| Candidat | Métier agenda | UI iPhone/iPad | IPA |
| --- | --- | --- | --- |
| `849bb27` | [Réussi](https://github.com/tomyrms/Drivy/actions/runs/40310710892) : 54 tests, 56 exécutions avec paramètres, aucun échec ni saut ; fixtures corrigées et sélection de séance incluses | [Échec](https://github.com/tomyrms/Drivy/actions/runs/40310714721) : 4 tests réussis et 2 échoués sur chacun des deux appareils | [Réussie](https://github.com/tomyrms/Drivy/actions/runs/40310688631), build 377, métadonnées et empreintes vérifiées |
| `bee144c` | [Réussi](https://github.com/tomyrms/Drivy/actions/runs/40315357182) : 55 tests, 57 exécutions avec paramètres, aucun échec ni saut | [Échec](https://github.com/tomyrms/Drivy/actions/runs/40315360630) : 4 tests réussis et 2 échoués sur chaque appareil ; causes détaillées ci-dessous | [Réussie](https://github.com/tomyrms/Drivy/actions/runs/40315357758), remplacée par le build 381 ci-dessous |
| `23b19f3` | [Réussi](https://github.com/tomyrms/Drivy/actions/runs/40317621203) : 58 tests, 62 exécutions avec paramètres, aucun échec ni saut | Vues inchangées par rapport à `bee144c` ; quatre cas réussis par appareil conservés, deux cas repris dans `00f0f45` | [Réussie](https://github.com/tomyrms/Drivy/actions/runs/40317577943), build 381 non signé, empreinte SHA-256 vérifiée après téléchargement |
| `00f0f45` | Produit inchangé depuis `23b19f3`, résultat métier conservé | [Réussi](https://github.com/tomyrms/Drivy/actions/runs/40320751020) : exactement 2 tests par appareil, aucun échec ni saut ; les 4 autres cas restent couverts par `bee144c` | Produit inchangé, IPA 381 conservée |

Preuves métier finales de `23b19f3` : [résumé](proofs/agenda-20261026/native/unit/summary.json), [inventaire](proofs/agenda-20261026/native/unit/tests.json). L'IPA livrée correspond à `23b19f3` : [métadonnées](proofs/agenda-20261026/native/ipa/build-info.json), [empreintes](proofs/agenda-20261026/native/ipa/SHA256SUMS.txt), SHA-256 `bda1e104263ff434eb12e2e640757ec73e5bced1ca71e0b735b3c49288cdcde7`. Le résultat métier de `bee144c` a été vérifié dans l'artefact `12647212793`.

L'identité des sources produit entre `23b19f3` et `00f0f45` a été vérifiée par les arbres Git : `apps/ios/Drivy` = `6c5bd311e7542ef6165e2c74b0af3f16134e8cdf` ; `apps/web` = `fef17b534d9a833914f7c3c880adac8cb9330606`. Les fixtures natives, comprises dans le premier arbre, sont également inchangées. Les résultats restent attribués au SHA qui les a exécutés ; cette identité de source justifie la conservation de l'IPA et des tests métier, sans prétendre les avoir relancés sur le dernier commit.

Les [deux échecs UI `849bb27`](proofs/agenda-20261026/native/ui-849bb27-failure.json) ont des causes distinctes : une assertion attendait un bilan alors que la fiche de la leçon planifiée s'ouvrait ; une actualisation interrompue pouvait laisser un indicateur de chargement permanent. `bee144c` corrige l'assertion et rend cette interruption reprenable en conservant les données autorisées. `23b19f3` complète la priorité du refus d'accès lors d'une interruption ; les tests de modèle et de client ont réussi, dont les HTTP 401/403/404 reçus après annulation, l'absence de renouvellement/rejeu du 401 annulé et le rejet d'un succès annulé.

La [recette UI `bee144c`](proofs/agenda-20261026/native/ui-bee144c-failure.json) a progressé mais conserve deux échecs par appareil :

- Leçon, ligne 29 : l'identité de l'élève, l'horaire 11 h–12 h et l'état avaient réussi ; l'action Démarrer attendue n'était plus proposée à l'heure du runner, après la fin prévue. Le test `00f0f45` conserve ces assertions, ferme la fiche et vérifie le retour à l'agenda avec la leçon accessible.
- Reprise, ligne 117 : le chargement permanent a disparu. La [capture avant reprise](proofs/agenda-20261026/native/ui-bee144c-refresh-before-retry.png) montre une interruption avant transport ; la première reprise consomme alors la panne unique de la fixture et conserve les données. Le test `00f0f45` exige une transition explicite vers la panne réseau ou vers le succès. Une seconde reprise au maximum est permise uniquement après cette transition ; la disparition de l'erreur et du chargement, les deux cours et la sélection conservée restent exigés.

Seuls ces deux tests sont ajustés, sans changement produit ni fixture. Le run `40320751020` et son artefact `12650236977` confirment deux tests réussis par appareil, aucun échec ni saut : [résumé iPhone](proofs/agenda-20261026/native/ui/Tests/summary.json), [inventaire iPhone](proofs/agenda-20261026/native/ui/Tests/tests.json), [résumé iPad](proofs/agenda-20261026/native/ui/iPadTests/summary.json), [inventaire iPad](proofs/agenda-20261026/native/ui/iPadTests/tests.json). Les quatre autres tests déjà réussis sur les deux appareils couvrent le changement de période, le jour avec seulement un cours en semaine/mois, la panne initiale suivie d'une reprise et la sélection de chaque occurrence d'une même série. Leurs noms sont conservés dans le résumé `ui-bee144c-failure.json` ; ils n'ont pas été relancés. La couverture combinée est donc de six cas réussis par appareil, répartis entre `bee144c` et `00f0f45`.

### Revue visuelle

La [référence corrigée](https://github.com/tomyrms/Drivy/actions/runs/40308624259), avec les vues d'origine, fournit 7 captures valides sur 8 : iPhone 17 Pro et iPad Pro 13 pouces M5, portrait, clair/sombre, taille normale. La première capture iPad semaine claire montre « Préparation du rendu… » et est exclue. L'ancien ordre 11 h / 09 h / 14 h et l'absence de repère le lendemain avec seulement un cours sont visibles. [Avant iPhone semaine](proofs/agenda-20261026/native/before/iPhone-agenda-mixed-light-synthetic.png), [avant iPad mois](proofs/agenda-20261026/native/before/iPad-agenda-mixed-month-light-synthetic.png).

Sur `849bb27`, les 24 captures après sont valides et inspectées :

- [Taille normale](https://github.com/tomyrms/Drivy/actions/runs/40312188189) : 12 PNG, quatre exécutions XCTest de capture réussies, taille `large` demandée et confirmée. Ordre 09 h / 11 h / 14 h visible en semaine iPhone et en semaine/mois iPad ; point du jour avec cours seul présent ; erreur et bouton Réessayer lisibles dans les quatre vues concernées. [Revue et limites](proofs/agenda-20261026/native/after-normal/review.json).
- [Grands textes](https://github.com/tomyrms/Drivy/actions/runs/40310718202) : 12 PNG, `accessibility-extra-large` demandé et confirmé. La chronologie complète et l'erreur avec reprise sont visibles sur iPad. Sur iPhone, une partie de la liste et de l'erreur reste sous le pli. [Métadonnées iPhone](proofs/agenda-20261026/native/after-large/visual-device-iPhone.json), [métadonnées iPad](proofs/agenda-20261026/native/after-large/visual-device-iPad.json).

En vue mois sur iPhone, les lignes de rendez-vous sont hors pli, comme avant ; ces captures prouvent les repères du calendrier, pas la liste complète. Les PNG ne prouvent ni le défilement, ni l'action Réessayer, ni l'annonce du résumé accessible. Le résumé est une valeur d'accessibilité contrôlée séparément par la recette UI, pas un texte visible sur ces images. Les correctifs de reprise ultérieurs ne changent pas ces vues ; les images restent néanmoins explicitement rattachées à leur SHA.

### Échecs de préparation conservés

Les [premières captures de référence](https://github.com/tomyrms/Drivy/actions/runs/40305370458), sur `fda97e5`, avaient un `requestId` synthétique non UUID incompatible avec le vrai client agenda. Leurs huit images ne prouvent aucun comportement d'événement. Les [premiers tests UI](https://github.com/tomyrms/Drivy/actions/runs/40305929146) et [premières captures candidates](https://github.com/tomyrms/Drivy/actions/runs/40305933009) ont été interrompus pour corriger cette cause. La référence `37a322a` ne change que les identifiants synthétiques et conserve les vues avant correction. Ces preuves invalides ne sont pas comptées dans les 7 références valides ni dans les 24 captures après.

## Couverture des tickets

| Issue | Contrôle de réalisation | Preuve ciblée / état |
| --- | --- | --- |
| #144 | Chronologie, égalités stables, statuts, fuseau, identités et ouverture exacte | PASS : projections métier, recette Edge et navigation exacte ; captures inspectées ; UI native leçon/retour réussie sur `00f0f45`, occurrences sur `bee144c` |
| #145 | Repères semaine/mois, cours seuls, brouillons/annulations et lecture incomplète | Tests métier réussis, repères visuels confirmés ; cas UI cours seul et résumé semaine/mois réussis dans `bee144c` |
| #146 | Panne distincte du vide, reprise, conservation à portée identique, révocation et réponses tardives | PASS : tests métier finaux `23b19f3`, dont priorité refus/interruption ; rendu d'erreur confirmé ; reprise UI réussie sur `00f0f45` |
| #147 | Actualisation des sources, fraîcheur et conservation sélection/focus | Recette Edge agenda réussie, 503/403 et réponse tardive inclus |
| #172 | Formateur de l'occurrence, séries multi-moniteurs, recherche limitée aux leçons | Projection et recette Edge réussies |
| #173 | Compteurs par jour/semaine et couverture partielle | Projection et recette Edge réussies, borne de 200 séries incluse |
| #175 | Leçon exacte, hors pagination, lien direct/rechargement/retour, refus et incohérences | Tests route/dossier/BFF et 10 scénarios Edge réussis ; route serveur existante réutilisée |

Intégration et clôture des tickets suivies par la [PR #178](https://github.com/tomyrms/Drivy/pull/178), sans les présenter comme déjà effectuées. Aucun déploiement, changement de base ou accès à des données réelles pour ce lot. L'IPA reste non signée pour iLoader. Cette qualification ciblée ne vaut pas qualification globale #84 ; aucun résultat physique VoiceOver, GPS ou batterie n'est déduit des tests synthétiques.
