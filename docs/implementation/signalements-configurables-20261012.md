# Signalements configurables — contrat et décisions (12 octobre 2026)

Ce document est la référence commune de l'API, de l'app iOS et du panneau web. Il fixe les clés, le contrat HTTP et les règles ; le récit de livraison (tests exécutés, limites) est à la fin.

## Ce qui existait

Les onze signalements n'étaient ni une table ni une liste en dur : « Signaler » dépliait les **compétences du référentiel** de la formation (`drivy.competency_definition`, propre à chaque école et à chaque catégorie). Neuf compétences donnaient onze tuiles, parce que « Priorités » se dépliait en trois sous-thèmes. Une observation enregistrée porte `competency_id` et le titre de la tuile dans `text` ; le pictogramme était retrouvé depuis ces deux valeurs. Aucun ordre ni masquage n'était réglable.

## Décisions

1. **Un catalogue de dix-huit thèmes à clés stables**, défini par le serveur (`apps/api/src/observation-themes.ts`) et publié par l'API. Chaque thème est rattaché à une compétence du référentiel par la clé stable de celle-ci : aucun référentiel parallèle, la progression et les bilans ne changent pas.
2. **Les sept nouveaux thèmes précisent des compétences existantes**, comme « Priorités » le faisait déjà : ils n'ajoutent aucune compétence au référentiel d'une école.
3. **La configuration (ordre, affichage) est une ligne par école** (`drivy.observation_theme_settings`). Sans ligne, l'école a la configuration d'origine : douze thèmes affichés sur dix-huit.
4. **La permission est un droit du système existant** (`membership.grants`) : `MANAGE_OBSERVATION_THEMES`. L'administrateur a toujours le droit ; un moniteur l'obtient par ce droit, accordé comme les autres depuis « Équipe » sur le web.
5. **Masquer n'est qu'un réglage d'affichage.** Le serveur accepte toujours une observation d'un thème masqué (file hors ligne, leçon en cours) et toutes les lectures reconnaissent les dix-huit thèmes.
6. **Chaque observation qualifiée garde la clé de son thème** (`geo_observation.theme_key`), indépendante de l'ordre, de l'affichage et du texte, que le moniteur peut réécrire à la relecture.

## Catalogue

| # | Clé | Titre | Compétence (`stable_key`) | Affiché à l'origine |
|---|---|---|---|---|
| 1 | `vehicle` | Maîtrise du véhicule | `vehicule` | oui |
| 2 | `observation` | Observation et contrôles | `observation` | oui |
| 3 | `right-priority` | Priorité à droite | `priorites` | oui |
| 4 | `signage` | Signalisation | `priorites` | oui |
| 5 | `give-way` | Céder le passage | `priorites` | oui |
| 6 | `intersections` | Intersections et giratoires | `intersections` | oui |
| 7 | `speed` | Vitesse | `vitesse` | oui |
| 8 | `placement` | Placement sur la chaussée | `placement` | oui |
| 9 | `manoeuvres` | Manœuvres | `manoeuvres` (ancien : `parking`) | oui |
| 10 | `motorway` | Autoroute | `autoroute` (ancien : `motorway`) | oui |
| 11 | `anticipation` | Anticipation | `anticipation` | oui |
| 12 | `indicators` | Clignotants | `observation` | oui |
| 13 | `following-distance` | Distance de sécurité | `vitesse` | non |
| 14 | `braking` | Freinage | `vehicule` | non |
| 15 | `lane-change` | Changement de voie | `placement` | non |
| 16 | `moving-off` | Démarrage | `vehicule` | non |
| 17 | `bends` | Virages | `placement` | non |
| 18 | `eco-driving` | Éco-conduite | `vehicule` | non |

La clé est aussi le nom du pictogramme : `Observation-<clé>` dans le catalogue Xcode, `<clé>.svg` sur le web.

### Pourquoi ces sept

Ce sont les remarques les plus fréquentes d'une leçon que les onze thèmes obligeaient à ranger sous un intitulé trop large :

- **Clignotants** : signaler ses intentions (oublié, trop tard, resté allumé). Geste distinct du regard, mais dans la même séquence « regarder, signaler, manœuvrer » : rattaché à « Observation et contrôles ». Affiché à l'origine, parce que c'est la remarque la plus courante des quatre.
- **Distance de sécurité** : l'écart avec le véhicule qui précède, que « Vitesse » ne dit pas.
- **Freinage** : tardif, brusque ou mal dosé ; « Maîtrise du véhicule » couvrait aussi le démarrage et la direction.
- **Changement de voie** : présélection, changement de voie, rabattement ; « Placement sur la chaussée » décrit la position tenue, pas le déplacement.

À la demande du porteur, trois thèmes de plus portent le catalogue à dix-huit, tous masqués à l'origine :

- **Démarrage** : calage, démarrage en côte, départ brusque.
- **Virages** : vitesse d'entrée, trajectoire et regard dans la courbe.
- **Éco-conduite** : rapport engagé, régime, lever le pied tôt (Eco-Drive, enseigné et évalué en Suisse).

