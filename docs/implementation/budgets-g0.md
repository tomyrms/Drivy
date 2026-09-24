# Budgets techniques provisoires G0

Version 0.1 · 24 septembre 2026 · **Cibles fixées avant essais, aucune mesure réalisée dans ce document.**

Ces bornes diagnostiques appliquent [DM07](../../Drivy_Conception_v3_17_2026-09-20/05-realisation/roadmap-backlog.md#dm07--budgets-non-fonctionnels-et-preuves-de-qualité) au laboratoire local. Elles ne constituent ni des performances mesurées, ni un engagement commercial, ni une validation de l'usage pendant la conduite. Le statut reste `NOT_QUALIFIED` tant que l'environnement, les cibles retenues et les preuves nécessaires ne sont pas établis. La conception d'origine reste intacte.

## Environnement à figer avant chaque série

Identifier un iPhone pilote et un iPad pilote : modèle exact, OS, état de santé de batterie disponible, espace libre, commit, SHA-256 de l'IPA, mode Release/Debug et méthode de signature. Les résultats sont séparés par appareil. Inscrire ces informations **avant** la première mesure ; un appareil ou un build différent ouvre une nouvelle série.

Pour les mesures chronométrées, utiliser de préférence Release, sans débogueur, sans téléchargement ou mise à jour en parallèle. Noter réseau, carte déjà consultée ou non, luminosité et température ambiante approximative. Le tout premier lancement, incluant création de clé et base, est mesuré séparément des suivants.

Les budgets de batterie ci-dessous concernent uniquement les appareils pilotes ainsi identifiés, avec leur état de batterie indiqué. Ils ne valent pas pour tout iPhone/iPad. Une mesure sur simulateur conserve la mention `SIMULATOR` : elle ne qualifie ni énergie, ni GPS, ni comportement sous verrouillage sur appareil.

## Invariants : aucun compromis avec une cible de vitesse

| Invariant | Preuve attendue |
|---|---|
| Zéro perte d'observation ou de bilan annoncé sauvegardé | Après fermeture/reprise, UUID, instant, texte et ancre restent identiques. Une commande en cours non confirmée reste distincte d'une sauvegarde acquise. |
| Zéro duplication après confirmations répétées | Un même identifiant d'observation produit un seul élément durable. |
| Arrêt immédiat de l'admission | Après la commande d'arrêt, aucune nouvelle mesure ou observation n'est admise ; les écritures déjà admises sont drainées avant une clôture réussie. Un échec de stockage est signalé et ne devient pas une fausse réussite. |
| Reprise explicite | Après fermeture forcée, seuls les faits durables sont retrouvés ; la séance est interrompue et le GPS ne redémarre pas automatiquement. |
| Aucun trajet inventé | Refus, manque de précision, période sans mesure et interruption restent des absences ou ruptures explicites. Le nombre de callbacks reçus n'est pas assimilé au nombre de points admissibles. |
| Chiffrement requis | Mauvaise clé, clé inaccessible ou SQLCipher indisponible empêchent l'accès/écriture ; aucun remplacement par une base en clair. |

Un dépassement de latence ne permet pas de supprimer des écritures ni d'afficher une confirmation anticipée. « Zéro perte » porte sur les données dont la sauvegarde a été confirmée ; il ne promet pas des mesures que le système n'a jamais livrées, ni la survie d'une file uniquement en mémoire lors d'une destruction du processus.

## Seuils pratiques initiaux

Les valeurs suivantes sont des **choix d'implémentation provisoires**, à éprouver sur les appareils pilotes. Elles servent à déclencher une analyse. Aucune colonne ne représente un résultat observé.

| ID | Mesure et charge | Cible provisoire | État initial |
|---|---|---|---|
| B01 | Premier lancement : ouverture jusqu'à écran interactif et stockage prêt | ≤ 5 s ; relever ce cas séparément | NOT_EXECUTED |
| B02 | Lancement à froid suivant, avec historique d'une séance de 60 min | ≤ 4 s sur chacun de 10 lancements | NOT_EXECUTED |
| B03 | Retour au premier plan, processus resté vivant | ≤ 1 s sur chacun de 10 retours | NOT_EXECUTED |
| B04 | Première réponse visuelle d'une commande locale, notamment Signaler/Arrêter | p95 ≤ 100 ms ; aucun blocage UI observé > 200 ms | NOT_EXECUTED |
| B05 | Confirmation d'une observation → confirmation visible après écriture durable | p95 ≤ 500 ms ; maximum ≤ 2 s, sur au moins 30 confirmations | NOT_EXECUTED |
| B06 | Enregistrer un bilan de 1 000 caractères → confirmation après écriture durable | p95 ≤ 500 ms ; maximum ≤ 2 s, sur au moins 30 sauvegardes | NOT_EXECUTED |
| B07 | Arrêt demandé → séance close, écritures admises drainées, historique consultable | p95 ≤ 2 s ; maximum ≤ 5 s, sur au moins 20 arrêts ordinaires | NOT_EXECUTED |
| B08 | Ouvrir la relecture d'une séance de 60 min, points et observations déjà locaux | ≤ 2 s sur chacun de 10 ouvertures ; interactions ensuite selon B04 | NOT_EXECUTED |
| B09 | Mémoire du processus pendant capture/relecture d'une séance de 60 min | Pic ≤ 350 MiB ; croissance entre minutes 10 et 60 ≤ 75 MiB dans le même profil | NOT_EXECUTED |
| B10 | Croissance du dossier SQLCipher pour une séance de 60 min, jusqu'à 50 observations et bilan de 1 000 caractères | ≤ 25 MiB pour base + WAL + SHM/journal ; relever le nombre réel de points | NOT_EXECUTED |
| B11 | Batterie pendant 60 min de capture, écran visible, luminosité fixe à 50 % | Baisse ≤ 18 points de pourcentage par essai | NOT_EXECUTED |
| B12 | Batterie pendant 60 min de capture, écran verrouillé au moins 55 min | Baisse ≤ 10 points de pourcentage par essai | NOT_EXECUTED |

Le MiB vaut 1 048 576 octets. Une baisse de 80 % à 72 % représente 8 **points de pourcentage**, pas une consommation de 8 % de l'énergie totale nominale. B09/B10 décrivent une séance et une charge comptée ; une fréquence ou un volume supérieur ouvre un essai distinct. La carte et ses caches influencent B09 mais ne font pas partie du dossier SQLCipher de B10.

## Protocole minimal de mesure

### 1. Temps et données durables

Sur simulateur ou appareil, exécuter d'abord le [parcours sans GPS](recette-g0.md#parcours-sans-gps). Relever les points de départ et d'arrivée définis par B01–B08 : ouverture de l'app, appui sur la commande, affichage de la confirmation, écran de relecture effectivement utilisable. Ne pas chronométrer la fermeture d'un panneau comme preuve si le contenu n'est pas ensuite retrouvé dans l'historique.

Pour B04, une vidéo à 60 images/s ou plus peut donner une borne entre l'appui/événement visible et la première réponse UI ; noter sa résolution temporelle et son imprécision. Un chronomètre manuel ne permet pas de valider 100 ms. Pour les autres temps, utiliser une vidéo ou un relevé automatisé XCUITest lorsqu'il est disponible. Si l'entrée n'est pas visible ou si la cadence ne distingue pas le seuil, classer la mesure comme inexploitable et la refaire ; ne pas lui attribuer une précision fictive.

Sur les 30 observations, varier thème/statut, conserver un repère ordinal non personnel dans la note et doubler quelques confirmations. Vérifier le nombre d'observations avant/après relance et le contenu exact des notes/bilans. La vidéo mesure le délai **commande → confirmation visible**, qui inclut UI, file et stockage ; elle ne mesure pas séparément la durée interne d'une transaction SQL. La revue du code et les tests de persistance doivent confirmer que cet affichage suit effectivement le commit.

Conserver les durées brutes, le nombre d'échantillons, la médiane, le maximum et, là où demandé, le p95 empirique : trier les durées et prendre le rang `ceil(0,95 × n)`. Ne pas supprimer les essais lents ; expliquer séparément une erreur de manipulation. Avec 20 ou 30 mesures, ce percentile reste un diagnostic à petit effectif, pas une garantie statistique de fiabilité.

### 2. Deux profils de 60 minutes

Faire deux profils distincts, idéalement deux répétitions chacun par appareil, sans chargeur. Commencer avec une batterie comprise entre 40 et 90 %, mode économie d'énergie désactivé et réglages réseau constants. Relever batterie et heure au départ/à la fin ; noter toute autre activité significative et toute alerte thermique du système. Un essai branché, interrompu prématurément ou chargé par une mise à jour ne qualifie pas B11/B12.

- **Profil visible B11 :** capture volontaire pendant 60 min, carte affichée, luminosité manuelle 50 %. Saisir les observations à l'arrêt ou par un passager ; relever combien ont réellement été créées.
- **Profil verrouillé B12 :** capture volontaire pendant 60 min dont au moins 55 min verrouillées. Ouvrir uniquement pour le départ, les vérifications nécessaires et l'arrêt ; consigner ces durées. Ne pas ajouter 30 saisies au milieu de ce profil et le présenter comme écran éteint.

Noter début/fin de capture, nombre de points durables, nombre de segments, observations et durée effectivement verrouillée. Aucun intervalle universel d'un point par seconde n'est supposé : comparer les volumes réellement reçus/admis. La réception du premier point GPS n'est pas un délai de lancement applicatif B01/B02.

### 3. Mémoire et stockage

La mémoire peut être relevée sur appareil connecté à un Mac avec les outils de profilage Xcode, ou sur simulateur avec un outil de mesure de processus. Conserver la **même métrique** et le même outil pour toute la série : empreinte mémoire physique si disponible, sinon métrique nommée séparément. Relever à vide, puis à 10, 30 et 60 min, et pendant l'ouverture de la relecture. Un chiffre de mémoire de la machine Mac entière n'est pas la mémoire de Drivy. Un essai avec profileur ne remplace pas le profil batterie sans débogueur. Sans outil accessible, B09 reste `NOT_EXECUTED`.

Pour B10, relever la taille du dossier `Library/Application Support/DrivyG0` de l'app avant l'essai, à 10/30/60 min si accessible et après l'arrêt. Sur simulateur, `xcrun simctl get_app_container <UDID> ch.drivy.qualification data` fournit le conteneur ; additionner les tailles des fichiers `sessions.sqlite`, `-wal`, `-shm` et `-journal` présents. Conserver pic et valeur finale, pas seulement le fichier principal après fermeture. Mesurer la croissance par rapport au relevé initial ; ne pas supprimer l'historique pour améliorer le chiffre.

Sur appareil, un accès autorisé au conteneur via les outils de développement permet la même mesure. Si la signature iLoader ou l'outillage ne l'autorise pas, relever cette limite et garder B10 non exécuté sur appareil. Le stockage arrondi affiché dans Réglages donne seulement un ordre de grandeur ; il ne valide pas le seuil en octets. Aucune exportation de base, clé ou coordonnée n'est nécessaire dans un artefact public : conserver les tailles et compteurs techniques.

### 4. Arrêts, erreurs et reprises

Exécuter séparément les cas ci-dessous ; relever ce qui était **confirmé** avant l'interruption et ce qui était encore en cours. Comparer après réouverture identifiants, notes, ancrages et points déjà durables.

| Cas | Vérification |
|---|---|
| Arrêt avec écritures GPS en attente | Plus d'admission immédiatement ; drainage puis clôture ; aucun point tardif ajouté après la barrière |
| Application tuée après confirmation, puis pendant une écriture non confirmée | Données confirmées conservées ; résultat incertain explicitement réconcilié à la reprise ; aucun succès inventé |
| Refus GPS initial, retrait puis rétablissement de permission | Parcours sans GPS disponible ; pas de redémarrage silencieux après retrait |
| Écran verrouillé pendant le profil B12 | Continuité réellement mesurée, trous visibles s'il y en a ; aucune continuité supposée |
| Erreur de sauvegarde injectée dans le magasin de test | Capture arrêtée et erreur visible ; aucune confirmation de la donnée non écrite |
| Changement d'horloge, puis limite de séance de 2 h | Interruption explicite, faits déjà écrits conservés ; ni temps ni position reconstruits |
| Redémarrage de l'appareil et premier déverrouillage | Clé/base préexistantes conservées ; aucun repli en clair ; pas de reprise GPS automatique |

Les tests de magasin à latence/échec contrôlés déjà présents dans `apps/ios/DrivyTests/SessionCoreTests.swift` servent aux premiers cas déterministes après compilation Apple. Une panne de stockage injectée teste une branche logicielle ; elle ne prouve pas à elle seule le comportement d'un iPhone presque plein. Les essais de permission, verrouillage, GNSS, batterie et redémarrage exigent un appareil. Une trace synthétique de simulateur est marquée `SIMULATED` et ne devient jamais une preuve de trajet réel.

## Fiche de résultat et évolution des cibles

Pour chaque série, conserver : version de ce document, ID de budget, appareil/OS, commit et empreinte du build, profil, charge/compteurs, outil/métrique, valeurs brutes, agrégats, cible initiale et écarts. Ajouter la décision : nouvelle mesure, correction, investigation ou proposition de changement de cible. Inscrire dans [STATUS](STATUS.md) uniquement les essais effectivement exécutés et leurs limites.

Si une cible doit changer, créer une nouvelle version avec **ancienne valeur, nouvelle valeur, raison et date** ; garder les résultats obtenus sous l'ancienne cible. Un budget manquant, une mesure indisponible ou une simple réussite fonctionnelle laisse la qualité concernée `NOT_QUALIFIED`. Aucun seuil de ce document ne constitue une mesure déjà acquise.
