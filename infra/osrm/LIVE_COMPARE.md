# Comparaison du recalage direct, sans export des mesures

`live-compare.py` et `live-compare.js` rejouent exactement deux captures explicitement désignées. Les points déchiffrés restent en mémoire dans CT114. Seuls des agrégats numériques et des empreintes de code reviennent. Les rapports JSON de captures réelles et leurs identifiants ne sont pas versionnés avec ces scripts. Une synthèse agrégée distincte peut être consignée dans `docs/implementation/`.

## Exécution

Depuis la racine du dépôt, avec les dépendances verrouillées déjà installées, Python 3 et Node disponibles :

```text
node --test infra/osrm/live-compare.test.js
python -B infra/osrm/live-compare_test.py
python -B infra/osrm/live-compare.py
python -B infra/osrm/live-compare.py --run <capture_1> <capture_2>
python -B infra/osrm/live-compare.py --run --diagnostic <capture_1> <capture_2>
```

Sans `--run`, le lanceur prépare uniquement le bundle de calcul local. Il ne contacte ni SSH ni la base. Les deux UUID restent des arguments locaux, jamais un exemple à copier dans Git. Les entrées `.local/osrm/live-compare.js/.py` délèguent à ces sources versionnées.

Avec `--run` :

1. Une sélection limitée aux deux captures s'exécute dans CT113 avec `BEGIN READ ONLY`, limite de temps et `ROLLBACK`. Aucun repli vers une sélection globale.
2. Les lignes restent chiffrées pendant leur transit en mémoire sur l'hôte du homelab.
3. Le script et un bundle du **vrai** `apps/api/src/live-matching.ts` sont transmis à Node dans CT114, sans fichier de mesures, installation, redémarrage de service ou déploiement.
4. La clé locale de CT114 sert au déchiffrement AES-GCM avec les AAD originales. Aucun secret n'est transmis au poste local.
5. Le seul destinataire HTTP autorisé est le chemin de matching du moteur `http://192.168.1.158:5000`. Redirections refusées, aucun fournisseur de secours.
6. Deux barrières de sortie rejettent les champs sensibles, chaînes libres et valeurs non finies. Aucun stderr SSH, PostgreSQL, Node ou moteur n'est recopié. Les échecs restent génériques.

L'ordre du tableau `captures` est celui des arguments. Les UUID, noms, coordonnées, horodatages individuels et réponses HTTP brutes n'y figurent jamais.

## Comparaison représentative du modèle actuel

- `before` : predictor actuel sans correction routière. Ce n'est **pas** l'ancien glide entre sommets filtrés.
- `after` : même predictor avec le déplacement routier et la correction exponentielle de `SchoolMapPredictor`.
- Requête au plus toutes les 2,5 secondes, déclenchée par une mesure, avec 3 à 20 mesures sur 30 secondes au maximum. À 1 Hz, la cadence effective est d'environ trois secondes.
- Les règles API sont exécutées par le module réel. Les raisons de refus sont une ventilation diagnostique des gardes, pas une deuxième source de décisions d'acceptation.
- Acquisition suivante : réponse antérieure périmée, y compris avant écriture durable de la nouvelle mesure. Réponse trop vieille : rejet. Expiration d'une correction acceptée après deux secondes sans nouvelle mesure.
- Les segments et ruptures temporelles de plus de quatre secondes ne sont pas reliés. Une rupture de séquence provoque aussi un reset conservateur dans ce modèle.
- La livraison après acquisition est supposée à 100 ms. Le predictor est ancré à la **livraison**, comme l'UI actuelle, sans `measuredAt`.
- `--network-ms N` ajoute un RTT client/API hypothétique à la durée mesurée du calcul. Cela ne constitue pas une mesure réseau iPhone.
- Le contrôle de fraîcheur API utilise des `capturedAt` translatés à l'époque du rejeu. Les intervalles originaux et `elapsedMs` restent inchangés.

Les paramètres de portage viennent de `SchoolMapMotion.swift`, `SchoolLiveMatchModels.swift`, `SchoolLiveMatchCoordinator.swift` et `SchoolCaptureLiveMap.swift`. Les empreintes `sourceHashes` identifient le bundle API, ces quatre fichiers Swift concaténés et le script JS. **Relire et adapter le port JS si le comportement Swift change** : son empreinte seule ne prouve pas l'équivalence.

