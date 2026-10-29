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

## Publication des trois pilotes

Le 28 octobre 2026, à la demande du porteur de voir l’état courant, l’aperçu remplace la page seule par les trois pilotes : Accès, Agenda, Élèves. Même adresse, même bloc Caddy, mêmes en-têtes ; seule la version servie change.

| Élément | Valeur |
| --- | --- |
| Identifiant | `20261028T205927Z-0688868ddabb` |
| Horodatage UTC | `2026-10-28T20:59:27.463546+00:00` |
| SHA du rendu | `0688868ddabbd6aa4c9e6000a2f25486e1d0e9e1` |
| SHA-256 archive | `e5785e356880522a35d4d371568414df31097bfd68c375461d71077217aa50b1` |
| Fichiers | 20 |
| Caddyfile avant et après | `bf3bb46771f37b2ad392bf0ddceb8889b547e95d4bab1c19ed73e14604e865ce` (inchangé) |
| Version précédente | `/srv/drivy-preview/releases/1812bd6056a970d94dd661443f2bcbbf3ac0a872` |

Exécuté : plan sans mutation puis publication ; contrôle du script sur le serveur (HTML servi identique, en-têtes de sécurité) ; manifeste public au bon SHA, CSP/HSTS/noindex présents, racine `shulker.ch` en 200 ; Élèves et Agenda chargés depuis l’adresse publique avec leurs morceaux lazy sous la CSP réelle.

Retour à la page seule : `python scripts/homelab/deploy-preview-311.py --rollback 20261028T205927Z-0688868ddabb`, puis `--execute`. Il remet le lien `current` sur `1812bd60` sans toucher Caddy. Le retrait complet de l’aperçu passe ensuite par `--rollback 20261028T202042Z-1812bd6056a9`, qui n’est accepté qu’une fois `1812bd60` redevenu actif.

## Publication avec Équipe, Disponibilités/Absences, Formations et tarifs

Le 28 octobre 2026 au soir, après intégration des premiers lots des agents (#325, #323, #326/#327 partiels) et de la console reconstruite. Même adresse, même bloc Caddy.

| Élément | Valeur |
| --- | --- |
| Identifiant | `20261028T215739Z-e2a0d5e65908` |
| SHA du rendu | `e2a0d5e65908cff3c7ca60e42ca97cadf194ea12` |
| SHA-256 archive | `45326711984190c4c166ca386ae2eeb2ae9e6d6b155c17f6fc72dff4450a57f9` |
| Fichiers | 53 |
| Caddyfile | `bf3bb467…865ce`, inchangé |
| Version précédente | `0688868ddabbd6aa4c9e6000a2f25486e1d0e9e1` |

Exécuté avant publication : typage client et serveur, 465 tests web, build de production, build d’aperçu (aucun import hérité), captures locales 1440/1024/390 en clair et sombre des nouvelles pages. Après publication : manifeste public au bon SHA, CSP présente, racine `shulker.ch` en 200, Équipe, Disponibilités, Formations et Invitations élèves chargées depuis l’adresse publique sans erreur ni débordement. Le champ `scope` du manifeste garde son ancien libellé.

Retour à la version précédente : `--rollback 20261028T215739Z-e2a0d5e65908` puis `--execute` ; ensuite, si besoin, la chaîne décrite plus haut.

## Publication du 29 octobre 2026 (cours, signalements, trajets, préférences, préparation, école)

| Élément | Valeur |
| --- | --- |
| Identifiant | `20261029T152320Z-ce3b35597771` |
| SHA du rendu | `ce3b355977710b05a8846fcfcb20fc8eac3306b2` |
| SHA-256 archive | `2acadf476d0196fe807be23204a34f70e4f07a0f0da538c9bb918524886c67ce` |
| Fichiers | 72 |
| Caddyfile | inchangé (`bf3bb467…865ce`) |
| Version précédente | `e2a0d5e65908cff3c7ca60e42ca97cadf194ea12` |

Contenu ajouté depuis `e2a0d5e6` : cours collectifs (#328), finitions Formations et tarifs (#326/#327, partielles), Signalements (#331), Trajets (#332), Préférences personnelles en page autonome `?page=preferences` (#333), Préparation de l’école (#321), fiche École (#330 partiel), menu du compte dans le shell. Exécuté avant : typage client et serveur, 472 tests web, deux builds ; après : manifeste au bon SHA, racine en 200, Signalements, Trajets, Agenda et Préférences chargés depuis l’adresse publique sans erreur ni débordement. Retour : `--rollback 20261029T152320Z-ce3b35597771` puis `--execute`.
