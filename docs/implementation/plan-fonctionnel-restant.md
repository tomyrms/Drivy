# Plan fonctionnel restant — audit backend du 25 septembre 2026

Audit **en lecture seule** de la branche `claude/tender-volta-bxdjd9` (tête `905b124`). Aucun test ni déploiement exécuté pour ce document. Il répond au constat du porteur : « il y a vraiment pas mal de choses à faire en termes de backend ». Ce constat est **exact** : 78 des 201 opérations canoniques sont routées (liste ci-dessous) et plusieurs d’entre elles n’ont aucun test automatisé.

## Avancement du 25 septembre 2026 (après audit)

Réalisé côté API sur la branche de travail, sans déploiement, avec tests PostgreSQL 16 réels (détail et résultats dans [STATUS.md](STATUS.md)) :

- **P0-5 (partie)** : sondes internes `GET /health/live` et `/health/ready`, 404 pour toute requête relayée par le proxy — [exploitation-sante.md](exploitation-sante.md). Sauvegarde/restauration/alertes restent à faire.
- **P0-3** : AP29/AP30, table `permit_check` (migration 010), `permitWarning` calculé, `anomalyReason` exigé seulement sans permis valide — [g2-permis.md](g2-permis.md).
- **P0-4 (partie)** : AP44, AP88, AP50 (transitions entre issues closes ; retours vers PLANNED/COMPLETED refusés explicitement), AP57 (migration 011) — [g2-issues-lecon.md](g2-issues-lecon.md).
- **P0-1 a/b** : tests d’intégration du planning, des prestations/conditions, de la préparation, du souhait, du constat, du bilan, de la progression et du compte — [tests-planning-bilan.md](tests-planning-bilan.md). P0-1 c (CI sur push) reste à faire.

Routes AP enregistrées : **84** (+AP29, AP30, AP44, AP50, AP57, AP88). Tables : **44**. Les sections ci-dessous conservent l’audit initial ; les lignes concernées sont annotées « → fait ».

Conventions de preuve utilisées ci-dessous :

- **Code** : route réellement enregistrée par `buildApp` (`apps/api/src/app.ts` → `register*`), table présente dans `apps/api/migrations/001–009`, appel réellement présent dans `apps/ios/Drivy/*API/` ou `apps/web/`.
- **Testé** : appelé par un fichier de `apps/api/test/` sur PostgreSQL réel. Les tests d’intégration ne tournent en CI que sur `workflow_dispatch` (`.github/workflows/refonte-checks.yml`, `if: github.event_name == 'workflow_dispatch'`), pas à chaque push.
- **Documenté seulement** : affirmé dans `STATUS.md` ou `g*/native-*.md` sans code ni test correspondant dans l’arbre.

## 0. Inventaire mesuré dans le code

**Routes AP enregistrées (78)** : AP01, AP04–AP08, AP10–AP16, AP18–AP24, AP26, AP27, AP31–AP37, AP39–AP43, AP45–AP49, AP52–AP56, AP58, AP65, AP72, AP94, AP95, AP100, AP101, AP152–AP158, AP160–AP177, AP190, AP191.

**Extensions hors canon** : `POST /v1/invitations/preview`, `GET/PUT /data-policy`, `GET/POST /commercial-terms`, `GET /lessons/{id}/report-drafts`, `GET /v1/capture-keys`, `GET /recording-notice`, alias `PATCH /learners/{id}` → profil administratif.

**Absentes (123)** : AP02, AP03, AP09, AP17, AP25, AP28–AP30, AP38, AP44, AP50, AP51, AP57, AP59–AP64, AP66–AP71, AP73–AP93, AP96–AP99, AP102–AP151, AP159, AP178–AP189, AP192–AP201.

**Persistance** : 40 tables (migrations 001–009). Aucune table pour documents, paiements, packs/droits, cours, notifications/livraisons, sync, demandes RGPD, rétention/tombstones, sites/salles, permis, demandes de formation.

**Tests API** : 9 fichiers, environ 108 cas `it()`. Couverture par tranche :