## Ce que mesurent les chiffres

| Champ | Définition |
|---|---|
| `storedSpeedSamples`, `storedCourseSamples` | Nombre de mesures qui contiennent effectivement vitesse ou cap. |
| `speedMs` | Vitesse estimée par une corde causale couvrant environ deux secondes quand disponibles. |
| `pairSpeedMs` | Distance entre deux mesures successives divisée par leur intervalle. |
| `clientRejections` | Mesures non envoyées, ventilées suivant l'ordre des gardes client. |
| `requests`, `accepted`, `applied` | Requêtes API simulées, réponses acceptées par le vrai module, puis corrections admises à l'affichage simulé. |
| `coveredFixes`, `coverageShare` | Fixes recevant une correction admise, rapportés à toutes les mesures. Pas une couverture cartographique d'un itinéraire. |
| `coverageSeconds`, `coverageTimeShare` | Temps simulé avec suggestion routière active, échantillonné à 60 Hz. |
| `osrmMs` | Durée du transport direct moteur et lecture de réponse, uniquement pour les appels vraiment effectués. |
| `matchLatencyMs` | Durée du calcul API pur, sans route Fastify, droits, réseau mobile ou ordonnanceur Apple. |
| `before.errorM`, `after.errorM` | Distance aux **mesures GPS interpolées**, jamais à une vérité terrain. |
| `eventJumpM` | Discontinuité à un événement calculée avant/après au même instant. |
| `frameStepM`, `frameSpeedMs` | Déplacement entre frames et vitesse apparente à 60 Hz. Ce ne sont pas des mesures de fluidité sur appareil. |

Les percentiles sont des rangs empiriques `floor(p × (n-1))`, sans interpolation. `null` signifie absence d'échantillons, pas zéro. Une absence d'appel due à la faible vitesse est un résultat légitime, pas un motif pour abaisser le seuil.

**Limite majeure : le Doppler n'est pas stocké dans le contrat actuel.** Le substitut causal sert au cap et à la vitesse du predictor ainsi qu'au garde client à 2 m/s. Il peut modifier les décisions qu'aurait prises le vrai téléphone. Le rejeu ne démontre ni exactitude routière, ni précision GPS, ni amélioration visuelle physique, ni consommation de batterie.

## Diagnostic moteur optionnel, distinct du produit

`--diagnostic` envoie en plus des fenêtres de mêmes taille et cadence directement au moteur, **sans les gardes d'admission client/API**. Ces réponses ne sont jamais appliquées au predictor et ne modifient ni `requests`, ni `accepted`, ni la couverture du scénario représentatif.

Tout est rangé sous `diagnosticDirectOSRM` :

- `tailAvailable` : fenêtres dont le dernier point dispose d'un résultat et d'une confiance exploitable.
- `fullWindows` : fenêtres dont tous les tracepoints sont présents. Cela ne signifie pas que les gardes de confiance, ambiguïté ou distance passent.
- `sampledTracepoints` et `nonNullTracepoints` comptent les occurrences dans les fenêtres **chevauchantes**, pas des mesures uniques.
- `failures` contient des conditions **indépendantes, donc non additionnables**. Confiance, ambiguïté et distance ne sont évaluées que si le dernier point est exploitable.
- `failures.provider` signifie rejet du transport adaptateur, pas nécessairement panne réseau. `transport` distingue HTTP 400, HTTP 429, HTTP 5xx et erreur réseau. Pour une réponse non-OK, seuls `NoMatch`, `NoSegment`, `InvalidQuery` ou `Other` peuvent être comptés. Le texte libre de réponse est jeté.
- Une réponse HTTP 400 `NoMatch` est une absence de correspondance routière sur cette fenêtre, **pas** une panne OSRM.

Les rapports JSON réels restent dans `.local/osrm/`. Les tests versionnés n'utilisent que des données synthétiques, y compris la réponse HTTP 400 `NoMatch`, les refus de confiance et de retard, et l'absence de mouvement appliqué quand le garde de faible vitesse bloque les requêtes.
