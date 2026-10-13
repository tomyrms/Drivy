# Textes de l'école : analyse et proposition

> 13 octobre 2026 · CC1.1 · analyse seule : aucun code, aucune base, aucun déploiement modifiés.
> Base lue : `origin/master` à `bb2449a` (release `e2f78a1` déployée). Une seule lecture du homelab, en transaction `READ ONLY` (§ 3.1).

Légende des sources : **[code]** vérifié dans le dépôt, **[base]** vérifié sur le homelab en lecture, **[dossier]** dossier de conception 3.17, **[impl]** `docs/implementation/`, **[supposé]** déduction non vérifiée.

---

## 0. En bref

Drivy porte aujourd'hui **sept familles de textes ou de règles**. L'administrateur doit les écrire à la main, chacune avec son propre cycle de version. Elles sont rangées dans **trois espaces du web** (Réglages, Formations, Tarifs) et **l'app les affiche sous au moins six noms**. Trois effets de bord sont sérieux :

1. Adopter une nouvelle version de l'information **coupe tous les trajets GPS en cours** de l'école et **rend caducs tous les accords GPS** déjà donnés **[code]**.
2. Le serveur accepte un texte d'un seul caractère. L'école d'essai a adopté « ddd » et « wssd » : c'est pour ça que l'écran « Information et conservation » paraît vide **[base]**.
3. Le texte de conservation est **déclaratif** : aucune purge automatique ne l'applique **[code]**.

Les élèves mineurs n'ont **aucun traitement** dans le code **[code]**. Le dossier de conception le demande pourtant avant tout pilote **[dossier]**.

**Cadre juridique :** le dossier vise le **droit suisse** (nLPD, PFPDT), pas le RGPD européen. Les catégories de permis suivent l'OAC et le domaine est en `.ch` (`04-technique/securite-vie-privee.md`) **[dossier]**. Le RGPD ne s'appliquerait qu'à des élèves ciblés dans l'UE. Tout ce qui suit sur le droit reste à faire confirmer par un juriste.

---

## 1. Inventaire

### 1.1 Vue d'ensemble

| # | Élément | Créé où | Montré où | Qui le voit | Ce qu'il bloque ou déclenche | Versionnage | Table · route · écran |
|---|---|---|---|---|---|---|---|
| T1 | **Information des personnes** (`noticeText`) | Web, Réglages › École › « Information et conservation » | App : invitation, accueil, Profil, Accord GPS, préparation du trajet | Admin (toutes versions, brouillon compris) ; tout membre (dernière version adoptée) ; invité (version liée à son invitation) | **Activation** de l'école ; **invitations** ; **choix GPS** ; informations demandées ; nouvelle version ⇒ trajets coupés et accords caducs | Insertion `version+1`, jamais réécrite ; la v1 est vide et non adoptée | `school_data_policy` (002, 004) · `GET/PUT /v1/schools/:id/data-policy`, `GET …/recording-notice` · `configuration.tsx`, `SchoolJoinView`, `SchoolOnboardingView`, `SchoolProfileView`, `SchoolRecordingChoiceView/Inline`, `SchoolCapturePreparationView` |
| T2 | **Conservation des données** (`retentionText`) | Même formulaire, même adoption que T1 | Mêmes écrans que T1, parfois collé à T1 | Comme T1 | Comme T1 (adopté avec T1) | Comme T1 | Même ligne de table |
| T3 | **Contact pour les données** (`contactEmail` de la politique) | Même formulaire | Sous T1/T2 dans l'app | Comme T1 | Requis pour adopter | Comme T1 | Même ligne ; distinct de l'e-mail de l'école |
| T4 | **Accord GPS** de l'élève (`recording_choice`) | App : l'élève (`SELF`) ou le moniteur pour lui (`RECORDED_VERBAL`), général ou pour une leçon | App : Profil élève « Accord GPS », fiche élève, démarrage du trajet. **Absent du web** | Élève ; moniteur affecté ; admin via l'API (aucun écran web) | **Seule condition d'un trajet GPS** : statut `ALLOWED` **et** attaché à la version **actuelle** de T1 | Insertion `version+1` par élève ; le refus de l'élève (`SELF`) prime sur un accord oral | `recording_choice` (008) · `GET/POST …/learners/:id/recording-choice` · `SchoolRecordingChoice*` |
| T5 | **Informations demandées aux élèves** (`profile_field_policy`) | Web, Réglages › « Informations élèves » | App : accueil (« Pourquoi ces informations ? »), Profil ; web : dossier élève (champs manquants) | Admin (tout) ; membres (version en vigueur) | **Planification** des leçons (`PROFILE_POLICY_NOT_READY`) ; profil, accueil, complétude du profil | Brouillon → publication avec date d'effet ; liée à une version de T1 | `profile_field_policy` (004) · `GET/POST …/profile-field-policies`, `…/:id/publish` · `profile-fields.tsx`, `SchoolOnboardingView`, `SchoolProfileView` |
| T6 | **Déroulement de la formation** et **conditions d'annulation**, par catégorie (`school_policy_version`) | Web, Formations › « Déroulement et annulation » | App : planification (boutons « Procédure », « Annulation ») | Admin ; membres liés à une offre active | Activer une **offre**, donc planifier | `version+1` par catégorie ; case « Approuver » + « Motif » | `school_policy_version` (005) · `POST …/policy-versions` · `catalog.tsx`, `SchoolPlanningView` |
| T7 | **Conditions commerciales** (`commercial_terms_version`) | Web, Tarifs › « Conditions commerciales » | App : planification (« Conditions tarifaires ») ; la leçon garde la version acceptée | Admin ; moniteur à la planification | Un **tarif** de leçon exige des conditions approuvées, donc planifier | `version`, dates de validité, case « Approuver » + « Motif » | `commercial_terms_version` (006) · `GET/POST …/commercial-terms` · `commerce.tsx`, `SchoolPlanningView` |