| Tranche | Test PostgreSQL dans l’arbre |
|---|---|
| G1A lectures, G1B setup, G1C invitations, G1D profils/onboarding | Oui (`g1a`, `g1b`, `g1c`, `g1d`) |
| Catalogue/formation/affectation/AP08 | Oui, 3 cas (`catalogue.integration.test.ts`, migrations 001–005 uniquement) |
| Capture AP152–158/160/190/191 | Oui, 1 parcours (`capture.integration.test.ts`) |
| Observations AP161–164 + AP49/52/54/56 | Oui, 1 parcours (`capture-observations.integration.test.ts`) |
| **Planning AP31–AP43, AP100/101, commercial-terms** | → fait : `lessons.integration.test.ts`. Audit initial : **Aucun.** Les leçons des tests capture sont insérées en SQL direct (`INSERT INTO drivy.lesson`). `g2-lessons.md` le reconnaît : « aucun parcours HTTP nominal… déclaré passé ». |
| **AP45–AP48, AP53, AP55, AP58, AP65** | → fait : `lesson-reports.integration.test.ts`. Audit initial : **Aucun test automatisé.** `g2-reports.md` cite un contrôle HTTP manuel local, non reproductible dans le dépôt. |

**Web (`apps/web`)** : BFF avec 9 routes (`/app/bff/session|login|callback|logout|me|invitation*`). L’UI (`client/App.tsx`, 416 lignes) ne couvre que la connexion et l’acceptation d’invitation. Le « journal de commandes web durable » de `STATUS.md` est **documenté seulement** : on ne trouve dans `apps/web` ni code, ni test, ni usage de `WEB_COMMAND_TEST_DATABASE_URL`, alors que l’installateur `infra/deploy/install-web-command-storage.py` existe. Aucune page de gestion scolaire.

**Exploitation** : aucune route santé dans l’API. Aucune unité systemd pour le worker e-mail : `infra/deploy` contient api, identity, ingress et web, mais pas `invitation-mail-worker`. En production, sans configuration SMTP, AP11/AP12 répondent `503 INVITATION_DELIVERY_UNAVAILABLE`. `lesson_event_outbox` est alimentée par AP40/42/43/49/54, mais **aucun consommateur** n’existe. Les sauvegardes sont manuelles et ponctuelles (avant migration), sans procédure automatisée ni restauration testée dans le dépôt.

## 1. Tableau de couverture par domaine

Légende API : ✔ route présente · ✔T route présente et testée sur PostgreSQL · ✘ absente.

