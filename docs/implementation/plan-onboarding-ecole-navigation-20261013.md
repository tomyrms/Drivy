# Ouvrir une école avec un guide, puis travailler dans un portail clair

> Plan validé par le porteur le 13 octobre 2026 : réalisation de tous les lots dans l’ordre proposé. Les résultats et limites sont consignés dans `realisation-onboarding-ecole-20261013.md` et `STATUS.md` ; aucune qualification produit ne découle du seul plan.
> Sources examinées à `bb2449a8d180cc3ab6bf2ddf64df68d41a1eb015`. Analyse du dépôt et du retour utilisateur ; aucun écran exécuté, aucun test produit effectué pendant cette préparation.

**Intégration du 13 octobre après validation.** Les [décisions sur les textes](decisions-2026-10-13.md), arrivées sur `master` pendant la réalisation, précisent les parties correspondantes de ce plan : textes proposés communs au guide et aux réglages, un seul texte de confidentialité, informations élèves appliquées immédiatement à la confirmation (aucune date future dans le guide), aucun motif d’approbation demandé ni durée chiffrée de conservation promise. La navigation et la présence de Préparation dans Réglages restent celles du présent plan. Le bilan de réalisation décrit le résultat intégré.

## 1. Résultat attendu

Le porteur génère un lien, le transmet lui-même à une auto-école, et n'a pas à créer son compte ou saisir son nom. Le responsable ouvre le lien sur le web, crée son compte ou se connecte, renseigne son école et suit un parcours de préparation. Drivy lui propose des contenus qu'il adapte et confirme. Il peut interrompre le parcours et reprendre les informations effectivement enregistrées.

Après activation, le portail s'ouvre sur Planning. Les éléments qui manquent à la première leçon deviennent des actions précises. La préparation reste accessible dans Réglages. Les réglages quotidiens et les étapes initiales utilisent les mêmes données et les mêmes règles.

L'ouverture de l'école se fait exclusivement sur le web, y compris depuis le navigateur d'un téléphone. L'app garde son rôle de terrain pour les moniteurs et élèves ; elle oriente vers le web si l'école est encore en préparation.

## 2. Ce qui existe et ce qui doit changer

### Langage visuel et preuves

- Surface auditée : entrée du portail, console de gestion, Préparation, Réglages, Formations et tarifs, navigation des cinq espaces ; impact limité à l'entrée scolaire de l'app.
- Référence visuelle actuelle : `DESIGN.md:103–152`, direction web Bureau et marque La trace, Source Sans 3, palette cobalt/encre/papier. Source réelle des tokens : `apps/web/client/styles.css`. Les anciennes références forêt ne gouvernent plus la palette.
- Règles actuelles : cinq espaces stables, une action principale par vue, textes courts, labels permanents, badges pour l'inhabituel. Les explications nécessaires apparaissent dans l'erreur ou dans un contenu ouvert volontairement.
- Propriétaires : `ManagementConsole`, `ConsoleNavigation`, `SectionNavigation`, `navigation.ts`, formulaires métier et composants `ui.tsx`/`layout.tsx`.
- Exceptions documentées : aucune exception applicable à cette proposition.
- Limite de preuve : la difficulté d'utilisation est rapportée par le porteur ; les chemins et contenus sont vérifiés dans les sources. Aucune nouvelle qualification visuelle n'est revendiquée.

| # | Problème | Preuve et conséquence | Changement proposé | Portée | Confiance |
|---|---|---|---|---|---|
| 1 | L'accueil donne des destinations, sans accompagner la tâche. | `Console.tsx:73` ouvre déjà `apercu` pour DRAFT. `overview.tsx:21–66` rend trois liens, sans lire `setup.currentStep`. `configuration.tsx:75–84` enregistre un avancement vers REVIEW. Le porteur demande un vrai parcours. | Donner à la préparation une composition d'assistant qui enregistre, conduit à l'étape suivante et reprend l'étape utile. | Entrée et préparation web. | Élevée sur le fonctionnement actuel ; efficacité du futur guide à tester. |
| 2 | Les pages d'une catégorie apparaissent ailleurs que sous cette catégorie. | `navigation.ts:9–27` définit les espaces ; `Console.tsx:252–301` sépare rail et onglets horizontaux. Le porteur demande explicitement les sous-pages dans le rail. | Afficher les destinations immédiatement sous la catégorie active. | Navigation desktop et menu web mobile. | Élevée. |
| 3 | Ajouter une formation demande d'assembler des objets techniques. | `formations.tsx:46,84–86` renvoie vers les compétences ; `catalog.tsx:52–162,279–435` expose catégorie libre, clés, révisions et références ; `commerce.tsx:141–295` sépare prestation et conditions. | Préparer une formation à partir d'un permis et d'un contenu proposé, dans une fiche métier commune au guide et à la maintenance. | Formations, tarifs et conditions associées. | Élevée sur la structure ; contenus proposés à qualifier. |

Priorité : le parcours de préparation. Il résout la question « que dois-je faire maintenant ? ». La navigation peut être réalisée en parallèle, mais son déplacement seul ne remplace pas ce parcours.

### Contrats conservés et évolutions explicites

Références : F20 dans `03-fonctionnel/onboarding.md:15–57`, R73–R81 dans `03-fonctionnel/regles-etats.md`, AP165–171 dans `04-technique/api.md` et OpenAPI canonique 3.11.0, E38/E39 dans `02-experience/ecrans.md`, T163–174 dans `05-realisation/tests-recette.md:2231–2371`. Tous ces chemins sont sous `Drivy_Conception_v3_17_2026-09-20/`.