Autres éléments liés, sans texte propre :

| Élément | Rôle | Source |
|---|---|---|
| Accusé de lecture à l'invitation | Interrupteur « J'ai pris connaissance de cette notice… » obligatoire pour rejoindre. L'invitation garde la version de T1 en vigueur à sa création. Il n'est pas enregistré comme consentement. | `SchoolJoinView.swift:105`, `invitations.ts:374-409` **[code]** |
| Préparation de l'école (readiness) | Calcule les manques : activation (identité + T1/T2/T3 adoptés), planification (offre, moniteur, disponibilités, tarif, T5). | `school-setup.ts:38-63`, `lessons.ts:195-218` **[code]** |
| « Services de l'école » | Liste des capacités. `CAN_CAPTURE` et `CAN_PUBLISH_COURSE` sont **toujours** « À configurer » (codé en dur). | `school-setup.ts:52,60-61` **[code]** |
| `school_settings_version` | Instantané interne de la configuration à chaque changement (inclut le n° de T1 et de T5). Invisible. | `school-setup.ts:73` **[code]** |
| Référentiel de compétences | Pas un texte juridique, mais suit le même rituel « Approuver + Motif » que T6/T7. | `catalog.tsx:35-160` **[code]** |

### 1.2 Détails vérifiés qui comptent pour la suite