| Domaine | API livrée (code) | iOS (code) | Web (code) | Manque (AP) |
|---|---|---|---|---|
| **Identité / compte / suppression** | AP01 ✔T. OIDC par JWT, `auth_time` pour réauth AP08 ✔T | AppAuth/PKCE, `/me`, réauth Équipe | BFF OIDC, session cookie, logout BFF, `/me` | AP02 logout serveur, AP03 bail hors ligne, AP89 `updateMe`, **AP193–AP198/AP200 suppression de compte** (rien : ni table ni route) |
| **Écoles / configuration** | AP05, AP06, AP165–AP168 ✔T, data-policy ✔T, AP72 ✔T | Configuration DRAFT/activation, adoption des textes | ✘ | AP84–AP87/AP92 logo et actifs, AP96–AP99/AP104–AP105 sites et salles, modules réels (CAN_PLAN etc. restent inactifs dans la readiness) |
| **Membres** | AP07, AP08 ✔T (dernier ADMIN, réauth) | Équipe (AP07/08) | ✘ | **AP09 révocation d’appartenance**, délégations/grants administrables, AP83 audit |
| **Invitations / email réel** | AP10–AP13 ✔T, AP04 ✔T, preview ✔T, worker SMTP (code + test Mailpit) | Invitations, rejoindre une école (preview/accept) | Acceptation web complète | **Relais SMTP externe + déploiement du worker** (pas d’unité systemd). Sans eux, AP11 répond 503 en production. Inscription publique fournisseur fermée. |
| **Profils / onboarding** | AP16, AP169–AP177 ✔T | Profil, politique de champs, accueil | ✘ | Photo (dépend de F09), préférences initiales (AP150/151), exigences AP120–AP122 |
| **Catalogue / prestations / conditions** | AP18–AP21, AP94/95 ✔T. AP100/101 et commercial-terms ✔ **sans test** | Catalogue et éditeur (référentiels, procédures, offres, prestations, conditions) | ✘ | AP106 archivage des prestations, AP102/103/AP107 packs, AP123–AP125 profils réglementaires |
| **Formations / affectations / demandes élève** | AP22–AP24, AP26, AP27 ✔T | Création de formation, affectation, dossier | ✘ | **AP25 état de formation** (pause/fin), **AP28 fin d’affectation**, AP17/AP182–AP186 archivage, **AP178–AP181 demandes élève** |
| **Permis / documents** | → AP29/AP30 ✔T (contrôle physique attesté, `permitWarning` calculé). Audit initial : ✘ (le Lesson renvoie `permitWarning:true` en dur) | ✘ | ✘ | **AP29/AP30 contrôle de permis**, AP59–AP64/AP90 documents (upload, scellement, ticket, suppression), stockage objet |
| **Planning / disponibilités / créneaux** | AP31–AP37 ✔ **sans test** | Réglages de planning (ouvertures, fermetures) | ✘ | **AP38 suggestions de créneaux**, AP147 calendrier agrégé, plages adjacentes non fusionnées, leçon limitée à une seule journée locale |
| **Leçons / constat / annulation / frais** | AP39–AP43 ✔ **sans test**. AP49 ✔T (partiel). AP65 ✔ sans test | Agenda, planifier, déplacer, annuler, constat | ✘ | → AP44 ✔T, AP88 ✔T, AP50 ✔T partiel, anomalie seulement sans permis valide. Audit initial : **AP44 absence (no-show)**, **AP50/AP88 correction de constat**, calcul des frais d’annulation (non implémenté : AP43 ne crée aucune charge), constat forcé avec `anomalyReason` tant qu’AP30 manque |
| **Capture GPS scolaire / lien trajet↔leçon / observations publiées** | AP152–AP158, AP160, AP190/191 ✔T. AP161–AP164 ✔T. Rattachement au brouillon dans AP49 ✔T | Préparation, choix élève, collecteur, transport des lots, replay, signalement | ✘ (hors périmètre web) | **AP54 sélection d’observations et de capture** (refusée : `OBSERVATION_PUBLICATION_NOT_READY`), **AP159 retrait de publication de capture**, AP160 par `reportRevisionId` (404), GeometrySnapshot/CapturePublication absents, rotation multiclés. Aucun profil d’appareil qualifié (`CAPTURE_QUALIFICATION_PROFILES_JSON=[]`). Un trajet local G0 n’est lié à aucune leçon, ce qui est voulu. |
| **Bilans / progression** | AP52–AP54, AP56 ✔T. AP53, AP55, AP58, AP45–AP48 ✔ **sans test** | Préparation, bilan, bilans publiés, progression | ✘ | → AP57 ✔T. Audit initial : **AP57 retrait de publication**, AP51 brouillon de correction par un autre auteur, pièces jointes (dépend de F09) |
| **Paiements / comptes / packs / entitlements** | AP65 (lecture, charge INITIAL créée au constat) ✔ | Lecture du compte de leçon | ✘ | **AP66–AP68/AP93 règlements de leçon**, AP115–AP119 comptes, AP108–AP114/AP199 achats et droits (constat `ENTITLEMENT` bloqué : `ENTITLEMENT_NOT_READY`) |
| **Cours collectifs / inscriptions** | ✘ | ✘ | ✘ | AP126–AP146, AP192, AP201 (G3 complet) |
| **Notifications (push/email)** | ✘. Outbox `lesson_event_outbox` écrite sans consommateur | ✘ (aucun enregistrement APNs) | ✘ | **AP69–AP71 centre interne**, AP148/AP149 push, AP150/AP151 préférences, worker de livraison, e-mail transactionnel (leçon planifiée, déplacée, annulée, bilan publié) |
| **Web de gestion** | Aucune API spécifique requise en plus du canon | — | Portail invitation seulement | Pages admin (école, membres, catalogue, formations, planning, règlements), proxy BFF générique avec CSRF, journal de commandes (documenté, code absent), AP147/AP38 pour l’agenda |
| **Exploitation / sauvegardes / observabilité** | Démarrage avec refus des rôles BYPASSRLS, journaux minimisés, `no-store` | — | — | Route santé, unité du worker e-mail, sauvegarde automatisée + restauration isolée testée, métriques/alertes, tests d’intégration à chaque push, procédure de rotation des clés de capture |
| **RGPD / rétention** | RLS FORCE sur 40 tables, chiffrement des lots et de l’outbox e-mail | — | — | AP76–AP82/AP91 demandes et exports, AP193–AP198/AP200 suppression globale, RetentionPolicyVersion, DeletionTombstone, purge programmée (captures, brouillons, e-mails), réapplication après restauration |

