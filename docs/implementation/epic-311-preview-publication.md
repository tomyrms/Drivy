# #311 — publication de la page d’aperçu

Le 28 octobre 2026, après la demande du porteur de publier une seule page pour juger la direction artistique, l’aperçu **Modifier les accès** est publié sur <https://shulker.ch/drivy-preview/>. Le coordinateur a fourni et autorisé l’artefact au SHA `1812bd6056a970d94dd661443f2bcbbf3ac0a872`.

Cette publication contient des données synthétiques et ne raccorde aucune API. Elle ne constitue ni la livraison de toute l’EPIC #311, ni une qualification des parcours métier. Les autres pilotes et la généralisation attendent le retour du porteur. Aucun IPA, migration, purge ou déploiement du produit n’est inclus.

## Périmètre exécuté

- Transport SSH existant vers le homelab, puis CT109 Caddy uniquement.
- 13 fichiers statiques dans `/srv/drivy-preview/releases/1812bd6056a970d94dd661443f2bcbbf3ac0a872`, servis par le lien `current`.
- Route limitée à `/drivy-preview/*` sur l’origine `shulker.ch`, distincte du portail `drivy.shulker.ch`. `/drivy-preview` redirige vers le chemin avec slash ; la racine réécrit vers `preview-311.html`. Les imports de l’artefact sont relatifs `./`.
- Bloc `crowdsec_protect`, HSTS et proxy racine de `shulker.ch` conservés. Les autres hosts Caddy sont identiques avant/après adaptation, après normalisation des identifiants internes de groupes.
- CSP : `default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'`.
- En-têtes `X-Robots-Tag: noindex, nofollow, noarchive`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, permissions caméra/micro/géolocalisation refusées, cache désactivé.
- Aucun changement CT114, PostgreSQL, API, worker ou portail produit.

## Preuves limitées de publication

Reçu : `/srv/drivy-preview/operator/20261028T202042Z-1812bd6056a9/receipt.json`.

| Élément | Valeur |
| --- | --- |
| Horodatage UTC | `2026-10-28T20:20:42.856817+00:00` |
| SHA du rendu | `1812bd6056a970d94dd661443f2bcbbf3ac0a872` |
| SHA-256 archive | `ebfcb4778763bb305c96acd8dc80e961223375c68353ca164998f70a0da76391` |
| Caddyfile avant | `3a8f6a7e32b0e4c4992c8e092bc78db075303a506e7488ec5ac44505d5f13655` |
| Caddyfile publié | `bf3bb46771f37b2ad392bf0ddceb8889b547e95d4bab1c19ed73e14604e865ce` |

Exécuté : syntaxe Python locale et distante ; archive déterministe ; plan sans mutation ; sauvegarde exacte ; `caddy validate` sur candidat avant remplacement ; comparaison des autres hosts ; reload et service actif ; réponse HTTP 200 et SHA-256 exacts pour HTML, métadonnées du build, script de thème, JavaScript, CSS et police ; HTML identique par l’adresse Cloudflare publique ; CSP/noindex/HSTS/nosniff présents. La racine `shulker.ch` répond toujours 200. Le plan de rollback a relu la sauvegarde exacte et vérifié la configuration ainsi que le lien actif.

Le coordinateur a confirmé indépendamment HTTPS et le smoke navigateur public (confirmation, lecture, refus conservant la saisie, thèmes clair/sombre, mobile), sans erreur JavaScript. Aucune campagne étendue n’a été lancée. Le rollback est préparé et contrôlé en lecture ; il n’a pas été exécuté, afin de laisser l’aperçu disponible pour l’essai.

## Opération et retour arrière

Script : [`scripts/homelab/deploy-preview-311.py`](../../scripts/homelab/deploy-preview-311.py). Sans `--execute`, il ne modifie pas le serveur. Il refuse les symlinks, fichiers cachés, sources et formats inattendus dans l’artefact ; vérifie le SHA visible ; contrôle l’extraction ; sauvegarde Caddy ; valide avant reload ; restaure automatiquement après un échec consécutif à l’activation.

Plan d’une publication :

```powershell
python scripts/homelab/deploy-preview-311.py --dist <dist-preview-311> --sha <SHA-complet>
```

L’ajout de `--execute` publie l’artefact. Chaque version est immuable ; un SHA déjà présent est refusé.

Plan de retrait de la publication actuelle :

```powershell
python scripts/homelab/deploy-preview-311.py --rollback 20261028T202042Z-1812bd6056a9
```

Le même appel avec `--execute` restaure exactement le Caddyfile sauvegardé et retire le lien `current` puisqu’aucun aperçu précédent n’existait. Les fichiers et preuves restent conservés sous `/srv/drivy-preview` ; aucun effacement récursif n’est nécessaire. Le script refuse le rollback si Caddy ou la version active a changé depuis cette publication, pour préserver une intervention ultérieure. Il valide la sauvegarde avant rechargement. Le reste du homelab n’est pas concerné.

Références de configuration : [Caddy handle_path](https://caddyserver.com/docs/caddyfile/directives/handle_path), [file_server](https://caddyserver.com/docs/caddyfile/directives/file_server), [validate et reload](https://caddyserver.com/docs/command-line).