Le dossier prévoit déjà un assistant, la reprise serveur, une confirmation et des contrôles par capacité. Deux évolutions demandées ici doivent être consignées après validation : l'opérateur donne un droit de création par lien avant que l'école existe ; l'accueil scolaire devient exclusivement web. Le dossier livré et son manifeste restent intacts.

L'analyse `analyse-textes-ecole-20261013.md` est une proposition antérieure, pas une décision validée. Ce plan la remplace pour le rangement et l'accueil : **Préparation reste dans Réglages**. La séparation d'un texte GPS, la migration des accords, les durées de purge et les règles sur les mineurs ne sont pas approuvées implicitement par ce plan.

## 3. Le parcours complet

```text
Opérateur : créer un lien → copier → transmettre à l'école
                                         ↓
Web : compte → école → confidentialité → informations élèves
                                         ↓
                     formations → tarifs → relire et activer
                                         ↓
Planning + prochaines actions utiles → première leçon dans l'app
```

### A. Le lien que le porteur remet à une école

Un petit espace réservé à l'opérateur Drivy propose « Créer un lien d'ouverture » puis « Copier le lien ». Aucun nom de responsable, nom d'école ou e-mail destinataire n'est obligatoire. Le porteur l'envoie par WhatsApp, e-mail ou le moyen de son choix ; Drivy n'intègre pas de messagerie pour cette tâche.

Proposition de fonctionnement :

- Un lien autorise la création d'une seule école. Validité initiale proposée : sept jours, réglable côté exploitation.
- La liste opérateur affiche les états Disponible, Utilisé, Expiré, Révoqué, avec création et expiration. Elle permet de révoquer un lien inutilisé et d'en générer un nouveau.
- Ouvrir la page ne consomme rien. Un aperçu WhatsApp, un robot de prévisualisation ou une visite abandonnée ne crée pas d'école.
- La personne se connecte avec OIDC ou crée son compte chez le fournisseur d'identité existant. Le compte utilisé est visible avant confirmation ; elle peut en changer.
- Le clic explicite « Créer mon école » consomme le droit et crée atomiquement l'école DRAFT et son premier administrateur. Deux clics ou deux navigateurs ne produisent pas deux écoles.
- Après cette création, le responsable reprend depuis son compte. Le lien initial ne sert pas de mot de passe et n'est plus nécessaire.
- Un lien expiré ou révoqué donne une page courte avec l'action pour obtenir un nouveau lien. Un lien utilisé ne révèle pas à un autre compte les informations de l'école créée.

Ce droit opérateur est distinct d'une invitation élève/moniteur et d'un rôle ADMIN dans une école. Un administrateur scolaire n'obtient pas le droit de distribuer des ouvertures d'écoles. La possession du lien autorise le compte qui le consomme : il n'est pas lié à un destinataire prédéfini. Cette règle correspond au lien sans nom demandé par le porteur.

### B. Un assistant de six étapes

L'entrée par lien et la connexion précèdent les six étapes. Le titre permanent est « Préparer votre école ». Sur ordinateur : étapes à gauche, formulaire central, actions stables en bas. Sur téléphone : une colonne, « Étape 2 sur 6 » et liste des étapes ouvrable.

| Étape | Ce que fait l'administrateur | Ce que Drivy prépare | Résultat attendu |
|---|---|---|---|
| 1. Votre école | Confirme son nom, nom de l'école, e-mail professionnel ; téléphone facultatif. Répond à « Donnez-vous aussi des leçons ? ». | Compte déjà connecté ; valeurs d'identité réellement disponibles proposées sans découper arbitrairement un nom d'affichage ; français et Europe/Zurich proposés. | École DRAFT créée, ADMIN rattaché, choix de rôle moniteur explicite, reprise possible. |
| 2. Confidentialité | Confirme le contact pour les données et adapte les textes proposés. | Modèle structuré correspondant au fonctionnement réel de Drivy, champs de l'école repris, aperçu exact des textes. | Brouillon complet prêt à relire ; aucune adoption par le bouton Continuer. |
| 3. Informations des élèves | Choisit les seules informations utiles et quand les demander. | Prénom/nom requis ; explications proposées ; autres informations désactivées ou facultatives selon le choix de l'école. Aperçu du formulaire élève. | Politique de champs prête à publier, liée à la bonne notice. |
| 4. Vos formations | Sélectionne les permis enseignés et adapte les compétences et le déroulement proposés. | Liste lisible A, A1, B, etc. ; modèle pédagogique proposé lorsqu'il est disponible et qualifié ; références techniques gérées en interne. | Formations préparées, sans déclarer d'habilitation professionnelle. |
| 5. Vos tarifs | Saisit ses prix, confirme durées et conditions ; peut appliquer les mêmes conditions à plusieurs formations. | Libellés et durées proposés à confirmer ; catégories déjà sélectionnées ; champs commerciaux simples. | Tarifs cohérents avec les formations choisies, sans montant inventé. |
| 6. Vérifier et démarrer | Relit l'école, les textes, les formations et tarifs retenus ; corrige les manques et confirme l'activation. | Résumé des choix, aperçu des contenus adoptés, liens « Modifier » vers l'étape exacte ; distinction entre indispensable et reporté. | Activation confirmée durablement et suite adaptée à la situation réelle. |