## 2. Manques bloquants pour une école pilote

Estimation relative : S ≈ quelques jours, M ≈ 1 à 2 semaines, L ≈ plus de 2 semaines. Ces valeurs sont indicatives et non calibrées (voir « Estimation » dans la roadmap).

Chaque tranche suit la définition READY d’AGENTS.md et de la roadmap : règle → contrat OpenAPI 3.11.0 canonique → persistance minimale sous FORCE RLS → erreurs métier nommées → test PostgreSQL réel (16 et 17) → client iOS et/ou web.

### P0 — sans cela, aucun usage réel

**P0-1 · Filet de tests du planning et du bilan déjà codés** (S–M) — → a/b faits, c à faire
- *Bloquant parce que* AP31–AP43, AP100/101, commercial-terms, AP45–48, AP53, AP55, AP58 et AP65 sont déployés, mais leur code n’est vérifié par aucun test du dépôt. Toute tranche suivante (no-show, permis, paiements) modifiera `lessons.ts` et `lesson-reports.ts` sans filet.
- *Dépendances* : aucune.
- *Tranches* : (a) `lessons.integration.test.ts` : création via AP40 et non via SQL, chevauchement moniteur/élève, tampon, fermeture bloquante, déplacement avec If-Match, `LESSON_STARTED`, annulation qui libère le futur, rejeu idempotent, moniteur non affecté refusé. (b) `lesson-reports.integration.test.ts` : préparation, souhait élève, constat puis charge unique, lecture élève limitée au publié, ADMIN seul refusé, progression après correction. (c) CI : lancer `npm test` sur push des branches de travail, pas seulement sur `workflow_dispatch`.

**P0-2 · Entrée réelle des personnes : SMTP et worker déployés** (S en code, dépendance externe)
- *Bloquant parce qu’*en production AP11/AP12 répondent 503. Un admin ne peut inviter ni moniteur ni élève sans passer par un script opérateur.
- *Dépendances* : relais SMTP choisi par le porteur (décision externe) ; clé `INVITATION_OUTBOX_KEY` ; rôle `drivy_invitation_mailer`.
- *Tranches* : (a) unité systemd `drivy-refonte-mail-worker.service` et installation du rôle ; (b) configuration SMTP TLS vérifiée ; (c) recette HTTPS : invitation → réception externe → acceptation web → dossier minimal, sans jeton dans les journaux.

**P0-3 · Contrôle de permis AP29/AP30** (M) — → fait côté API (écran web et badge iOS restent)
- *Bloquant parce que* chaque leçon porte `permitWarning:true` et que chaque constat AP49 exige un `anomalyReason`. Tout usage réel produit donc des constats « en anomalie ».
- *Dépendances* : grant `permit_review` (déjà modélisé dans `membership.grants`). Une attestation physique explicite suffit, le dépôt de document F09 n’est pas nécessaire (voir `g1d-formation-ready.md`).
- *Tranches* : règle R06/R07 (décision humaine, catégorie, date, contrôleur, sans durée de validité inventée) → AP29/AP30 → table `permit_check` append-only → `PERMIT_REVIEW_FORBIDDEN`, `CATEGORY_MISMATCH` → AP40/AP49 relisent le contrôle et `permitWarning` devient calculé → test PostgreSQL → écran web admin et badge sur iOS.

