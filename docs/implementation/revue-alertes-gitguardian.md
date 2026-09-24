# Revue des alertes de secrets

## PR 2 — G1C

24 septembre 2026, contrôle `107747726180`, commit `6ffc1036890ccc3d8232f5f8b90be4d77f6db195`. L'incident **37580704** indique « Generic Password » dans `infra/deploy/install-web-service.py`, ligne 24 : `account = pwd.getpwnam('drivy-web')`. Cette instruction appelle le module standard Python `pwd` pour rechercher le compte Unix **drivy-web** ; elle ne lit ni ne définit un mot de passe. Le secret OIDC, généré aléatoirement sur CT114, provient d'un coffre root/0600 séparé et ne figure pas dans ce source.

Conclusion : **faux positif documenté**, contrôle externe toujours en échec tant que son classement n'est pas enregistré dans GitGuardian. Aucun détecteur n'est neutralisé et aucun historique n'est réécrit. Gitleaks sur `master..HEAD` et sur les changements préparés ne relève aucun secret. Le scan de l'historique complet trouve 44 occurrences supplémentaires dans le commit initial de conception `4b5f293f` : les 44 lignes sont des empreintes SHA-256 documentaires, pas des credentials. Le dossier canonique et ses empreintes restent inchangés.

## PR 1 — G1A/G1B

24 septembre 2026, contrôle `107728038753`, source `d2093125e2e8ee9b89e9a7ab57d372bb543e8f62`. GitGuardian signale trois occurrences du commit `0158f8efa5db338cff9b79fd4e3ab3b6a57c440f` dans l'historique de la PR. Leur code source a été relu, sans consulter ni publier les secrets hébergés.

| Incident | Source | Conclusion de la revue |
|---|---|---|
| 37578146 | `scripts/dev/provision-school.test.mjs` | Mot de passe public `local-development-only` du seul laboratoire loopback, créé puis nettoyé par un test. Aucun mot de passe hébergé n'utilise cette valeur. |
| 37578147 | Même fichier | URL portant le mot de passe factice `unused`, fournie à `assert.throws` pour vérifier le refus d'une cible invalide. Elle n'est pas utilisée pour ouvrir une connexion. |
| 37578148 | `infra/deploy/install-services.py` | L'expression construit une variable d'environnement à partir de `values['bootstrapAdminPassword']`. Le source contient le nom du champ, aucune valeur de mot de passe. Le coffre est chargé séparément depuis un fichier privé root. |

Ces alertes sont classées par cette revue comme credential de test et faux positifs. Le contrôle GitGuardian reste signalé en échec tant que sa propre interface n'a pas enregistré leur classement ; cette revue ne prétend pas l'avoir rendu vert. Aucun détecteur n'est désactivé, aucun chemin n'est exclu et l'historique n'est réécrit pour masquer les occurrences. Le contrôle Gitleaks de l'historique `master..HEAD` ne relève aucun secret.

[GitGuardian documente](https://docs.gitguardian.com/internal-monitoring/prevent/detect-secrets-in-real-time-in-github) l'analyse de chaque commit de la PR et le classement des faux positifs ou credentials de test. Les alertes présentes dans un ancien commit ne disparaissent donc pas simplement avec une modification ultérieure.
