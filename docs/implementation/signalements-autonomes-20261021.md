# Signalements autonomes (21 octobre 2026, issue #56)

## Décision

Demande du porteur : une formation configurée avec six compétences ne donnait que six ou sept boutons dans « Signaler », alors que tous les signalements étaient activés. Il veut une **dissociation complète**, de l'interface à la base.

Règle retenue : **les compétences d'une formation servent à son évaluation. Elles ne décident plus quels signalements existent, peuvent être créés, enregistrés ou relus.** Les thèmes affichés dans les paramètres de signalement sont la seule source de la palette.

```
Catalogue des signalements + affichage et ordre de l'école → palette « Signaler » → événement identifié par themeKey
Formation → référentiel de compétences → évaluation et progression        (indépendant)
```

Cette règle remplace la section « Tuiles d'une leçon » et l'exigence de compétence décrite dans [signalements-configurables-20261012.md](signalements-configurables-20261012.md).

## Cause du nombre réduit de tuiles

Avant ce changement, l'app gardait un thème seulement si l'une de ses `competencyKeys` existait dans le référentiel de la formation, puis ajoutait une tuile générique par compétence non couverte. Une compétence pouvait produire trois thèmes (`priorites`) ou deux (`observation`), et une compétence propre à l'école produisait sa tuile générique. Le nombre affiché dépendait donc du référentiel et pas des réglages de l'école. La composition exacte du référentiel du porteur n'a pas été lue.

## Ce qui change

### Base : migration `036_autonomous_signals.sql`

- Les contraintes de 009 (`LIVE QUALIFIED` exige une compétence) et de 026 (`theme_key` exige une compétence) sont retrouvées par leur définition puis supprimées. La migration échoue si l'une manque ou existe en double. 009 et 026 ne sont pas réécrites.
- `geo_observation_live_qualified` : un signalement `LIVE QUALIFIED` garde un statut et nomme ce qui est observé, par son thème ou, pour les observations antérieures, par sa compétence.
- `geo_observation_theme_key` : clé au bon format, jamais sur un repère (`MARKER`).
- Aucune ligne existante n'est modifiée : toutes avaient une compétence. RLS, auteur, contexte de leçon, ancres, versions, idempotence et retraits sont inchangés.

### API

- `geoObservationCommand` : `themeKey` + statut suffisent pour qualifier un signalement `LIVE`. Thème inconnu : 400. Statut absent, ou ni thème ni compétence : 400. Thème sur un repère : 400.
- `OBSERVATION_THEME_MISMATCH` n'est plus émis : aucune correspondance thème/compétence n'est vérifiée. Une compétence fournie (ancien client, note de relecture) doit toujours appartenir au référentiel de la formation (`CURRICULUM_VERSION_MISMATCH`).
- Modification (`PUT`) : un corps sans `themeKey` **garde** le thème enregistré, même si le texte ou la compétence change. Avant, changer la compétence effaçait le thème. Seuls un `null` explicite ou le passage en repère le retirent. Le service revérifie après résolution qu'un signalement qualifié garde un thème ou une compétence.
- `competencyKeys` reste publié dans `GET /observation-themes`, sans être relu par aucune règle : les apps antérieures au 21 octobre refusent une configuration sans ce champ (`(1...8).contains`). Il est déprécié. Le retirer demandera une version minimale de l'app.

### iOS

- `SchoolLiveObservationTheme` n'a plus de compétence : `key` + `title`, identité = clé. Les tuiles sont les thèmes affichés de la configuration, dans l'ordre manuel ou figé, sauf ceux que l'école ne liste pas.
- L'enregistreur ne lit plus le référentiel : plus de `loadCompetencies`, plus de chargement ni de « Réessayer » liés au référentiel dans « Signaler ». La palette est prête dès l'ouverture, avec ou sans réseau.
- Le corps envoyé porte `themeKey`, `competencyId: null`. Aucune compétence n'est jointe ni déduite.
- Validateurs aller (`SchoolObservationBody.isValid`) et retour (`hasValidObservation`) acceptent un signalement qualifié par son seul thème. Ils refusent toujours un signalement sans statut, ou sans thème ni compétence.
- Éditeur d'observation : un signalement se qualifie par un **thème** (liste des thèmes de l'école, masqués compris). Une compétence déjà portée par un ancien signalement est conservée telle quelle. Une note de relecture garde son choix facultatif de compétence.
- `SchoolObservationTheme` lit `competencyKeys` s'il est présent, vide sinon.

### Web

- `observationThemeSchema` : `competencyKeys` facultatif. La console ne le lisait déjà pas.

## Compatibilité et ordre de déploiement

1. **Service d'abord** (migration 036 + API). Les apps déjà installées continuent de fonctionner : elles envoient encore une compétence, toujours acceptée. Leur palette reste filtrée tant qu'elles ne sont pas mises à jour.
2. **App ensuite**. Une app à jour face à un service sans 036 se verrait refuser ses signalements (400). La demande resterait dans la file chiffrée, sans perte, jusqu'au déploiement du service.
3. Une ancienne app qui relit un signalement autonome le refuse dans son validateur de lecture (`competencyId == nil`), donc toute la liste de la leçon. Le porteur est le seul utilisateur de l'app : la mise à jour de son iPhone suit le déploiement. Aucune compétence n'est fabriquée pour tromper un ancien client.
4. Les commandes déjà écrites dans la file chiffrée ne sont pas réécrites : même `operationId`, même corps, donc pas d'`IDEMPOTENCY_MISMATCH`. Elles portent une compétence et restent valides.

## Historique et consommateurs

- Les anciennes observations gardent compétence, texte, clé éventuelle, instant, ancre et bilans. Les anciennes tuiles génériques ne créent plus de bouton, mais leurs événements restent lisibles.
- Liste, replay, carte, bilan et agenda résolvent déjà le pictogramme par `themeKey` d'abord. Aucun ne joint `competency_definition` pour lire une observation.
- Classement intelligent : inchangé, il compte déjà par `theme_key` des événements `LIVE QUALIFIED`.
- Bilan : les regroupements « compétences travaillées » ne retiennent que les observations qui portent une compétence. Un signalement autonome ne marque aucune compétence et ne crée ni note ni niveau. C'est voulu.

## Vérifications

| Exigence de #56 | Vérification | Résultat |
|---|---|---|
| 18 thèmes enregistrables sans compétence correspondante | API, vraie PostgreSQL : les 18 clés en `POST` avec `competencyId: null` | Réussi |
| Création, relecture, modification sans compétence ; thème conservé quand `themeKey` est omis | API, vraie PostgreSQL | Réussi |
| Thème inconnu, statut absent, ni thème ni compétence : refusés | API (400) et SQL direct (contraintes nommées) | Réussi |
| Progression et compétences intactes après signalement | API : `GET /trainings/{id}/progress` identique avant/après | Réussi |
| Palette identique quel que soit le référentiel | Swift : `tiles(for:)` n'accepte plus de compétences ; 18 tuiles si tout est affiché | Écrit, à exécuter sur runner Apple |
| Validateurs iOS aller/retour | Swift : corps et lecture autonomes valides, sans thème ni compétence refusés | Écrit, à exécuter sur runner Apple |
| Masquage, ordre, instantané, école ancienne | Tests Swift existants adaptés | Écrit, à exécuter sur runner Apple |
| Suite serveur et web complète | `npm test` API (vraie PostgreSQL, Mailpit) et web | 557 API, 316 web |
| Palette sur iPhone/iPad, VoiceOver | Recette sur appareil (#55) | Non exécutée |
