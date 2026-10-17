# Démarrage d’une leçon et GPS — 17 octobre 2026

## Défaut

Signalement du porteur : après connexion et ajout d’un élève, démarrer une leçon conduit directement à « Terminer la leçon », sans trajet ni raison visible. Le parcours paraît interrompu.

Le code reproduit ce cas pour une école nouvellement ouverte : la création conserve `modules.gpsEnabled = false`, et aucun écran du portail ne proposait de changer ce réglage. `SchoolStartNowLaunch` ne préparait donc pas le GPS, puis ouvrait la leçon dont `actualStart` avait été enregistré par `POST /lessons/start-now`. La fiche masquait « Démarrer le trajet » et ne proposait plus que la fin. Ce diagnostic repose sur le code et les scénarios synthétiques ; l’état du compte réel du porteur n’a pas été lu.

Le départ d’une leçon et l’autorisation de capture restent deux écritures distinctes. La connexion native transmet bien le contrôleur de capture ; aucune régression d’injection liée à la connexion n’a été constatée.

Un second signalement a révélé la preuve `auth_time` absente de la connexion par mot de passe et le retour vers l’ancienne page du fournisseur pendant l’activation. Ce défaut, distinct du contrôleur GPS, est corrigé dans [la confirmation d’identité](re-authentification-gps-20261017.md). La [livraison consolidée](deploiement-parcours-comptes-20261017.md) complète le premier correctif web ci-dessous.

## Correction

- Le portail propose **Trajets GPS** dans **Confidentialité et conditions** : état lu de l’école, activation ou désactivation explicite. Le composant utilise la commande durable `updateModules` existante, `PUT /v1/schools/{schoolId}/modules`, avec version, idempotence, droits administrateur et confirmation renforcée imposés au serveur. Une demande incertaine reste à vérifier ; un conflit propose de recharger le réglage.
- La fiche leçon et le récapitulatif du départ affichent la raison d’un GPS indisponible. Un administrateur peut rejoindre le réglage du portail ; le moniteur sait qu’il doit solliciter l’administration. La relecture récupère le réglage sans nouvelle connexion ni nouvelle leçon.
- Le bouton de départ annonce **Démarrer avec GPS** ou **Démarrer sans GPS**. La lecture de l’accord bloque aussi la commande dans le modèle, pas seulement le bouton. Choisir de partir sans GPS ne fabrique pas de refus de l’élève.
- Quand le module devient disponible, la préparation peut apparaître dans le récapitulatif déjà ouvert. Cette relecture ne démarre pas automatiquement l’enregistrement d’un trajet. La préparation peut préchauffer le récepteur lorsque les conditions le permettent ; accord de l’élève, permission iOS, diagnostic et autorisation du serveur restent nécessaires au départ explicite.
- Un trajet déjà arrêté reste consultable depuis la leçon. Il n’est pas présenté comme un module GPS désactivé.

L’activation n’est pas ajoutée implicitement à l’ouverture d’une école et le réglage d’aucune école existante n’est modifié par cette livraison. Le parcours terrain reste natif ; l’administration du module reste au bureau.

## Références

R41–R46, R74/R80, AP152–AP154 et scénarios T097–T099/T164 de la référence 3.17. Le contrat OpenAPI canonique 3.11.0 et le dossier de conception ne sont pas modifiés. Cette correction complète la limite signalée dans `realisation-onboarding-ecole-20261013.md`.

## Vérification

Web et API : **459 tests API/PostgreSQL**, **254 tests web**, types et builds réussis sur `e8d7b75` ([run](https://github.com/tomyrms/Drivy/actions/runs/39037098306)). **100 contrôles intégrés de connexion/ouverture** réussis sur `0ad37f9`, sources API/web identiques ([run](https://github.com/tomyrms/Drivy/actions/runs/39036951653)). Activation/désactivation, annulation, réauthentification et conflit de version vérifiés dans le navigateur avec un transport synthétique.

[Web publié](deploiement-gps-web-20261017.md), sauvegarde vérifiée avant bascule ; aucun réglage d’école réelle modifié.

Apple : **641 tests Swift dans 61 suites réussis**, dont disponibilité GPS et reprise ([run](https://github.com/tomyrms/Drivy/actions/runs/39037350431)). L’IPA non signée **0.7.0, build 275**, compilée sur `e8d7b75`, est disponible pour iLoader ([run](https://github.com/tomyrms/Drivy/actions/runs/39037098345)). Empreinte SHA-256 : `1e6158eb168bbc89cc20dddf9218eb5814e54e415bd5d0a3e225f70813a48173`. Les commits `df211b4` et `e61eb3f` corrigent uniquement des fixtures/tests ; les sources produit de ces preuves GPS sont identiques. Les corrections ultérieures du compte et des accueils sont suivies dans [leur rapport](audit-parcours-comptes-20261017.md).

Parcours UI Apple : **10/10 sur iPhone et 10/10 sur iPad**, aucun échec ni test ignoré ([run](https://github.com/tomyrms/Drivy/actions/runs/39039437389)). Neuf scénarios GPS/leçon et un guide personnel sont exécutés sur chaque appareil simulé. Le module désactivé, la relecture sans départ automatique, le choix sans GPS et la permission refusée sont couverts. [Départ iPhone sans module](assets/demarrage-lecon-gps-20261017/iphone-gps-desactive-synthetic.png) · [iPad](assets/demarrage-lecon-gps-20261017/ipad-gps-desactive-synthetic.png). La version livrée actuelle est l’IPA **build 277**, avec les corrections de compte décrites dans [le rapport des parcours](audit-parcours-comptes-20261017.md).

La capture GPS physique, la batterie, VoiceOver et la fluidité ressentie sur appareil restent à qualifier. Des scénarios simulés ne prouvent pas ces propriétés.