Précisions :

- La création à l'étape 1 ne publie rien. Les choix suivants restent des brouillons tant qu'ils ne sont pas adoptés ou publiés explicitement.
- ADMIN et INSTRUCTOR restent deux rôles. « Oui, je donne aussi des leçons » conduit à une attribution explicite contrôlée dans la transaction de création. Le premier ADMIN reçoit le grant `CONFIGURE_CATALOG` nécessaire au parcours commercial, sans ajout global des autres grants ni droits opérateur. La commande actuelle de changement de rôle AP08 exige une école ACTIVE : ne pas l'assouplir globalement pour contourner cette création initiale.
- Le contact données reprend l'e-mail professionnel sauf modification volontaire. Aucune donnée d'une autre école n'est copiée automatiquement.
- Le téléphone, le logo, une équipe complète, les cours collectifs et les packs ne conditionnent pas l'activation. Logo, packs et cours ne sont pas présentés comme des fonctionnalités configurables dans ce lot lorsqu'ils ne sont pas livrés.
- Informations élèves, formations et tarifs peuvent être préparés plus tard. Le parcours normal les propose pour rendre l'école utile rapidement ; les reporter ne force pas à saisir de fausses valeurs.
- Le choix des informations élèves garde le catalogue et les finalités autorisées. « Non demandé », « Facultatif », « À l'inscription », « Avant une leçon » sont présentés selon les combinaisons réellement permises ; les exigences particulières restent accessibles si elles existent. La photo ne devient jamais obligatoire.
- Le modèle minimal des informations élèves se confirme sans rédiger une justification à partir d'un champ vide. Sa date d'effet initiale est proposée à l'activation ; une école déjà active conserve le choix explicite de la date pertinente.
- L'étape Confidentialité présente du contenu utile, avec aperçu et édition, sans paragraphes d'aide ajoutés sous toutes les sections.

### C. Sauvegarde et navigation dans le guide

Action principale : « Enregistrer et continuer ». Action secondaire : « Retour ». « Enregistrer et quitter » permet une interruption assumée. « Plus tard » n'existe que sur les étapes reportables.

Le brouillon serveur accepte un contenu partiel valide pour son type ; il n'applique pas les exigences d'une publication complète à chaque sauvegarde. Les contrôles requis pour poursuivre ou activer nomment les champs manquants. L'interface indique Enregistrement, Enregistré ou l'erreur réelle ; elle ne confirme rien sur le seul clic.

Revenir à une étape ne perd pas les données. Une fermeture après sauvegarde, une reconnexion ou un autre navigateur retrouvent la dernière version confirmée. Une saisie non envoyée reste seulement dans l'onglet ; quitter avec cette saisie demande de l'enregistrer ou de la perdre explicitement. Aucune promesse de récupération de frappes non enregistrées.

Les étapes déjà traitées sont accessibles. Une étape dépendante indique précisément ce qui manque. Une modification qui rend une étape suivante incohérente la marque « À revoir » et montre la dépendance concernée, sans tout remettre à zéro.

### D. Après l'activation : accompagner la première leçon

L'activation ouvre le portail. Elle ne signifie pas que l'école peut déjà planifier n'importe quelle leçon, démarrer un trajet ou publier un cours.

Sur l'Agenda, un bloc compact « Pour votre première leçon » affiche la prochaine action, puis permet d'ouvrir la liste complète. Exemples selon les manques réels : terminer une formation, ajouter son tarif, donner le rôle moniteur, définir les disponibilités, inviter un premier élève, compléter son dossier, ouvrir sa formation et l'affecter à un moniteur.

Chaque action conduit au bon formulaire avec l'école, la catégorie ou le membre déjà sélectionné. Après confirmation, le serveur recalcule ce qui manque. Un souci de disponibilité apparaît dans Planning ; il ne fait pas passer une formation complète pour inachevée.

Une invitation envoyée n'est pas une invitation acceptée. Son simple envoi n'inscrit ni n'affecte l'élève. Le mécanisme existant peut porter une formation et un moniteur explicitement choisis : à l'acceptation, il les relit et réalise le rattachement si les conditions sont encore remplies. La préparation de la première leçon suit ces résultats réels, y compris une formation qui n'a pas pu s'ouvrir.

Le bloc peut être réduit pour la session ; les actions restent dans Réglages → Préparation. Il disparaît quand la préparation du premier usage est réellement suffisante. Une nouvelle difficulté métier apparaît ensuite à l'action concernée, sans relancer tout l'onboarding.

Une fois l'école activée, « Ouvrir l'app » ou un lien/QR vers son accès peut être proposé selon la distribution réellement disponible. Ne pas inventer une disponibilité App Store ou une procédure d'installation grand public : la distribution actuelle est une IPA d'essai signée/installée par le porteur.

## 4. Des contenus proposés qui font gagner du temps

### Catalogue de modèles

Créer un petit catalogue versionné, revu, propre à cette tranche : catégories de permis, base pédagogique, exemples de déroulement, informations demandées, structure de confidentialité et de conditions commerciales. Les données de seed, de démonstration et du homelab ne deviennent pas les textes d'une vraie école.

Chaque modèle a un identifiant, une version, une langue, sa portée et les données à confirmer. Les variables connues sont reprises depuis l'école. Les variables inconnues restent des champs à renseigner ; aucun texte « [à compléter] » ne peut être publié par inadvertance.