- **Création d'école.** Aucune création en libre-service : `infra/deploy/provision-school.mjs` crée une école `DRAFT` et son admin. Un déclencheur ajoute alors une T1 **vide et non adoptée** (`002`, `initialize_school_setup`). Rien d'autre n'est pré-rempli. C'est un choix écrit : « Aucun texte juridique n'est généré ou adopté par défaut » (`g1b-school-setup.md:64`) et « Aucun contenu ni consentement n'est proposé automatiquement » (`native-school-settings-design.md:14`) **[impl]**.
- **Validation minimale.** T1 et T2 doivent seulement être « non blancs » (1 à 20 000 caractères) : `school-setup.ts:20,24` et contrainte SQL de `002` **[code]**.
- **Effet d'une nouvelle version de T1.** Le déclencheur `capture_notice_changed` passe **toutes** les sessions de capture `AUTHORIZED` de l'école à `REVOKED` (`008_capture.sql:189-195`). Le démarrage d'un trajet exige ensuite `choice.notice_version_id == notice actuelle` (`captures.ts:147,167`). Un accord donné sur l'ancienne version ne suffit donc plus : l'app affiche « L'information de l'école a changé » et repose la question **[code]**. Le dossier le veut ainsi : « un accord ne dépasse pas la finalité/version » (`04-technique/modele-donnees.md:69`) **[dossier]**.
- **T5 et ses contraintes.** 2 à 7 champs ; prénom et nom forcés « Requis · À l'entrée » ; **une explication écrite obligatoire pour chaque champ** ; finalités imposées par champ ; date d'effet ; brouillon puis publication, avec deux dialogues et deux cases à cocher (`profiles.ts:17-56`, `profile-fields.tsx`) **[code]**.
- **Mineurs.** Aucune occurrence de mineur, de représentant légal ou de calcul d'âge dans l'API, le web ou l'app (recherche `mineur|minor|guardian|tuteur|responsable légal`). La seule occurrence trouvée est un nom de variable monétaire **[code]**. La date de naissance est un champ facultatif parmi d'autres.
- **Conservation.** Aucune tâche de purge des trajets ou des données selon une durée n'a été trouvée. Seule existe la suppression du tracé recalé quand la capture est supprimée (`024`) **[code, par recherche]**.
- **Web et accord GPS.** Aucun écran du web ne montre qui a accepté ou refusé le GPS (aucune lecture de `recording-choice` dans `apps/web`) **[code]**.

---

## 2. Ce qui est vraiment nécessaire

Échelle : **Loi** = obligation légale probable (à faire confirmer) ; **Dossier** = exigence du dossier de conception ; **Choix** = décision d'implémentation qu'on peut revoir.

| Élément | Nature | Ce qui est réellement exigé | Ce qui est un choix révisable |
|---|---|---|---|
| T1 Information | **Loi** + Dossier | Informer la personne au moment de la collecte : responsable et contact, finalités, destinataires, pays étrangers le cas échéant (nLPD art. 19 ; RGPD art. 13 si applicable) **[à confirmer juriste]**. Le dossier demande l'information « au bon moment » : à l'invitation, avant le premier GPS, et toujours consultable dans le compte (`securite-vie-privee.md`, § Information au bon moment) **[dossier]**. | Texte entièrement libre ; aucun modèle ; adoption sans contrôle de contenu. Le dossier interdit qu'une politique « non qualifiée » soit **approuvée** par défaut (`onboarding.md:43`). Il n'interdit pas de **proposer** un modèle que l'admin relit et adopte. |
| T2 Conservation | Loi (RGPD : durée obligatoire dans l'information ; en Suisse, durée **non listée** dans le contenu minimal de l'art. 19 nLPD, mais principe de proportionnalité) **[à confirmer juriste]** + Dossier (« politique de rétention signée » avant pilote) | Des durées **réelles et appliquées**. Le dossier propose 30 jours de GPS brut, « à arbitrer, pas une obligation légale » (`gps-replay.md:163`) **[dossier]**. | Texte séparé de T1 ; texte libre plutôt que durées paramétrées ; aucune application automatique. |
| T3 Contact données | Loi (contact du responsable) | Une adresse joignable. | Doublon de l'e-mail de l'école dans la plupart des cas. |
| T4 Accord GPS | Dossier (toujours) ; Loi selon le fondement retenu | Choix volontaire, distinct de la permission iOS ; alternative « sans GPS » aussi visible ; refus de l'élève protégé (`gps-replay.md:19`, `regles-etats.md:780`) **[dossier]**. Le fondement juridique (consentement ou intérêt prépondérant) n'est **pas tranché** (Q06) **[dossier]**. | Lier l'accord à la **totalité** de T1 : une faute corrigée dans l'information générale relance tous les accords. Le dossier lie l'accord à « la finalité/version » ; un texte GPS séparé et versionné à part le respecterait. |
| T5 Informations demandées | Loi (minimisation, finalité) + Dossier (catalogue borné, pas de champ arbitraire : `onboarding.md:97`, `modele-donnees.md:98`) | Ne demander que l'utile, et dire pourquoi. | Explication obligatoire par champ ; date d'effet libre ; brouillon + publication ; **blocage de la planification** tant qu'aucune version n'est publiée ; lien explicite à une version de T1. |
| T6 Déroulement et annulation | Choix métier (pas une obligation de protection des données) ; les conditions d'annulation relèvent du **contrat** avec l'élève | Que l'élève connaisse les conditions qui l'engagent avant de réserver **[supposé, droit des contrats]**. | Un texte par catégorie, « Approuver + Motif », obligatoire pour activer une offre. |
| T7 Conditions commerciales | Choix métier / contrat | Idem T6. | Doublon partiel de T6 (l'annulation est souvent dans les conditions générales) ; « Motif » d'approbation. |
| Activation de l'école | Dossier (l'activation exige T1/T2 adoptés : `regles-etats.md:545`) | — | « Enregistrer l'avancement » et étapes `school_setup` : vestiges du parcours en 6 étapes, sans usage visible. |
| Mineurs | **Dossier : bloquant avant le pilote** (`vision-perimetre.md:84-88`, `securite-vie-privee.md` § Qualification du cas mineur, Q06) | Faire qualifier qui crée le compte, qui engage les prestations, quand un représentant intervient, comment c'est prouvé et révoqué. **Ne pas inventer** de consentement parental fondé sur un âge arbitraire. | Tout reste à construire. |