**P0-4 · Issues réelles d’une leçon : absence, correction, retrait** (M) — → AP44, AP57, AP88 faits ; AP50 partiel (vers PLANNED/COMPLETED à faire)
- *Bloquant parce que* l’absence d’un élève (AP44) ne peut pas être enregistrée : il ne reste qu’annuler ou constater faussement. Un constat erroné n’est pas corrigeable (AP50/AP88), et un bilan publié par erreur n’est pas retirable (AP57).
- *Dépendances* : P0-1 ; compte de leçon (AP65) pour l’effet sur la charge.
- *Tranches* : (a) AP44 `NO_SHOW` : l’enum existe déjà dans `LessonRow`. Charge selon les conditions commerciales figées, jamais inventée. (b) AP50 + AP88 : correction motivée, approbation par un moniteur affecté, consommation atomique. (c) AP57 : pointeur de publication retiré, révisions conservées, `training_progress` recalculée. Chaque tranche a son test de concurrence et de rejeu.

**P0-5 · Exploitation minimale avant données réelles** (M) — → sonde santé faite ; sauvegarde, restauration, alertes à faire
- *Bloquant parce que* des personnes réelles (`moniteur`, `eleve`) sont déjà en base, alors qu’il n’existe ni sauvegarde automatisée, ni restauration testée, ni sonde de santé.
- *Dépendances* : hébergement CT113/CT114.
- *Tranches* : `GET /health` interne (non exposé par Caddy), sauvegarde planifiée chiffrée de `drivy_refonte` avec restauration isolée documentée dans `docs/implementation/`, alerte minimale (processus arrêté, disque), rotation des journaux sans données personnelles.

### P1 — nécessaire pour une utilisation quotidienne pilote

**P1-1 · Cycle de vie administratif** (M) : AP25 (pause, fin, annulation de formation), AP28 (fin d’affectation), AP09 (révocation d’un membre, avec incrément d’`access_epoch` et arrêt des baux de capture), AP89. *Bloquant parce qu’*un moniteur qui quitte l’école ou une formation terminée ne peuvent pas être traités. *Dépendances* : triggers de révocation déjà présents dans `008_capture.sql`. Première cible du web de gestion.

**P1-2 · Règlements de leçon** (M) : AP66, AP67, AP68, AP93 sur le compte existant (`lesson_account`, `charge_entry`) avec une nouvelle table `payment_entry` append-only. *Bloquant parce que* l’admin voit un montant dû sans pouvoir enregistrer qu’il est payé. *Dépendances* : grant `cash_record`. Aucun PSP nécessaire. Écran web uniquement.

**P1-3 · Notifications minimales** (L) : consommateur de `lesson_event_outbox`, `in_app_notification` et `delivery_attempt`, AP69–AP71, AP150/AP151, e-mail transactionnel via le worker SMTP de P0-2 ; push AP148/AP149 ensuite (APNs, clé à provisionner). *Bloquant parce que* l’élève n’apprend un rendez-vous planifié, déplacé ou annulé, ou un bilan publié, qu’en ouvrant l’app. *Règle* : lien relu sous les droits courants, aucun texte de bilan dans la notification ou les journaux.

**P1-4 · Publication des observations et de la capture dans le bilan** (L) : AP54 avec `textObservationSelection` et `captureSelection`, GeometrySnapshot/CapturePublication, AP160 par `reportRevisionId`, AP159 retrait avec purge des dérivés. *Bloquant pour la valeur produit* (observation au bon moment, puis partage choisi), pas pour un bilan texte. *Dépendances* : P0-4 (AP57, pour que le retrait soit cohérent) ; qualification physique d’au moins un profil d’appareil avant d’activer la collecte réelle.

**P1-5 · Suggestions de créneaux et calendrier** (M) : AP38 (ouvertures moins occupations, tampons, fermetures, fuseau/DST) et AP147 (vue agrégée). *Utile parce que* le planning manuel fonctionne mais exige de connaître les ouvertures ; l’agenda web a besoin d’AP147. Fusion des plages adjacentes à décider ici.

### P2 — avant la sortie G1/G2 complète