La suggestion ne vaut pas adoption. La confirmation porte sur le contenu exact présenté, modifié ou non, et reste traçable. Le rôle du modèle est de réduire la rédaction, pas d'accorder un consentement GPS ou de certifier une conformité juridique.

| Proposé par Drivy | À confirmer ou renseigner par l'école |
|---|---|
| Catégories et intitulés de formations disponibles | Catégories réellement enseignées |
| Compétences pédagogiques et déroulement de départ | Programme retenu et adaptations |
| Libellés, unités et durées de leçon proposées | Durées réellement vendues et prix réels |
| Explications des champs du profil | Utilité et moment de collecte |
| Structure des textes et informations techniques vérifiées | Coordonnées, pratiques propres à l'école, choix et textes finaux |
| Organisation d'une condition d'annulation | Délai, frais et exceptions réellement appliqués |

Les modèles doivent décrire le partage automatique des leçons réalisées tel qu'implémenté, tout en excluant les notes privées du moniteur des données montrées à l'élève. Ils ne doivent pas promettre une suppression automatique, une durée de conservation ou un traitement de mineurs que le service n'applique pas.

Les règles réglementaires des permis et les textes destinés à des personnes réelles doivent être vérifiés avant mise à disposition. Les contenus non qualifiés peuvent être travaillés comme exemples, mais ne constituent pas un jeu de modèles prêt à publier pour des écoles réelles. C'est une dépendance de contenu du lot, pas une raison de bloquer la réalisation du guide et de ses tests synthétiques.

Une évolution du modèle n'écrase jamais les textes déjà adaptés ou adoptés par une école. L'administrateur peut examiner une nouvelle proposition puis choisir de l'adopter. Le catalogue des catégories et celui des modèles sont distincts : l'absence d'un modèle ne supprime pas une catégorie prise en charge. Elle permet une préparation manuelle de cette catégorie, sans inventer son programme ; les catégories déjà présentes dans une école sont conservées.

### Conditions et formations : une seule saisie métier

Dans l'interface, une formation devient une fiche « Permis B » regroupant programme, déroulement et tarifs associés. Cette fiche peut contenir plusieurs offres, durées et tarifs ; elle n'impose pas une offre unique par catégorie. « Ajouter une formation » utilise le même parcours que l'étape 4. L'administrateur ne crée plus successivement un référentiel, une procédure puis une offre pour atteindre cet objectif.

« Ajouter un tarif » pour une leçon individuelle demande la formation/catégorie, le libellé, la durée et le prix, puis les conditions associées. Les autres types de prestations déjà pris en charge restent disponibles avec leurs contraintes propres, sans leur imposer une catégorie de permis. Le montant n'est jamais saisi à nouveau dans une autre rubrique. Les clés techniques sont générées ; l'historique et les références exactes restent consultables dans les détails.

Les conditions communes se gèrent dans Formations et tarifs → Conditions. Leur annulation est réutilisée là où elle s'applique. Les exceptions par formation restent explicites. Cette unification de saisie conserve les versions métier et les conditions attachées aux engagements existants ; elle ne réécrit pas l'historique.

Pour la première configuration, le motif technique peut être « Première configuration de l'école », associé au vrai geste de confirmation. Une modification ultérieure ne reçoit pas un motif fictif ; les exigences d'audit métier demeurent. Le plan ne supprime pas globalement les motifs, brouillons ou approbations.

## 5. La navigation après préparation

Cliquer une catégorie ouvre toujours sa première page et déploie ses sous-pages directement dessous. Une seule catégorie est dépliée. Les liens profonds ouvrent leur catégorie et marquent la destination courante ; les retours navigateur fonctionnent comme aujourd'hui.

| Catégorie | Première page | Sous-pages visibles sous la catégorie active |
|---|---|---|
| Planning | Agenda | Agenda · Disponibilités · Absences |
| Élèves | Dossiers | Dossiers · Invitations · Trajets |
| Équipe | Membres | Membres et accès · Invitations |
| Formations et tarifs | Formations | Formations · Tarifs · Conditions |
| Réglages | École | École · Confidentialité · Informations élèves · Signalements · Préparation |

Exemple avec Planning ouvert :

```text
Planning
    Agenda                 ← page courante
    Disponibilités
    Absences
Élèves
Équipe
Formations et tarifs
Réglages
```

Les sous-pages sont des liens de navigation. Cliquer à nouveau Planning ramène à Agenda. Les clics modifiés pour ouvrir un autre onglet restent natifs. Le titre du contenu demeure, mais les mêmes destinations ne sont plus répétées dans une seconde barre horizontale sur ordinateur.

Disponibilités et Absences deviennent deux pages distinctes qui réutilisent les lectures et commandes actuelles. Les anciens liens `disponibilites`, les filtres de moniteur et le retour depuis Équipe continuent de fonctionner.

Les éditeurs approfondis de programme ou de conditions conservent un fil d'Ariane et un retour à la formation ou au tarif. Les filtres pertinents sont conservés entre sous-pages ; un clic sur une catégorie repart de son accueil sans sélection héritée d'un autre contexte. Les invitations élèves et équipe gardent leur audience distincte.

