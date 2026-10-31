# Lot iOS de 15 tickets — livraison et recette

Branche `codex/ios-batch-15-20261029`, base `2d9a5f64` de l'IPA 446. Les 25 corrections précédentes restent incluses. Ce document suit 15 tickets supplémentaires, soit 40 tickets traités au total ; les preuves et limites ci-dessous distinguent réalisation native, essai et qualification.

L'EPIC #311 et son périmètre web sont exclus. Les trois branches spécialisées sont `codex/ios-durability-113-117-118-125`, `codex/ios-messages-200-238-246` et `codex/ios-layout-196-220-227-231`. Aucun déploiement homelab, modification API ou fusion dans master. Les filtres de lancement des contrôles Apple permettent de sélectionner consentement, brouillons et profil ; les fixtures servent aux comparaisons visuelles.

## IPA à installer

**Drivy 0.7.0, build 447**, non signé, iOS/iPadOS 26 minimum. Fichier copié et vérifié dans `C:\Users\jtoma\Downloads\Drivy-0.7.0-447.ipa`. Le signer et l'installer avec iLoader, comme les précédents essais. L'IPA 446 reste disponible séparément.

- [Téléchargement GitHub](https://github.com/tomyrms/Drivy/actions/runs/40959499844/artifacts/12935631882) ; [compilation Release réussie](https://github.com/tomyrms/Drivy/actions/runs/40959499844).
- Code produit : `633f20d3b6893f66151ea95d266ac0fb5ceef1bf`. Les deux corrections de tests intervenues ensuite ne changent pas le binaire.
- 18 293 386 octets ; SHA-256 : `92be049a68418aea3fc5994e01c23d5c62c1cf2533a5ac7f84c00f41c99ff2cc`.
- Manifeste de sommes, commit/run, verrou des dépendances, CRC de l'archive, version du plist et absence de signature vérifiés. Empreinte du fichier dans Téléchargements identique. Connexion scolaire configurée et accès Messages de qualification compilé.

## État des preuves

- Agenda : compilation Apple et sélection de quatre suites réussies, [run 40954007339](https://github.com/tomyrms/Drivy/actions/runs/40954007339), SHA `a444d2d38e8ca95272c3c0c40c1f3b57f1f96d4a`. Rapport : 73 tests, 78 exécutions avec paramètres, zéro échec/ignoré. Les corrections ultérieures de génération des lectures et d'annulation au changement de jour sont relues ; elles ne sont pas assimilées à ce SHA testé.
- Consentement : [run 40957419205](https://github.com/tomyrms/Drivy/actions/runs/40957419205) réussi sur `1cc85310`, 20 tests réussis, zéro échec/ignoré.
- Captures originales : [run 40953177715](https://github.com/tomyrms/Drivy/actions/runs/40953177715), puis comparaison de vingt PNG, dix [avant](https://github.com/tomyrms/Drivy/actions/runs/40954527122) (`ee5bc2cb`) et dix [après](https://github.com/tomyrms/Drivy/actions/runs/40957481494) (`1cc85310`), iPhone/iPad, clair, données synthétiques. Les corrections #196/#220/#227/#231 sont visibles. Deux superpositions système limitent des zones de capture ; voir la [preuve détaillée](ios-layout-196-220-227-231.md).
- Profil : [run 40960532711](https://github.com/tomyrms/Drivy/actions/runs/40960532711) réussi sur `cec9a058`, 10 tests réussis, zéro échec/ignoré. La première compilation des tests (`40959548945`) avait échoué sur une assertion incompatible avec la macro Swift Testing ; correction limitée au test.
- Brouillons : [relance ciblée 40961435005](https://github.com/tomyrms/Drivy/actions/runs/40961435005) réussie sur `da901183274c707163e4b2e59e54a7e990c3c130`, 49 tests, 53 exécutions avec paramètres, zéro échec/ignoré. Le premier contrôle (`40958460343`) avait 48 tests réussis et un test en échec : l'identifiant invalide de la fixture empêchait de charger le souhait, donc d'exercer sa reprise. Identifiant corrigé et préconditions explicites ajoutées ; aucun changement produit. Le lancement `40958362414` a été annulé avant exécution au profit d'une branche CI distincte.
- Compilation Release finale réussie, IPA ci-dessus. Les tests Messages et mise en page préparés ne sont pas revendiqués comme exécutés.
- Grandes suites, recette physique, GPS/batterie/VoiceOver : non exécutés. Aucun rendu simulateur ne qualifie ces points physiques.

Les **40 issues** des deux tableaux ci-dessous ont été fermées sur demande explicite du porteur : les 25 de l'IPA 446, puis les 15 de ce lot après les contrôles ciblés. Les PR [#337](https://github.com/tomyrms/Drivy/pull/337), [#338](https://github.com/tomyrms/Drivy/pull/338) et [#339](https://github.com/tomyrms/Drivy/pull/339) restent en brouillon ; cette clôture n'autorise ni fusion ni tests complets. L'essai du porteur reste attendu avant la qualification pertinente puis fusion. Aucune case de qualification physique n'a été cochée par assimilation à la compilation ou au simulateur.

## Comment essayer les 15 nouveaux tickets

Utiliser des comptes et objets d'essai avec les rôles indiqués. Les modifications de profil, invitations, choix GPS et règlements suivent les droits et écritures réels du service.

Pour commencer sans matériel supplémentaire : connexion (#195–#199), navigation Messages (#200/#202/#238/#240/#241/#246), agenda (#207–#210), historique et progression (#206/#214–#218), puis les écrans de cours et invitations selon vos droits. Essayer ensuite les écritures sur des objets d'essai.

Pour les cas hors réseau, charger d'abord l'écran, couper Wi-Fi et données mobiles, effectuer la manipulation, puis rétablir le réseau et utiliser la vérification/reprise proposée. Le mode avion seul ne reproduit pas précisément une réponse perdue après écriture : ce cas, les réponses retardées dans un ordre précis, une panne du coffre et le changement de textes de consentement exigent un scénario contrôlé. Ils sont décrits pour la qualification technique, sans manipulation à deviner dans l'IPA. Les conflits inter-appareils demandent deux sessions du même compte. Les essais iPad, GPS physique et VoiceOver demandent le matériel ou les réglages correspondants.

| Issue | Manipulation | Résultat attendu |
|---|---|---|
| #113 Brouillons | Modifier préparation/note d'une leçon et souhait de la formation ; fermer puis rouvrir. Pendant l'envoi de N, saisir N+1, ou revenir au texte d'origine A ; fermer/réouvrir après la réponse. | Dernière saisie conservée dans le bon dossier ; une réponse à N n'efface ni N+1 ni A. Panne du coffre expliquée sans annoncer une sauvegarde. |
| #117 Progression | Ouvrir deux permis, revenir à une progression déjà lue et interrompre l'actualisation. | Données connues conservées avec état/date de leur propre lecture ; une panne n'affiche pas une progression neuve ni une réussite d'examen inventée. |
| #118 Profil | Modifier nom/contact/photo, naviguer entre Profil, compte, dossier personnel et Messages pendant l'envoi ; fermer/réouvrir après coupure réseau. | Même projection personnelle avec attente visible ; versions officielles distinctes ; dernière saisie reprise ou conflit à revoir, aucun tiers modifié. |
| #125 Refus GPS | Élève : accepter avec réseau ralenti, puis « Refuser le GPS maintenant » avant la réponse ; recommencer hors réseau et rouvrir. | Refus conservé et collecte locale arrêtée ; l'ancien accord ne déclenche pas de reprise. Une opération incertaine reste à vérifier, sans faux reçu de refus. |
| #196 Identité étroite | Formulaire prénom/nom : noms longs, fenêtre iPad étroite ou grande taille de texte, clavier ouvert et rotation. | Champs sur deux lignes lorsque nécessaire ; textes et focus conservés, commandes atteignables. |
| #200 Messages ADMIN | Compte ADMIN sans rôle moniteur : ouvrir l'accueil de gestion, Messages, puis revenir au compte/portail. | Destination nommée visible dans le contenu ; un seul parcours Messages, mêmes droits. |
| #208 Moniteur | ADMIN : Agenda → Moniteur ; choisir deux moniteurs, puis toute l'école ; semaine/mois et retour de fiche. | Leçons, cours, repères et compteurs suivent le même filtre. Homonymes distingués ; choix retiré non remplacé sous un autre nom. |
| #209 Prochain RDV | Jour vide → Prochain rendez-vous ; essayer avec cours avant leçon, annulation de recherche, changement de jour et panne réseau. | Bonne date dans la fenêtre de 90 jours ; recherche bornée/annulable, couverture incomplète explicite ; aucune ancienne réponse ne déplace la sélection. |
| #210 Recherche agenda | Chercher élève avec/sans accents ou titre de cours ; changer période/moniteur, ouvrir un résultat et revenir. | Période/couverture explicites, occurrence exacte ; saisie et filtre conservés au retour. |
| #214 Historique | Dossier A : statut/mois/tri ; passer à B puis revenir à A ; Réinitialiser l'historique ; changer d'école. | B n'hérite pas de A ; A retrouve ses choix pendant la session ; remise à zéro visible ; aucun critère hérité dans une autre portée. |
| #220 Surfaces cours | Ouvrir liste de cours, cours disponible puis inscrit, sur iPhone/iPad et en clair/sombre. | Surfaces, titres et largeur cohérents avec les composants Drivy ; chargement/erreur/vide lisibles. |
| #227 Règlements | Personnel habilité, cours d'essai : consulter plusieurs règlements dont un annulé, ouvrir le menu d'un versement précis puis sa correction motivée. | Historique compact avec vraies dates/montants ; entrée annulée visible ; correction visant exactement le versement choisi. |
| #231 Invitations | iPad à deux colonnes : sélectionner une invitation d'essai, lancer une opération puis provoquer une réponse incertaine ; changer de sélection et revenir. | Un seul retour principal à la bonne cible ; erreur de lecture indépendante conservée ; action de vérification accessible. |
| #238 Suppression Messages | Ouvrir actions d'un message par appui long ou réaction ; choisir chaque portée de suppression puis Annuler. | Rôle destructif visible, une seule confirmation en français ; réactions conservées et autorisations relues. |
| #246 Appareils | Messages → appareils : nommer deux appareils, rouvrir, retirer un alias ; changer de compte/école. | Alias locaux conservés de façon protégée ; appareils distingués, ID/empreinte accessibles ; aucune modification de confiance ou fuite d'alias entre contextes. |

## Les 25 corrections déjà livrées

Elles sont incluses dans le même binaire ; fermer une issue ne remplace pas son essai.

| Issue | Essai rapide et résultat attendu |
|---|---|
| #195 | Connexion : couper le réseau, puis essayer un mot de passe incorrect. Les deux causes doivent recevoir des messages différents. |
| #197 | Connexion : laisser un champ requis vide après interaction. La cause empêchant l'envoi doit être compréhensible sans effacer les autres champs. |
| #198 | Récupération indisponible : revenir à la connexion depuis l'écran d'erreur. |
| #199 | Saisir un code valide partiel, puis coller un contenu trop long ou non reconnu. Refus expliqué et saisie précédente préservée. |
| #201 | Sélectionner une école en préparation puis archivée. Le statut et l'action possible doivent être explicites. |
| #202 | Notifications : ouvrir les réglages Messages par leur entrée dédiée, puis revenir ; portée des réglages compréhensible. |
| #203 | Modifier une préférence hors réseau. L'attente est visible ; le retour réseau ne doit pas transformer un refus en réussite. |
| #204 | Lire les réglages de notifications en changeant d'école. Compte, école et appareil sont distingués. |
| #206 | Ouvrir une progression vide/en chargement. Texte d'attente adapté à cet écran et au rôle. |
| #207 | Moniteur avec cours collectif prochain : Aujourd'hui doit le mettre en avant et ouvrir la bonne séance. |
| #211 | Préférences de planning : choisir entre deux tarifs proches. Durée et prix permettent de les distinguer. |
| #212 | Changer le permis avec un tarif incompatible sélectionné. Remise à zéro expliquée, pas de sauvegarde silencieuse. |
| #213 | Modifier les mêmes préférences depuis deux appareils. Comparer versions locale/école avant de remplacer la saisie. |
| #215 | Progression : rechercher compétence par mots, accents et casse. Résultats limités au référentiel autorisé. |
| #216 | Ouvrir deux détails de compétences. Le second ne referme pas le premier. |
| #217 | Comparer compétences évaluées lors de leçons différentes. Chaque date correspond à son évaluation. |
| #218 | Ouvrir une compétence jamais observée. Définition du référentiel visible lorsqu'elle existe, aucune définition inventée. |
| #219 | Mon profil : vérifier l'indication d'identité commune avant modification dans un compte multi-écoles. |
| #228 | Invitations : rechercher/filtrer puis charger la suite. Les limites des pages lues restent explicites. |
| #229 | Deux invitations de même formation : références courtes distinctes, sans révéler les codes secrets. |
| #230 | Invitations proche échéance/expirée : date utile visible dans le fuseau de l'école, sans état serveur inventé. |
| #232 | Pendant un trajet, Terminer la leçon : lire la conséquence et confirmer seulement sur une leçon d'essai. Arrêt et fin durables restent distincts d'un simple appui. |
| #237 | Messages : couper le réseau pendant un envoi. Attente, résultat incertain et refus sont distincts ; reprise sans nouveau doublon d'intention. |
| #240 | Messages → Non lus : conversations connues non lues et état inconnu distingués ; recherche et pages suivantes restent cohérentes. |
| #241 | Ouvrir une épingle puis utiliser le parcours des épingles. L'aperçu sélectionné reste stable et la navigation ouvre le message exact. |

## Détails techniques

[Agenda/historique](ios-agenda-discovery-208-214-20261029.md), [brouillons](ios-preparation-drafts-113.md), [progression](ios-progress-freshness-117.md), [profil](ios-profile-intents-118.md), [projection du profil dans Messages](ios-messages-self-profile-projection-118-20261029.md), [refus GPS](ios-priority-refusal-125.md), [mise en page](ios-layout-196-220-227-231.md), [Messages](ios-messages-entry-menu-aliases-200-238-246.md), [lot précédent](ios-suite-19-delivery-20261029.md).
