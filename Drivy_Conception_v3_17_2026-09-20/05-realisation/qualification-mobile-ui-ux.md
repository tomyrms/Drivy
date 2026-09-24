# Qualification mobile et UI/UX

> Référence 3.13 · [Index](../README.md). **68 scénarios complémentaires spécifiés, aucun exécuté.** Ils ne sont pas ajoutés aux 434 scénarios métier T comme si une nouvelle fonctionnalité avait été livrée.

## Qualification du signalement avant tout usage routier

Comparer repère temporel, choix rapide thème/statut et relecture différée. D’abord tâches sur prototype hors véhicule, puis véhicule stationné moteur coupé avec le moniteur à sa place réelle ; enfin observation passive d’une leçon sans demander d’utiliser l’app. Mesurer erreurs de thème/statut, moments perdus, confusion entre sauvegarde/publication, annulations, charge de relecture et visibilité de Signaler/Arrêter sur la plus petite fenêtre. Tester texte agrandi, contraste renforcé et mouvement réduit.

Aucun seuil NHTSA visant le conducteur n’est transposé comme norme du moniteur ni comme autorisation d’usage. Les seuils et effectifs proposés par Claude restent hypothèses à approuver avec un protocole approprié. Une tâche réussie en véhicule stationné ne qualifie pas une leçon en mouvement. Pas d’essai de saisie sur route publique avec un élève dans ce dossier. Sans preuve adaptée, le statut de sûreté reste `NOT_QUALIFIED` (DM07).

## Références et autorité

Le [registre structuré](../annexes/qualification-mobile-v3-12.json) porte MX01–MX16 et MOB001–MOB068 ; les sections ci-dessous en sont la lecture développée. Les références F/E relient chaque cas au produit existant. AS01–AS10 désignent les exigences de la [charte anti-slop](../02-experience/qualite-ui-ux-anti-slop.md), pas une certification.

## Matrice matérielle avant déclarer un support

Pour le pilote Apple : iPhone et iPad sur 26 et 27, version exacte et modèle consignés, au moins un appareil aux ressources plus limitées parmi ceux visés, tablette qualifiable pour le GNSS et tablette sans GNSS pour le parcours de refus. Aucun modèle précis n’est présenté comme acheté ou disponible. Simulateurs utiles aux layouts, mais insuffisants pour valider une collecte réelle, batterie, comportement verrouillé ou autorisations de fond.

Pour Android : prototype natif GA0 avant sa réalisation complète ; avant diffusion, téléphone et tablette avec appareils de constructeurs distincts, version minimale retenue et versions récentes visées. Tester gestes/boutons de navigation, restrictions de fond et binaire release. Les cellules de [matrice](../annexes/matrice-build-mobile-v3-4.json) restent NOT_QUALIFIED tant que les preuves manquent.

Pour le web : clavier seul, zoom/reflow, lecteur d’écran et tailles de fenêtre ; mêmes états métier mais pas promesse de collecte native. Un screenshot du lecteur HTML de ce dossier n’est aucune de ces preuves.

## Protocole UX proposé

Recruter un petit groupe diversifié de moniteurs, responsables et élèves volontaires pour une première itération, par exemple 5 à 8 personnes selon accès et rôles. Ce nombre est un choix pratique proposé, pas une garantie de saturation ou une loi statistique. Utiliser des dossiers fictifs et mener les interactions à l’arrêt. Ne pas demander à un conducteur de manipuler l’app pour réussir un test.

Tâches : préparer la bonne leçon, choisir sans GPS, démarrer/arrêter une capture, expliquer qui voit le replay, s’inscrire à une sensibilisation multi-dates, reprendre le profil et expliquer les conséquences de l’archivage. Noter erreurs, demandes d’aide, hésitations, termes incompris, résultat effectif et perception du partage. La réussite n’est pas le pourcentage acceptant la collecte GPS.

Avant un test, écrire ce qu’est le succès et les données attendues. Après correction, rejouer les mêmes cas difficiles ; ne pas comparer des parcours différents pour annoncer un gain. La préparation ne vaut pas enquête menée.

## Budgets initiaux à mesurer, pas résultats

Hypothèses G0 proposées : première réponse visuelle à une commande locale en moins de 100 ms au p95 sur appareil cible ; absence de longue tâche UI bloquante supérieure à 200 ms sur les actions d’arrêt/reprise ; replay de référence de 10 000 points puis essai de stress plus long selon limite du produit. Ces valeurs servent à déclencher une analyse, pas une promesse de SLA ni une norme Apple.

Distinguer réactivité du bouton, persistance locale, confirmation serveur et vitesse de réception du premier point. Mesurer mémoire, écritures disque, température et énergie pendant une séance contrôlée, en indiquant écran/réseau/luminosité et état batterie. Aucun budget universel de pourcentage batterie n’est fixé sans appareil et protocole. Ne jamais inventer une géométrie pour rendre l’animation fluide.

## Priorité des blocages

Un défaut de confidentialité, une fausse inscription, une capture qui ne s’arrête pas ou un accès impossible à l’action essentielle bloque la diffusion. Une incompatibilité de build bloque la plateforme concernée. Une dérive visuelle cosmétique peut être différée si elle ne masque pas l’état ni le focus. La qualité n’est pas une note moyenne où une belle animation compense une fuite.

G0 Apple : profil Swift natif, outillage, prototype iPhone/iPad, contrats portables et accessibilité des premiers patterns. GA0 : premier prototype natif Android quand ses ressources sont engagées. G1 : auth, liens, import et onboarding. G2 : collecte/replay et cycle local, rendu tablette. G3 : cours/notifications et confirmation inter-clients. G4 : gestion/statistiques et séparation des droits. G5 : release, données, migrations et mesures. La suppression globale doit être contractualisée **avant publication publique store**, indépendamment du nombre de tranches terminées. Android possède ses jalons GA0 et de lancement ; G0 Apple prépare les contrats sans imposer sa compilation.