Sur web mobile/tablette étroite, le bouton Menu ouvre la même hiérarchie, avec la catégorie active dépliée. Le libellé d'une catégorie ouvre sa première page et ferme le menu ; un bouton chevron distinct développe ses sous-pages sans naviguer. Une seule catégorie est dépliée à la fois. Choisir une sous-page ferme le menu ; Échap restitue le focus au bouton Menu. La barre horizontale des destinations locales disparaît aussi sur mobile. Le chevron possède un nom accessible et annonce son état déplié/replié.

## 6. Réglages après l'onboarding

- **École** : identité, contact et état de l'école.
- **Confidentialité** : textes adoptés, contact données, aperçu, modification et historique. Les versions restent techniques, accessibles sans envahir le résumé.
- **Informations élèves** : tableau simple des informations demandées, aperçu du formulaire et modification de la politique réellement applicable.
- **Signalements** : configuration actuelle, sans refonte de ce parcours.
- **Préparation** : état de la configuration et prochaines actions ; lien pour reprendre une étape inachevée. Une école active ouvre la tâche choisie, sans repasser par « activer ».

Le guide et les réglages utilisent les mêmes éditeurs de contenu et validations. Il ne doit pas y avoir deux textes de confidentialité, deux prix ou deux états d'avancement concurrents.

Lorsqu'une école active change sa notice, l'interface doit présenter les conséquences réelles sur les accords GPS et les captures avant l'adoption. Le comportement serveur existant peut révoquer les captures autorisées ; le nouveau rangement ne doit pas masquer cet effet. Séparer la notice GPS ou changer cet effet demande un chantier distinct explicitement arbitré.

## 7. Règles d'entrée, reprise et écoles existantes

| Situation | Destination et comportement |
|---|---|
| Lien neuf, compte non connecté | Page d'ouverture puis OIDC ; lien conservé de façon sûre pendant l'aller-retour. |
| Compte sans école et sans droit de création | Accès au compte/rejoindre une école ; aucun bouton qui crée une école sans autorisation. |
| École DRAFT avec brouillon | Reprise de la dernière étape utile, sans présentation préalable des tableaux de gestion vides. |
| École DRAFT sans progression exploitable | Calcul des éléments déjà renseignés et ouverture du premier manque ; aucune remise à zéro. |
| École ACTIVE existante | Planning à l'entrée habituelle ; accès direct respecté. Aucune obligation de rejouer le guide. |
| École ACTIVE avec manques pour planifier | Planning et actions ciblées ; pas de nouvelle activation. |
| Compte administrant plusieurs écoles | Choix d'école ; le nouveau lien crée un contexte distinct après confirmation explicite. |
| Accès révoqué ou école archivée | État spécifique ; arrêter les écritures et retirer les données auxquelles la personne n'a plus droit. |

Les écoles existantes ne reçoivent pas automatiquement les modèles. Une migration ajoute la structure de brouillon et conserve données, versions, adhésions et engagements. Aucun modèle ne remplace un texte ou tarif existant sans action de l'école.

## 8. Travail technique nécessaire

### 8.1 Autorisation de création

Le script `infra/deploy/provision-school.mjs:225–241` est un bootstrap de base vide, pas un service d'accueil multi-écoles. Construire une tranche dédiée, avec permission opérateur authentifiée au serveur, émission/révocation et consommation du lien. Ne pas utiliser un rôle scolaire fourni par l'interface ou un simple claim non qualifié comme autorisation opérateur.

Stocker l'empreinte du secret, son expiration, son auteur et le résultat de consommation. Garder le secret hors des journaux, URL de requête, analytics et artefacts CI. Réutiliser le principe du fragment nettoyé et de la session BFF pour le passage OIDC ; permettre une reprise sûre si cette session expire. Les aperçus/GET ne mutent rien.

La transaction de consommation crée ou retrouve la personne selon son identité OIDC, puis l'école DRAFT et le premier membership ADMIN avec `CONFIGURE_CATALOG`, complété par INSTRUCTOR si ce choix a été explicitement confirmé à l'étape 1. Elle initialise la préparation, consomme le lien et conserve un reçu idempotent. Une réponse perdue permet au même acteur de retrouver le résultat ; une autre identité n'accède pas à ce reçu. Une modification ultérieure des rôles utilise les contrôles de la gestion des accès après activation, sans déduire un rôle de la seule progression du guide.

L'invitation scolaire actuelle est un autre objet : elle exige une école active et une notice. Réutiliser les protections pertinentes des invitations et du BFF, pas leurs préconditions métier.

La configuration d'identité de déploiement autorise actuellement l'inscription mais désactive la vérification d'e-mail et la récupération par e-mail (`infra/deploy/drivy-realm.json:8–9,76–77`). Avant l'ouverture aux nouvelles écoles, qualifier l'inscription, le contrôle du contact et la récupération du compte avec le fournisseur existant et un envoi réel. Ne pas prétendre que le contact est vérifié à partir de la seule chaîne saisie, ni reconstruire un système de mots de passe dans Drivy. Les comptes existants doivent conserver un accès utilisable.

### 8.2 Un brouillon serveur, distinct des données adoptées

`school-setup.ts:151–159` conserve seulement des marqueurs de progression. `PUT data-policy` adopte les textes ; la politique initiale DRAFT est vide. Il faut donc un brouillon versionné de configuration, à schéma borné, pour enregistrer les contenus de l'assistant avant adoption.

Étendre le propriétaire du setup avec ce brouillon et ses métadonnées plutôt que créer une table par étape. Réutiliser les ressources métier existantes lorsqu'elles savent déjà porter le brouillon nécessaire. Les textes adoptés, politiques publiées, offres et tarifs restent les données de référence ; le brouillon ne devient pas une seconde configuration active.