Écartés pour doublon : angle mort (déjà « Observation et contrôles »), feux de circulation (« Signalisation », dont le pictogramme est un feu), passage piéton (« Anticipation », dont le pictogramme est un piéton).

### Tuiles d'une leçon

Pour une formation donnée, « Signaler » montre, dans l'ordre configuré, les thèmes **affichés** dont la compétence existe dans le référentiel de cette formation (première clé de `competencyKeys` trouvée). Une compétence du référentiel qu'aucun thème du catalogue ne désigne (référentiel moto, remorque, ou propre à l'école) garde sa tuile générique, placée après les thèmes configurés : rien ne disparaît pour ces formations, et ces tuiles ne sont pas réglables.

## Permission

- Droit : `MANAGE_OBSERVATION_THEMES`, libellé « Gérer les signalements ».
- Peut modifier : un membre actif `ADMIN`, ou `INSTRUCTOR` portant le droit. La règle vit en base (`drivy.can_manage_observation_themes(school)`), utilisée à la fois par les politiques RLS de la table et par la commande.
- Peut lire : tout membre actif `ADMIN` ou `INSTRUCTOR`. Un élève seul reçoit 403.
- Le droit se donne par la commande existante `PATCH /v1/schools/{schoolId}/members/{membershipId}` (réauthentification récente, audit), sans mécanisme nouveau.

## API

### Lire

`GET /v1/schools/{schoolId}/observation-themes`

```json
{
  "data": {
    "id": "<schoolId>", "schoolId": "<schoolId>", "version": 1, "canManage": true,
    "themes": [
      {"key": "vehicle", "title": "Maîtrise du véhicule", "competencyKeys": ["vehicule"],
       "visible": true, "defaultVisible": true, "defaultPosition": 0}
    ]
  },
  "requestId": "...", "serverTime": "..."
}
```

- `themes` contient toujours les dix-huit thèmes, dans l'ordre configuré. `version` vaut 1 tant que l'école n'a rien modifié ; en-tête `ETag: "<version>"`.
- `defaultVisible` et `defaultPosition` décrivent la configuration d'origine : un client réinitialise en renvoyant cet ordre (et, pour une réinitialisation complète, cet affichage) par la commande ci-dessous.
- `canManage` est une aide d'affichage ; le serveur revérifie à chaque écriture.

### Modifier

`PUT /v1/schools/{schoolId}/observation-themes` avec `If-Match: "<version>"` et `Idempotency-Key: <operationId>`

```json
{"operationId": "<uuid>", "themes": [{"key": "right-priority", "visible": true}, {"key": "vehicle", "visible": false}]}
```

- `themes` : les dix-huit clés, chacune une fois, dans le nouvel ordre ; au moins une `visible`. Toute autre forme : 400 `INVALID_REQUEST`.
- 200 : la même projection que la lecture, `version` augmentée de 1.
- 403 `OBSERVATION_THEMES_ACCESS_REQUIRED` : ni administrateur ni droit. 412 `VERSION_CONFLICT` : la configuration a changé depuis la lecture (relire, puis rejouer le changement). 428 sans `If-Match`.
- Commande `SAVE_OBSERVATION_THEMES`, ressource `ObservationThemeSettings` (identifiant : celui de l'école), audit `ObservationThemesSaved`, rejouable avec le même `operationId` et consultable par `GET /operations/{operationId}`.

### Observations

`POST /lessons/{lessonId}/geo-observations` et `PUT /geo-observations/{observationId}` acceptent un champ facultatif `themeKey` (une des dix-huit clés, ou `null`). Il exige `competencyId`, et la clé stable de cette compétence doit figurer dans `competencyKeys` du thème, sinon 422 `OBSERVATION_THEME_MISMATCH`. Les réponses portent `themeKey` (`null` si absent).

Un client n'envoie `themeKey` que si la configuration qu'il utilise vient du serveur (lecture réussie, même mise en cache) : une API antérieure refuse un champ inconnu.

## Synchronisation

- La configuration est petite et versionnée : pas de flux, chaque client relit à ses moments naturels.
- **iOS** : lecture à l'ouverture de l'espace de l'école et à chaque ouverture de « Signaler » ; copie locale par école pour le hors-ligne ; une lecture arrivée pendant que « Signaler » est ouverte ne s'applique qu'à l'ouverture suivante.
- **Web** : lecture à l'ouverture de la section ; en cas de 412, la section recharge et le dit.
- Deux modifications concurrentes : la seconde reçoit 412 et rien n'est écrasé.

## Compatibilité

- Les observations existantes gardent `competency_id` et `text` ; la migration renseigne `theme_key` pour celles dont le texte est encore exactement le titre de la tuile. Les autres restent sans clé et continuent d'être reconnues par leur compétence et leur texte, comme avant.
- Une école sans ligne de configuration voit ses onze tuiles dans le même ordre, plus « Clignotants ».
- Une clé inconnue dans une configuration enregistrée est ignorée à la lecture ; un thème ajouté plus tard au catalogue prend sa place d'origine.