- **Demandes de formation par l’élève** AP178–AP181 (M), puisque l’admin peut créer directement via AP23.
- **Documents privés** AP59–AP64/AP90 et logo AP84–AP87/AP92 (L) : stockage objet, intention d’upload, scellement, quarantaine, ticket borné. Débloque photo de profil, pièce de permis et pièces jointes de bilan.
- **Continuité** AP03 (bail), AP73–AP75 (snapshots et deltas) (L).
- **Frais d’annulation** calculés depuis les conditions figées (S–M, après P1-2).
- **Archivage des prestations** AP106, sites et salles AP96–AP99/AP104/AP105 (S–M).

### P3 — condition d’ouverture réelle (G4/G5) puis G3

- **RGPD** (L), obligatoire avant un pilote réel selon la roadmap (DM06) : AP193–AP198/AP200, AP76–AP82/AP91, AP83, RetentionPolicyVersion approuvée par le porteur, tombstones réappliqués après restauration.
- **G3** : packs et droits AP102–AP114/AP199, comptes AP115–AP119, exigences AP120–AP125, cours collectifs AP126–AP146/AP192/AP201.
- **G4** : archives AP17/AP182–AP186, indicateurs et exports AP187–AP189.

## 3. Ordre recommandé des prochaines tranches backend

Contexte : l’administration part sur le web de gestion, alors que l’iPhone se recentre sur le moniteur et l’élève. Les commandes d’administration nouvelles se conçoivent donc **API + web**, sans nouvel écran iOS, sauf lecture utile au moniteur.

| # | Tranche | Client servi | Raison de la place |
|---|---|---|---|
| 1 | P0-1 tests planning/bilan + CI sur push (→ tests faits, CI à faire) | — | Filet avant toute modification de `lessons.ts`/`lesson-reports.ts` |
| 2 | P0-2 SMTP et worker déployés | web (acceptation), admin | Sans eux, aucune personne nouvelle n’entre ; le code existe déjà |
| 3 | P0-5 santé, sauvegarde, restauration (→ santé faite) | exploitation | Des comptes réels existent déjà |
| 4 | P0-3 permis AP29/AP30 (→ API faite) | web admin, badge iOS moniteur | Supprime l’anomalie systématique au constat |
| 5 | P0-4 AP44, puis AP50/AP88, puis AP57 (→ faits, AP50 partiel) | iOS moniteur, lecture élève | Boucle leçon honnête : absence, erreur, retrait |
| 6 | P1-1 AP25/AP28/AP09/AP89 | web admin | Premières pages de gestion qui ont un effet |
| 7 | P1-2 règlements AP66–68/AP93 | web admin | S’appuie sur le compte déjà créé au constat |
| 8 | P1-5 AP38 + AP147 | web agenda, iOS planification | Le web de gestion a besoin d’une vue calendrier |
| 9 | P1-3 notifications internes + e-mail, puis push | élève iOS/web | Réutilise le worker SMTP de l’étape 2 |
| 10 | P1-4 publication des observations et de la capture | iOS moniteur, élève | Nécessite AP57 (étape 5) et un profil d’appareil qualifié |
| 11 | P2 documents, demandes élève, continuité | tous | Débloquent la fin de G1/G2 |
| 12 | P3 RGPD, puis G3, puis G4 | tous | RGPD avant toute ouverture réelle hors école d’essai |

Côté web, en parallèle des étapes 4 à 8 et sans changement d’API : proxy BFF générique `/app/bff/api/*` avec CSRF/Origin, puis réalisation effective du journal de commandes durable. Celui-ci est aujourd’hui seulement documenté ; son code et ses tests sont absents de l’arbre.

## Limites de cet audit

- Il se fonde sur la présence de routes, tables et tests dans l’arbre. Il ne vérifie ni l’exactitude métier de chaque route ni l’état du serveur déployé.
- Les nombres de tests déclarés dans `STATUS.md` (89, puis 113) ne correspondent pas aux fichiers actuels ; aucun run n’a été relancé ici.
- Aucun résultat physique (GPS, batterie, VoiceOver) n’est déduit ; la collecte scolaire reste conditionnée à un profil d’appareil qualifié, qui n’existe pas.
- Les dépendances de `apps/api/package.json` utilisent en partie des plages (`jose ^6.1.0`, `pg ^8.16.3`, `zod ^4.0.0`). Le verrouillage repose sur `package-lock.json` ; à aligner avec l’exigence « dépendances verrouillées ».