Le serveur conserve version, auteur, date, provenance de modèle et contenu réellement choisi. Chaque sauvegarde contrôle le droit ADMIN, la portée école, les champs autorisés et la version. Un conflit ne remplace jamais silencieusement le travail de l'autre administrateur. Les données de formulaire ne vont pas dans localStorage, sessionStorage ou les URLs.

La projection de préparation distingue étapes à faire, brouillons enregistrés, éléments à revoir, éléments en vigueur et reports volontaires. Elle calcule l'état depuis les références réelles et les dates d'effet. Une politique publiée pour demain n'est pas prête pour aujourd'hui. Les marqueurs `completedSteps` ne constituent jamais une autorisation.

### 8.3 Revue finale et activation

Prévoir une commande bornée d'application du setup initial pour éviter une cascade fragile de clics et d'appels depuis le navigateur. Le résumé est construit depuis une version serveur du brouillon et les références effectivement relues ; les erreurs pointent vers les champs/étapes.

Le bouton final doit nommer l'engagement : « Adopter les textes et activer l'école », avec présentation des autres configurations sélectionnées et confirmation explicite du contenu exact. Une modification après revue invalide la confirmation correspondante. Sauvegarder le brouillon, ouvrir l'aperçu ou cliquer Continuer ne valent jamais adoption.

Au serveur : vérifier à nouveau identité, membership/grants, version du brouillon, version école/configuration et modèles ; adopter/publier les seuls éléments explicitement retenus ; créer les versions liées et activer l'école dans une transaction ; conserver un reçu idempotent. Extraire et réutiliser les validations métier actuelles, sans appeler les routes HTTP les unes après les autres. Toute erreur annule ce changement global et conserve le brouillon.

L'activation minimale garde les prérequis R74. Un tarif reporté reste absent, une formation non confirmée reste non disponible ; ces éléments ne sont pas remplis arbitrairement pour faire passer un contrôle. L'application des choix initiaux ne crée ni élève, ni rendez-vous, ni achat, ni accord GPS.

Point à traiter dans le compositeur : l'offre actuelle exige `defaultPriceCents`, et le formulaire historique crée une nouvelle offre avec zéro implicite (`catalog.tsx:335–339`). Une formation dont le prix est reporté reste donc dans le nouveau brouillon, sans création d'une offre artificiellement tarifée. À confirmation du prix, la même saisie alimente les champs de compatibilité nécessaires et la prestation commerciale réelle. Ne pas réutiliser telle quelle l'écriture du formulaire actuel ; toute séparation ultérieure du prix hérité doit être contractualisée et testée.

Cette orchestration est une extension à contractualiser ; les routes de maintenance existantes et AP168 restent compatibles. L'activation ne dépend pas de l'acceptation future d'une invitation d'équipe ou de la disponibilité d'un appareil GPS.

### 8.4 Propriétaires à réutiliser et changements prévus

| Zone | Fichiers actuels | Changement et vérification |
|---|---|---|
| Entrée web et BFF | `apps/web/client/main.tsx`, `App.tsx`, `server/app.ts`, sessions/connexion/invitation et `server/school-routes.ts` | Routes d'ouverture et guide, retours OIDC strictement autorisés, commandes dédiées et mêmes protections CSRF/session. Vérifier anonyme, nouvel acteur et compte existant. |
| Navigation | `console/Console.tsx`, `navigation.ts`, `route.ts`, `sections.ts`, `styles.css` | Arbre sous catégorie active, nouvelles destinations confidentialité/absences, anciens liens compatibles. Vérifier filtres, audiences, clavier et retour. |
| Assistant et réglages | `console/overview.tsx`, `configuration.tsx`, `profile-fields.tsx`, `context.ts`, `draft-model.ts` | Extraire les éditeurs réutilisables, composer le guide et la maintenance, retirer le bouton d'avancement manuel. Vérifier une seule source de données. |
| Catalogue | `console/formations.tsx`, `catalog.tsx`, `commerce.tsx`, API `catalogue.ts`/`lesson-setup.ts` | Parcours Ajouter une formation et Ajouter un tarif avec modèles ; détails versionnés conservés. Vérifier cohérence catégories/durées/prix/conditions. |
| Planning | `console/availability.tsx`, `agenda.tsx` | Séparer les deux vues horaires/absences ; afficher la prochaine action utile sans recopier tout le tableau de préparation. |
| Commandes | `client/command-core.ts`, `command-store.ts`, `school-api.ts`, API `commands.ts` | Enregistrer/reprendre les nouvelles commandes et leurs reçus ; conserver AP72, If-Match et états incertains. |
| Backend setup | `apps/api/src/school-setup.ts`, `profiles.ts`, `lessons.ts`, migrations et contrats implémentés | Brouillon, projection de préparation, application atomique ; réutiliser `schoolPlanningBlockers` et distinguer les manques par domaine. |
| Identité/opérateur | BFF et routes API dédiées, configuration de déploiement OIDC | Émission/consommation autorisée sans privilège de superutilisateur dans le navigateur ; récupération du résultat et du compte. |
| App Apple | `SchoolUI/SchoolHomeView.swift`, `SchoolRootView.swift`, `SchoolAccountComponents.swift`, `Identity/AppConfiguration.swift` | État DRAFT avec reprise web, puis relecture du statut/droits au retour ; aucun assistant scolaire natif. |

