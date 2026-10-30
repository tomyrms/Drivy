# EPIC #280 — publication pour essai personnel

28 octobre 2026, publication vérifiée à 19:21 UTC (20:21 Europe/Zurich). Le porteur a remplacé la demande d'accord final par l'autorisation explicite : « déploie directement sans mon accord si j'aime pas on revient en arrière ». La livraison est publiée pour son essai ; l'épic reste en cours jusqu'à sa validation et à la qualification différée.

- URL : https://drivy.shulker.ch/app/
- Source publiée : `be8a02457ef2c8877117e9a13557b288738fc4bf`, branche `codex/epic-280-web`, base qualifiée `c94ec2bb` fusionnée.
- Archive Git allowlistée : 312 fichiers sources/API/web/migrations et outils nécessaires, sans données privées, tests de fixtures ni dossier `.local`. SHA-256 : `61c0b4340d970b14635e526b57173ccd9b3cc42702f7d22486d1f897ec4b5fd2`.
- Ancienne release conservée : `a41cf64d153252dc133a60f29755f0685516be8f`.

## Exécution réelle

Sauvegarde fraîche de `drivy_refonte` sur CT113 à 19:20:28 UTC : 1 805 023 octets, fichier privé root 0600, catalogue et tous les blocs relus avec `pg_restore`. Chemin exact dans le [reçu expurgé](epic-280-publication-receipt.json). Aucune restauration d'essai exécutée pour cette sauvegarde ; ne pas confondre intégrité de lecture et restauration réelle.

Installation des dépendances verrouillées, compilation API et web/BFF sur Node 24.21.0 dans un répertoire immuable ; migration additive `20261028b_lesson_gps_preparation_audit.sql`, vérification des rôles et RLS, réduction aux dépendances runtime. Les anciens services sont restés actifs pendant le build. Le lien `current` a ensuite été changé atomiquement, puis API/web/course-worker redémarrés sur la même release.

La première tentative à 19:17 UTC s'est arrêtée au staging : Python 3.11.2 ne supportait pas le paramètre `tarfile.extractall(filter=...)`. Aucune migration, bascule ou interruption de service n'avait eu lieu. La procédure privée a été corrigée par extraction manuelle des seuls fichiers réguliers autorisés, empreintes et confinement des chemins vérifiés, liens refusés et permissions explicites. Une **nouvelle** sauvegarde a précédé la reprise réussie ; aucun contrôle de sécurité n'a été désactivé.

Pas de remise à zéro, de restauration, de suppression de données ou de comptes, de changement DNS/identité/environnement/drop-in. Les empreintes des six fichiers de configuration concordent avant/après. GPS obligatoire reste désactivé et la qualification Messages existante est conservée.

## Vérifications après publication

[Sonde indépendante en lecture seule](epic-280-publication-homelab-20261028.json), exécutée après la vérification intégrée de l'installateur :

- API, web et course-worker actifs ; CWD réels dans `be8a0245`, zéro redémarrage automatique, aucun override. Identité active et hors mutation.
- API readiness `ready`. 57 migrations sur 57, zéro empreinte divergente ou migration inconnue ; policy d'audit présente.
- 91 tables avec RLS + FORCE RLS, rôles applicatifs sans privilèges excessifs. Base `drivy_web` absente, aucune base nouvelle créée.
- Callback OIDC exact inchangé, sans joker. Configuration conservée avec permissions 0600.
- Les cinq entrées publiques répondent avec l'HTML exact de la release, `no-store` et CSP conservée ; JS/CSS d'entrée identiques par empreinte, cache immutable. API anonyme refusée en 401.
- Rechargement réel de la page publique dans le navigateur Atrium : nouvelle feuille `index-CZnPAVFO.css`, formulaire présent, largeur globale 1440/1440. Aucun login ni acte métier sur les données du porteur.
- [Contrôle local du build sous CSP exacte](epic-280-publication-csp.md) : popups fonctionnels ; le probe Zod préexistant produit un refus `eval` intercepté, sans assouplissement CSP.

Ce contrôle de publication ne qualifie pas tous les parcours authentifiés, les appareils physiques ou la campagne #309/#84.

## Retour arrière et attente

Le [plan de rollback](epic-280-delivery.md) restaure ensemble API/web/worker vers `a41cf64d`. L'ancienne release et ses artefacts sont présents. Le script privé `.local/deploy-epic-280.py --rollback --sha be8a02457ef2c8877117e9a13557b288738fc4bf` vérifie le contexte, sauvegarde, bascule le lien et vérifie la publication. Aucun rollback n'a été nécessaire ou exécuté. La policy additive reste compatible ; les écritures reçues depuis la publication sont conservées, aucune restauration de base automatique.

Le code et les preuves sont committés localement ; aucun workflow de campagne ni fermeture d'issue n'est déclenché pour présenter cette publication comme une qualification complète. Les commits de reçu postérieurs n'altèrent pas le SHA produit déployé.

**État : DEPLOYED_AWAITING_USER_TRIAL.** Attendre le retour du porteur. Après sa validation explicite seulement, exécuter #309/#84, corriger, qualifier les critères et finaliser fusion/clôture. Aucune nouvelle IPA n'est produite par cette refonte web.
