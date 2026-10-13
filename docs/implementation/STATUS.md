# État de la réalisation

## 13 octobre 2026 — onboarding école et navigation web

Le porteur a validé la réalisation des six lots du [plan](plan-onboarding-ecole-navigation-20261013.md). Navigation à sous-pages sous la catégorie, création par lien opérateur à usage unique, guide web de six étapes avec exemples adaptables et brouillon serveur, activation transactionnelle explicite, ajout guidé des formations/tarifs, prochaines actions serveur, invitations d’équipe disponibles selon la messagerie et renvoi natif DRAFT vers le web. [Réalisation et exploitation](realisation-onboarding-ecole-20261013.md), [contrat de réalisation](onboarding-api-20261013.md).

**Exécuté** : 424 tests API sur PostgreSQL, dont migration synthétique peuplée 028→029/030 conservant les données historiques ; 217 tests web ; types, builds et intégrité documentaire ([CI `22650ba`](https://github.com/tomyrms/Drivy/actions/runs/38403370545)). [Navigateur intégré](https://github.com/tomyrms/Drivy/actions/runs/38403370696) : 43 contrôles, Keycloak et SMTP réels de test, compte vérifié, ouverture, brouillon/reprise AP72 après rechargement, activation, ajout de tarif avec réponse perdue récupérée sans rechargement ni doublon, mobile, invitation d’équipe acceptée et récupération du compte. Revue Chrome locale : 26 interactions initiales, 5 contrôles d’invitations et 4 de reprise, avec captures synthétiques. Apple : [628 tests Swift Testing et 3 XCTest](https://github.com/tomyrms/Drivy/actions/runs/38397622660) réussis ; [IPA compilée à `7ae86d5`](https://github.com/tomyrms/Drivy/actions/runs/38402353534). **En cours** : suite UI Apple iPhone/iPad, après correction d’un identifiant parent qui masquait les boutons aux tests. **Non exécuté** : déploiement homelab, recette avec un responsable d’auto-école, essais physiques GPS/batterie/VoiceOver. Les modèles restent à adapter par l’école ; aucune validation juridique ni évolution du régime GPS n’est revendiquée.

## 13 octobre 2026 — homelab remis à zéro

À la demande du porteur, pour essayer le parcours d’une école neuve. **Sauvegarde vérifiée avant tout effacement** (`pg_dump` puis `pg_restore --list`) de `drivy_refonte` et `drivy_identity` : `/root/drivy-reset-20261013T112412Z/` sur CT113 et sur l’hôte Proxmox, copie dans `.local/backups/` (empreintes identiques). Toutes les données de Drivy sont effacées : écoles, élèves, leçons, trajets, bilans, textes. Les comptes de connexion (`luc`, `moniteur`, `eleve`) sont gardés. Une seule école est recréée : « Luc auto école », en préparation, vide, luc administrateur et moniteur, GPS actif (repris de l’ancienne école : une école neuve l’a désactivé et aucun écran ne permet de l’activer).

## 13 octobre 2026 — textes de l’école : lot 1

[Décisions du porteur](decisions-2026-10-13.md) : textes proposés par défaut, un seul texte, informations demandées sans brouillon, plus de motif d’approbation.

- **API.** `GET /text-proposals` (textes rédigés par Drivy, jamais adoptés par une lecture ; Mapbox cité seulement s’il est configuré ; aucune durée chiffrée). `PUT /data-policy` avec `publishProposedFields` publie aussi les informations demandées proposées : prénom et nom requis, téléphone et e-mail facultatifs, rien qui bloque la planification. `POST /profile-field-policies` avec `publishNow`. `approvalReason` facultatif. `GET /recording-choices` (migration 030) : accord GPS de chaque élève pour l’administration.
- **Web.** Réglages : École, **Confidentialité et conditions**, Signalements. La page regroupe les textes (préremplis tant qu’ils ne sont pas adoptés), les informations demandées en tableau et un accès aux conditions. Le menu ne montre plus « Préparation » : l’Agenda affiche ce qui manque pour planifier, avec un lien par manque. Le dossier élève montre l’accord GPS (« À redonner » s’il date d’anciens textes). Plus de « Motif » ; une nouvelle procédure ou de nouvelles conditions partent des textes proposés.
- **iOS.** Un seul composant pour les textes de l’école : trois lignes sur le GPS (« Enregistré pendant la leçon seulement », « Visible par toi et ton école », « Sans GPS, la leçon a lieu quand même »), puis « Tes données » (élève) ou « Confidentialité » (moniteur) ouvre le texte complet. Il remplace les six présentations différentes.

**Exécuté** : API sur PostgreSQL en CI (nouveaux tests : textes proposés, adoption en un geste, accords GPS lus par l’administration, motif facultatif, publication immédiate) ; tests unitaires des textes proposés en local ; web 199 tests, typecheck et build en local. CI verte et IPA compilée sur `0775be9`. **Non exécuté** : tests Swift, captures, essai sur appareil. **Déployé le 13 octobre 2026** à la demande du porteur : release `0775be9` sur le homelab après sauvegarde vérifiée, 30 migrations aux empreintes conformes, services actifs (`.local/deploy-textes-lot1-release.py`).

## 13 octobre 2026 — textes de l’école : lot 0

Suite de l’[analyse des textes de l’école](analyse-textes-ecole-20261013.md), lot 0 seulement (aucune décision juridique requise) :

- **Adoption prévenue.** Le dialogue « Relire les textes » lit `GET /v1/schools/{id}/data-policy/impact` (administration seule, migration 029). Il dit combien d’élèves avaient accepté le GPS avec les textes actuels et combien de trajets en cours s’arrêteront. L’API ne renvoie que deux nombres, jamais un nom.
- **Textes vides refusés.** L’information et la conservation demandent au moins 40 caractères utiles, dans l’API comme dans le web : « ddd » n’est plus accepté.
- **École sans textes.** L’app affiche « L’école n’a pas encore publié ses textes de confidentialité. La leçon peut se faire sans GPS. » au lieu de « L’accord GPS n’a pas pu être lu ».
- **Vocabulaire.** Web : « Confidentialité », « Lire les textes », « Modifier les textes », « Adoptés le … » au lieu de « Version 2 » ; « Informations demandées » dans le menu et le titre. « Services de l’école » (toujours « À configurer ») et « Enregistrer l’avancement » sont retirés ; le bloc « Activation » n’apparaît que pour une école en préparation. App : « Tes données » pour l’élève, « Confidentialité » pour le moniteur, « Conservation » ; plus de « notice » ni de « Version N » à l’écran.

**Exécuté** : typecheck API ; web 193 tests (dont 3 nouveaux) et typecheck en local. **À exécuter sur la CI** : tests API sur PostgreSQL (nouveau test d’impact, textes trop courts), compilation de l’IPA. **Non exécuté** : tests Swift, captures, essai sur appareil. **Déployé le 13 octobre 2026** à la demande du porteur : release `a2ab75a` sur le homelab après sauvegarde vérifiée de `drivy_refonte`, 29 migrations aux empreintes conformes, services actifs (`.local/deploy-textes-release.py`). Les textes adoptés de Luc auto école restent « ddd » / « wssd » : les réécrire depuis le web redemandera l’accord GPS à 23 élèves (30 accords).

## 13 octobre 2026 — actions à effectuer : du point bleu jusqu’à la résolution

Le point bleu d’« Élèves » et les lignes « Profil à compléter » ne menaient à rien dans le dossier. Cause : un état de profil stocké qui ne suivait pas la politique de l’école (11 faux « à compléter » sur le homelab, dont la politique n’exige que prénom et nom). L’API calcule désormais l’état à la lecture, avec la même règle que le dossier et la planification. Le dossier nomme chaque information manquante (« Profil à compléter · 3 informations manquantes ») ; chaque ligne ouvre le formulaire sur le champ, clavier prêt, et le formulaire marque d’un point les champs requis encore vides. Le point de l’onglet suit toute l’école, plus la page affichée, et s’éteint dès la correction relue. L’élève qui a laissé son accueil en route le reprend depuis Profil (« Reprendre l’accueil »), sans attendre sept jours. Sur le web, le dossier d’un élève incomplet nomme les informations manquantes et les fait saisir sur place. Corrigés aussi : « Leçon à terminer » s’allume à la fin prévue et s’éteint à la confirmation ; « Accord GPS » allume Profil sans visite préalable ; une panne ne retire plus « Reprendre l’accueil ». [Audit, décisions et limites](guidage-actions-20261013.md).

**Exécuté** : API, 340 tests sur PostgreSQL dont 4 nouveaux (sans politique, champ facultatif, incomplet → partiel → complet, champ vidé) ; **571 tests Swift réussis** dont 10 nouveaux ; IPA d’essai compilée ; captures iPhone clair/sombre du dossier incomplet (`dossier-incomplete`). Web : 188 tests, dont 3 nouveaux (décompte, corps de la saisie, routes du relais), types. **Non exécuté** : parcours UI, iPad, rendu du bloc web dans un navigateur. **Déployé** sur le homelab le 13 octobre (release `e2f78a1`, API et web, sauvegarde `drivy_refonte-before-e2f78a1…-20261012T235700Z` prise avant, 28 migrations vérifiées) ; l’app est à installer. **Reste à qualifier** : ouverture au clavier et défilement jusqu’au champ sur appareil, VoiceOver, grand texte.

## 13 octobre 2026 — classement intelligent des signalements

Paramètres → Signalements porte une option « Classement intelligent », désactivée par défaut, propre à chaque moniteur. Activée, elle range **tous** les signalements affichés d’après ses habitudes ; la grille de « Signaler » garde ses trois colonnes et ses neuf tuiles visibles, qui sont simplement les neuf premières places. L’ordre manuel reste celui de l’école et n’est jamais écrit par le classement : désactiver l’option le rend tel quel. Le service classe (moteur pur, `observation-ranking-engine.ts`) au plus une fois par jour, sur les usages des jours précédents lus dans `geo_observation` ; l’app applique l’ordre et le fige pour toute la leçon, reprise comprise. Conception, paramètres, contrat et simulations : [classement-intelligent-20261013.md](classement-intelligent-20261013.md) ; app : [classement-intelligent-ios-20261013.md](classement-intelligent-ios-20261013.md).

**Exécuté** : moteur et simulations en local et sur la CI (25 tests) ; tests PostgreSQL sur la CI (10 tests : défaut, activation, retour au manuel, un reclassement par jour avec deux lectures simultanées, isolement entre moniteurs et entre écoles, RLS), suite API complète verte ; compilation de l’IPA ; tests Swift sur la CI (cinq suites du classement vertes). Une assertion de hauteur de la grille, antérieure à ce lot (quatre et six tuiles tiennent sur deux rangées), est corrigée. **Déployé sur le homelab** le 13 octobre à la demande du porteur : release `be5d5d8` (API de cette branche, qui porte aussi la recherche du prochain créneau), sauvegarde vérifiée avant, 28 migrations aux empreintes conformes, `/health/ready` 200, la route répond 401 sans jeton. **Reste à qualifier** : l’app qui porte l’option n’est pas installée ; l’écran de réglage et la grille classée n’ont pas été vus, ni sur simulateur ni sur appareil ; VoiceOver non essayé ; les paramètres viennent de simulations, pas d’usages mesurés. **À confirmer par le porteur** : l’ordre manuel reste celui de l’école (pas d’ordre manuel personnel par moniteur) ; une leçon fige l’ordre connu de l’app à sa première ouverture de « Signaler », qui peut dater de la veille si l’app n’est pas repassée par l’accueil.
## 12 octobre 2026 — reprise d’une leçon après fermeture ou crash

Après une fermeture, un crash ou un redémarrage, la fiche propose « Continuer le trajet » au lieu de « Démarrer le trajet ». Le chronomètre reprend la durée réelle de la leçon depuis son départ enregistré par l’école ; la carte redessine le tracé et les signalements des trajets précédents ; l’arrêt du trajet interrompu part avant le nouveau départ, sans doublon. Rien n’était perdu avant, rien n’était repris. [Cause, décisions et limites](reprise-lecon-20261012.md).

**Exécuté** : rien ici (pas de toolchain Swift sous Windows) ; tests Swift ajoutés (crash simulé sur le coffre SQLCipher, durée de leçon, tracé antérieur), à exécuter sur la CI. **Reste à qualifier** sur iPhone : fermeture forcée, crash, redémarrage, reprise après plusieurs minutes, perte de réseau au moment de continuer.

## 12 octobre 2026 — Paramètres du moniteur, ouverts depuis le Profil

L’engrenage du Profil du moniteur (barre de navigation, « Paramètres », `profile-settings`) pousse une page « Paramètres » dans la pile du Profil : Préférences de leçon (la feuille existante), Signalements (mêmes conditions qu’avant : droit de gérer les thèmes), Apparence, Sécurité (verrou biométrique, si l’appareil en a un), Se déconnecter (même ligne et même confirmation pendant un trajet). Ces lignes ont quitté le Profil, qui garde l’en-tête, Leçons et le compte (Mes informations, Reprendre l’accueil, Invitations, Gérer l’école, Changer d’école). Aucun réglage nouveau ; Profil et Paramètres de l’élève inchangés. Vue `SchoolStaffSettingsView`.

**Exécuté** : rien (pas de compilation possible sur la machine Windows). **Reste à qualifier** : compilation, tests UI mis à jour (`NativeNavigationTests`, `AppearanceSettingsTests`), push et retour natifs, feuille des préférences ouverte depuis la page poussée, clair et sombre à l’œil, VoiceOver, grand texte, iPad.

## 12 octobre 2026 — « Planifier une leçon » s’ouvre sur le prochain créneau libre

À l’ouverture, l’école cherche le prochain créneau réellement libre (ouvertures du moniteur, pauses, indisponibilités, leçons du moniteur tampon compris et de l’élève dans toute l’école, durée, affectation, jours non travaillés) et l’app le présélectionne ; un squelette tient la place de la date pendant la recherche, sans saut. Choix manuel prioritaire, « Chercher plus loin » quand la période est vide. Calcul au serveur parce que les occupations de l’élève sont masquées au moniteur : nouvelle route `GET …/lessons/next-slot`, extension hors contrat canonique, sans migration. [Architecture, comportement et limites](prochain-creneau-20261012.md).

**Exécuté** (Windows, sans base ni toolchain Swift) : 17 tests purs de la recherche (`test/next-slot.test.ts`, fuseau, heure d’été et d’hiver, pauses, fermetures, tampon, élève, affectation, période vide) et les 85 autres tests unitaires de l’API, réussis ; `tsc --noEmit` sans erreur. **Écrit, non exécuté** : `lesson-next-slot.integration.test.ts` (PostgreSQL : occupation privée de l’élève, tampon, fermeture, contrat, droits) et 11 tests Swift, 17 cas (`SchoolPlanningNextSlotTests`). **Reste à qualifier** : compilation et tests Swift sur la CI, squelette et position du calendrier sur appareil, clair et sombre, VoiceOver. **Ordre de déploiement** : API d’abord ; une app plus récente que l’API retombe sur la saisie manuelle (404 silencieux).

## 12 octobre 2026 — audit global et corrections

Cinq audits en lecture seule (écrans iOS, API et base, UI/UX, architecture, fiabilité terrain), puis corrections par lots. 65 constats distincts : 1 P0, 8 P1, 30 P2, 26 P3 ; 41 corrigés. Le P0 : une affectation faite au bureau arrêtait le trajet du moniteur et bloquait l’iPhone (positions jamais envoyées, plus aucun départ). Corrigé côté serveur (migration 025) et côté app. Aussi : verrou Face ID au-dessus des feuilles, bilans lisibles au bureau, l’élève ne reçoit plus que la version courante d’un bilan, heure réelle d’un départ hors ligne, signalements renvoyés seuls, reprise du GPS sans réseau, positions purgées une fois confirmées, replay paginé sans tout déchiffrer. [Constats, décisions du porteur, changements d’API et limites](audit-global-20261012.md).

**Exécuté** : API 322/322 tests sur PostgreSQL locale (base 311) ; web 149/149 ; IPA d’essai compilée ; tests Swift sur la CI (résultat dans la PR). **Non fait** : audit UI/UX sur captures (agent arrêté par la limite d’usage), aucune retouche visuelle. **Non déployé** : migrations 025 et 027, `WEB_TRUST_PROXY`. **Reste à qualifier** : tout sur iPhone (verrou au-dessus d’une feuille, adoption d’époque, purge, reprise hors réseau). **Au porteur** : un départ immédiat lancé par erreur ne s’annule plus, il se termine puis l’école corrige l’issue.

## 12 octobre 2026 — « Signaler » : douze tuiles visibles, la suite défile

Le volet montre d’emblée les douze premiers signalements affichés, dans l’ordre de l’école ; au-delà, la même grille continue en dessous et défile, avec l’amorce estompée de la rangée suivante. Le volet garde la hauteur de douze tuiles quel que soit leur nombre ; tuiles de hauteur égale. [Règle et contrôle](signalements-ios-20261012.md#mise-à-jour--douze-tuiles-visibles-la-suite-défile-12-octobre-troisième-lot).

**Exécuté** : voir la PR (IPA et captures sur la CI). **Reste à qualifier** : défilement et fondu sur appareil, tailles d’iPhone autres que celle de la campagne, VoiceOver.

## 12 octobre 2026 — signalements configurables : 18 thèmes, réglés par école

« Signaler » ne déplie plus le référentiel tel quel : un catalogue de dix-huit thèmes à clés stables (les onze d’avant, plus Clignotants, Distance de sécurité, Freinage, Changement de voie, Démarrage, Virages, Éco-conduite), dont douze affichés à l’origine. Chaque école règle l’ordre et l’affichage ; l’administrateur le peut toujours, un moniteur avec le nouveau droit « Gérer les signalements ». Masquer un thème ne retire aucune observation : chaque observation garde la clé de son thème. Réglage dans l’app (Profil → Signalements, glisser-déposer natif) et sur le web (section Signalements, droit dans Équipe). Sept pictogrammes dessinés avec les skills logo-design et brand-identity, trois études chacun. [Contrat et décisions](signalements-configurables-20261012.md) · [icônes](icones-signalements-20261012.md) · [iOS](signalements-ios-20261012.md) · [web](signalements-web-20261012.md).

**Exécuté** sur `506f205` : API, 14 tests d’intégration nouveaux sur PostgreSQL (droits, RLS, conflit de version, deux écoles, historique après masquage) et « Refonte · vérifications » verte ([run 38288053857](https://github.com/tomyrms/Drivy/actions/runs/38288053857)) ; web, 186 tests, types et build, section vue dans Chromium avec une API simulée ; IPA d’essai compilée ([run 38288054203](https://github.com/tomyrms/Drivy/actions/runs/38288054203)) ; **538 tests Swift réussis** ([run 38289548778](https://github.com/tomyrms/Drivy/actions/runs/38289548778)). **Non exécuté** : parcours UI iOS, captures d’écran, migration 026 sur le homelab (rien n’est déployé). **Reste à qualifier** : glisser-déposer et grille de 13 à 18 tuiles sur appareil (hauteur calculée, pas vue ; la grille défile sur un petit iPhone), clair et sombre à l’œil, VoiceOver, toucher sur le web, synchronisation iOS ↔ web contre une vraie API, choix du porteur sur les sept icônes (`assets/icones-signalements-20261012/choix.png`). **Ordre de déploiement** : API avant l’app ; une app plus récente que l’API garde son catalogue embarqué et n’envoie pas la clé de thème.

## 12 octobre 2026 — leçon terminée en onglets, « Mon souhait », Formation d’un permis, icône Progression

La leçon terminée se lit en trois onglets sous la carte de l’élève (Bilan, Compétences, Trajet & notes), même vue pour le moniteur et l’élève. Côté élève, « Mon souhait » ferme enfin son clavier, et l’accord GPS sous le souhait ne reste plus en squelette (une lecture annulée par un `Group` n’était jamais relancée). Dans le profil, la Formation d’un permis passe au-dessus de Leçons et Progression, dense, avec des décomptes réels du référentiel. L’onglet Progression de l’élève a son icône dessinée (une courbe montante, choisie par le porteur parmi dix pistes). [Décisions, causes et limites](lecon-onglets-20261012.md).

**Exécuté** : IPA d’essai compilée ; 497 tests Swift réussis dont 7 nouveaux ; captures iPhone clair/sombre des nouveaux écrans relues. **Reste à qualifier** : clavier et transitions sur appareil, VoiceOver, grand texte, iPad, icône dans la barre d’onglets réelle. Pas de note sur 10 (l’école évalue en trois niveaux) ni d’exigences de formation (aucune donnée dans l’API).

## 12 octobre 2026 — icônes des catégories de permis

Les 16 catégories de l’OAC (A, A1, M, B, B1, BE, C, C1, CE, C1E, D, D1, DE, D1E, F, G) ont leur icône. L’atelier a produit trois directions par catégorie ; la direction « Signature » (aplats, roues = repère de la marque) est retenue partout sur notes pondérées. Composant central `DrivingLicenseIcon`, assets vectoriels `License-*`, intégration dans les filtres Leçons/Progression, le Profil, l’accueil élève, la planification, « Commencer maintenant », les réglages d’agenda et l’invitation. [Démarche, notes et limites](icones-permis-20261012.md).

**Exécuté** sur `b56bde5` : IPA d’essai 0.7.0/212 compilée ([run38233544399](https://github.com/tomyrms/Drivy/actions/runs/38233544399)) ; **490 tests Swift réussis**, dont les 4 nouveaux ([run38233574292](https://github.com/tomyrms/Drivy/actions/runs/38233574292)) ; vérifications API/web vertes ; captures iPhone clair/sombre de 7 écrans ([run38233578314](https://github.com/tomyrms/Drivy/actions/runs/38233578314), `assets/icones-permis-20261012/captures-simulateur.png`) où les icônes apparaissent dans Progression, Profil, invitation et planification. **Non vu en capture** : le menu de filtre ouvert, l’accueil « Ta formation » (la scène capturée est l’étape récapitulative), le sélecteur de « Commencer maintenant » (scène à une formation). **Reste à qualifier** : appareil réel, VoiceOver, iPad ; lisibilité des ensembles avec remorque à 16 pt.

## 12 octobre 2026 — audit du thème sombre « Soft Charcoal »

54 écrans iPhone capturés en clair et en sombre avant et après, couleurs mesurées sur les pixels, bascule clair → sombre → clair à chaud sur chaque écran (nouvelle option `visual_hot_switch`). Le thème est appliqué partout. Un défaut corrigé : les interrupteurs et les sélecteurs de date prenaient le bleu d’encre pastel sous un élément blanc ; ils prennent l’aplat `accentFill`, inchangé en clair. [Constats, méthode et limites](sombre-audit-20261012.md).

**Exécuté** : IPA d’essai compilée ; 54 captures claires identiques au pixel près, hors heure, chronomètre et animations ; contraste du thème 204/204. **Non exécuté** : tests Swift, parcours UI. **Reste à qualifier** : appareil réel, états pressés et menus ouverts, Contraste accru, iPad. **Au porteur** : bleu système des alertes (pas de couleur d’accent globale).

## 12 octobre 2026 — couleurs de l’échelle d’appréciation en clair

« Signaler » peignait ses trois appréciations avec les encres de texte (`success`/`warning`/`danger`, réglées pour 4,5:1), d’où un bordeaux, un brun et un vert bouteille en clair. Trois tokens de signal (#26A058, #D1760E, #E5484D en clair, sombre inchangé) servent désormais à tout ce qui *dessine* un état : feuille Signaler, marqueurs de carte, rail et frise du replay, fil du bilan, alerte GPS, point d’état. Le texte garde ses encres. `theme-contrast.py` couvre les nouveaux couples ; clair existant inchangé. Rendu sur appareil non qualifié. [Cause, décision et audit](couleurs-signal-20261012.md).

## 11 octobre 2026 — dossier de l’élève en blocs

À la demande du porteur, le dossier prend le fond et les blocs blancs de Profil et de l’historique des leçons ; « Informations personnelles » devient une ligne qui se déplie. [Détail](direction-artistique-20261011.md).

**Exécuté** : IPA d’essai compilée ; captures iPhone clair et sombre relues. **Non exécuté** : tests Swift, parcours UI. **Reste à voir** : onglet Progression du dossier, volet déplié, VoiceOver.

## 11 octobre 2026 — GPS fluide, tracés fidèles et recalage routier

Une seule carte pour la leçon et le replay, animée image par image : le marqueur glisse vers chaque position enregistrée, la caméra suit sans à-coups, le curseur du replay avance en continu et répond aussitôt à la chronologie. Le filtre d’affichage ne dessine plus la dérive à l’arrêt ni les sauts, sans couper le trait à chaque feu rouge. Le serveur sait recaler un trajet sur la route (Mapbox ou OSRM auto-hébergé), à la première lecture, en couche distincte des mesures. [Causes, architecture, décisions et limites](gps-fluide-recalage-20261011.md).

**Exécuté** : IPA d’essai compilée ; tests Swift (482 tests passent après fusion de master) ; 311 tests API sur PostgreSQL ; client vérifié contre l’API Mapbox réelle avec une ligne synthétique. **Non exécuté** : parcours UI. **Reste à qualifier** : tout sur iPhone — fluidité, position du marqueur sous les panneaux, seuils du filtre sur route, VoiceOver. Aucune mesure de performance n’a été faite.

**Déployé le 11 octobre 2026**, à la demande du porteur : release `de2f331` sur le homelab après sauvegarde vérifiée de `drivy_refonte`, 24 migrations aux empreintes conformes, services actifs. Recalage activé avec Mapbox (`MAP_MATCHING_PROVIDER=mapbox` et le jeton du porteur dans `api.env`, copie de l’ancien fichier conservée à côté) ; la route répond 401 sans jeton d’accès et l’API atteint `api.mapbox.com`. Aucun trajet réel n’a encore été recalé en production : à constater à la première ouverture d’un replay. **Reste au porteur** : les conditions de Mapbox demandent d’afficher ses résultats sur une carte Mapbox et interdisent de les stocker, et les positions partent chez un tiers, ce qui touche la notice ; un OSRM sur le homelab évite les deux. Pour couper : retirer les lignes `MAP_MATCHING_*` et redémarrer l’API.

## 11 octobre 2026 — direction artistique commune (Profil, Élèves, Agenda)

Audit croisé des onglets et de leurs feuilles, puis règles communes : une ligne prend le rythme de sa famille de page (liste groupée ou page de lecture), une seule action en texte, un badge pour ce qui attend une réponse, « Fermer » toujours au même endroit, vides et attentes par les composants partagés. Le Profil du moniteur prend la structure des Paramètres de l’élève, et les deux Profils posent l’en-tête sur le fond. Aujourd’hui n’est pas refait. [Audit, règles et décisions](direction-artistique-20261011.md). Branche `claude/da-harmonisation-20261011`, sur la PR #12.

**Exécuté** : IPA d’essai compilée sur chaque lot ; captures iPhone clair et sombre avant et après, relues ; contraste du thème vérifié (clair inchangé). **Non exécuté** : tests Swift et parcours UI. **Reste à qualifier** : VoiceOver, grand texte et iPad sur appareil.

## 11 octobre 2026 — Profil de l’élève restructuré

Identité et « Mes informations », permis en liste compacte (une ligne et une synthèse par permis, détail au toucher avec accès à Leçons et Progression sur ce permis), « Paramètres » dans la barre (compte, enregistrement GPS, Face ID, déconnexion). Le message « Le choix n’a pas pu être vérifié » venait d’une lecture de l’accord GPS annulée et prise pour une panne : corrigé à la source. La Progression de l’élève suit : mêmes cartes que le Profil, et une toile des compétences (niveaux publiés, sans score). [Détail et arbitrages](profil-eleve-20261011.md).

**Exécuté** : IPA d’essai compilée sur `e78b00c`. **Reste à qualifier** : rendu réel (clair, sombre, iPad, grand texte, VoiceOver), jamais vu tourner ; tests Swift non lancés à la demande du porteur.

## 11 octobre 2026 — thème sombre « Soft Charcoal »

Le thème sombre de l’app native est refait en anthracite neutre : un bloc est plus clair que la page qui le porte, le bouton principal est un cobalt plein au libellé blanc, une feuille monte d’un niveau. Le thème clair ne change pas. Détail, références et mesures : [dark-soft-charcoal-20261011.md](dark-soft-charcoal-20261011.md). Branche `claude/dark-soft-charcoal-20261011`, partie de la PR #10.

**Exécuté** : IPA compilée sur `73bd0ec` ; 455 tests métier passent ; 141 couples de contraste sombres au-dessus de leur seuil (calcul sur les valeurs déclarées) ; 28 écrans iPhone capturés en clair et en sombre avant et après. En clair, 23 écrans sont identiques au pixel près ; les 5 autres diffèrent par l’heure, un chronomètre, une animation ou la galerie enrichie.

**Reste à qualifier** : carte sombre réelle, Liquid Glass, ombres et bascule clair/sombre sur appareil ; Contraste accru, Réduire la transparence, grand texte, iPad et paysage, jamais rendus ; parcours UI non rejoués. **Au porteur** : valider à l’œil le bleu du bouton principal (`#3D70E2` au lieu de `#4D80EB`, pour le contraste du libellé) et l’aspect des interrupteurs. Le thème sombre du web n’est pas touché.

## 11 octobre 2026 — audit des parcours moniteur et élève

Une leçon ne se commence plus que le jour de son rendez-vous (l’agenda proposait de commencer celle de la semaine suivante) ; un rendez-vous manqué propose « Élève absent » et ne reste plus en tête d’Aujourd’hui ; accord GPS synchronisé entre la fiche et Profil ; filtres de l’élève alignés sur sa carte ; VoiceOver et Réduire les animations dans Progression ; lectures réseau de la fiche réduites ; l’app accepte un trajet sans identifiants d’appareil du moniteur. [Détail, points ouverts et limites](audit-parcours-20261011.md).

**Exécuté** : IPA d’essai sur chaque lot, sans avertissement ; 455 tests métier ; parcours UI iPhone et iPad (un échec de dérive corrigé, voir le détail). **Reste à qualifier** : tout sur iPhone, VoiceOver compris. **API (validé par le porteur)** : départ refusé avant le jour du rendez-vous (`LESSON_NOT_TODAY`), identifiants d’appareil du moniteur retirés des trajets lus par l’élève ; 275 tests API et 148 tests web passent. **Non déployé** : l’app de l’élève doit être installée avant l’API.

## 11 octobre 2026 — parcours de l’élève : Profil, prochaine leçon, Progression

Trois onglets pour l’élève (Leçons, Progression, Profil), prochaine leçon en tête, historique lu en entier, Progression refaite sur retours du porteur (un permis à la fois, « 4 sur 9 en autonomie », détail déplié sur place), ralentissements corrigés (dates et formateurs mis en cache). [Détail, relecture QA et points ouverts](parcours-eleve-profil-20261011.md).

**Exécuté** : IPA d’essai compilée sur chaque lot ; campagne complète sur `4e1b594` (452 tests métier, 12 parcours UI iPhone, 12 iPad). Tests métier relancés sur la dernière version (`941ea06`) : 453 passent ; les parcours UI n’y ont pas été rejoués. Fluidité confirmée par le porteur sur son iPhone.

**Reste à qualifier** : dernière version de la Progression, zoom de la carte, VoiceOver et grandes tailles de texte sur appareil. **Au porteur** : identifiants d’appareil du moniteur envoyés à l’élève (API et déploiement), objectifs visibles avant la leçon.

## 11 octobre 2026 — parcours de l’élève et agenda

Fiche de leçon chargée en parallèle (élève et moniteur), souhait et replay plus calmes ; planning qui se ferme dès la confirmation, formulaire stable pendant la vérification du créneau, semaines de l’agenda réaffichées sans squelette. [Détail et questions ouvertes](parcours-eleve-agenda-20261011.md).

**Exécuté** : compilation de l’IPA d’essai. **Non exécuté** : tests Swift, à la demande du porteur.

Accord GPS de l’élève lui-même (`SELF`) : question sous « Mon souhait » dans la fiche de sa prochaine leçon, envoyée aussitôt. Depuis la passe suivante, le choix général se modifie aussi depuis Profil. Non vu tourner.

## 11 octobre 2026 — parcours terrain fluides, deuxième passe

« Commencer la leçon » part directement sous le rideau quand rien n’est à demander ; la fin de leçon n’a plus qu’une attente et revient proprement à Aujourd’hui ; l’écran du trajet garde son dock stable. [Détail](parcours-fluides-20261011.md).

**Exécuté** : compilation de l’IPA d’essai sur chaque lot. **Non exécuté** : tests Swift, à la demande du porteur. **Reste à qualifier** : tout le parcours sur iPhone.

## 10 octobre 2026 — démarrage instantané en un seul parcours

Le geste « Démarrer une leçon » devient une seule interface : élève, récapitulatif et accord GPS dans une même feuille, puis le trajet sous le rideau ou la leçon ouverte sur place. [Causes, décisions et limites](demarrage-instantane-20261010.md).

- **Accord GPS** demandé dans le récapitulatif, au niveau de l’élève, enregistré au départ avec la leçon ; plus jamais pendant le rideau. Même chose depuis « Démarrer le trajet » d’une leçon planifiée.
- **GPS** : récepteur réveillé dès que le trajet est voulu et permis, conservé jusqu’au segment ; mesure de diagnostic tirée du réveil ; une seule relecture du départ et lectures en parallèle (environ 18 requêtes de moins).
- **Rideau** : plus de séquence fixe de 2 s ; levé à la première position (7 s au plus), hors de toute vue ; la carte montre la position de l’appareil tant qu’aucune n’est enregistrée.
- **Fiabilité** : garde contre le double appui, autorisation de capture toujours enregistrée pour être scellée, attente du premier plan avant le départ.

**Exécuté** : compilation de l’IPA d’essai (workflow « IPA d’essai · iLoader »). **Non exécuté**, à la demande du porteur : tests Swift (nouveaux tests écrits, cible de tests non compilée).

**Reste à qualifier** : parcours vu tourner sur iPhone, délai réel de première position, question d’iOS au premier usage.

## 10 octobre 2026 — audit global et corrections

Audit technique et UI/UX de toute l’application en cinq lots (API, web, trois lots iOS) suivis d’une revue croisée. [Corrections, limites et constats laissés au porteur](audit-global-20261010.md).

- **Règle commune** : 503 et 408 se réessaient et ne déconnectent jamais, 400 `INVALID_REQUEST` est un refus définitif, un reçu introuvable après une écriture confirmée reste une incertitude.
- **API** : panne d’identité en 503, valeur inacceptable en 400, pool protégé contre une connexion coupée, ouvertures modifiables pendant une leçon en cours.
- **Web** : sortie d’une session expirée, refus affichés dans leur dialogue, session gardée pendant une panne d’identité, fuseau de l’école.
- **iOS** : signalement refusé qui ne bloque plus la file, écriture confirmée jamais annoncée perdue, session conservée hors réseau, bouton d’école masqué pendant un trajet, leçons « À terminer » sous Aujourd’hui.
- **Déployé** : release `071af98` sur le homelab après sauvegarde vérifiée de la base ; aucune migration nouvelle.

**Exécuté** sur `071af98` : 436/436 tests Swift, IPA Release compilée, vérifications serveur et web réussies ; 148/148 tests web et 58/58 tests unitaires API en local.

- **Rideau de départ (retour du porteur)** : le contenu du rideau était vidé à l’instant où son fondu commençait, d’où une coupure nette ; il reste dessiné jusqu’à la fin, le symbole se retire avant le fond, et il entre en fondu. Le fond suit le thème (`canvas`) au lieu d’un noir ou d’un blanc pur. Second retour : le rideau attend la première position sur la carte, sept secondes au plus après la confirmation de l’école, et la séquence est jouée par Core Animation pour ne plus se figer quand le fil principal est occupé. Compilé ; le porteur a vu la première version sur son iPhone, pas la seconde.

**Reste à qualifier** : aucun écran iOS de cette passe n’a été vu tourner ; aucun parcours réel rejoué sur l’école hébergée ; aucun appareil physique.

## 10 octobre 2026 — demandes bloquées, recherche d’élève et API à jour

Incident du porteur : impossible de commencer une leçon (« Demande à vérifier », puis message de droits) ni d’en lancer une sans rendez-vous. Cause unique : l’app à départ explicite parlait à une API sans la route de départ ; le 404 restait en file sans issue et bloquait toute l’école sur l’appareil. [Cause, corrections et limites](deblocage-demandes-20261010.md).

- **Déployé** : API `040c8ed` puis `771a131` sur le homelab, migration 023, chaque fois après sauvegarde vérifiée de la base.
- **iOS** : refus 404 définitif, demande inconnue de l’école renvoyable ou abandonnable sur chaque écran, panneau qui nomme la demande, choix de l’élève avec recherche, droits de déplacement et d’annulation alignés sur l’école, GPS arrêté avant annulation.
- **Web** : même sortie pour une demande introuvable, relances manquantes, recherches agenda et invitations.

- **Seconde passe** : demandes GPS inconnues de l’école abandonnables, confirmation avant déconnexion pendant un trajet, recherche d’élèves sans accents, liste Élèves à chargement continu ; API `771a131` redéployée après sauvegarde. Huit constats GPS, adhésion et élève laissés au porteur.

**Exécuté** sur `771a131` : 420/420 tests Swift, IPA Release compilée, vérifications serveur et web réussies ; 138/138 tests web en local.

**Non vérifié** : aucun écran iOS de cette passe vu tourner ; aucune leçon réelle démarrée sur l’école après déploiement ; pas d’essai web avec l’identité réelle.

## 9 octobre 2026 — stabilité des parcours, démarrage réel des leçons et nettoyage

À la demande du porteur, revue de l’existant sans ajout de fonctionnalités ni refonte visuelle. Décisions et périmètre : [stabilite-parcours-20261009.md](stabilite-parcours-20261009.md), [serveur](stabilite-api-20261009.md), [iOS](stabilite-ios-parcours-20261009.md), [web](stabilite-web-20261009.md).

- **Leçons** : départ explicite durable (`actualStart`) depuis agenda ou manuellement ; « En attente » après dépassement sans départ, « Continuer »/« À terminer » seulement après départ confirmé. Fin fondée sur les heures réelles de la leçon, indépendante du trajet facultatif. Aucune annulation ni réalisation automatiques. Migration 023 reprend uniquement les départs prouvés par une commande ou capture.
- **Données et droits** : réponses anciennes ignorées, conflit de profil conservé jusqu’au rechargement explicite, dossier accessible après nouvelle lecture autorisée ; les détails web suivent immédiatement le filtre et le périmètre affichés. Les formulaires refusés gardent leur saisie et la déconnexion attend une confirmation réelle.
- **Navigation et nettoyage** : refus de démarrage manuel conservé sur son écran ; parcours sans GPS vers la fiche ; retraits d’états et de branches sans lecteurs vérifiés. Les écrans de recette visuelle sont conservés. README remis en accord avec l’application actuelle.

**Exécuté après fusion.** Sur `f8f5c63` : **248 tests API/PostgreSQL et 125 tests web réussis**, typage, builds et contrôles documentaires ([run37940876067](https://github.com/tomyrms/Drivy/actions/runs/37940876067)). Agenda web, changement de semaine lent et refus du formulaire de permis vérifiés avant fusion dans le navigateur à 1280 × 900 et 390 × 844 ; captures synthétiques dans la revue web. Après fusion, compilation, tests et fichiers d’icônes vérifiés ; navigateur indisponible pour une nouvelle capture.

**Vu après fusion.** 24 captures sur `6443d02`, iPhone 17 Pro et iPad Pro 13 pouces M5, clair/sombre, portrait, taille usuelle : attente et démarrage réel distingués, agenda/dossier/fiche/historique lisibles dans les viewports examinés. Le départ manuel secondaire est clarifié en « Leçon sans rendez-vous » puis vérifié dans deux captures iPhone supplémentaires sur `45691db`. [Preuve des 26 images et limites](proofs/stabilite-native-visual-20261009.json).

**Tests natifs.** **413/413 tests Swift et 3/3 tests de présentation réussis** sur `bc0bfa7`, sans échec ni test ignoré ([run37939864868](https://github.com/tomyrms/Drivy/actions/runs/37939864868)). Les quatre régressions de transfert GPS passent après remise en conformité des réponses de test ; [preuves et périmètres](proofs/stabilite-verifications-20261009.json). La campagne `6026104` avait réussi **12 parcours UI et 3 tests de présentation sur chaque appareil**, iPhone 17 Pro et iPad Air 11 pouces M4 ; les échecs de fixture et leurs corrections sont détaillés dans la revue.

**Finition du bilan vérifiée.** Huit captures des parcours UI ont révélé la saisie iPhone paysage masquée par la barre fixe puis un défilement inadapté. `ccef297` et `f8f5c63` libèrent l’espace et ramènent le champ actif dans la zone visible. La [recette renforcée sur `f8f5c63`](https://github.com/tomyrms/Drivy/actions/runs/37940876364) réussit **1/1 test sur iPhone et 1/1 sur iPad**, sans échec ni test ignoré. Ses cinq captures ont été ouvertes : saisie visible, texte conservé après rotation, retour de l’enregistrement après fermeture du clavier. [Preuve d’interaction, avant/après et limites](proofs/stabilite-native-interactions-20261009.json). Les autres parcours UI n’ont pas été répétés après ce correctif de disposition ; les textes longs et les autres champs en cours de frappe restent à qualifier.

**IPA préparée.** Version 0.7.0 **build 128**, source `f8f5c63`, [compilation Release réussie](https://github.com/tomyrms/Drivy/actions/runs/37940876258). Paquet non signé téléchargé ; les trois empreintes SHA-256 de l’artefact sont vérifiées. IPA : `16f2412e12767ef807094298acb5e983fcf0b1f974eabd8aa92374c45b5cb9b1`.

**Non déployé.** Les corrections restent sur la branche de travail. Mise à jour API/migration avant distribution de l’app ; sauvegarde obligatoire avant migration lors du déploiement.

**Fusion demandée par le porteur.** La branche `claude/marque-la-trace-20261006`, au commit `b710303c40b8f4462e8a4b39817544ecb53bde65`, est réunie à cette passe : marque et icônes web/iOS, carte Aujourd’hui compacte, cartes et écrans de protection conservés. Les conflits d’Aujourd’hui conservent le démarrage durable et la stabilité des feuilles ; les deux historiques documentaires sont conservés. Les tests finaux portent sur la version fusionnée. Le déploiement web séparé préparé par le porteur garde l’API hors de sa bascule ; son résultat n’est pas vérifié ici.

**Non qualifié.** Aucun essai physique GPS, batterie ou VoiceOver. Le navigateur utilise uniquement des données synthétiques ; la CI native utilise des simulateurs et transports synthétiques. La revue ne vaut pas qualification exhaustive de tous les écrans, tailles de texte, volumes ou usages sur appareil.
## 9 octobre 2026 — branding web en ligne

**Déployé à 14:36 Europe/Zurich** sur `https://drivy.shulker.ch/app`, source `b710303` : logo, cobalt, favicon et manifeste. Release web isolée, seul `drivy-refonte-web` redémarré. API et lien partagé restent sur `ef0ea216` ; ancienne release conservée, sauvegarde privée vérifiée avant bascule. Aucun fichier de la passe stabilité `codex/stabilite-parcours-20261009` livré.

**Vérifié** : build Linux sous Node verrouillé, onze fichiers publics avec empreintes exactes, routes d’entrée et protections anonymes, rendu du logo dans le navigateur sans erreur. [Détails, preuve et retour arrière](web-brand-deployment-20261009.md). Le prochain déploiement global doit traiter le drop-in `90-brand-web-release.conf` pour mettre le web à jour ; une simple bascule du lien partagé n’y suffit plus.

## 9 octobre 2026 — carte Aujourd’hui et logo de protection

À la demande du porteur : résumé Aujourd’hui réduit à horaire, élève, lieu et état inhabituel ; prochaines leçons repliées initialement sur iPad aussi. Le masque d’arrière-plan et l’écran verrouillé montrent le logo Drivy. Face ID et les règles métier restent identiques. [Décisions et suivi](today-privacy-20261009.md).

**Vérifié sur `86ef790`** : relecture indépendante, diff propre, deux contrôles du harnais ; 238 tests API/PostgreSQL et 104 tests web ; compilation Release/simulateur. Six tests d’interface ciblés réussissent ; 20 captures en taille usuelle inspectées sur iPhone 17 Pro et iPad Air 11 pouces M4, clair/sombre, portrait et iPad paysage. Résumé lisible, état À terminer et suivante préservés, logo centré sur les deux écrans de protection. [Preuve et limites](proofs/today-privacy-20261009.json).

**Livré** : IPA 0.7.0 **build 121**, non signée pour iLoader, téléchargée et SHA-256 vérifié. La suite native métier complète n’est pas répétée pour cette passe graphique. Face ID et les transitions d’arrière-plan sur appareil physique restent à qualifier.

## 9 octobre 2026 — intégration de La trace

Le chantier de marque reprend à la demande du porteur. [Décisions et périmètre](brand-integration-20261009.md).

- **Implémenté** : primitives ligne/repère, parcours des compétences, fils de l’agenda, de la progression et des observations ; cartes atténuées, bornes et lacunes mesurées ; symbole de connexion animé, icônes d’application, marque/cobalt/favicons web.
- **Vérifié** : 238 tests API/PostgreSQL et 104 tests web, types/builds et intégrité documentaire réussis sur `bb75ae5` ([CI](https://github.com/tomyrms/Drivy/actions/runs/37858824079)) ; 52 couples de contraste web conformes aux seuils mesurés. Tests natifs et parcours iPhone/iPad réussis sur `aecdac1` ([campagne](https://github.com/tomyrms/Drivy/actions/runs/37857755974)). Les deux corrections graphiques ultérieures de `bb75ae5` ont été compilées et capturées, sans nouvelle campagne complète.
- **Vu** : 56 captures des écrans natifs sur iPhone 17 Pro et iPad Pro 13 pouces M5, clair/sombre, 28 en grands caractères sur `aecdac1` et 28 à taille normale sur `bb75ae5`. Toutes ouvertes pour inspection, [preuve et limites](proofs/brand-native-visual-20261009.json), [six aperçus](assets/brand-integration-20261009). Quatre vues web inspectées. Contenu hors viewport, interactions et détails du replay synthétique non qualifiés : voir le [suivi](brand-integration-20261009.md#limites-des-captures).
- **Livré** : IPA 0.7.0 **build 120**, source `bb75ae5`, [compilation Release réussie](https://github.com/tomyrms/Drivy/actions/runs/37858824190), téléchargée et SHA-256 vérifié ; paquet non signé pour iLoader.
- **Différé** : vignettes de trajet dans les listes (aucune géométrie dans leur contrat), déploiement homelab, validation physique et recherche de marque. Aucune donnée ni règle d’accès modifiée.

## 6 octobre 2026 — passe de marque « La trace » (proposition, non codée)

Trois territoires explorés, « La trace » retenu : [compte rendu](brand-pass-20261006.md), [Drivy Brand System](brand-system.md), [fichiers](assets/brand-20261006).

- **Exécuté** : audit du code et des captures ; rendus et audits SVG du logo, de l'icône et des pictogrammes ; contrastes calculés ; onze maquettes avant/après capturées sous Windows (police de repli, carte schématique).
- **Reste à qualifier** : validation du porteur ; toute l'implémentation Swift et web ; rendu MapKit atténué ; icône sur appareil (Liquid Glass, mode teinté) ; Dynamic Type et VoiceOver sur le rail et le parcours ; mouvement ; impression ; recherche d'antériorité de la marque.

## 5 et 6 octobre 2026 — dossier par permis, fiche et récapitulatif de leçon, bilan en étapes, Leçons du moniteur

À la demande du porteur. Décisions : [passe-ui-20261005-soir.md](passe-ui-20261005-soir.md), conception : [conception-dossier-lecon-20261006.md](conception-dossier-lecon-20261006.md), reprise : [reprise-passe-ui-20261005-soir.md](reprise-passe-ui-20261005-soir.md).

- **Données fictives** : plus aucune mention « exemple » dans les noms, fermetures, conditions générales et adresses de l’école du homelab (`infra/deploy/provision-realistic-labels.sql`, sauvegarde vérifiée, répétition sur copie). E-mails et téléphones laissés non attribués. Photos de profil non faites : la base les interdit et aucun dépôt de documents n’existe.
- **États de leçon** : un mot de texte dans la ligne, plus de pastille ; lignes de compte et de profil sans symbole de tête.
- **Dossier** : sous l’identité, « Leçons | Progression » en place, un seul filtre par permis. Ligne de leçon avec « Bilan · Trajet » en mots. Progression : dernière leçon évaluée, décompte en mots, à travailler, en autonomie, pas encore vues.
- **Leçon** : récapitulatif en lecture par défaut à toute largeur (bilan, compétences, trajet avec bouton lecture sur la carte, observations, objectifs prévus), deux colonnes sur iPad large. La rédaction du bilan ne s’ouvre qu’après « Terminer la leçon » ou sur demande : étapes Trajet → Compétences → Bilan sur iPhone, un envoi final, brouillon local chiffré. Le constat de fin de leçon ne publie plus les objectifs comme bilan.
- **Profil** : « Leçons » remplace « Trajets » ; historique récent d’abord, par mois, recherche par élève, même fiche que partout ailleurs.
- **API** : paramètre `order` sur la liste des leçons (extension hors contrat canonique, le contrat du dossier de conception n’est pas modifié).

**Exécuté sur la CI.** Sur `0d42721` : **388 tests unitaires sur 388 et les parcours d’interface iPhone et iPad** ([run37422613310](https://github.com/tomyrms/Drivy/actions/runs/37422613310)) ; captures de dix écrans sur simulateur iPhone et iPad, en clair ([run37422615940](https://github.com/tomyrms/Drivy/actions/runs/37422615940)) : [dossier](assets/passe-ui-20261006/iPhone-dossier-multi.png), [leçon](assets/passe-ui-20261006/iPhone-lesson.png), [leçon iPad](assets/passe-ui-20261006/iPad-lesson.png), [leçon annulée](assets/passe-ui-20261006/iPhone-lesson-cancelled.png), [progression](assets/passe-ui-20261006/iPhone-progression-multi.png), [leçons du moniteur](assets/passe-ui-20261006/iPhone-lessons-history.png). Vérifications API et web réussies, dont les tests PostgreSQL du tri et du trajet masqué à l’élève. IPA compilée sur `5054914` ([run37422673391](https://github.com/tomyrms/Drivy/actions/runs/37422673391)), non téléchargée ; ce dernier commit (situation notée en Progression) n’a que la compilation.

**Déployé.** Release `ef0ea21` sur le homelab le 6 octobre, après sauvegarde vérifiée (`/root/drivy_refonte-before-ef0ea216…-20261006T055442Z-4c5d61b6eca2.dump`), 22 migrations inchangées, services actifs. Elle inclut le nom affiché recomposé (`4daae5f`), accepté par le porteur le 6 octobre : écart assumé avec R77.

**Non qualifié.** Les étapes de rédaction du bilan et l’écran deux colonnes de rédaction sur iPad n’ont jamais été capturés (les tests d’interface les traversent, sans image regardée). Aucun essai sur appareil : clavier, longs textes, rotation, reprise du brouillon après arrêt de l’app, VoiceOver, grand texte, mode sombre. Profil → Leçons n’a pas été vu avec un compte réel ni avec du volume ; sa recherche lit tout l’historique. Aucun trajet GPS dans le jeu fictif : carte et bouton lecture ne se voient que sur des leçons réellement enregistrées.

## 5 octobre 2026 — passe UX sobre : dossier, leçon, bilan, GPS, modification du dossier

À la demande du porteur. Décisions : [ux-sobre-20261005.md](ux-sobre-20261005.md). Reprise : [reprise-ux-sobre-20261005.md](reprise-ux-sobre-20261005.md).

- **Identité de l’élève** : composant partagé `DrivyLearnerIdentity` (dossier, fiche de leçon, bilan, Leçons, Progression, observations, préparation du trajet).
- **Dossier** : en-tête compact avec pastilles de contact ; coordonnées, date de naissance, adresse et « Modifier les informations » dans une zone dépliable.
- **Fiche de leçon et bilan** : une vingtaine de symboles décoratifs retirés ; une ligne « Prix de la leçon » ; « À payer » retiré (aucun paiement n’est enregistré) ; bouton « Enregistrer et partager le bilan » ou « pour moi » selon le partage.
- **Planification** : un seul tarif possible s’affiche en une ligne, le sélecteur n’apparaît qu’avec plusieurs tarifs.
- **Modification du dossier** : les six champs en accès complet, e-mail et téléphone pour le moniteur affecté, alignés sur les droits du serveur. Le formulaire ne suivait que la politique de champs de l’école.
- **GPS actif** : « Signaler » ne se grise plus pendant l’envoi ; pause, reprise et perte de signal récupérée ne reconstruisent plus le panneau ni la carte.
- **Relectures** : fiche de leçon, observations, profil, planification, démarrage et préparation du trajet ne se grisent plus et ne se décalent plus pendant une relecture silencieuse.

**Exécuté sur la CI.** IPA compilée à chaque étape. Vérifications API et web réussies sur `fa72b75`, dont le nouveau test PostgreSQL du dossier ([run37297614674](https://github.com/tomyrms/Drivy/actions/runs/37297614674)). Campagne native sur `4cb4cee` ([run37335264393](https://github.com/tomyrms/Drivy/actions/runs/37335264393)) : 322 tests unitaires sur 324 et les 12 parcours d’interface, iPhone et iPad. Les deux échecs venaient de fixtures de test écrites la veille sans être exécutées (reçu de déplacement à version inchangée, attente oubliant la création confirmée) ; elles sont corrigées et la campagne de confirmation réussit sur `e1097eb` : **324 tests unitaires sur 324 et les parcours d’interface iPhone et iPad** ([run37340252666](https://github.com/tomyrms/Drivy/actions/runs/37340252666)). IPA finale compilée sur `e1097eb` ([run37340253321](https://github.com/tomyrms/Drivy/actions/runs/37340253321)), non téléchargée. Captures de 15 écrans sur simulateur iPhone, en clair ([run37332255921](https://github.com/tomyrms/Drivy/actions/runs/37332255921)) : [dossier](assets/ux-sobre-20261005/dossier.png), [leçon](assets/ux-sobre-20261005/lecon.png), [saisie](assets/ux-sobre-20261005/saisie.png), [GPS](assets/ux-sobre-20261005/gps.png).

La cible de tests ne compilait plus depuis `9dcad86` (macros `#require` imbriquées ou sans `try` interne) : corrigé.

**Non déployé.** `apps/api/src/profiles.ts` recompose le nom affiché quand le prénom ou le nom changent. C’est un écart avec R77 (nom public distinct de l’identité administrative) : le porteur tranche avant tout déploiement. Sans lui, les six champs fonctionnent déjà ; seul le nom affiché dans les listes ne suit pas.

**Non qualifié.** Aucune transition n’a été vue : clignotement de « Signaler », pause et reprise, relectures. Ni GPS réel, ni VoiceOver, ni grandes tailles de texte, ni mode sombre, ni rendu iPad de ces écrans. Le dossier déplié, le formulaire du moniteur affecté et la liste des pays n’ont pas été capturés.

## 4 octobre 2026 — jeu de volume fictif en production

À la demande du porteur, la base du homelab contient maintenant un jeu d’essai volumineux : **86 élèves (+80), 7 moniteurs (+5 sans compte), 108 formations (+102) et 1 298 leçons (+1 236)** sur 180 jours passés et 45 jours à venir, avec 751 révisions de bilan, 1 912 observations sans position, des objectifs, 82 contrôles de permis, des disponibilités et deux fermetures. La catégorie B reprend l’offre existante ; les offres A et BE sont nouvelles. Script `infra/deploy/provision-volume-data.sql`, une transaction, refuse une seconde exécution ; il vérifie avant validation qu’aucune ligne existante n’a changé, hors champs vides du dossier de l’élève d’essai. **Sauvegarde vérifiée avant application**, répétition jouée deux fois sur une copie restaurée puis supprimée, résultat identique en production. Sous les droits par ligne : `luc` lit tout, `moniteur` 66 élèves sur 86, `eleve` ses 174 leçons, 93 bilans partagés, aucun brouillon ni repère privé. API prête après application. [Preuve](proofs/volume-seed-20261004.json), [reprise](reprise-jeu-volume-20261004.md).

**Non qualifié :** aucun écran n’a été vu avec ce volume ; rendu, pagination et temps de réponse restent à constater dans l’app et sur le web. Aucune capture GPS d’exemple : les 1 236 leçons ajoutées n’ont pas de trajet.

## 4 octobre 2026 — dossier par pages et corrections tarif/Signaler

Le tarif et le solde sont affichés directement dans la fiche de leçon, sans seconde fenêtre. Signaler gagne 40 pt et conserve trois colonnes sur petit iPhone. Le dossier ouvre une carte d’informations de l’élève, puis des pages séparées Leçons et Progression avec retour natif ; coordonnées et champs personnels suivent les droits serveur existants. Samaritains/sensibilisation restent non implémentés, sans statut inventé. Le rapprochement générique des commandes ne peut plus acquitter une annulation de signalement avec un reçu de création. Sources relues et contrôles généraux réussis. **IPA 0.7.0/build103 compilée et téléchargée**, source `9603eb3` ([run37219639586](https://github.com/tomyrms/Drivy/actions/runs/37219639586)), archive et empreintes vérifiées. Tests Apple et rendu physique non exécutés à cette étape. [Décision et limites](dossier-pages-tarif-signaler-20261004.md).

## 4 octobre 2026 — retours de signalement, disponibilité et accès directs

**IPA 0.7.0/build102 compilée et téléchargée, empreintes vérifiées**, source `9dcad86` ([run37217708082](https://github.com/tomyrms/Drivy/actions/runs/37217708082)) : bandeau Signaler avec annulation durable, modes carte libre/centré/orienté, profil et tarif visibles, alertes compactes. La planification vérifie le créneau avant le tarif et retire la case d’acceptation locale. **Serveur déployé après sauvegarde vérifiée** : release `52c355f`, migration022, services actifs et contrôles HTTPS conformes. **234 tests API dont dix nouveaux sur PostgreSQL, 104 web, types et builds réussis** (run37217180774). Tests Apple ajoutés/adaptés non exécutés ; rendu, gestes, GPS et VoiceOver sur appareil restent à qualifier. [Décisions et vérifications](live-feedback-planning-20261004.md).

## 4 octobre 2026 — prochaines leçons, palette Signaler et confirmation de fin

Le porteur valide les feuilles stables de build100. La liste secondaire d’Aujourd’hui conserve les prochaines leçons PLANNED uniquement (créneau en cours inclus), sans terminées/annulées/absences ni doublon du focus. Signaler devient une palette sur la carte iPhone, avec ses catégories et appréciations réunies ; iPad et grand texte gardent une présentation native. La fin de leçon demande confirmation avant toute mutation et conserve une attente neutre jusqu’au bilan, sans formulaire planifié fugitif. **IPA 0.7.0/build101 compilée avec succès** sur `ffd860c`, [run37215218985](https://github.com/tomyrms/Drivy/actions/runs/37215218985), téléchargée et empreintes vérifiées. Tests ciblés adaptés mais non exécutés ; aucune longue campagne native. Rendu et transitions sur appareil restent à qualifier. [Décision et limites](today-signal-finish-20261004.md).

## 4 octobre 2026 — correction des hauteurs et gestes de feuille

Le retour du porteur sur build99 signale une mauvaise hauteur initiale et des saccades à l’agrandissement. Le composant de mesure automatique est supprimé : dix présentations utilisent désormais des hauteurs natives stables, sans pilotage de la sélection ni recalcul sur le contenu ; popover Signaler iPad fixé à 480 × 560 pt. Contenus compacts et gestes gérés par SwiftUI. **IPA 0.7.0/build100 compilée avec succès** sur `9c1b12a`, [run37213508972](https://github.com/tomyrms/Drivy/actions/runs/37213508972), téléchargée et empreintes vérifiées. Fluidité, clavier et accessibilité sur appareil restent à qualifier. Aucune longue campagne native lancée. [Décision et limites](stable-sheets-20261004.md).

## 4 octobre 2026 — panneaux compacts et orientation du téléphone

Livraison initiale build99, dont le dimensionnement est remplacé ci-dessus après retour du porteur. Feuilles ajustées au contenu pour Démarrer, préparation/accord GPS, Signaler, préférences, période et choix d’école. Signaler passe en rangées compactes puis se réduit aux trois appréciations. La carte active reçoit le cap réel du téléphone, sans changer les positions enregistrées ni le replay. Relectures de code terminées ; **IPA 0.7.0/build99 compilée avec succès** sur `a2dc49c`, [run37212556376](https://github.com/tomyrms/Drivy/actions/runs/37212556376), téléchargée et SHA-256 vérifié. À la demande du porteur, aucune nouvelle longue campagne native/captures. Rendu réel, clavier, iPad, VoiceOver et boussole sur appareil restent à qualifier. [Décision](compact-sheets-20261004.md), [cap de la carte](live-device-heading-20261004.md).

## 4 octobre 2026 — revue native, icônes et IPA livrée

Huit lots intégrés : Aujourd’hui, squelettes, navigation de leçon, sélection GPS partagée, agenda/planification, dossiers/progression, bilan/observations et compte/invitations. Cinq propositions d’application et cinq pictogrammes par catégorie conservés, puis sélection et finition ; Signaler simplifié. À la demande du porteur, skill logo-design installé, trois pistes vectorielles comparées et d continu intégré à l’icône et à l’accueil.

**Livré : IPA 0.7.0/build98**, source `e36b0d4`, [compilation Apple réussie](https://github.com/tomyrms/Drivy/actions/runs/37210789141), téléchargement et SHA-256 vérifiés. [PR5 ouverte](https://github.com/tomyrms/Drivy/pull/5), retirée du brouillon à sa demande. Le porteur souhaite l’IPA sans attendre toutes les campagnes : tests natifs restants et captures complémentaires arrêtés, aucun succès supposé pour ces vérifications.

**Exécuté** : 224 tests API PostgreSQL et 104 web sur la CI générale ; première campagne Apple : 241 Swift et 12 UI iPhone réussis, UI iPad 11/12 (sélecteur corrigé). 48 captures finales normales et AX inspectées individuellement ; aucun nouveau P0–P2 établi, avec limites de champ documentées. Tests ajoutés après la première campagne non déclarés qualifiés. Deux captures AX complémentaires confirment la fixture Aujourd’hui corrigée et la connexion ; quatorze autres vues non qualifiées. GitGuardian signale trois détections non vérifiées, détails absents du résultat accessible. Aucun résultat physique GPS, batterie ou VoiceOver ; aucun déploiement homelab. [Revue et preuves](native-ui-review-20261004.md), [icônes](native-icon-signal-review-20261004.md), [logo](drivy-logo-skill-20261004.md), [passation](reprise-revue-ui-20261004.md).

## 30 septembre 2026 — diagnostic de la campagne de captures iOS

Correctif local de l’archive jointe : noms de captures validés avant lancement, diagnostics explicites avant les assertions, attente du compte sur son identifiant existant et export des pièces jointes même après échec. Le code 65 reste propagé ; les contrôles de rotation et de complétude restent obligatoires. **Le journal d’échec et l’archive sont des versions différentes** : l’ancien écran `student-file` n’existe pas dans cette campagne. Aucune équivalence avec un autre écran ni résolution de l’ancien parcours n’est revendiquée.

**Exécuté** : syntaxe Bash, analyse syntaxique Swift Linux et 11 contrôles du script avec commandes Apple simulées. **Non exécuté** : compilation Apple et XCUITest iPhone/iPad. Aucun push ni déploiement. [Diagnostic et reprise](visual-ci-diagnostics-20260930.md).

## 30 septembre 2026 — passe UI/UX native iPhone et iPad

Le porteur autorise maintenant la revue et l’amélioration des écrans natifs. Trois agents traitent agenda/démarrage, dossiers/compte et séance/carte avec les UI Skills et SwiftUI. Les changements de composition conservent l’identité native, les droits et la persistance. Compilation, tests et nouvelles captures Apple en cours de préparation. [Périmètre et suivi](native-ui-pass-20260930.md).

## 30 septembre 2026 — deuxième passe des layouts web

Les 18 destinations web ont reçu une seconde revue de composition, avec trois agents et une revue indépendante des changements. Les en-têtes sont rapprochés, les fils d’Ariane limités aux véritables sous-pages, les listes/détails adaptés à la largeur du conteneur. Annuaires entièrement cliquables, horaires/absences côte à côte, réglages en sections alignées et entrée simplifiée. Palette et typographie conservées. [Décisions et vérification](web-layout-pass2-20260930.md).

- **104 tests web**, typecheck et build réussis. Revue visuelle à 1200/390 px, contrôles des 18 destinations à 320 px avec textes longs, détails/formulaires et clavier à 834 px sombre. Après correction, aucun débordement mesuré sur les 58 relevés retenus. [Preuve](proofs/web-layout-pass2-20260930.json).
- **Déployé sur le homelab : `e30e4ea`**, après nouvelle sauvegarde vérifiée. API/web/identité actifs, migrations 001–021 conformes, JavaScript/CSS/police publics identiques au build testé. CI réussie : **224 tests API et 104 tests web**. [Preuve de déploiement](proofs/deployment-web-layout-pass2-20260930.json). Zoom 200 %, lecteurs d’écran et appareils physiques restent à qualifier.

## 30 septembre 2026 — finition esthétique et ergonomique de chaque écran web

Le porteur juge l’organisation plus claire mais l’apparence encore trop élémentaire. Passe réalisée, **web uniquement** : palette encre/papier, typographie Source Sans 3 auto-hébergée, contrôles et tableaux retravaillés, hiérarchie des identités, heures et prix, états ordinaires allégés. Deux agents ont partagé composants communs et parcours métier ; l’intégration couvre catalogue, réglages, entrée et revue navigateur. Les cinq espaces de navigation sont conservés. [Décisions et guides](web-craft-20260930.md).

- **104 tests web et 224 tests API** réussis sur la CI `36733112389` du commit `946476a`, typechecks et builds réussis. 18 destinations desktop/mobile inspectées, contrôle de repli à 320 px, tablette sombre 834 px, liste/détail 1360 px ; 44 captures, filtres et clavier contrôlés. 52 couples de contraste passent les seuils mesurés. [Preuve](proofs/web-craft-20260930.json).
- **Déployé sur le homelab : `946476a`**, après nouvelle sauvegarde vérifiée de `drivy_refonte`. API/web/identité actifs, migrations 001–021 conformes, JavaScript/CSS/police servis en HTTPS identiques au build local. [Preuve de déploiement](proofs/deployment-web-craft-20260930.json). Zoom 200 %, lecteur d’écran, Safari et appareils physiques restent à qualifier.

## 30 septembre 2026 — organisation des parcours web

Le retour complémentaire sur la difficulté à se repérer a conduit à une nouvelle répartition des informations : **cinq espaces**, accueil Planning, formations reliées à leurs compétences/procédures/tarifs, invitations séparées et détails mobiles avec retour. Les liens conservent leurs identifiants et filtres ; les brouillons de catalogue non soumis survivent aux renvois dans la même session. Le dossier place le suivi avant les formulaires administratifs. [Décision](web-architecture-20260930.md).

- Typecheck/build et **100 tests web** réussis ; parcours vérifiés dans le shell réel avec données synthétiques, aux largeurs320/390/834/1440, clair et sombre. [Preuve](proofs/web-architecture-20260930.json). Déployé sur le homelab : `b5c6c38`, après nouvelle sauvegarde vérifiée. API/web/identité actifs, migrations001–021 conformes, assets HTTPS identiques au build local. [Preuve](proofs/deployment-web-architecture-20260930.json).
- IPA native **0.7.0/build87** téléchargée et vérifiée ; source produit identique à `fe9fe6b`, seule la fixture de captures a changé sur `cd5a394`. [Preuve](proofs/native-ipa-retours-20260930.json).
- Tests Apple : après correction des six échecs de fixtures/macros, reprise `36727211560` sur `e4eea1c` réussie : **218/218 iPhone** (208 Swift Testing, 3 présentation, 7 UI), **10/10 iPad** (3 présentation, 7 UI). IPA **0.7.0/build129** vérifiée ; binaires identiques à la build87. [Preuve complète](proofs/native-retours-20260930.json).
- 24 captures ciblées Apple inspectées, avec limites explicites (observations vides, notification système sur une capture, cartes synthétiques). [Revue](native-visual-retours-20260930.md).

## 30 septembre 2026 — retours complémentaires, validation en cours

Source native et web `fe9fe6b` : **refonte visuelle générale web uniquement**. Le thème et l’identité iOS/iPadOS restent conservés ; les modifications natives portent sur les demandes ciblées. [Liste détaillée](plan-retours-20260930.md).

- **Web** : navigation par usages, palette papier/forêt, sections plates et listes compactes. Rendu navigateur vérifié à 320/390/834/1440 px, clair/sombre, menu mobile et retour de focus. Typecheck/build et 93 tests réussis ; contrastes mesurés. Zoom texte 200 %, lecteurs d’écran et appareils physiques restent à qualifier. [Direction web](web-direction-20260930.md).
- **Carte/replay** : caméra orientée et suivi initial, exploration/recentrage, géométrie retenue, signalements après persistance chiffrée avec ancre durable, compteur retiré, annulation sans bilan depuis la carte. Le recalage automatique sur route n’est pas activé ; précision réelle et batterie restent à mesurer. [Décision carte/GPS](carte-replay-gps-20260930.md).
- **Planification** : lieu facultatif, moniteur courant éligible, préférences personnelles de catégorie/tarif dans Profil, secondaires repliés. Migration021 et routes `/planning-defaults` déployées sur le homelab. [Détail](planning-defaults-20260930.md).
- **Dossier/bilan** : mois/année, pagination complète, propagation après reçu durable, relecture au premier plan, évaluations réversibles dans la leçon et observations compactes partagées. [Détail](dossier-progression-20260930.md).
- **Revue croisée** : reprise d’historique pendant une page lente, confirmation d’une autre leçon, annulation suivie d’une panne de relecture, changement d’école dans les préférences corrigés et couverts par des tests ajoutés.
- **Serveur/web qualifiés localement** : API **224/224**, web **93/93**, typechecks et builds réussis sur PostgreSQL17.11 et Mailpit Docker isolés ; 21 migrations et 45 tables avec RLS forcée. Trois attentes de test obsolètes adaptées au lieu facultatif et à la nouvelle table, sans retirer les contrôles. Conteneurs temporaires supprimés. [Preuve](proofs/backend-retours-20260930.json).
- **Homelab déployé** : `fe9fe6b`, sauvegarde privée vérifiée avant migration, empreintes001–021 concordantes, API/web/identité actifs, chemins des processus et routes HTTPS contrôlés. [Preuve](proofs/deployment-retours-20260930.json).
- **Qualification Apple exécutée** : les échecs de macros/fixtures des premiers runs ont été corrigés dans les tests ; reprise finale `36727211560` réussie, 218 tests iPhone et 10 tests iPad, IPA129 vérifiée. Les 24 captures ciblées et leurs limites sont conservées dans la preuve native. Les essais physiques restent distincts.

## 30 septembre 2026 — reprise de la passe de bugs

- **Passe Claude reprise et validée sur `8547d95`** : la fixture du test de filtre des trajets répondait avec des trajets au contrôle d'identité ; correction du test et ajout d'un cas de révocation pendant pagination. Run Apple `36716875435` réussi : **198/198 iPhone 17 Pro et 10/10 iPad Air 11 M4**, zéro échec/ignoré, iOS simulateur 26.4.1. [Preuve native](proofs/native-resume-20260930.json).
- **Correction complémentaire** : une panne de relecture des formations ne retire plus le dossier déjà affiché et ses feuilles ; une erreur avec Réessayer reste visible.
- **Agenda** : les erreurs au retour sur l'onglet sont affichées ; la feuille de leçon reste portée par la racine stable.
- **Backend déjà déployé et revérifié** : release `5406f65`, code API/web identique à `39704b6`, 20 migrations comparées par nom/SHA-256, trois services actifs, chemins des processus et santé/HTTPS contrôlés. La migration020 est donc exécutée, contrairement au dernier paragraphe historique ci-dessous. Aucun redéploiement identique nécessaire.
- **Tests serveur exécutés** : run `36716860267` sur `8547d95`, API 218/218 sur PostgreSQL 17.11 et Mailpit, web 93/93, typechecks/builds réussis. Même résultat sur le PC, avec PostgreSQL Docker isolée et 20 migrations. [Preuve backend](proofs/backend-resume-20260930.json).
- **Docker rétabli** : sockets temporaires inaccessibles conservés dans des dossiers de sauvegarde ; moteur opérationnel, volumes et conteneurs antérieurs présents. Les deux conteneurs de recette ont été arrêtés et retirés. [Intervention](docker-recovery-20260930.md).
- **IPA disponible** : 0.7.0/build 83, source `8547d95`, run `36716860249`. Téléchargement, CRC ZIP, hashes des binaires, absence de signature et configuration du homelab vérifiés. [Preuve IPA](proofs/native-ipa-resume-20260930.json).
- **Nouveaux retours en cours** : carte/replay/GPS, préférences de planification, dossier/compétences/synchronisation et refonte visuelle **web uniquement**. [Liste complète](plan-retours-20260930.md). Les résultats de `8547d95` ne qualifient pas les modifications ultérieures de ce chantier.
- **Reste sur appareil** : gestes iPhone/iPad, GPS, batterie et VoiceOver. [Détail de la reprise](reprise-bugs-20260930.md), [vérification homelab](proofs/deployment-resume-20260930.json).

## 29 septembre 2026 — retour sur appareil et revue UI Skills

Le retour du porteur après installation a ouvert une nouvelle passe ; les résultats de la passe précédente ci-dessous ne qualifient pas ces corrections.

- **Signalement restauré** : Signaler → type de situation → statut explicite → écriture durable et fermeture. Même geste avec ou sans GPS ; type visible dans le replay. Accord GPS direct, documents sur demande, arrêt/transfert automatiques à la fin de leçon, bilan facultatif et fermeture après confirmation. [Revue de chaque écran natif](ui-review-native-20260929.md).
- **Serveur exécuté et déployé** : 215/215 tests sur PostgreSQL 16.14 isolée ; API/web du homelab à `f054bc6`, sauvegarde privée contrôlée avant migration019, 19 migrations comparées par nom et SHA256, trois services actifs et routes publiques contrôlées. [Tests](proofs/api-field-flow-20260929.json), [déploiement](proofs/deployment-field-20260929.json).
- **iPad autorisé pour essai** : profil limité au modèle réel `iPad13,17`, conservé au déploiement. [Preuve](proofs/ipad-trial-20260929.json). Aucune qualification GPS/batterie physique n’est revendiquée.
- **UI Skills installé** : dix guides permanents, appliqués à l’inventaire natif et aux composants communs. Les rapports distinguent lecture du code, mesures de contraste, rendus et gestes exécutés.
- **Validation Apple exécutée** : source `e720c45`, run `36584364280`, **171/171 tests iPhone et 8/8 iPad**, zéro échec/ignoré. Dix images d’étapes terrain inspectées. La revue visuelle comprend aussi 90 originaux iPad Pro 13 en clair dans les deux orientations, quatre en sombre et huit iPhone ; les preuves conservent les limites de chaque lot. La campagne complémentaire sur Air 11 et rotation de saisie est distincte. Première position, autonomie, biométrie et VoiceOver physiques restent à constater sur les appareils du porteur.
- **iPad portrait et paysage** : dispositions fondées sur la largeur disponible, colonnes pour agenda/journée/listes et détails, largeur bornée des formulaires, signalement ancré au-dessus du trajet. [Revue des compositions](ui-review-ipad-lessons-20260929.md). Les nouvelles captures tournent le simulateur réellement et vérifient les dimensions des originaux.

- **IPA d’essai disponible** : version 0.7.0 build 73, source `be76813`, archive non signée et configuration du homelab contrôlées ; bundle français et orientations iPad vérifiés. [Preuve](proofs/native-ipa-final-20260929.json). Signature et installation par le porteur avec iLoader.

## 29 septembre 2026 — reprise et intégration des parcours

L’inventaire ci-dessous décrit le code intégré, avec les [corrections API du 29 septembre](corrections-api-2026-09-29.md) et les [décisions du porteur](decisions-2026-09-28.md). L’app couvre le terrain ; la console web couvre l’administration. La présence d’un parcours et sa compilation ne constituent pas une qualification sur appareil.

| Parcours / problème | Correction présente | Preuve et qualification |
|---|---|---|
| **Comptes et entrée élève :** invitation e-mail bloquée sans SMTP, formation unique. | Connexion OIDC existante ; « J’ai un code » ; invitation multi-permis avec moniteur, copie/partage et renouvellement. Acceptation atomique et reprise de la même opération. | Tests API codes, double acceptation et droits ; tests Swift réussis (campagne ci-dessous). [Invitations natives](native-invitations-design.md), [entrée dans l’école](native-join-school.md), [contrat codes](api-trajets-codes.md). |
| **Élèves, formations et équipe :** cycle de vie incomplet, lectures en attente prises pour des données absentes. | Retrait d’accès, fin d’affectation, pause/reprise/clôture/réouverture, archivage/restauration ADMIN ; filtre équipe et dossiers archivés ; permis et moniteurs attendent leur lecture. Offre déjà active/en pause exclue du nouveau formulaire. | Tests PostgreSQL des droits, versions, rejeux et affectations futures annulées ; tests web des commandes et règles de formulaire. [Contrats et refus](corrections-api-2026-09-29.md). |
| **Agenda et leçons :** entrées dispersées, création immédiate difficile, réglages et tarifs incohérents. | Aujourd’hui, Agenda et dossier ouvrent la même leçon : préparation, trajet, observations, bilan et fin. Démarrage immédiat, déplacement/annulation, contrôle du permis et dernière prestation applicable raccordés. | Tests API de planification, permis, issues et bilans ; tests Swift de la leçon réussis sur simulateur Apple. [Planification](g2-lessons.md), [permis](g2-permis.md), [corrections](corrections-api-2026-09-29.md). |
| **Trajets et replay :** historique peu accessible et administration sans vue d’école. | Onglet Trajets iOS et page web ; moniteur limité à ses trajets accessibles, ADMIN à son école. Replay, erreurs et transferts en attente restent visibles ; départ toujours avec un élève. | Tests PostgreSQL d’isolement des écoles et des observations privées ; tests Swift trajets réussis sur simulateur Apple. [Trajets et droits](api-trajets-codes.md), [capture native](native-capture-live.md). |
| **Observations et compétences :** signalement pendant le trajet trop lent, repères vulnérables à l’interruption. | Tuiles directes horodatées au geste, intention chiffrée avant envoi, même opération au renvoi ; précision ultérieure depuis le référentiel réel. Progression par compétence avec accès à la leçon source. | Tests API observations/bilans et tests Swift de persistance réussis sur simulateur Apple. [Observations natives](native-school-observations.md), [dossier et progression](native-training.md). |
| **Espace élève et console :** accès au suivi et séparation des rôles à consolider. | Élève : Leçons/Progression, trajet, observations partagées, bilan et objectifs ; notes gardées privées exclues. Console : école, politique de profil, catalogue/tarifs, équipe, invitations, élèves, agenda, trajets et disponibilités. | Tests API partage et confidentialité ; TypeScript et 93 tests web réussis. [Partage élève](partage-eleve.md), [console](../../apps/web/README.md). |

**Vérifications exécutées :** PostgreSQL **16.14 réel sur le homelab**, dans une instance de recette distincte : **208 tests réussis**, puis **98 tests ciblés réussis** après les dernières corrections ([preuve](proofs/review-api-20260929.json)). La [CI serveur/web 36570914236](https://github.com/tomyrms/Drivy/actions/runs/36570914236) passe également sur PostgreSQL 17 : **208 tests API et 93 tests web**, typage, builds et intégrité du canon. Le [run Apple 36569928729](https://github.com/tomyrms/Drivy/actions/runs/36569928729), source native `1014cce`, réussit : **145/145 tests iPhone** (métier et UI) et **4/4 iPad** (présentation et lancement), sans échec ni test ignoré, sur simulateurs iOS 26.4.1. Les rapports exportés ont été relus ; le build final ajoute seulement les deux finitions visuelles et les fixtures de contrôle. Les captures ont conduit à centrer le formulaire de leçon sur iPad et à remplacer « À venir » par « Prévues » pour ne pas mal classer les leçons en retard. La [revue visuelle finale 36572113947](https://github.com/tomyrms/Drivy/actions/runs/36572113947) a produit **28/28 captures exploitables et relues**, sur iPhone/iPad en clair et sombre : trajets, replay synthétique, progression, accueil, dossier et leçons. Aucune anomalie visuelle bloquante relevée sur ces captures. [Preuve native détaillée](proofs/native-review-20260929.json).

**Homelab déployé :** API et web `7b2d8aa`, migrations **001 à 018**, trois services actifs, chemins des processus et contrôles HTTPS vérifiés. Sauvegarde privée de `drivy_refonte` avant migration et de `drivy_identity` avant activation de l’inscription ; catalogues `pg_restore --list` relus. Inscription OIDC et libellés français actifs, sans SMTP ni vérification par e-mail ; aucun compte créé pour cette vérification. [Preuve de déploiement](proofs/deployment-review-20260929.json).

**IPA exportée :** **0.7.0 / build 63**, source `41f6c791177c76cddb077eb7d6fd6aa68018578b`, [run 36572072736](https://github.com/tomyrms/Drivy/actions/runs/36572072736). Archive Xcode créée, IPA appareil arm64 non signée ; téléchargement, CRC ZIP, hashes des binaires et configuration API/OIDC de production vérifiés. SHA-256 : `4d633e74ff1ce291b96405f70800d43267db21f3872994db69eb4ed2db3a6b8f`. Le code API/web de cette source est identique à la release déployée `7b2d8aa`. Fichier local : `artifacts/review-20260929/ipa-final/Drivy.ipa`. Signature et installation par le porteur avec iLoader ; aucune installation de ce build revendiquée.

**Limites :** pas encore de documents, cours collectifs/packs, saisie des règlements ni notifications in-app/push ; les charges du compte de leçon ne constituent pas un module de paiements. Aucun SMTP ajouté : le code permet l’invitation élève, mais la récupération de mot de passe par e-mail reste indisponible. Les sauvegardes ne sont pas automatisées. **Les brouillons web ne sont pas persistés** : les saisies restent en mémoire ; seules les métadonnées de commande permettent de rechercher un reçu après rechargement, sans restaurer le contenu. Après reconnexion, une saisie peut donc devoir être refaite. Installation iPhone/iPad, GPS réel, autonomie et VoiceOver restent à qualifier ; aucun résultat physique n’est déduit du simulateur.

## Historique (états datés)

Les états suivants sont conservés avec leurs dates et leurs preuves. Leurs mentions « courant », « déployé » ou « reste » décrivent leur jalon historique ; l’état du 29 septembre ci-dessus prévaut.

**28 septembre 2026 · phase 2 en cours** ([décisions du porteur](decisions-2026-09-28.md), [carte cible](carte-cible.md)). Branche `claude/refonte-parcours`, issue de `claude/tender-volta-bxdjd9`.

- **Homelab :** CT114 agrandi à chaud de 16 à 32 Go (45 % utilisés). Release API et web `1b03ae1` déployée le 28 septembre 2026 (migrations 010 à 013), chaque installation précédée d’une sauvegarde `/root/drivy-refonte-before-<SHA>.dump` sur CT113 ; services actifs, `/app/gestion` sert la console avec Élèves et Disponibilités. Aucune tâche de sauvegarde automatique n’existe sur le Proxmox.
- **Correctif du 28 septembre (retour du porteur) :** planifier une leçon bouclait sur « la procédure de la formation a changé ». Cause : l’iPhone envoie les UUID en majuscules et plusieurs contrôles serveur les comparaient comme du texte aux valeurs minuscules de PostgreSQL. L’API normalise désormais les UUID reçus (paramètres, requête, corps) ; test PostgreSQL ajouté. « Démarrer le trajet » enchaîne en un geste accord de l’élève (demandé une fois), localisation, mesure, diagnostic (valable 5 minutes) et départ ; seul un blocage s’affiche.
- **Données d’essai (production) :** `luc` devient ADMIN et INSTRUCTOR ; offre Permis B complétée (9 compétences, 95 CHF les 50 min, conditions, disponibilités) ; 21 leçons fictives, 12 bilans publiés, 32 observations. Sauvegarde préalable `/root/drivy-refonte-before-example-seed-20260928.dump` (CT113). Aucun trajet GPS d’exemple.
- **1. Connexion unique : appliquée.** Thème `drivy`, e-mail accepté, `offline_access`, sessions hors ligne 30/180 jours, verrou Face ID. Première connexion sur appareil à qualifier. [Détail](connexion-unique.md).
- **2. Partage automatique et « Ma leçon » : déployés.** Migration 012 et extensions `/sharing`, `/captures` en production ; l’écran de leçon unique montre trajet, erreurs, bilan et objectifs, avec « Visible par l’élève » (trajet, bilan) et « Gardée pour moi » (observation). [Détail](partage-eleve.md).
- **3. Trajet toujours avec un élève : fait.** Laboratoire G0 et trajets d’exemple retirés ; Aujourd’hui lance le trajet depuis la leçon. Profil GPS d’essai de l’iPhone du porteur actif (`NOT_QUALIFIED`).
- **4. Administration sur le web : déployée.** Console : élèves (ouvrir une formation, affecter un moniteur) et disponibilités/absences des moniteurs, en plus du reste. Une invitation d’élève peut porter sa formation et son moniteur (migration 013, test PostgreSQL réel). Les écrans d’administration de l’iPhone sont supprimés.
- **5. Onglets par rôle : compilés.** Moniteur Aujourd’hui/Agenda/Élèves ; élève Leçons/Progression ; compte derrière l’avatar avec « Gérer l’école » (web) pour l’administration. Passe « moins de texte » sur ces écrans et le planning. IPA [run 36457219287](https://github.com/tomyrms/Drivy/actions/runs/36457219287) ; tests natifs sur runner Apple en cours ; aucun écran vu sur appareil.
- **Bloquant : e-mail.** Sans relais SMTP en production, créer une invitation répond `INVITATION_DELIVERY_UNAVAILABLE` : « Inviter un élève » et « mot de passe oublié » ne fonctionnent pas encore.
- **CI :** tests serveur et web à chaque push (y compris `claude/**`).
- **Travail Codex conservé :** `codex/g1d-profils` et `codex/g1d-web-wip` (non relu, non testé).
- **Reste :** relais e-mail, essais sur appareil (connexion, trajet, écrans élève), passe « moins de texte » sur profil, accueil guidé et web, sauvegardes automatiques du homelab, purge de l’ancienne base locale G0 sur les appareils.

Mise à jour : 25 septembre 2026 (passe de design) ; 24 septembre 2026, après recentrage demandé par le porteur. **L’application complète reste en construction.** Priorité aux parcours utilisables et à l’apparence des maquettes ; campagnes exhaustives reportées à la fin. Les builds restent automatiques, la suite native et les tests serveur sont déclenchables manuellement. Une capture des vraies vues SwiftUI avec fixtures sert à corriger l’affichage, sans déclarer une recette métier complète.

**Web de gestion (25 septembre 2026, non déployé) :** console d'administration `/app/gestion` (vue d'ensemble, configuration et activation, champs du profil, catalogue : offres, référentiels, procédures, prestations et conditions commerciales, équipe et accès, invitations) derrière un BFF à liste blanche stricte méthode+chemin, CSRF, Idempotency-Key = operationId, If-Match fort, ETag relayé, no-store ; demandes incertaines vérifiables par AP72 et renvoyables à l'identique. Typecheck, 44 tests web et build réussis localement ; aucune recette contre l'API/Keycloak réels, aucun test navigateur en CI. Non couverts : disponibilités, dossiers/formations/affectations, profil administratif élève. L'iPhone conserve ses écrans d'administration jusqu'à qualification du web. Accueil guidé iOS et refonte trajet/replay intégrés (IPA run `36138415242` pour l'accueil). Audit fonctionnel : [plan restant](plan-fonctionnel-restant.md).

**Passe de design du 25 septembre 2026 :** système de design partagé iOS/web (tokens 3.8 complets, composants communs, Liquid Glass limité aux commandes sur la carte, signalement à grandes tuiles, haptique de succès après écriture durable) appliqué à tous les écrans principaux, sans changement métier. Voir [le système de design](design-system.md). IPA compilé avec succès jusqu’à `c07b4c6` (run `36131760336`) ; le lot final est vérifié par le run déclenché au push. Captures, VoiceOver, grand texte, sombre et appareil restent à qualifier.

**État courant :** API001–009 déployée depuis `069ea8fa369317543668ca7541e6c10269099aba`, sauvegarde vérifiée avant migration, trois services actifs. Profils, catalogue, formations, affectations, planification, préparation, constat, compte de leçon, publication du bilan et observations privées pendant la leçon sont implémentés côté serveur. Les limites effectives sont détaillées dans [la planification](g2-lessons.md) et [les bilans](g2-reports.md). L’école « Luc auto école » avait été activée par son administrateur ; ses coordonnées et textes ont été conservés. Six dossiers et six formations fictifs, identifiés « exemple », ainsi que deux comptes réels `moniteur` et `eleve` ont été ajoutés à sa demande. Connexion OIDC client Apple via navigateur : moniteur voit six dossiers/formations ; élève un seul. Les formations d’exemple initiales utilisent encore une offre désactivée sans configuration métier complète ; elles ne constituent pas des leçons planifiables déjà approuvées. Aucun mot de passe de `luc` n’a été utilisé, changé ou réinitialisé.

**API — tranches du 25 septembre 2026 (branche de travail, non déployées, migrations 010–011 non appliquées au service public) :** sondes internes `/health/live` et `/health/ready` ([exploitation-sante.md](exploitation-sante.md)) ; contrôle du permis AP29/AP30 avec `permitWarning` calculé et anomalie de constat exigée seulement sans permis valide ([g2-permis.md](g2-permis.md)) ; absence AP44, approbation AP88, correction AP50 entre issues closes (retours vers PLANNED/COMPLETED refusés explicitement) et retrait AP57 ([g2-issues-lecon.md](g2-issues-lecon.md)) ; filet de tests du planning, des prestations et du bilan ([tests-planning-bilan.md](tests-planning-bilan.md)). **Exécuté** sur PostgreSQL 16 local (`drivy_test`) : `tsc --noEmit` et `npm run build` réussis ; suite API **131 tests, 128 réussis, 3 échecs préexistants** (2 cas F02 sans Mailpit, 1 cas G1B « RLS interdit mutation… » qui échouait déjà avant ces tranches). Les 3 nouveaux fichiers (14 tests) et les deux fichiers capture mis à jour réussissent ; les réponses nouvelles sont validées contre l’OpenAPI 3.11.0 canonique. **Reste à qualifier** : PostgreSQL 17, CI d’intégration sur push, déploiement et règle Caddy `/refonte/health*`, écrans web/iOS du permis et des issues, transitions AP50 vers PLANNED/COMPLETED, frais d’absence/annulation.

**IPA courant compilé et téléchargé : 0.7.0/build28**, source `cfde4d8d12d3f7a727db768180cf642666b343e3`, [run36063213867 réussi](https://github.com/tomyrms/Drivy/actions/runs/36063213867), SHA-256 conforme au manifeste : `8f8f87eb68d5afddf201a744eb525cccfb5446fa5802eecd74bf9abc32389f0a`. Il inclut les correctifs de navigation du build25, profils/agenda/équipe/invitations/planning affinés, signalement personnel, préparation GPS scolaire et choix de l’élève, diagnostic, départ explicite AP154 et carte scolaire liée au propriétaire conservé à la racine. Fermer une feuille ou changer d’onglet ne réinitialise pas cette séance. La collecte reste conditionnée à un profil physique qualifié ; aucun profil n’a été inventé. Les reprises après relance et la passe visuelle demandée sur séance/replay sont en intégration après ce snapshot.

**IPA 0.7.0/build 20 livré**, source `05febc56afd118d8a747590597d1d0094c7f76bc`, [run `36052457170` réussi](https://github.com/tomyrms/Drivy/actions/runs/36052457170) : accueil Séance, trajet et replay avec carte dominante, catalogue, planification et bilans natifs, Équipe et accès. Deux trajets fictifs sont installés une seule fois dans le stockage local chiffré : Cernier → Neuchâtel et retour via Peseux, cinq observations et un bilan chacun. Leur origine d’exemple est visible ; aucune acquisition GPS n’est revendiquée. Ils sont supprimables sans réapparition au lancement suivant. SHA-256 de l’IPA téléchargé, conforme au manifeste : `57f1c4afcf2c46ce95b9ba93ae45165c9348ee6ce95245299720c5706c3127d4`.

Dix captures iPhone clair/sombre des vues natives de `072e724` ont été inspectées ; aucune qualification iPad supplémentaire n’est revendiquée. **IPA 0.7.0/build21 compilé et téléchargé**, source `394d4cd1d4736c33e1c4792a98e715dad51fea66`, run`36054482531`, SHA-256 `d76b2c64c0e96953167d6cd96f5bc1e514c79732e9c232aa2d67a75e3a29796c` : nouvelle hiérarchie des formulaires planning/bilan, catalogue/configuration et [dossier de formation](native-training.md) avec leçons, bilans publiés et progression. Les finitions suivantes restent en intégration. [L’accès Équipe](native-members.md) utilise une réauthentification OIDC ; la présence de `auth_time` dans un véritable jeton d’accès a été vérifiée sur l’hébergement avec le compte moniteur fictif, sans utiliser `luc`.

**Correctif de navigation compilé et livré dans le build25 :** les feuilles Équipe, catalogue, profil, configuration, invitations et rejoindre une école reçoivent désormais leur modèle dans l’item de présentation ; formation et éditeur du catalogue transportent également tous leurs paramètres dans cet item. Fermer Équipe sans changement de ses propres droits ne recharge plus le compte. Fermer les réglages sans changement ne recharge plus l’école. L’onglet actif appartient à la racine et survit à une relecture des accès ; seul un changement volontaire de destination ou la déconnexion le remplace. Les rafraîchissements du dossier conservent les sélections. IPA 0.7.0/build25, source `0676b8318a56cfaf981d6a84c35f3fa532532423`, [run36058166375 réussi](https://github.com/tomyrms/Drivy/actions/runs/36058166375), SHA-256 du téléchargement vérifié : `b580c875b748a937de7e59ea3770183c9746ebe11502957c41abb9c6617e59b8`. La première ouverture et le maintien de l’onglet restent à confirmer sur appareil ; la compilation ne remplace pas cette observation.

**API001–009 déployée** : le serveur expose les autorisations de capture, lots chiffrés, arrêt, finalisation, relecture privée et AP161–164. Les observations temporelles existent sans GPS et sont rattachées au brouillon lors du constat, sans publication implicite ; une ancre exige un lot confirmé. Le [transport natif](native-capture-transport.md), le coffre SQLCipher, le collecteur Core Location et la composition scolaire sont compilés dans le build28. Les clés dédiées sont actives sur CT114 ; aucun profil physique n’est déclaré qualifié. L’extension iOS AP190 conserve la capacité disque sur l’appareil (`freeBytes:null`). Le web hébergé reste G1C.

Les [finitions du profil et de la politique de champs](native-profile-design.md), intégrées dans `dbc5037`, sont compilées dans les builds26 et28 : libellés persistants, action principale fixe, validation des champs, relecture de la version réellement publiée et conservation des erreurs de commande.

Le journal web durable reste compilable mais non qualifié/non déployé ; le web hébergé conserve G1C. Aucun mode produit « Drivy Démo » séparé : les données d’exemple empruntent les vrais accès. La capture scolaire partagée, les documents, les packs/cours et l’envoi SMTP externe restent des chantiers nécessaires à l’application complète ; un trajet privé local n’est pas encore lié à une leçon scolaire.

Les paragraphes et tableaux suivants conservent les jalons antérieurs et leurs preuves ; ils ne remplacent pas l’état courant ci-dessus.

**G1C testé et déployé, G1D1 en développement :** invitations API/iOS, outbox d’email chiffrée et acceptation web React/BFF sont implémentées. L’API passe **89 tests** sur PostgreSQL 16.14 et 17.11 (57 précédents + 32 F02), avec SMTP Mailpit réel. Le web passe **19 tests**, **10 contrôles** de connexion locale et la [recette complète de 18 contrôles](recette-entree-web.md) SMTP → vérification d’adresse → identité nouvelle → acceptation explicite → un dossier minimal, sans formation. Le [run serveur/web `36033466605`](https://github.com/tomyrms/Drivy/actions/runs/36033466605) réussit. **API et web sont déployés depuis `6ffc103`**, avec **11 contrôles HTTPS publics réussis** et nettoyage de la sonde. Le transport email externe reste à raccorder. **IPA 0.4.0/build 9 compilé et vérifié** ; les tests natifs `36033239715` réussissent : **97/97 iPhone et 4/4 iPad**, zéro échec/ignoré, après correction de deux erreurs de compilation SwiftUI. [PR2 fusionnée](https://github.com/tomyrms/Drivy/pull/2), [déploiement et preuves](preparation-deploiement-web.md), [couverture complète](couverture-produit.md), [tranche F02](g1c-invitations.md), [web/BFF](../../apps/web/README.md). Les profils administratifs G1D1 sont travaillés dans un worktree séparé.

| Élément | État | Preuve / suite |
|---|---|---|
| Conception V3.17, 556 fichiers | Intégrité vérifiée | Manifeste SHA-256 conservé, contrat OpenAPI 3.11.0 immuable |
| Données et dépôt | Historique neuf, sans migration de données | `tomyrms/Drivy` public ; `tomyrms/Drivy-old` privé |
| Laboratoire G0 | Compilé et testé sur simulateurs | Séance locale, GPS facultatif, observations, historique, bilan local et SQLCipher |
| Accès scolaire G1A | Client et API implémentés | AppAuth/PKCE, écoles et rôles, élèves et formations en lecture |
| Configuration G1B | Client compilé, serveur déployé | Coordonnées, textes adoptés explicitement, préparation et activation ADMIN ; commandes chiffrées avant émission |
| Serveur G1A/G1B/G1C | 89 tests réussis | PostgreSQL 16.14 et 17.11 réels ; typecheck/build et CI réussis |
| Entrée par invitation G1C | API/web déployés ; SMTP externe manquant | 19 tests web, 18 contrôles locaux complets, 11 contrôles HTTPS de connexion |
| Tests Apple G0/G1A/G1B/G1C | iPhone 97/97, iPad 4/4 | Run `36033239715` entièrement réussi ; zéro échec ou test ignoré |
| IPA connecté | 0.4.0/build 9 disponible ; tests natifs réussis | Run `36033239737`, source `7836441`, CRC/hashes/configuration compilée vérifiés |
| Hébergement HTTPS | API, web/BFF, identité et filtrage actifs | Release `6ffc103`, CT114, PostgreSQL UTF8 CT113, Caddy CT109 |
| Première école | DRAFT, ADMIN actif | Compte `luc`, « Luc auto école » ; aucune adoption ou activation faite automatiquement |
| Essais physiques | Installation du premier IPA confirmée ; recette restante | Connexion 0.3.0, VoiceOver, interruptions réseau, GPS et budgets à qualifier |
| G1 complet / G2 connecté | À poursuivre | SMTP externe, profils/onboarding, formations administrées, planning, leçons et bilans partagés |
| G3/G4 et pilote G5 | À réaliser | Cours/packs, web de gestion, exploitation et procédures |

### G1D1 en développement isolé

La [PR3 en brouillon](https://github.com/tomyrms/Drivy/pull/3), branche `codex/g1d-profils`, contient API et formulaires natifs de politique de champs, profil scolaire et onboarding. Migration004 et AP16/AP169–177 passent **113 tests** sur PostgreSQL17.11 et16.14 ; typecheck/build réussis. Une revue indépendante a corrigé la portée AP169 non-ADMIN et l’encodage d’adresse native sans complément. Les **27 nouveaux tests Swift et une présentation capturée** sont en cours sur [GitHub Apple](https://github.com/tomyrms/Drivy/actions/runs/36037236148), version0.5.0 ; ne pas les déclarer réussis avant le rapport.

Le web G1D1 a passé34 tests et une revue visuelle synthétique, puis son journal de commandes durable a été mis en chantier : PostgreSQL séparé, chiffrement authentifié, droits et confirmation relus après reconnexion. Le harness intégré OIDC/BFF/API réel et le stockage sont en cours. Les installateurs de cette base distincte et du keyring privé sont préparés, **pas appliqués**. Aucun G1D1 n’est déployé ; l’IPA proposé et l’hébergement restent G1C.

### Preuves serveur

Sous Node 24, `npm run typecheck`, `npm test` et `npm run build` réussissent. Les **89 tests** comprennent 13 tests JWT/configuration/curseurs, 21 tests d’intégration G1A, 23 tests d’intégration G1B et 32 tests F02 ; aucun n’est ignoré. La suite passe sur PostgreSQL 17.11 et 16.14, version hébergée. Le [run `36033466605`](https://github.com/tomyrms/Drivy/actions/runs/36033466605) confirme tests serveur/web, builds et intégrité documentaire.

G1A couvre les six lectures du contrat, les dates et curseurs, affectations moniteur, accès à soi, multi-rôles, révocation avec JWT valide et séparation scolaire sous `drivy_app`. Six réponses PostgreSQL réelles servent de fixtures aux tests Swift.

G1B couvre coordonnées, progression, readiness, adoption versionnée des textes, activation et preuve AP72. Les tests vérifient atomicité effet/preuve/audit, idempotence concurrente, versions obsolètes, refus d'activation prématurée, révocation pendant l'attente, rollback sur échec d'audit et séparation des écoles. L'extension `data-policy` possède son propre schéma machine, sans modifier le canon. La migration 002 a également été éprouvée après 001 et deux écoles existantes sous un propriétaire NOSUPERUSER/NOBYPASSRLS/NOCREATEDB/NOCREATEROLE. Voir [G1B](g1b-school-setup.md) et [le guide API](../../apps/api/README.md).

### Hébergement et identité

La release API/web **`6ffc1036890ccc3d8232f5f8b90be4d77f6db195`** tourne sous Node 24.21.0 dans `/opt/drivy-refonte` sur CT114. Une sauvegarde privée vérifiée de la seule base `drivy_refonte` a précédé la migration 003. Les processus API et web utilisent les dossiers de cette release ; identité et filtrage sont actifs. Le Caddyfile complet a été validé avant le rechargement du snippet refonte. L’ancienne API sur 3000 et les anciennes bases sont conservées.

Les bases `drivy_refonte` et `drivy_identity` sont neuves, UTF8, avec rôles distincts non superutilisateurs. La vraie connexion runtime vérifie les privilèges, le certificat TLS/hostname PostgreSQL, `SET LOCAL ROLE drivy_app` et l'absence de personne visible sans contexte. Les quinze tables métier ont ENABLE/FORCE RLS. Les adaptations LXC et les bases de bootstrap SQL_ASCII conservées sont expliquées dans [le déploiement](deploiement-refonte.md).

L'API répond sous `https://drivy.shulker.ch/refonte`, Keycloak 26.7.4 sous `https://drivy.shulker.ch/identity/realms/drivy`. Discovery et JWKS répondent 200 ; les lectures protégées sans jeton répondent 401/no-store. Les chemins admin, master, health et metrics publics répondent 404 ; les ports 3001/3002/8081 refusent les connexions LAN hors proxy. Les accès sensibles sont exclus des journaux Caddy.

Le [contrôle OIDC HTTPS](controle-oidc-deploye.md) a réussi avec une sonde indépendante : PKCE S256 obligatoire, code/jetons/signatures/nonce vérifiés, identité sans lien métier refusée (403), ID token refusé comme accès API (401), renouvellement puis rejeu refusé (400). Sonde, sessions et credentials ont été supprimés, puis l'absence du compte vérifiée. La [preuve datée](proofs/oidc-https-2026-09-24.json) ne contient aucun secret. Le banc OIDC local compte également 29 contrôles réussis et le provisionnement 8 tests réussis.

Le compte initial `luc` et « Luc auto école » proviennent du provisionnement contrôlé, sans élève ni formation. `luc@example.com` est le contact d'essai autorisé par le porteur ; aucun email n'a été envoyé. Un navigateur éphémère a vérifié la connexion et le formulaire obligatoire de changement de mot de passe, sans soumettre un nouveau mot de passe. Le fichier d'accès initial est privé sur le PC ; il n'est jamais inclus dans Git ou les artefacts CI.

La [preuve du déploiement G1B](proofs/g1b-deployment-2026-09-24.json) confirme une école DRAFT, un ADMIN actif, un setup initial et une politique vide non approuvée. Aucune commande, aucun élève ni formation n'a été créé par ce contrôle. Adoption et activation restent des gestes explicites de l'administrateur.

Le client OIDC public `drivy-apple` a reçu le scope `email` le 24 septembre pour préparer F02 : scopes `basic/email/profile`, callback exact et PKCE S256 relus et inchangés. Une requête d’autorisation HTTPS avec `openid profile email` retourne le formulaire 200 sans soumettre d’identifiants. Le portail web a ensuite été déployé avec son propre client confidentiel. Sa recette HTTPS compte 11 contrôles réussis, sans utiliser `luc` ; la sonde a été supprimée et son absence relue. Ce contrôle ne qualifie pas la connexion Apple physique ou le SMTP externe.

### IPA et preuves Apple

Le [run IPA G1C `36033239737`](https://github.com/tomyrms/Drivy/actions/runs/36033239737) produit **0.4.0/build 9**, source `7836441a2e1a2f62071f28fdcadb8239a2780efb`, SHA-256 `bad253440bd97bca2a2a5fa4051832d1a5c13e2ef38dc7523adfc751e6faf1e1`. CRC ZIP, manifeste, hashes des deux binaires et configuration HTTPS ont été vérifiés après téléchargement ; aucun bundle signé. Le [run natif `36033239715`](https://github.com/tomyrms/Drivy/actions/runs/36033239715) réussit : **97/97 tests sur iPhone 17 Pro et 4/4 sur iPad Pro 13 pouces (M5), simulateurs iOS 26.4.1**, zéro échec/ignoré. Les 27 nouveaux tests Swift et le nouveau test de présentation G1C passent. Les huit captures F02 iPhone/iPad (clair, sombre, grand texte, demande incertaine) sont relues sans défaut visuel bloquant ; [preuve native](proofs/g1c-native-2026-09-24.json). Le champ descriptif `scope` de son manifest mentionne encore G1B ; la source et les versions ci-dessus identifient le contenu G1C. Les précédentes preuves G1B sont conservées ci-dessous pour la traçabilité. Les essais physiques restent distincts.

Le [run IPA `36024174745`](https://github.com/tomyrms/Drivy/actions/runs/36024174745) produit **Drivy 0.3.0/build 5**, minimum iOS/iPadOS 26.0, bundle `ch.drivy.qualification`, source `c3e5e6733282a77be779f1c99661f0831c74c5d8`. Xcode 26.6 (17F113), SDK iPhoneOS 26.5. Les deux binaires sont arm64 appareil et les quatre bundles non signés. SHA-256 : `8d7ecee21aaa72e29e3f6c9b3fb1ca7e9ba8bc4f6ee1601c4314790cb8e0405f`. Après téléchargement, CRC ZIP, hashes du manifeste et des binaires, ainsi que les trois paramètres HTTPS dans Info.plist ont été vérifiés ; `schoolConnectionConfigured=true`.

Le workflow d'essai produit cet IPA indépendamment des tests. Le [run natif G1B `36024174590`](https://github.com/tomyrms/Drivy/actions/runs/36024174590) est entièrement réussi : **69/69 tests iPhone** (66 Swift Testing, deux tests de présentation XCTest et un parcours G0), **3/3 tests iPad**, sans échec ni test ignoré. Les sept tests de stockage des commandes passent individuellement avec le vrai Keychain, chiffrement, barrière de fichier et synchronisation de dossier sur simulateur. Les rapports et captures ont été téléchargés et relus : configuration G1B claire lisible, état non approuvé explicite, contraste de sélection iPad rétabli et navigation G0 visible sous son bandeau. La capture G1B ne qualifie pas encore son apparence sombre sur appareil. Le précédent [run G1A `36020145724`](https://github.com/tomyrms/Drivy/actions/runs/36020145724) avait réussi 43/43 tests iPhone et 2/2 iPad, dont historique et bilan après relance. G1B corrige aussi le contraste de la ligne sélectionnée iPad et le bandeau de retour des essais qui masquait la navigation.

Les rapports G0 joignent un avertissement UIKit sur l'insertion de `UIKitToolbar` dans un `UIHostingController`. Aucun test n'échoue et la navigation reste visible sur les captures ; cet avertissement reste à surveiller dans la recette physique. Les simulateurs étant configurés en anglais, les dates et le nom localisé du fuseau suivent cette locale ; les libellés applicatifs sont français.

Les [commandes scolaires](commandes-ios.md) sont chiffrées et persistées avant chaque émission. Une demande incertaine conserve son UUID, son contenu exact et sa version à travers les relances ; une preuve AP72 peut confirmer le résultat sans renvoi. Un refus lors d'une reprise ne suffit pas à effacer la demande. Les tests de recréation et d'erreur de stockage ne constituent pas des essais physiques de perte d'alimentation.

Le porteur a confirmé l'installation et l'ouverture du premier IPA 0.1.0/build 1 (`ebdb6ca`, run `36013615026`), tout en signalant son faible contenu. Cela ne valide pas encore la connexion AppAuth ni la configuration de 0.3.0 sur appareil. La [recette scolaire](recette-g1b.md) et la [recette G0](recette-g0.md) restent à exécuter sur les appareils concernés.

### Limites de qualification et suite

Le laboratoire G0 n'est pas une capture scolaire ni un bilan partagé. Le produit complet conserve invitations, onboarding, administration des formations, agenda, leçons, bilans publiés, cours collectifs, packs et web de gestion dans son périmètre. Aucun service d'envoi d'emails utilisable n'a été établi par la documentation de l'ancien hébergement ; il reste à raccorder pour les invitations.

Les 434 scénarios métier et 68 scénarios mobiles ne changent pas de statut par simple création de code ou de workflows. G0 complet reste **NOT_QUALIFIED** : tests physiques GPS, autonomie, VoiceOver et budgets à mesurer. Aucune conformité juridique, disponibilité ou performance n'est déduite des tests automatisés.

### Progression des compétences (essai terrain du 30 septembre 2026)

Écrit, non exécuté : la migration `020_admin_progress_read.sql` (progression lisible en lecture seule par l'administration de l'école, bilans et brouillons inchangés), le rappel du niveau actuel de chaque compétence dans le bilan d'une nouvelle leçon (sans l'écrire dans ce bilan), et la relecture de la formation à chaque affichage. Les tests PostgreSQL (`lesson-reports.integration.test.ts`) et Swift (`SchoolLessonFinishTests`, `SchoolLessonHubTests`) tournent dans la CI « Refonte · vérifications ». À revérifier sur l'iPhone après déploiement (sauvegarde de la base d'abord) : enchaîner deux leçons, puis ouvrir la progression en moniteur, en élève et en administrateur.