**Pile Apple confirmée : Swift natif.** Swift Testing est proposé pour les tests unitaires/intégration ; XCTest pour UI et mesures [S102](../06-gouvernance/sources.md#s102). Les cas Android s’exécutent avec le client futur, pas comme prérequis implicite au build Apple. MOB041–MOB052 complètent la revue de concurrence, contrat et distribution native.

## Exigences d’intégration

<a id="mx01"></a>
### MX01 · Support documenté par OS et binaire

Référence : [Support documenté par OS et binaire](../04-technique/integration-ios-ipados.md). Premier jalon : **G0**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S63](../06-gouvernance/sources.md#s63), [S64](../06-gouvernance/sources.md#s64), [S88](../06-gouvernance/sources.md#s88).

<a id="mx02"></a>
### MX02 · Matériaux et composants adaptés sans fausse intégration native

Référence : [Matériaux et composants adaptés sans fausse intégration native](../02-experience/patterns-mobile-parcours.md). Premier jalon : **G0**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S65](../06-gouvernance/sources.md#s65), [S97](../06-gouvernance/sources.md#s97).

<a id="mx03"></a>
### MX03 · Fenêtres, clavier et accessibilité indépendants du modèle d’appareil

Référence : [Fenêtres, clavier et accessibilité indépendants du modèle d’appareil](../02-experience/plateformes-tablette-web.md). Premier jalon : **G2**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S68](../06-gouvernance/sources.md#s68), [S97](../06-gouvernance/sources.md#s97), [S84](../06-gouvernance/sources.md#s84).

<a id="mx04"></a>
### MX04 · Capture facultative et trois niveaux d’autorisation distincts

Référence : [Capture facultative et trois niveaux d’autorisation distincts](../03-fonctionnel/gps-replay.md). Premier jalon : **G2**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S73](../06-gouvernance/sources.md#s73), [S99](../06-gouvernance/sources.md#s99).

<a id="mx05"></a>
### MX05 · Collecteur durable, arrêt local et limites temporelles

Référence : [Collecteur durable, arrêt local et limites temporelles](../04-technique/integration-mobile-transverse.md). Premier jalon : **G2**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S73](../06-gouvernance/sources.md#s73), [S99](../06-gouvernance/sources.md#s99), [S100](../06-gouvernance/sources.md#s100).

<a id="mx06"></a>
### MX06 · Authentification système et liens relus sous droits courants

Référence : [Authentification système et liens relus sous droits courants](../04-technique/integration-mobile-transverse.md). Premier jalon : **G1**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S77](../06-gouvernance/sources.md#s77), [S78](../06-gouvernance/sources.md#s78), [S79](../06-gouvernance/sources.md#s79).

<a id="mx07"></a>
### MX07 · Stockage, secrets, sauvegarde et purge traités ensemble

Référence : [Stockage, secrets, sauvegarde et purge traités ensemble](../04-technique/integration-mobile-transverse.md). Premier jalon : **G2**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S100](../06-gouvernance/sources.md#s100), [S104](../06-gouvernance/sources.md#s104), [S90](../06-gouvernance/sources.md#s90).

<a id="mx08"></a>
### MX08 · Notifications facultatives sans effet métier caché

Référence : [Notifications facultatives sans effet métier caché](../03-fonctionnel/calendrier-notifications.md). Premier jalon : **G3**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S105](../06-gouvernance/sources.md#s105), [S83](../06-gouvernance/sources.md#s83).

<a id="mx09"></a>
### MX09 · Import de fichiers explicite et permissions minimales

Référence : [Import de fichiers explicite et permissions minimales](../04-technique/integration-mobile-transverse.md). Premier jalon : **G1**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S93](../06-gouvernance/sources.md#s93), [S94](../06-gouvernance/sources.md#s94).

<a id="mx10"></a>
### MX10 · Même sémantique de confirmation sur tous les clients

Référence : [Même sémantique de confirmation sur tous les clients](../04-technique/synchronisation.md). Premier jalon : **G3**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S67](../06-gouvernance/sources.md#s67).

<a id="mx11"></a>
### MX11 · Profil Android de localisation et FGS déclaré et éprouvé

Référence : [Profil Android de localisation et FGS déclaré et éprouvé](../04-technique/preparation-android.md). Premier jalon : **ANDROID_LAUNCH**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S81](../06-gouvernance/sources.md#s81), [S82](../06-gouvernance/sources.md#s82), [S83](../06-gouvernance/sources.md#s83).

<a id="mx12"></a>
### MX12 · Adaptation Android et compatibilité du binaire natif

Référence : [Adaptation Android et compatibilité du binaire natif](../04-technique/preparation-android.md). Premier jalon : **ANDROID_LAUNCH**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S84](../06-gouvernance/sources.md#s84), [S85](../06-gouvernance/sources.md#s85), [S86](../06-gouvernance/sources.md#s86), [S87](../06-gouvernance/sources.md#s87).

<a id="mx13"></a>
### MX13 · Binaire natif et migrations sans interruption volontaire de capture

Référence : [Binaire natif et migrations sans interruption volontaire de capture](../04-technique/integration-mobile-transverse.md). Premier jalon : **G5**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S97](../06-gouvernance/sources.md#s97).

<a id="mx14"></a>
### MX14 · Déclarations et suppression globale avant publication store

Référence : [Déclarations et suppression globale avant publication store](../04-technique/integration-mobile-transverse.md#cloture-compte). Premier jalon : **BEFORE_PUBLIC_STORE**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S91](../06-gouvernance/sources.md#s91), [S92](../06-gouvernance/sources.md#s92), [S93](../06-gouvernance/sources.md#s93), [S95](../06-gouvernance/sources.md#s95).

<a id="mx15"></a>
### MX15 · Contenu et interactions revus sans production générique non vérifiée

Référence : [Contenu et interactions revus sans production générique non vérifiée](../02-experience/qualite-ui-ux-anti-slop.md). Premier jalon : **G2**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S69](../06-gouvernance/sources.md#s69), [S67](../06-gouvernance/sources.md#s67).

<a id="mx16"></a>
### MX16 · Mesures sur appareils et observations UX, preuves séparées

Référence : [Mesures sur appareils et observations UX, preuves séparées](../05-realisation/qualification-mobile-ui-ux.md). Premier jalon : **G5**. Statut documentaire : DESIGN_REQUIREMENT. Sources : [S68](../06-gouvernance/sources.md#s68), [S90](../06-gouvernance/sources.md#s90).

## Catalogue des essais à réaliser

Les identifiants MOB001–MOB040 sont conservés ; les cas techniques devenus inadaptés sont révisés. Les douze cas Swift introduits en V3.4 et les huit cas mobiles V3.7 restent distincts du registre des scénarios métier T.

<a id="mob001"></a>
### MOB001 · Matrice iOS 26/27 reproductible

**Plateformes :** IOS, IPADOS. **Exigences :** [MX01](#mx01). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F21](../03-fonctionnel/onboarding.md#f21). **Écrans :** [E44](../02-experience/ecrans.md#e44).

**Préconditions :** Projet Swift, versions Xcode/macOS/SwiftPM, modèles et commit identifiés.

**Procédure :** Construire le binaire Apple signé ; installer sur chaque cellule iOS/iPadOS 26/27 prévue ; vérifier les versions réellement embarquées.

**Résultat attendu :** Preuve par cellule, aucune ligne marquée supportée sans exécution ; dépendance incompatible bloque cette cellule.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob002"></a>
### MOB002 · Liquid Glass et repli accessible

**Plateformes :** IOS, IPADOS. **Exigences :** [MX02](#mx02). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F16](../03-fonctionnel/gps-replay.md#f16). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E24](../02-experience/ecrans.md#e24).

**Préconditions :** Même scène de carte avec texte et commandes, binaire qualifiable.

**Procédure :** Comparer 26/27, thème clair/sombre, réduction de transparence et des animations, API de verre disponible puis indisponible.

**Résultat attendu :** Même sens et mêmes actions ; surfaces lisibles ; pas de fonction désactivée du seul fait du repli opaque.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob003"></a>
### MOB003 · VoiceOver et grand texte

**Plateformes :** IOS, IPADOS. **Exigences :** [MX03](#mx03). **Fonctions :** [F16](../03-fonctionnel/gps-replay.md#f16), [F18](../03-fonctionnel/cours-collectifs.md#f18), [F20](../03-fonctionnel/onboarding.md#f20). **Écrans :** [E24](../02-experience/ecrans.md#e24), [E26](../02-experience/ecrans.md#e26), [E40](../02-experience/ecrans.md#e40).

**Préconditions :** Données fictives avec noms longs, plusieurs dates et observations.

**Procédure :** Activer VoiceOver et une grande taille de texte ; parcourir fiche cours, formulaire et replay sans exploiter la carte tactile.

**Résultat attendu :** Labels/états et ordre compréhensibles ; alternative aux gestes complexes ; erreurs annoncées sans répétition permanente.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob004"></a>
### MOB004 · Fenêtre iPad et clavier pendant collecte

**Plateformes :** IPADOS. **Exigences :** [MX03](#mx03), [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F21](../03-fonctionnel/onboarding.md#f21). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E44](../02-experience/ecrans.md#e44).

**Préconditions :** Une capture autorisée active, clavier matériel connecté.

**Procédure :** Tourner, réduire/agrandir la fenêtre, ouvrir/fermer un panneau, utiliser Tab/Échap et revenir à la leçon.

**Résultat attendu :** Un seul collecteur ; arrêt accessible ; focus logique ; aucun reset du trajet, de la sélection ni du brouillon.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob005"></a>
### MOB005 · Refus de GPS sans exclusion du produit

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX04](#mx04). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F20](../03-fonctionnel/onboarding.md#f20). **Écrans :** [E22](../02-experience/ecrans.md#e22), [E42](../02-experience/ecrans.md#e42).

**Préconditions :** Leçon valide avec élève n’acceptant pas l’enregistrement.

**Procédure :** Refuser le choix métier puis refuser la permission OS dans un autre scénario ; réaliser la séance et son bilan sans GPS.

**Résultat attendu :** Pas de point collecté ni prompt en boucle ; cours, agenda, bilan et packs restent utilisables selon droits.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob006"></a>
### MOB006 · Profil iOS réel de permission de fond

**Plateformes :** IOS, IPADOS. **Exigences :** [MX04](#mx04), [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F21](../03-fonctionnel/onboarding.md#f21). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E44](../02-experience/ecrans.md#e44).

**Préconditions :** Profil Core Location natif déclaré, Info.plist, sessions et messages inspectés.

**Procédure :** Tester chacun des droits effectivement requis, notamment autorisation provisoire et précision réduite ; verrouiller puis rouvrir.

**Résultat attendu :** Profil whenInUse et session de fond qualifiés séparément de la permission métier ; aucun Always demandé par défaut ni capacité annoncée sans essai ; refus explicite si une condition manque.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob007"></a>
### MOB007 · Terminaison système et fermeture forcée

**Plateformes :** IOS, IPADOS. **Exigences :** [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E17](../02-experience/ecrans.md#e17).

**Préconditions :** Capture active avec points persistés et état de transport connu.

**Procédure :** Simuler terminaison système autorisée par le protocole de test, puis fermeture forcée utilisateur séparément ; relancer l’app.

**Résultat attendu :** Cas distingués ; état réconcilié ; pas de trou inventé ni auto-relance promise contre le choix utilisateur.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob008"></a>
### MOB008 · Clé et fichier accessibles sous verrouillage

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX05](#mx05), [MX07](#mx07). **Fonctions :** [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12), [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E17](../02-experience/ecrans.md#e17).

**Préconditions :** Build chiffré avec classes de protection documentées et file test.

**Procédure :** Verrouiller pendant écriture de points puis vérifier base, WAL/journal, erreur de clé et redémarrage.

**Résultat attendu :** Pas de point déclaré conservé avant écriture ; aucune copie de secours en clair ; erreur expliquée et données restantes identifiées.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob009"></a>
### MOB009 · Horloge changée et budget expiré

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E23](../02-experience/ecrans.md#e23).

**Préconditions :** Autorisation bornée et référence de temps connue.

**Procédure :** Changer heure/fuseau local, suspendre puis rouvrir après expiration ; essayer d’envoyer des points hors bornes.

**Résultat attendu :** Pas de prolongation via horloge ni reboot ; collecteur arrêté ou reprise refusée selon état réel ; serveur rejette hors bornes.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob010"></a>
### MOB010 · Deux appareils pour la même leçon

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX04](#mx04), [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F21](../03-fonctionnel/onboarding.md#f21). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E44](../02-experience/ecrans.md#e44).

**Préconditions :** Même compte autorisé ouvert sur téléphone et tablette.

**Procédure :** Démarrer sur A puis tenter sur B ; revenir sur A après ouverture de la carte B.

**Résultat attendu :** Pas de deuxième capture active ; B ne présente pas un état live non observé ; aucune reprise implicite du droit.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob011"></a>
### MOB011 · Pas de réseau et carte indisponible

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F16](../03-fonctionnel/gps-replay.md#f16). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E24](../02-experience/ecrans.md#e24).

**Préconditions :** Départ préautorisé ; données test avec source GNSS réelle.

**Procédure :** Couper réseau ; provoquer une erreur de carte ; continuer puis reconnecter. Tester séparément départ entièrement hors ligne.

**Résultat attendu :** Capture autorisée indépendante du rendu ; absence de fond de carte expliquée ; pas de nouvelle autorisation hors ligne ; transfert sans doublon.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob012"></a>
### MOB012 · Arrêt local avec callbacks tardifs

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E23](../02-experience/ecrans.md#e23).

**Préconditions :** Collecte active sans réseau, mécanisme de callbacks contrôlable.

**Procédure :** Presser Arrêter, puis injecter/observer callbacks retardés ; reconnecter avec jeton d’envoi expiré puis réauthentifié.

**Résultat attendu :** Source coupée sans réseau ; aucune extension de capture ; manifeste et reprise conformes aux droits actuels.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob013"></a>
### MOB013 · Replay partiel, publication et retrait

**Plateformes :** IOS, IPADOS, ANDROID, WEB. **Exigences :** [MX05](#mx05), [MX10](#mx10). **Fonctions :** [F16](../03-fonctionnel/gps-replay.md#f16), [F08](../03-fonctionnel/bilans-documents.md#f08), [F14](../03-fonctionnel/hors-ligne-vie-privee.md#f14). **Écrans :** [E24](../02-experience/ecrans.md#e24), [E09](../02-experience/ecrans.md#e09).

**Préconditions :** Bilan fictif publié puis arrivée tardive de points et retrait autorisé.

**Procédure :** Lire depuis chaque client, parcourir plusieurs pages puis appliquer un retrait ; rouvrir et vérifier caches/miniatures.

**Résultat attendu :** Snapshot ancien inchangé ; trous visibles ; après retrait appris, aucune géométrie/observation/cursor de données retirées exposée.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob014"></a>
### MOB014 · Lien de cours à froid et repli web

**Plateformes :** IOS, IPADOS, ANDROID, WEB. **Exigences :** [MX06](#mx06). **Fonctions :** [F01](../03-fonctionnel/identites-formations.md#f01), [F18](../03-fonctionnel/cours-collectifs.md#f18), [F19](../03-fonctionnel/calendrier-notifications.md#f19). **Écrans :** [E26](../02-experience/ecrans.md#e26), [E02](../02-experience/ecrans.md#e02).

**Préconditions :** Domaines de test associés au binaire et compte élève valide.

**Procédure :** Ouvrir lien app absente, app fermée, app ouverte ; terminer auth si nécessaire.

**Résultat attendu :** Même fiche accessible après droits ; app absente renvoie au web ; aucune ouverture ou installation n’inscrit automatiquement.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob015"></a>
### MOB015 · OIDC et lien dans la mauvaise école

**Plateformes :** IOS, IPADOS, ANDROID, WEB. **Exigences :** [MX06](#mx06). **Fonctions :** [F01](../03-fonctionnel/identites-formations.md#f01), [F02](../03-fonctionnel/identites-formations.md#f02). **Écrans :** [E01](../02-experience/ecrans.md#e01), [E02](../02-experience/ecrans.md#e02).

**Préconditions :** Deux comptes et deux écoles sans accès croisé, redirect de test.

**Procédure :** Ouvrir lien sous mauvais compte ; essayer state/nonce/redirect altéré et lien expiré.

**Résultat attendu :** Refus sans fuite ; switch explicite puis nouvelle vérification ; pas de WebView collectant mot de passe ni de redirect libre.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob016"></a>
### MOB016 · Réinstallation et secrets résiduels

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX07](#mx07). **Fonctions :** [F01](../03-fonctionnel/identites-formations.md#f01), [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12). **Écrans :** [E01](../02-experience/ecrans.md#e01), [E17](../02-experience/ecrans.md#e17).

**Préconditions :** Cache/credentials de test et état serveur révoqué.

**Procédure :** Désinstaller puis réinstaller ; changer biométrie dans scénario séparé ; essayer de réutiliser la session précédente.

**Résultat attendu :** Revalidation serveur ; pas de compte actif par simple secret résiduel ; perte de clé expliquée sans export de données interdites.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob017"></a>
### MOB017 · Sauvegarde restaurée sans clé

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX07](#mx07). **Fonctions :** [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12), [F14](../03-fonctionnel/hors-ligne-vie-privee.md#f14). **Écrans :** [E17](../02-experience/ecrans.md#e17), [E18](../02-experience/ecrans.md#e18).

**Préconditions :** Sauvegarde de test conforme au périmètre choisi.

**Procédure :** Inspecter exclusions cloud/device-transfer ; restaurer une sauvegarde ou base sans clé.

**Résultat attendu :** Secrets et traces non exportés par inadvertance ; aucune restauration en clair ; caches reconstitués seulement sous droits actuels.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob018"></a>
### MOB018 · Refus des notifications ordinaires

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX08](#mx08). **Fonctions :** [F19](../03-fonctionnel/calendrier-notifications.md#f19), [F20](../03-fonctionnel/onboarding.md#f20). **Écrans :** [E32](../02-experience/ecrans.md#e32), [E42](../02-experience/ecrans.md#e42).

**Préconditions :** Élève sans droit push mais membre actif.

**Procédure :** Refuser permission puis consulter calendrier/cours et s’inscrire explicitement.

**Résultat attendu :** Centre in-app et inscription restent accessibles ; aucun consentement GPS inféré de ce refus.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob019"></a>
### MOB019 · Push dupliqué, ancien ou objet inaccessible

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX08](#mx08), [MX06](#mx06). **Fonctions :** [F19](../03-fonctionnel/calendrier-notifications.md#f19), [F18](../03-fonctionnel/cours-collectifs.md#f18). **Écrans :** [E32](../02-experience/ecrans.md#e32), [E26](../02-experience/ecrans.md#e26).

**Préconditions :** Notification fictive pour un cours ensuite modifié ou inaccessible.

**Procédure :** Recevoir deux fois, ouvrir tard, puis sous permissions révoquées.

**Résultat attendu :** Pas de double inscription ; lecture courante ; contenu verrouillage minimal ; refus ne révèle pas l’objet.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob020"></a>
### MOB020 · Photo facultative et accès fichier expiré

**Plateformes :** IOS, IPADOS, ANDROID, WEB. **Exigences :** [MX09](#mx09). **Fonctions :** [F09](../03-fonctionnel/bilans-documents.md#f09), [F20](../03-fonctionnel/onboarding.md#f20). **Écrans :** [E10](../02-experience/ecrans.md#e10), [E40](../02-experience/ecrans.md#e40).

**Préconditions :** Profil sans photo et document de test issu du sélecteur système.

**Procédure :** Passer la photo ; annuler import ; révoquer accès URI ; essayer fichier invalide puis fichier valide.

**Résultat attendu :** Onboarding possible sans photo ; erreur conservant le contexte ; quarantaine/READY exacts, aucune permission globale inutile.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob021"></a>
### MOB021 · Dernière place depuis deux clients

**Plateformes :** IOS, ANDROID, WEB. **Exigences :** [MX10](#mx10). **Fonctions :** [F18](../03-fonctionnel/cours-collectifs.md#f18), [F17](../03-fonctionnel/catalogue-packs.md#f17). **Écrans :** [E26](../02-experience/ecrans.md#e26).

**Préconditions :** Une place disponible et deux élèves autorisés sur clients distincts.

**Procédure :** Lancer les demandes simultanément, puis vérifier calendrier et droits des deux élèves.

**Résultat attendu :** Une seule place confirmée ; perdant informé sans débit/droit consommé ; aucune coche anticipée.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob022"></a>
### MOB022 · 202 et perte de réponse après commit

**Plateformes :** IOS, IPADOS, ANDROID, WEB. **Exigences :** [MX10](#mx10). **Fonctions :** [F18](../03-fonctionnel/cours-collectifs.md#f18), [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12). **Écrans :** [E26](../02-experience/ecrans.md#e26), [E17](../02-experience/ecrans.md#e17).

**Préconditions :** Mutation identifiable avec réponse retardée et backend de test.

**Procédure :** Déclencher PENDING ou timeout après commit ; fermer écran ; reprendre la même opération.

**Résultat attendu :** Intention conservée, aucune nouvelle commande doublonnante ; résultat définitif explique refus ou confirme une seule inscription.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob023"></a>
### MOB023 · Durée et pack révisés entre appareils

**Plateformes :** IOS, IPADOS, ANDROID, WEB. **Exigences :** [MX10](#mx10). **Fonctions :** [F04](../03-fonctionnel/planning-lecons.md#f04), [F17](../03-fonctionnel/catalogue-packs.md#f17). **Écrans :** [E05](../02-experience/ecrans.md#e05), [E30](../02-experience/ecrans.md#e30).

**Préconditions :** Leçon planifiée, pack et versions connues.

**Procédure :** Modifier 45 vers 90 minutes avec condition commerciale puis provoquer un conflit sur un autre client.

**Résultat attendu :** Mêmes conditions affichées ; refus préserve ancien créneau/droits/compte ; aucun calcul fondé sur durée GPS.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob024"></a>
### MOB024 · Disque plein et brouillon repris

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX07](#mx07), [MX10](#mx10). **Fonctions :** [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12). **Écrans :** [E17](../02-experience/ecrans.md#e17), [E08](../02-experience/ecrans.md#e08).

**Préconditions :** Brouillon autorisé et espace local contrôlable.

**Procédure :** Provoquer écriture refusée ; tenter quitter ; libérer espace puis relancer sous même compte.

**Résultat attendu :** Pas de faux enregistrement ; avertissement exploitable ; seules données persistées sont reprises.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob025"></a>
### MOB025 · FGS Android lancé explicitement

**Plateformes :** ANDROID. **Exigences :** [MX11](#mx11). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F21](../03-fonctionnel/onboarding.md#f21). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E44](../02-experience/ecrans.md#e44).

**Préconditions :** Release Android avec type/permissions manifestés et profil de collecte retenu.

**Procédure :** Lancer depuis préparation visible, passer au fond ; tester un lancement illégitime depuis push séparément.

**Résultat attendu :** Service et indication conformes ; lancement caché refusé ; pas d’autorisation de fond assimilée au consentement métier.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob026"></a>
### MOB026 · Android approximatif ou permission refusée

**Plateformes :** ANDROID. **Exigences :** [MX11](#mx11), [MX04](#mx04). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F20](../03-fonctionnel/onboarding.md#f20). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E42](../02-experience/ecrans.md#e42).

**Préconditions :** App Android autorisée seulement approximativement, puis refus complet.

**Procédure :** Préparer une leçon, examiner qualité possible et continuer sans trace quand insuffisante.

**Résultat attendu :** Aucune observation prétendument précise à partir d’une position vague ; pas de blocage du reste du produit.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob027"></a>
### MOB027 · Notification Android refusée pendant FGS

**Plateformes :** ANDROID. **Exigences :** [MX11](#mx11), [MX08](#mx08). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F19](../03-fonctionnel/calendrier-notifications.md#f19). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E32](../02-experience/ecrans.md#e32).

**Préconditions :** Version Android soumise à POST_NOTIFICATIONS ; FGS légalement démarrable.

**Procédure :** Refuser notifications ordinaires puis démarrer le service avec son indication obligatoire et consulter état système.

**Résultat attendu :** Comportement Android réel documenté ; pas de dépendance artificielle aux annonces push ; arrêt toujours accessible dans l’app.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob028"></a>
### MOB028 · Arrêt Android et constructeurs distincts

**Plateformes :** ANDROID. **Exigences :** [MX11](#mx11), [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E17](../02-experience/ecrans.md#e17).

**Préconditions :** Deux appareils de constructeurs différents avec build release.

**Procédure :** Tester verrouillage/économie d’énergie, terminaison, arrêt utilisateur du service et redémarrage.

**Résultat attendu :** Pas de garantie universelle inventée ; incident et segments conservés correctement ; aucune relance de surveillance cachée.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob029"></a>
### MOB029 · Insets, clavier et retour prédictif

**Plateformes :** ANDROID. **Exigences :** [MX12](#mx12), [MX03](#mx03). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F20](../03-fonctionnel/onboarding.md#f20). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E40](../02-experience/ecrans.md#e40).

**Préconditions :** Android avec navigation gestuelle et clavier logiciel.

**Procédure :** Ouvrir formulaire et carte, afficher clavier, faire retour prédictif et changer fenêtre.

**Résultat attendu :** Aucune commande cachée sous barre/clavier ; retour attendu ; collecte ne s’arrête pas à cause de navigation.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob030"></a>
### MOB030 · Tablette Android et TalkBack

**Plateformes :** ANDROID. **Exigences :** [MX12](#mx12), [MX03](#mx03). **Fonctions :** [F16](../03-fonctionnel/gps-replay.md#f16), [F18](../03-fonctionnel/cours-collectifs.md#f18), [F22](../03-fonctionnel/gestion-web-archivage.md#f22). **Écrans :** [E24](../02-experience/ecrans.md#e24), [E26](../02-experience/ecrans.md#e26), [E34](../02-experience/ecrans.md#e34).

**Préconditions :** Tablette ou appareil adaptable avec TalkBack et grand texte.

**Procédure :** Réduire fenêtre, utiliser liste/détail, parcourir cours et observations sans gestes de carte.

**Résultat attendu :** Sens identique au téléphone, focus cohérent, texte complet, alternative accessible aux seules coordonnées visuelles.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob031"></a>
### MOB031 · Compatibilité pages natives 16 Ko

**Plateformes :** ANDROID. **Exigences :** [MX12](#mx12), [MX01](#mx01). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E17](../02-experience/ecrans.md#e17).

**Préconditions :** AAB/APK release, dépendances natives identifiées.

**Procédure :** Contrôler les bibliothèques natives et exécuter sur environnement/appareil à pages 16 Ko selon procédure officielle.

**Résultat attendu :** Chargement, chiffrement et carte fonctionnent ; rapport lié au binaire Android, pas simple succès d’un test de contrat.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob032"></a>
### MOB032 · Signature, environnements et liens distribués

**Plateformes :** ANDROID, IOS, IPADOS. **Exigences :** [MX01](#mx01), [MX06](#mx06). **Fonctions :** [F01](../03-fonctionnel/identites-formations.md#f01). **Écrans :** [E01](../02-experience/ecrans.md#e01), [E02](../02-experience/ecrans.md#e02).

**Préconditions :** Builds dev et release séparés, certificats/domaines identifiés.

**Procédure :** Installer depuis canal de distribution de test ; vérifier API ciblée, association et login, puis tenter données de production depuis dev.

**Résultat attendu :** Bon environnement ; clés bornées ; association de distribution effective ; aucune confusion dev/prod.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob033"></a>
### MOB033 · Changement de binaire et interruption pendant capture

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX13](#mx13), [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E17](../02-experience/ecrans.md#e17).

**Préconditions :** Capture active, deux binaires de test signés et journal durable inspectable.

**Procédure :** Vérifier qu’aucune relance n’est imposée par l’app ; tester séparément une terminaison/remplacement de processus puis lancer le nouveau binaire.

**Résultat attendu :** Pas d’interruption volontaire pour mise à jour ; après remplacement système, données persistées retrouvées, trou explicite, aucun droit de capture prolongé ni garantie de continuité inventée.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob034"></a>
### MOB034 · Migration locale et downgrade contrôlé

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX13](#mx13), [MX07](#mx07). **Fonctions :** [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12), [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E17](../02-experience/ecrans.md#e17), [E23](../02-experience/ecrans.md#e23).

**Préconditions :** Base chiffrée contenant brouillons/points test, version précédente disponible.

**Procédure :** Mettre à jour le binaire, interrompre la migration, reprendre puis essayer le scénario de downgrade supporté ou son refus.

**Résultat attendu :** Migration atomique, données protégées ; schéma trop récent refusé sans perte ; aucun retour de binaire présumé inverser les données.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob035"></a>
### MOB035 · Audit du binaire et déclarations de données

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX14](#mx14), [MX01](#mx01). **Fonctions :** [F14](../03-fonctionnel/hors-ligne-vie-privee.md#f14), [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E19](../02-experience/ecrans.md#e19), [E42](../02-experience/ecrans.md#e42).

**Préconditions :** Binaire release, SDKs, flux réseau de test et fiches store préparés.

**Procédure :** Comparer permissions générées, manifests, notices et tiers effectivement utilisés ; inspecter logs en refus et en capture.

**Résultat attendu :** Aucune collecte non déclarée, secret/coordonnée en logs ou permission sans finalité ; écart bloque publication.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob036"></a>
### MOB036 · Suppression globale multi-écoles

**Plateformes :** IOS, IPADOS, ANDROID, WEB. **Exigences :** [MX14](#mx14). **Fonctions :** [F01](../03-fonctionnel/identites-formations.md#f01), [F14](../03-fonctionnel/hors-ligne-vie-privee.md#f14). **Écrans :** [E18](../02-experience/ecrans.md#e18), [E19](../02-experience/ecrans.md#e19).

**Préconditions :** Contrat global de clôture à compléter ; personne avec deux écoles puis sans appartenance.

**Procédure :** Demander suppression depuis Compte et web ; tester responsabilités restantes, tokens, accès et confirmation.

**Résultat attendu :** Demande durable hors scope scolaire ; pas simple désactivation ; pas suppression d’autrui ; délais/conservation expliqués et traitement testé.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob037"></a>
### MOB037 · Revue anti-slop des six patterns

**Plateformes :** IOS, IPADOS, ANDROID, WEB. **Exigences :** [MX15](#mx15). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F16](../03-fonctionnel/gps-replay.md#f16), [F18](../03-fonctionnel/cours-collectifs.md#f18), [F20](../03-fonctionnel/onboarding.md#f20). **Écrans :** [E22](../02-experience/ecrans.md#e22), [E24](../02-experience/ecrans.md#e24), [E26](../02-experience/ecrans.md#e26), [E40](../02-experience/ecrans.md#e40).

**Préconditions :** Prototypes puis implémentations avec mêmes jeux fictifs et états réels.

**Procédure :** Passer AS01–AS10, tester chaque action visible, demander source des chiffres et sens des confirmations.

**Résultat attendu :** Aucun faux succès, bouton décoratif ou jugement pédagogique inventé ; écarts documentés sans note moyenne compensant un blocage.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob038"></a>
### MOB038 · Statistiques et textes longs sans remplissage

**Plateformes :** IOS, IPADOS, ANDROID, WEB. **Exigences :** [MX15](#mx15), [MX03](#mx03). **Fonctions :** [F23](../03-fonctionnel/statistiques.md#f23). **Écrans :** [E33](../02-experience/ecrans.md#e33), [E45](../02-experience/ecrans.md#e45).

**Préconditions :** Compte à permissions limitées, données absentes puis valeurs fictives connues.

**Procédure :** Comparer périodes/unités, droits absents, long nom de formation et traductions français/allemand/italien de test.

**Résultat attendu :** Pas de zéros pour données interdites ni de chiffres de démonstration en production ; terminologie et reflow cohérents.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob039"></a>
### MOB039 · Performance, batterie et confidentialité en mesure

**Plateformes :** IOS, IPADOS, ANDROID. **Exigences :** [MX16](#mx16), [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F16](../03-fonctionnel/gps-replay.md#f16). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E24](../02-experience/ecrans.md#e24).

**Préconditions :** Protocole contrôlé 90 minutes proposé, mêmes appareils/températures/configurations notés.

**Procédure :** Mesurer mémoire, stockage, énergie et latence UI avec carte visible puis fond, réseau intermittent et long replay.

**Résultat attendu :** Mesures par modèle/build, aucune promesse sans résultat ; seuils approuvés ; rapport sans traces réelles exposées.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob040"></a>
### MOB040 · Observation UX sur parcours complets

**Plateformes :** IOS, IPADOS, ANDROID, WEB. **Exigences :** [MX16](#mx16), [MX15](#mx15). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F18](../03-fonctionnel/cours-collectifs.md#f18), [F20](../03-fonctionnel/onboarding.md#f20), [F22](../03-fonctionnel/gestion-web-archivage.md#f22). **Écrans :** [E22](../02-experience/ecrans.md#e22), [E26](../02-experience/ecrans.md#e26), [E40](../02-experience/ecrans.md#e40), [E36](../02-experience/ecrans.md#e36).

**Préconditions :** Participants consentants de rôles pertinents, données fictives, scénario sans conduite active.

**Procédure :** Faire préparer/arrêter une capture, comprendre un bilan, s’inscrire à un cours, reprendre onboarding et expliquer un archivage.

**Résultat attendu :** Erreurs/hésitations et compréhension consignées ; petit échantillon non présenté comme preuve statistique ; problèmes critiques corrigés puis retestés.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob041"></a>
### MOB041 · Démarrages concurrents et réentrance Swift

**Plateformes :** IOS, IPADOS. **Exigences :** [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E22](../02-experience/ecrans.md#e22), [E23](../02-experience/ecrans.md#e23).

**Préconditions :** Coordinateur avec source et réseau de test ; génération de session observable.

**Procédure :** Déclencher deux démarrages ; suspendre le premier à un await puis demander arrêt avant son retour.

**Résultat attendu :** Une seule source admise ; réponse tardive rejetée après changement de génération ; aucune transition doublée.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob042"></a>
### MOB042 · Durée de vie du collecteur hors des vues SwiftUI

**Plateformes :** IOS, IPADOS. **Exigences :** [MX03](#mx03), [MX05](#mx05). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F21](../03-fonctionnel/onboarding.md#f21). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E44](../02-experience/ecrans.md#e44).

**Préconditions :** Capture active possédée par la racine ; deux compositions de fenêtre.

**Procédure :** Détruire et reconstruire la vue carte, changer NavigationStack, faire apparaître une seconde scène autorisée.

**Résultat attendu :** Un propriétaire local de collecte ; aucune tâche de vue ne coupe le service ; pas de nouvelle capture implicite.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob043"></a>
### MOB043 · Stop et écritures locales déjà admises

**Plateformes :** IOS, IPADOS. **Exigences :** [MX05](#mx05), [MX07](#mx07). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E17](../02-experience/ecrans.md#e17).

**Préconditions :** Magasin chiffré avec latence d’écriture et callbacks contrôlés.

**Procédure :** Bloquer une écriture admise, arrêter localement, émettre un callback tardif puis libérer la transaction.

**Résultat attendu :** Source coupée immédiatement ; barrières et manifeste cohérents ; mesure tardive rejetée ; aucun succès avant commit.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob044"></a>
### MOB044 · Confirmer SQLCipher natif dans le binaire

**Plateformes :** IOS, IPADOS. **Exigences :** [MX07](#mx07), [MX01](#mx01). **Fonctions :** [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12), [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E17](../02-experience/ecrans.md#e17), [E23](../02-experience/ecrans.md#e23).

**Préconditions :** Binaire Apple signé et base fictive contenant marqueurs connus.

**Procédure :** Vérifier liaison de la bibliothèque, lecture sans clé/clé erronée, fichiers DB/WAL/temp et écriture écran verrouillé.

**Résultat attendu :** Chiffrement effectif démontré ; pas de repli SQLite en clair ; politique Keychain/fichiers cohérente ou test déclaré en échec.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob045"></a>
### MOB045 · Couverture du client HTTP Swift sur OpenAPI

**Plateformes :** IOS, IPADOS. **Exigences :** [MX01](#mx01), [MX10](#mx10). **Fonctions :** [F17](../03-fonctionnel/catalogue-packs.md#f17), [F18](../03-fonctionnel/cours-collectifs.md#f18), [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E26](../02-experience/ecrans.md#e26), [E28](../02-experience/ecrans.md#e28).

**Préconditions :** Client Swift généré ou adaptateurs écrits avec version fixée.

**Procédure :** Compiler les opérations critiques ; décoder les fixtures et comparer null, omission, unions, conditions et erreurs aux schémas canoniques.

**Résultat attendu :** Aucune validation serveur affaiblie pour générer ; écarts documentés et adaptateurs testés ; aucune couverture intégrale déduite de la seule génération.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob046"></a>
### MOB046 · PATCH partiel, centimes et préconditions en Swift

**Plateformes :** IOS, IPADOS. **Exigences :** [MX10](#mx10). **Fonctions :** [F20](../03-fonctionnel/onboarding.md#f20), [F17](../03-fonctionnel/catalogue-packs.md#f17). **Écrans :** [E40](../02-experience/ecrans.md#e40), [E30](../02-experience/ecrans.md#e30).

**Préconditions :** Profil, achat et versions de test ; encodeur/décodeur du client Apple.

**Procédure :** Encoder champ omis puis explicitement null, montant centimes et If-Match ; exercer une précondition périmée.

**Résultat attendu :** Omission et effacement distingués ; montant entier exact ; conflit présenté sans écrasement ni prix recalculé en Double.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob047"></a>
### MOB047 · Périmètre scolaire après réponse réseau retardée

**Plateformes :** IOS, IPADOS. **Exigences :** [MX06](#mx06), [MX07](#mx07). **Fonctions :** [F01](../03-fonctionnel/identites-formations.md#f01), [F03](../03-fonctionnel/identites-formations.md#f03), [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12). **Écrans :** [E01](../02-experience/ecrans.md#e01), [E07](../02-experience/ecrans.md#e07), [E17](../02-experience/ecrans.md#e17).

**Préconditions :** Deux écoles et comptes sans accès croisé, réponse et refresh bloqués.

**Procédure :** Lancer lecture/upload sous A, changer vers B puis libérer les réponses et la tentative de refresh.

**Résultat attendu :** Résultat ancien rejeté ; données non affichées ni transmises sous B ; les commandes conservent leur périmètre original.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob048"></a>
### MOB048 · URLSession sans faux acquittement de capture

**Plateformes :** IOS, IPADOS. **Exigences :** [MX05](#mx05), [MX10](#mx10). **Fonctions :** [F15](../03-fonctionnel/gps-replay.md#f15), [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12). **Écrans :** [E23](../02-experience/ecrans.md#e23), [E17](../02-experience/ecrans.md#e17).

**Préconditions :** Chunks durables, autorisations de collecte/envoi distinctes, serveur de recette.

**Procédure :** Faire échouer la réponse après réception, suspendre l’app puis revenir au premier plan ; expirer le jeton avant un autre essai.

**Résultat attendu :** Reprise idempotente selon droits actuels ; octets envoyés non assimilés à ack ; aucun spool GPS en clair ni prolongement de collecte.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob049"></a>
### MOB049 · Snapshot MapKit retiré et pagination de segments

**Plateformes :** IOS, IPADOS. **Exigences :** [MX03](#mx03), [MX10](#mx10). **Fonctions :** [F16](../03-fonctionnel/gps-replay.md#f16), [F14](../03-fonctionnel/hors-ligne-vie-privee.md#f14). **Écrans :** [E24](../02-experience/ecrans.md#e24), [E19](../02-experience/ecrans.md#e19).

**Préconditions :** Long trajet fictif à plusieurs pages, snapshot publié puis retrait.

**Procédure :** Charger par fragments, déplacer la caméra, changer de vue et appliquer la notification de retrait avec nouvelle lecture autorisée.

**Résultat attendu :** Même segment à travers pages ; aucune nouvelle collecte par la carte ; géométries et caches retirés quand le retrait est appris.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob050"></a>
### MOB050 · APNs natif et environnement de distribution

**Plateformes :** IOS, IPADOS. **Exigences :** [MX08](#mx08), [MX01](#mx01). **Fonctions :** [F19](../03-fonctionnel/calendrier-notifications.md#f19), [F01](../03-fonctionnel/identites-formations.md#f01). **Écrans :** [E32](../02-experience/ecrans.md#e32), [E18](../02-experience/ecrans.md#e18).

**Préconditions :** Deux environnements Apple avec installations et tokens de test distincts.

**Procédure :** Renouveler le token, réinstaller, refuser les notifications et ouvrir un avis ancien depuis TestFlight.

**Résultat attendu :** Installation mise à jour sans fuite de token ; pas de mélange sandbox/production ; centre in-app disponible et objet relu sous droits.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob051"></a>
### MOB051 · Navigation SwiftUI et contrat de commande durable

**Plateformes :** IOS, IPADOS. **Exigences :** [MX03](#mx03), [MX10](#mx10). **Fonctions :** [F18](../03-fonctionnel/cours-collectifs.md#f18), [F20](../03-fonctionnel/onboarding.md#f20). **Écrans :** [E26](../02-experience/ecrans.md#e26), [E40](../02-experience/ecrans.md#e40).

**Préconditions :** Formulaire et inscription avec opération en attente ; iPhone puis fenêtre iPad étroite.

**Procédure :** Valider, revenir en arrière pendant 202, élargir la fenêtre puis revenir à la destination par lien.

**Résultat attendu :** État et intention retrouvés ; une annulation de tâche de vue n’annule pas le commit serveur ; pas de double inscription ni formulaire réinitialisé.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

<a id="mob052"></a>
### MOB052 · Distribution native et schéma local plus récent

**Plateformes :** IOS, IPADOS. **Exigences :** [MX13](#mx13), [MX01](#mx01), [MX07](#mx07). **Fonctions :** [F12](../03-fonctionnel/hors-ligne-vie-privee.md#f12), [F15](../03-fonctionnel/gps-replay.md#f15). **Écrans :** [E17](../02-experience/ecrans.md#e17), [E23](../02-experience/ecrans.md#e23).

**Préconditions :** Deux binaires Apple et base versionnée ; configurations de test distinctes.

**Procédure :** Inspecter provenance/Package.resolved et secrets ; tenter ancienne version sur schéma nouveau et configuration distante changeant le code.

**Résultat attendu :** Binaire traçable ; downgrade incompatible refusé sans purge ; aucune exécution de bundle métier distant ni secret de signature embarqué.

**Statut : NOT_EXECUTED.** Aucune preuve d’exécution jointe.

## Conservation des preuves

Chaque exécution attache binaire/version, appareil/OS exact, données fictives employées, profil de permission, résultat observé et anomalies. Les captures ne contiennent pas d’élèves réels. Une mesure de benchmark, une réussite de schéma JSON et un scénario humain sont trois objets distincts. Le dossier de conception conserve la recette ; les résultats futurs doivent être ajoutés sans réécrire l’historique des versions antérieures.

<a id="compléments-natifs-v37"></a>
## Qualification des sources natives
Ces huit cas restent NOT_EXECUTED. Les sources/horloges simulées ne remplacent pas une capture réelle ni un envoi APNs de recette.

<a id="mob053"></a>
### MOB053 · Ancienne position au démarrage

**Préconditions :** Source de test délivrant une position avant la nouvelle autorisation puis un point actuel.
**Procédure :** Démarrer une nouvelle leçon sur iPhone puis iPad.
**Attendu :** Le cache antérieur n’entre pas dans la trace ; état En attente de position puis sauvegarde réelle.
**Statut :** NOT_EXECUTED. **Exigences :** MX04, MX05. **Fonctions :** F15, F16. **Écrans :** E23. **Plateformes :** IOS, IPADOS.

<a id="mob054"></a>
### MOB054 · Réception en lot et horloge

**Préconditions :** Build qualifié avec horloge/source contrôlées et persistance chiffrée.
**Procédure :** Livrer des positions dans l’intervalle avec délai puis provoquer un saut d’horloge.
**Attendu :** Lots valides conservés, rupture explicite si mapping perdu ; bail non prolongé, manifeste stable.
**Statut :** NOT_EXECUTED. **Exigences :** MX05, MX07. **Fonctions :** F12, F15. **Écrans :** E23. **Plateformes :** IOS, IPADOS.

<a id="mob055"></a>
### MOB055 · iPad non qualifié pour capture

**Préconditions :** Binaire sans exigence globale gps, appareil de test non qualifié pour collecte.
**Procédure :** Installer, ouvrir agenda/cours/bilan puis tenter GPS.
**Attendu :** Usages non GPS accessibles ; diagnostic limite seulement la capture, aucune fausse position.
**Statut :** NOT_EXECUTED. **Exigences :** MX01, MX03, MX04. **Fonctions :** F15, F18, F08. **Écrans :** E23, E27. **Plateformes :** IOS, IPADOS.

<a id="mob056"></a>
### MOB056 · Absence de mesure et accessibilité

**Préconditions :** Source sans mesure exploitable ; VoiceOver et grande taille de texte actifs.
**Procédure :** Démarrer/arrêter puis consulter le replay.
**Attendu :** État sans point annoncé sans carte fictive ; arrêt accessible, aucune réussite de trajet prétendue.
**Statut :** NOT_EXECUTED. **Exigences :** MX05, MX15, MX16. **Fonctions :** F15, F16. **Écrans :** E23. **Plateformes :** IOS, IPADOS.

<a id="mob057"></a>
### MOB057 · Connexion de deux comptes sur une installation

**Préconditions :** Comptes de recette A/B et tokens fournisseur de test, réseau contrôlé.
**Procédure :** Basculer de A vers B, actualiser AP148 et déclencher l’ancienne route.
**Attendu :** Pas de nouveau message de A après revalidation serveur ; ouverture exige droits de B, aucune donnée personnelle dans payload.
**Statut :** NOT_EXECUTED. **Exigences :** MX06, MX08, MX07. **Fonctions :** F01, F11. **Écrans :** E01, E02. **Plateformes :** IOS, IPADOS.

<a id="mob058"></a>
### MOB058 · Entitlement et environnement APNs

**Préconditions :** Deux binaires signés recette/distribution et configurations fournisseur distinctes.
**Procédure :** Inspecter entitlement réel, récupérer token puis soumettre une mauvaise combinaison.
**Attendu :** Environnement concordant enregistré ; mismatch refusé, pas de fallback caché vers production.
**Statut :** NOT_EXECUTED. **Exigences :** MX01, MX08, MX13. **Fonctions :** F11. **Écrans :** E19. **Plateformes :** IOS, IPADOS.

<a id="mob059"></a>
### MOB059 · Token renouvelé et révocation obsolète

**Préconditions :** Installation réinscrite avec token courant et ancienne commande de révocation.
**Procédure :** Recevoir nouveau token, rejouer l’ancienne révocation et reconnecter.
**Attendu :** Token relu au système ; nouvelle liaison non supprimée par commande obsolète, logs sans token.
**Statut :** NOT_EXECUTED. **Exigences :** MX06, MX08. **Fonctions :** F01, F11. **Écrans :** E19. **Plateformes :** IOS, IPADOS.

<a id="mob060"></a>
### MOB060 · Push déjà en transit et retour web

**Préconditions :** Message accepté avant logout hors réseau ; compte courant différent.
**Procédure :** Livrer le message, le toucher, puis ouvrir le portail web sans push.
**Attendu :** Message générique, dossier refusé/relu sous bons droits ; calendrier web indépendant du token natif.
**Statut :** NOT_EXECUTED. **Exigences :** MX08, MX10, MX15. **Fonctions :** F01, F11, F19. **Écrans :** E01, E27. **Plateformes :** IOS, IPADOS.

<a id="mob061"></a>
### MOB061 · Sessions API et staging séparées

**Plateformes :** IOS, IPADOS. **Exigences :** MX06, MX07. **Fonctions :** F01, F09. **Écrans :** E01, E10. **Statut :** NOT_EXECUTED.

**Préconditions :** Compte connecté et ticket fictif qualifié.

**Procédure :** Observer les requêtes API et PUT sur un environnement contrôlé.

**Attendu :** Le bearer Drivy et les cookies API ne sont jamais envoyés au stockage ; méthode/headers exacts.

Aucune preuve appareil n’a été recueillie dans ce dossier.

<a id="mob062"></a>
### MOB062 · Origine et redirect hostiles

**Plateformes :** IOS, IPADOS. **Exigences :** MX06, MX07. **Fonctions :** F09, F14. **Écrans :** E10, E18. **Statut :** NOT_EXECUTED.

**Préconditions :** Ticket malformé ou réponse de redirection de contenu.

**Procédure :** Tester userinfo, sous-domaine trompeur, HTTP et redirect vers une autre origine.

**Attendu :** Refus avant émission de secrets ; aucune acceptation par simple suffixe de domaine.

Aucune preuve appareil n’a été recueillie dans ce dossier.

<a id="mob063"></a>
### MOB063 · Caches de médias et export

**Plateformes :** IOS, IPADOS. **Exigences :** MX07, MX15. **Fonctions :** F09, F12, F14. **Écrans :** E10, E18. **Statut :** NOT_EXECUTED.

**Préconditions :** Pièce et export consultés, sans sauvegarde volontaire externe.

**Procédure :** Inspecter URLCache, caches d’aperçu et fichiers temporaires avant/après logout.

**Attendu :** Aucun cache disque clair sensible ; les copies temporaires et projections suivent les règles de purge.

Aucune preuve appareil n’a été recueillie dans ce dossier.

<a id="mob064"></a>
### MOB064 · Snapshot de scène sensible

**Plateformes :** IOS, IPADOS. **Exigences :** MX03, MX07. **Fonctions :** F01, F12. **Écrans :** E04, E23. **Statut :** NOT_EXECUTED.

**Préconditions :** Fiche ou carte avec contenu privé affichée.

**Procédure :** Passer au sélecteur d’apps, verrouiller, revenir ; répéter sur plusieurs scènes.

**Attendu :** Couverture opaque neutre au snapshot et retour sans ancienne identité ; hook qualifié sur chaque OS.

Aucune preuve appareil n’a été recueillie dans ce dossier.

<a id="mob065"></a>
### MOB065 · Couverture sans perte GPS

**Plateformes :** IOS, IPADOS. **Exigences :** MX03, MX05, MX07. **Fonctions :** F12, F15. **Écrans :** E23. **Statut :** NOT_EXECUTED.

**Préconditions :** Capture valide avec points déjà conservés.

**Procédure :** Présenter la couverture de confidentialité en arrière-plan puis reprendre.

**Attendu :** Le collecteur conserve sa session ; aucune interruption créée uniquement par la couverture.

Aucune preuve appareil n’a été recueillie dans ce dossier.

<a id="mob066"></a>
### MOB066 · Dépôt expiré réconcilié

**Plateformes :** IOS, IPADOS. **Exigences :** MX07, MX09. **Fonctions :** F09, F12. **Écrans :** E10. **Statut :** NOT_EXECUTED.

**Préconditions :** PUT reçu sans réponse puis URL expirée.

**Procédure :** Rouvrir la fiche et reprendre avec droits valides.

**Attendu :** Finaliser le même objet si encore disponible ; pas de nouveau dépôt aveugle ni texte perdu.

Aucune preuve appareil n’a été recueillie dans ce dossier.

<a id="mob067"></a>
### MOB067 · Retour de scène après changement de compte

**Plateformes :** IOS, IPADOS. **Exigences :** MX03, MX06, MX07. **Fonctions :** F01, F12. **Écrans :** E01, E04. **Statut :** NOT_EXECUTED.

**Préconditions :** Une ancienne scène a une réponse de téléchargement en attente.

**Procédure :** Changer de compte puis réactiver l’ancienne scène.

**Attendu :** Résultat obsolète non présenté et aucune capture d’ancienne identité au retour.

Aucune preuve appareil n’a été recueillie dans ce dossier.

<a id="mob068"></a>
### MOB068 · Copie explicite hors de Drivy

**Plateformes :** IOS, IPADOS. **Exigences :** MX07, MX15. **Fonctions :** F14, F22. **Écrans :** E18, E46. **Statut :** NOT_EXECUTED.

**Préconditions :** Export READY reçu sous type/longueur/hash corrects.

**Procédure :** Choisir une sauvegarde/partage système puis se déconnecter.

**Attendu :** La copie externe volontaire est expliquée comme non révocable ; les temporaires internes sont traités séparément.

Aucune preuve appareil n’a été recueillie dans ce dossier.