Les chemins `console/…` ci-dessus sont sous `apps/web/client/`. Les chemins `client/…` et `server/…` sont sous `apps/web/`. `App.tsx` désigne `apps/web/client/App.tsx` ; les noms courts `navigation.ts`, `route.ts`, `sections.ts`, `context.ts`, `draft-model.ts`, `configuration.tsx`, `profile-fields.tsx`, `catalog.tsx`, `commerce.tsx` et `agenda.tsx` sont sous `apps/web/client/console/`. `styles.css` est sous `apps/web/client/`. Les chemins Swift sont sous `apps/ios/Drivy/` ; `SchoolRootView.swift` et `SchoolAccountComponents.swift` sont dans son dossier `SchoolUI/`.

Réemployer `SectionHeading`, `LoadState`, `OutcomeNotice`, `ConfirmDialog`, les champs `ui.tsx`, `useCommandRunner` et le panneau de commande incertaine. Garder les tokens `--canvas`, `--surface`, `--text`, `--muted`, `--accent`, `--space-*` et `--radius-*`. `SplitView` sert à la maintenance, pas à imposer un panneau vide au guide.

Un composant de progression du guide est justifié : aucun composant actuel ne relie étapes, brouillon serveur, reprise et revue. Il appartient à la préparation web et ne devient pas un framework général de formulaires. L'éditeur de confidentialité et le compositeur de formation sont partagés entre leur étape et leur réglage correspondant.

### 8.5 Impact natif limité et explicite

L'app a déjà « Gérer l'école → Sur le web ». Elle peut pourtant afficher les onglets du personnel pour une école DRAFT ou un ADMIN seul (`SchoolHomeView.swift:38`). Ajouter une garde avant les onglets : ADMIN DRAFT → « Continuer la préparation sur le web » ; non-ADMIN DRAFT → attente claire ; ARCHIVED → état propre.

Le lien utilise HTTPS et l'identifiant scolaire, sans transporter de jeton. Au retour du navigateur, relire droits et statut. Pour ADMIN seul d'une école active, l'entrée renvoie clairement à la gestion web ; ADMIN + INSTRUCTOR reçoit les fonctions terrain correspondantes.

L'accueil individuel STAFF/STUDENT existant est distinct de l'ouverture de l'école. Il demeure, avec une garde ACTIVE avant sa présentation automatique pour ne pas recouvrir l'écran de reprise web. Les consentements GPS et permissions appareil restent demandés au moment utile.

## 9. Réalisation par lots après validation

| Lot | Livraison vérifiable | Dépendance |
|---|---|---|
| 1. Navigation | Catégories et sous-pages dans le rail/menu ; Disponibilités et Absences séparées ; rangement École/Confidentialité/Informations élèves. | Peut avancer indépendamment du backend d'ouverture. |
| 2. Lien et création | L'opérateur génère un lien ; un nouveau compte crée une seule école DRAFT et retrouve son accès. | Contrat, droits opérateur et transaction PostgreSQL. |
| 3. Guide et reprise | Étapes 1–3, brouillon serveur, erreurs utiles, reprise après fermeture, revue et activation minimale réelles. | Lot 2 ; données synthétiques jusqu'à qualification des modèles. |
| 4. Formations et tarifs | Étapes 4–5 et mêmes parcours en maintenance, modèles versionnés, revue groupée des choix. | Infrastructure de brouillon/commandes du lot 3 ; contenus qualifiés pour usage réel. |
| 5. Premiers usages | Checklist issue des manques réels, chemin équipe/disponibilités/élève/formation/affectation ; entrée native adaptée. | Lots précédents ; qualification réelle des invitations par e-mail pour le personnel. |
| 6. Qualification | Parcours navigateur complet, PostgreSQL, CI Apple, migration sur copie, rapport de limites et recette avec un utilisateur. | Ensemble intégré. |

Avant le lot 1, ouvrir une branche de travail `codex/…` et relever l'état actuel ; ne pas incorporer les fichiers de skills, patches ou analyses personnels non liés. La validation de ce plan permet ensuite d'avancer sur ces lots sans redemander une autorisation pour chaque écran réversible.

L'invitation d'équipe réutilise le parcours par e-mail existant, qui accepte les rôles ADMIN/INSTRUCTOR avec les droits appropriés ; c'est l'invitation par code qui est limitée à LEARNER (`invitations.ts:21–27,60`). Le lot 5 doit qualifier la remise du message et l'identité avec e-mail vérifié nécessaires à son acceptation. Une invitation émise ne valide jamais une disponibilité ou une affectation. Ne pas étendre les codes élèves au personnel pour contourner ce parcours.

## 10. Recette et critères d'acceptation

### Parcours produit

1. Le porteur obtient un lien sans saisir l'identité du responsable ; une prévisualisation ne le consomme pas.
2. Un nouveau responsable crée son école sans intervention dans la base ou échange de mot de passe avec le porteur.
3. Il comprend sa prochaine action à chaque étape ; une erreur le ramène au champ concerné.
4. Un indépendant peut préparer une formation et son tarif sans éditer une clé, une révision ou un identifiant de politique.
5. Les prix et les pratiques de l'école ne sont pas inventés. Les textes proposés sont relus et adoptés explicitement.
6. Après sauvegarde et fermeture, un autre navigateur reprend le même brouillon et l'étape utile.
7. Une école peut être activée sans packs, cours collectifs, photo, équipe complète ou permission GPS. Les capacités incomplètes restent identifiées honnêtement.
8. Le premier moniteur peut suivre les actions jusqu'à une leçon réellement planifiable pour un élève ; le GPS reste facultatif.
9. Cliquer Planning ouvre Agenda et affiche Agenda/Disponibilités/Absences sous Planning. Même logique dans les autres espaces.
10. Une école active existante garde ses données et son entrée habituelle ; les modèles ne réécrivent ni contrats ni accords existants.