**Note juridique prudente (à faire valider).** En droit suisse, un mineur **capable de discernement** exerce en principe lui-même ses droits strictement personnels, protection de ses données comprise (CC art. 19c). Les élèves conducteurs mineurs ont en général 15 à 17 ans (catégories M, A1, et B dès 17 ans pour le permis d'élève) **[à confirmer]**. Un accord GPS donné par l'élève lui-même n'est donc pas forcément invalide. Le **contrat** (prix, annulation) peut en revanche demander le représentant légal.

Deux autres points sont à instruire :
- La position est enregistrée par **l'iPhone du moniteur**, pas par celui de l'élève. Sous RGPD, les règles sur l'accès à l'appareil (ePrivacy) ne visent peut-être pas ce cas.
- Le recalage routier envoie des positions à **Mapbox** (fournisseur américain, activé sur le homelab). C'est un destinataire étranger que l'information doit nommer (`gps-fluide-recalage-20261011.md`) **[impl ; à confirmer juriste]**.

---

## 3. Problèmes actuels

### 3.1 Écrans vides ou trompeurs

1. **« Information et conservation » paraît vide.** Sur le homelab, Luc auto école a adopté en v2 `noticeText = "ddd"` et `retentionText = "wssd"`. Ses 30 accords GPS (29 avec, 1 sans) sont attachés à cette version **[base]**. Le serveur l'a accepté parce qu'un caractère suffit. Dans l'app, la feuille affiche alors trois lettres et l'e-mail. Si l'école n'a **rien** adopté, la lecture renvoie `409 RECORDING_NOTICE_NOT_READY` et l'app montre « L'accord GPS n'a pas pu être lu ». C'est un message d'erreur technique pour une simple absence de configuration **[code]**.
2. **« Services de l'école » ment.** « Enregistrement des trajets » et « Publication des cours » sont toujours « À configurer », même quand les trajets fonctionnent (`later()` renvoie `ready:false` en dur) **[code]**.
3. **La préparation ne dit pas ce qui manque vraiment pour planifier.** La page « Préparation » a trois lignes. Une école peut pourtant rester bloquée par une T6 ou une T7 non approuvée, que seule la ligne « Formations et tarifs » laisse deviner **[code]**.

### 3.2 Doublons

- **Readiness affichée trois fois** : page « Préparation », bloc « Activation / Fonctionnement » de la page École, liste « Services de l'école » **[code]**.
- **Deux e-mails de contact** : celui de l'école et « Contact pour les données », pré-rempli avec le premier **[code]**.
- **Annulation écrite deux fois** : dans T6 (par catégorie) et dans T7 (conditions commerciales) **[code ; recouvrement supposé selon les écoles]**.
- **Le texte d'information est affiché dans 6 écrans iOS**, chacun avec sa propre mise en page : concaténé, en deux liens, en section dépliable, en feuille **[code]**.

### 3.3 Vocabulaire incohérent ou jargonneux

| Le même objet… | …s'appelle |
|---|---|
| T1+T2 dans l'app | « Information et conservation » · « Information et conservation des données » · « Informations de ton école » + « Conservation des données » · « Comment l'école utilise tes données » · « la notice » (« Lire la notice et choisir », « J'ai pris connaissance de cette notice ») |
| T1+T2 dans le web | « École et confidentialité » (Préparation) · « Information et conservation » (titre de section) · « Information des personnes » / « Conservation des données » (champs) · « Notice de données » (T5) · « Consulter les textes adoptés » |
| T5 | Menu « Informations élèves » · titre « Informations demandées aux élèves » · `sectionTitles` « Informations des élèves » · « politique de champs » et « règles » dans les messages |
| La préparation | Menu « Préparation » · titre « Préparation de l'école » · page École « Préparer l'école » / « Activation » / « Fonctionnement » |

Mots du serveur visibles par l'admin, contraires à la règle « les mots de l'auto-école » des décisions du 28/09 : « Version 2 », « Brouillon », « Publiée · à venir », « Ancienne version », « Prise d'effet », « Notice liée », « Approuver… », « Motif », « Révision », « Préparer une nouvelle version », « Abandonner cette version ».

### 3.4 Réglages éparpillés

Pour planifier une première leçon, l'admin écrit ou valide **neuf contenus** dans **trois espaces** **[code]** :
- Réglages : T1, T2, T3, et T5 avec une explication par champ ;
- Formations : le référentiel avec son motif, puis T6 (déroulement, annulation, motif) ;
- Tarifs : T7 avec son motif.

Il faut en plus l'offre, le tarif, le moniteur et les disponibilités.

### 3.5 Étapes inutiles ou coûteuses

- **T5 en deux temps** (brouillon puis publication), une date d'effet à saisir et deux cases « J'ai relu… » : c'est excessif pour cocher « téléphone requis avant une leçon » **[code]**.
- **« Motif » d'approbation** obligatoire sur T6, T7 et le référentiel, alors que l'admin est le seul à approuver **[code]**.
- **« Enregistrer l'avancement »** : vestige des 6 étapes de configuration, sans effet visible **[code]**.
- **Corriger une faute dans T1** coupe les trajets en cours et repose la question du GPS à tous les élèves, sans que le dialogue d'adoption prévienne l'admin **[code]**. C'est l'effet le plus grave pour le terrain.

### 3.6 Mineurs

- Aucune notion de mineur : l'app tutoie l'élève et lui demande « Acceptes-tu le GPS ? » quel que soit son âge **[code]**.
- La date de naissance n'est demandée que si l'admin l'a cochée dans T5 ; elle est facultative par défaut **[code]**.
- Aucun représentant légal : ni contact, ni accord, ni accès **[code]**. Le dossier refuse un compte parent automatique et un âge arbitraire, et bloque le pilote tant que ce n'est pas qualifié **[dossier]**.
- Données d'essai : 76 dates de naissance sur 86 élèves, aucun mineur **[base]**. Ce cas n'a jamais été vu tourner.

### 3.7 Promesses non tenues

- Le texte de conservation peut annoncer « 30 jours » : rien ne supprime le trajet au bout de 30 jours **[code]**.
- L'admin ne voit nulle part sur le web qui a accepté ou refusé le GPS **[code]**.

---

## 4. Trois parcours repensés

Les trois partagent quatre corrections de base, peu coûteuses :
- **(a)** un vocabulaire unique ;
- **(b)** une longueur minimale sérieuse pour les textes (par exemple 80 caractères) ;
- **(c)** un écran app jamais vide ;
- **(d)** « Services de l'école » corrigé ou retiré.

Vocabulaire proposé :

| Objet | Nom unique (admin, web) | Nom dans l'app (élève) |
|---|---|---|
| T1+T2+T3 | **Confidentialité** | « Tes données » |
| Texte GPS (nouveau dans B et C) | **Trajets GPS** | « Trajets GPS » |
| T4 | **Accord GPS** | « Accord GPS » (inchangé) |
| T5 | **Informations demandées** | « Pourquoi ces informations ? » (inchangé) |
| T6+T7 | **Conditions** (déroulement, annulation, tarifs) | « Conditions » |
| Version | « Mis à jour le 13 octobre 2026 » ; l'historique reste dans un menu, jamais en badge | — |

### Parcours A : modèles pré-remplis, structure inchangée

**Idée.** À la création de l'école, Drivy pré-remplit T1, T2 et T5 (et T6/T7 par catégorie) avec des **modèles** rédigés une fois pour toutes et relus par un juriste. Ils restent **non adoptés**. La page Réglages affiche une carte « Textes proposés par Drivy · à relire » avec un bouton « Relire et adopter ». Un seul dialogue montre tous les textes, avec une seule case à cocher. L'admin peut les modifier avant ou après l'adoption.

- Les modèles se complètent seuls : nom de l'école, e-mail, fournisseurs connus de Drivy (hébergement, identité, Mapbox pour le recalage, Apple Plans pour les fonds de carte), modules actifs.
- T5 par défaut : prénom et nom (à l'entrée), téléphone (avant une leçon), e-mail (facultatif), avec des explications déjà écrites, publiés **sans date d'effet** (effet immédiat).
- L'écran GPS de l'app ne montre plus le texte complet. Il affiche trois lignes fixes écrites par Drivy (« Enregistré pendant la leçon seulement », « Visible par toi et ton école », « Supprimé après N jours »), puis le lien « Tes données ».

| Avantages | Inconvénients |
|---|---|
| Une école est utilisable en quelques minutes. | Garde 3 espaces et 7 objets : la confusion de rangement reste. |
| Peu de code : du contenu, un dialogue, des valeurs par défaut. | Les modèles engagent Drivy : relecture juridique indispensable avant usage réel. |
| Compatible avec le dossier : rien n'est **approuvé** sans geste de l'admin. | Ne règle ni la caducité des accords GPS, ni les mineurs, ni la conservation non appliquée. |
| | Contredit deux phrases d'implémentation citées en § 1.2 : décision du porteur nécessaire. |

### Parcours B (recommandé) : un seul endroit « Confidentialité et conditions », texte GPS séparé

**Idée.** Le parcours A, plus un regroupement des écrans et une séparation qui supprime l'effet de bord.

**Web.** Le menu Réglages passe à trois entrées : **École** (coordonnées, activation), **Confidentialité et conditions**, **Signalements**. La page « Préparation » disparaît. Ses lignes deviennent un bandeau en tête de l'Agenda tant qu'il manque quelque chose, avec un lien direct vers le manque exact, T6 et T7 compris.

« Confidentialité et conditions » regroupe quatre cartes, chacune avec son état en un mot et son bouton :

```
Confidentialité et conditions
┌ Tes données (information + conservation + contact) ……… À jour · Modifier
┌ Trajets GPS (3 lignes + durée de conservation) ……………… À jour · Modifier
┌ Informations demandées (tableau à cases) ……………………… 3 champs · Modifier
└ Conditions (déroulement, annulation, tarifs) par permis …… B · A · Modifier
  Historique ▸ (versions, dates, auteur)
```

- **Un seul geste pour la première adoption** (« Adopter ces textes »), puis une modification carte par carte.
- **Informations demandées** devient un tableau : chaque champ reçoit « Pas demandé », « Facultatif » ou « Avant une leçon ». Les explications sont pré-écrites et modifiables, l'effet est immédiat et le **brouillon disparaît**. Le serveur garde chaque version, immuable.
- **Le « Motif »** disparaît pour T6, T7 et le référentiel : l'audit existant garde déjà l'auteur et l'heure.
- **T6 et T7 sont fusionnés à l'écran** sous « Conditions » : un texte de conditions par école, plus un déroulement facultatif par catégorie.

**Le changement de fond : un texte GPS séparé.** « Trajets GPS » devient un texte à part, avec sa propre version : finalité courte, qui voit, **durée en jours choisie dans une liste** (30, 90, 365). L'accord GPS s'attache à **ce** texte, et non plus à l'information générale. Corriger l'information générale ne touche donc plus aux trajets.

Modifier le texte GPS **prévient l'admin** (« 29 élèves devront redonner leur accord ; les trajets en cours se terminent »). Un trajet en cours n'est coupé qu'à la fin de la leçon **[à valider par un juriste : un changement de finalité doit-il couper immédiatement ?]**.

**App.** Un seul composant « Tes données » remplace les six présentations actuelles. Il garde toujours le même ordre : les trois lignes GPS, puis le lien vers le texte complet. S'il manque quelque chose, un seul message sert partout, pour le moniteur comme pour l'élève : « Ton école n'a pas encore publié ses textes. La leçon peut se faire sans GPS. »

| Avantages | Inconvénients |
|---|---|
| Un seul endroit, quatre mots, plus de « Version 2 » à l'écran. | Migration de données (nouvelle table ou colonne pour le texte GPS) et reprise des 30 accords existants. |
| Supprime l'effet de bord le plus grave : des trajets coupés et des accords perdus pour une faute de frappe. | Touche l'API, le web et iOS. |
| Respecte le dossier : l'accord reste lié à « la finalité/version », puisque la finalité GPS a son propre texte. | Demande des décisions du porteur (séparation du texte GPS, fin du brouillon T5) et un avis juridique sur les modèles. |
| L'app tient en trois lignes (règle « peu de texte »). | |

### Parcours C : textes structurés, durées appliquées, mineurs instruits

**Idée.** Le parcours B, plus deux changements : les textes libres deviennent des **paramètres** à partir desquels Drivy compose le texte, et ce qui est promis est réellement appliqué.

- **Conservation paramétrée** : une durée par catégorie (trajet brut, tracé simplifié, observations, bilans, dossier après départ). Une **tâche de purge** les applique, et l'écran de l'élève lit ces durées dans les données plutôt que dans un texte libre.
- **Information générée** à partir des paramètres et de la liste des fournisseurs. L'admin peut ajouter un paragraphe libre.
- **Mineurs.** Prévoir un **mécanisme** sans figer la règle avant l'avis du juriste :
  - La date de naissance passe à **« Avant une leçon »** par défaut, avec une nouvelle finalité « Vérifier l'âge pour les accords » ajoutée au catalogue borné.
  - Un réglage d'école, désactivé tant qu'il n'est pas qualifié : « Pour un élève mineur, l'accord GPS est aussi confirmé par un représentant légal ».
  - S'il est activé, l'accord d'un mineur reste en attente (« À confirmer par un représentant »). Le moniteur enregistre ensuite la confirmation orale ou écrite du représentant (nouvelle source, par exemple `GUARDIAN_RECORDED`), avec son nom et un moyen de contact. Pas de compte parent.
  - Au 18e anniversaire, l'app redemande l'accord à l'élève lui-même.
  - Le refus de l'élève prime toujours, comme aujourd'hui.
  - Pour le contrat (T6/T7), une mention « signé par un représentant légal » au dossier suffit au début, sans parcours numérique.

| Avantages | Inconvénients |
|---|---|
| Ce qui est affiché est ce qui est fait : plus de promesse non tenue. | Le plus coûteux. La purge touche aux données réelles : tests sur vraie PostgreSQL et sauvegarde obligatoires. |
| Couvre l'exigence « mineurs » du dossier avant le pilote. | La règle sur les mineurs dépend d'un avis juridique ; en attendant, le réglage reste inactif. |
| Des textes homogènes d'une école à l'autre, faciles à relire juridiquement. | Moins de liberté rédactionnelle pour l'école. |

---

## 5. Recommandation

**Faire B tout de suite, en deux lots, et préparer C pour le pilote.**

1. **Lot 0, immédiat, sans décision juridique.**
   - Corriger « Services de l'école ».
   - Remplacer l'erreur « L'accord GPS n'a pas pu être lu » par le message d'absence de textes.
   - Imposer une longueur minimale aux textes.
   - **Prévenir l'admin, dans le dialogue d'adoption, que les accords GPS seront redemandés et les trajets en cours coupés.**
   - Unifier le vocabulaire.
   - Sur le homelab, faire réécrire par le porteur les textes « ddd » et « wssd », en sachant que cela relancera les 30 accords GPS.
2. **Lot 1 (parcours B).**
   - Page « Confidentialité et conditions ».
   - Modèles pré-remplis, adoptés en un geste.
   - Tableau des informations demandées, sans brouillon.
   - Suppression des « Motif ».
   - Texte GPS séparé, auquel l'accord s'attache.
   - Composant « Tes données » unique dans l'app.
   - Liste des accords GPS dans le dossier élève du web.
3. **Avant le pilote (parcours C), après avis juridique.** Conservation paramétrée avec purge, et mécanisme mineurs activable.

**Décisions du porteur nécessaires avant le lot 1 :**
- autoriser des **modèles proposés par Drivy**, ce qui revient sur `g1b-school-setup.md:64` et `native-school-settings-design.md:14` ;
- séparer le **texte GPS** de l'information générale ;
- supprimer le brouillon de T5 et les motifs d'approbation.

**À faire relire par un juriste :**
- les modèles ;
- le fondement de l'accord GPS ;
- la mention de Mapbox comme destinataire étranger ;
- le traitement des mineurs (discernement, contrat, représentant) ;
- l'effet d'un changement de texte GPS sur un trajet en cours ;
- le droit applicable (nLPD seule, ou aussi le RGPD).

---

> **Lot 1 réalisé le 13 octobre 2026** sans texte GPS séparé, selon les [décisions du porteur](decisions-2026-10-13.md).
>
> **Lot 0 réalisé le 13 octobre 2026** sur la branche `claude/textes-ecole-lot0-20261013` (voir `STATUS.md`). La longueur minimale est vérifiée par l'API sans contrainte SQL ; « Services de l'école » est retiré du web plutôt que recalculé.

## 6. Ce qu'il faudrait toucher (estimation grossière)

Estimations en jours de travail d'un agent, tests compris, hors relecture juridique. Ce sont des ordres de grandeur.

| Lot | Couche | Changement | Jours |
|---|---|---|---|
| 0 | API | Longueur minimale de T1/T2 (`school-setup.ts` + contrainte SQL dans une migration 029). `CAN_CAPTURE` calculé à partir du profil d'appareil et du module GPS plutôt qu'en dur. Nombre d'accords concernés renvoyé avant l'adoption. | 1 |
| 0 | Web | Avertissement dans le dialogue d'adoption ; vocabulaire ; retrait ou correction de « Enregistrer l'avancement » et de « Services de l'école » | 0,5 |
| 0 | iOS | Message d'absence de textes (`RECORDING_NOTICE_NOT_READY`) ; mêmes titres partout | 0,5 |
| 1 | Migration | Table `school_gps_notice` (ou colonnes versionnées) et `recording_choice.gps_notice_version_id`. Reprise des accords existants vers la v1 du texte GPS. Déclencheur `capture_notice_changed` limité au texte GPS et à la fin de leçon. Motifs rendus facultatifs. | 2 |
| 1 | API | Modèles (contenu + génération à partir de l'école) ; commande atomique « adopter l'ensemble » ; publication immédiate de T5 ; lecture des accords GPS par élève pour l'admin ; contrat OpenAPI | 3 |
| 1 | Web | Page « Confidentialité et conditions » (4 cartes, historique) ; tableau T5 ; fusion T6/T7 à l'écran ; bandeau de préparation dans l'Agenda ; colonne « Accord GPS » dans le dossier élève | 3 |
| 1 | iOS | Composant « Tes données » unique à la place des 6 présentations ; texte GPS en trois lignes ; renvoi vers la nouvelle version | 2 |
| 1 | Contenu | Rédaction des modèles : information, conservation, GPS, conditions, explications des champs | 1 + juriste |
| C | API + migration | Durées paramétrées, tâche de purge planifiée, tests sur vraie PostgreSQL | 3 |
| C | Mineurs (API, web, iOS) | Âge calculé, réglage d'école, accord confirmé par un représentant, relance à la majorité, tests | 4 |

**Total indicatif : lot 0 ≈ 2 j ; lot 1 ≈ 11 j ; C ≈ 7 j.**

Chaque lot déployé sur le homelab demande la sauvegarde habituelle de la base. La migration du lot 1 doit d'abord être répétée sur une copie de `drivy_refonte`, à cause des 30 accords existants.

---

## 7. Reste à qualifier

- Aucun écran n'a été lancé pour cette analyse : l'affichage de « ddd » est déduit du code et de la base, pas d'une capture.
- Le recouvrement réel entre T6 et T7 dépend des écoles. Je ne l'ai vu que sur les données d'essai : 3 versions de T6, 1 version de T7.
- Je n'ai pas vérifié si l'élève voit T6/T7 dans son propre parcours. C'est confirmé côté moniteur, à la planification (`SchoolPlanningView.swift:342-348`).
- Les points juridiques (§ 2, § 5) sont des pistes, pas des avis.