### Cas techniques et erreurs

- Lien expiré/révoqué/utilisé ; double clic ; deux comptes concurrents ; réponse perdue avant/après commit ; reprise sans la session BFF d'origine.
- Identité OIDC nouvelle/non liée ; compte déjà membre d'une autre école ; contact non vérifié ; récupération de compte ; aucun privilège opérateur obtenu par rôle scolaire.
- Brouillon partiel, conflit entre deux administrateurs, modification des droits, publication future, modèle actualisé, contenu modifié après revue.
- Une commande incertaine ne devient jamais un succès ou une nouvelle opération ; conservation de la clé et vérification du reçu.
- Activation atomique : aucune moitié de publication, aucun doublon ; rollback réel sur échec intermédiaire.
- École DRAFT incapable de vendre/publier ; historique des écoles actives préservé ; changement de notice présentant ses conséquences réelles.
- Navigation par URL, retour/avance, rechargement, nouvel onglet, changement d'école, audiences d'invitations et sélection de catégorie.
- Desktop, tablette et téléphone web, clair/sombre, zoom, clavier et lecteur d'écran ; focus au titre/erreur, progression annoncée, menu utilisable sans souris.
- Swift/UI Apple : DRAFT ADMIN, DRAFT non-ADMIN, ACTIVE ADMIN seul, ACTIVE ADMIN-INSTRUCTOR, ARCHIVED, retour du web et échec de relecture ; aucun accueil personnel superposé au renvoi web.

### Moyens de vérification

Réutiliser T163–174 en adaptant T167 à la reprise sur un autre navigateur web pour la configuration scolaire ; conserver les tests de reprise des accueils personnels séparément.

- `npm run typecheck --prefix apps/api` ; `npm test --prefix apps/api` avec vraie PostgreSQL provisionnée pour les tests d'intégration.
- `npm run typecheck --prefix apps/web` ; `npm test --prefix apps/web` ; `npm run build --prefix apps/web`.
- Étendre les tests `console-route`, `console-access`, `school-bff`, `command-core` et les tests d'intégration métier ; ajouter les cas d'ouverture, de brouillon et de transaction.
- Ajouter une recette navigateur automatisée contre OIDC, BFF, API et PostgreSQL de test. Le dépôt n'a pas aujourd'hui cette preuve complète en CI ; la bibliothèque de test choisie sera verrouillée.
- Les vues synthétiques de `apps/web/test/visual.tsx` servent à relire les états et dimensions, sans prétendre vérifier la persistance.
- `.github/workflows/refonte-ios.yml` et la CI Apple pour Swift/UI ; IPA non signée si nécessaire, installation par le porteur. Aucun résultat GPS/batterie/VoiceOver physique déduit du simulateur.

Aucun de ces tests n'a été exécuté pendant la rédaction de ce plan. Leur réussite sera consignée lot par lot dans `STATUS.md`, avec les limites restantes. Une revue documentaire ne qualifie pas le produit.

## 11. Bornes et points d'arrêt

Inclus : ouverture contrôlée d'écoles, guide web, contenus proposés, brouillons/reprise, navigation, maintenance plus simple des formations/tarifs, prochaines actions et renvoi natif cohérent.

Hors de ce plan : inscription publique sans lien, abonnement/facturation SaaS de Drivy, refonte Planning/Élèves/Équipe hors navigation et dépendances du premier usage, paiements/packs/cours non livrés, reprise de l'ancien projet, refonte de l'app terrain, consentement GPS automatique, migration des accords GPS ou nouveau régime de purge/mineurs.

Arrêter le lot concerné et exposer le problème concret si le contenu proposé affirme un traitement non implémenté, si une règle métier doit être changée pour rendre le parcours possible, si une migration ne peut préserver les engagements/accords, ou si les permissions opérateur ne peuvent être établies avec l'identité existante. Continuer les lots indépendants.

Le déploiement public n'est pas implicite. Une livraison homelab suit l'autorisation existante : sauvegarde de base avant chaque déploiement, migration éprouvée et procédure de retour. Aucun déploiement n'est effectué pendant la phase de planification.

## 12. Décisions soumises au porteur

La validation demandée porte sur cet ensemble : lien opérateur à usage unique sans saisie préalable ; six étapes web avec vraie reprise ; modèles adaptables et adoption explicite ; activation minimale suivie d'actions pour la première leçon ; sous-pages sous la catégorie active ; Réglages réorganisés et formation préparée dans une fiche métier.

Après validation, enregistrer ces décisions et les écarts à F20 dans `docs/implementation/`, mettre à jour les règles web courantes et les contrats d'implémentation, conserver l'OpenAPI canonique 3.11.0 et la livraison de conception intacts. L'entrée « Préparation dans Réglages » reste vraie en maintenance ; elle ne décrit plus la composition de la première arrivée DRAFT.
