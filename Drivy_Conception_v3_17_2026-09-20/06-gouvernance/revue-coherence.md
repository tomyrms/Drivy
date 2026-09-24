# Revue de cohérence documentaire V3.17

> 20 septembre 2026 · [Index](../README.md) · [Audit courant](audit-corrections-v3-17.md).

## Preuves de cette livraison

| Portée | Rapport courant |
|---|---|
| Source V3.16 avant modification | [496 empreintes vérifiées](../annexes/source-v3-16.json) |
| Application, interactions et dispositions | [Application V3.17](../annexes/verification-application-v3-17.json) |
| Régression de la carte et du signalement | [Atelier V3.17](../annexes/verification-atelier-v3-17.json) |
| Couverture, composants, absence de dérive des contrats | [Cohérence V3.17](../annexes/verification-composants-v3-17.json) |
| Liens et contrats de forme | [Documentaire exécuté sur V3.17](../annexes/verification-documentation-v3-17.json) |
| Lecteur et galerie complémentaire | [Lecteur V3.17](../annexes/verification-lecteur-v3-17.json) |
| Ouverture directe locale | [Blocage de l’environnement, non qualifié](../annexes/verification-ouverture-locale-v3-17.json) |
| Captures de la nouvelle application | [Registre de génération](../DESIGN/assets/application-v3-17/captures.json) |
| Intégrité de livraison | [Manifeste SHA-256](../SHA256SUMS.txt) |

Ces rapports portent leur environnement et leur date. Une absence de dépendance, un timeout ou une assertion fausse produit un code non nul. Les anciens rapports gardent leur numéro et leur portée historique. La version interne 3.12 du vérificateur documentaire général n’est pas renumérotée arbitrairement : le fichier de résultat V3.17 identifie l’exécution sur cette livraison.

## Référence active et couverture

[APPLICATION.html](../DESIGN/APPLICATION.html) et [LECON.html](../DESIGN/LECON.html) sont deux entrées générées à partir de la même bibliothèque et des mêmes sources. La première ouvre Séance ; la seconde ouvre la carte. Le registre de couverture recense 20 compositions actuelles, soit 17 écrans métier ; avec les variantes historiques restantes, 23/49 écrans sont illustrés. Les 26 autres sont spécifiés, pas dessinés. Le mapping des composants ne se substitue pas à un rendu ou un test d’écran.

## Reproduire sans réécrire les originaux

Depuis le dossier extrait, installer les dépendances déclarées dans `requirements.txt`, `requirements-browser.txt` et, pour les exports, `requirements-export.txt`. Installer un navigateur Playwright compatible ou fournir son chemin avec `--chromium CHEMIN`. Les nouveaux scripts acceptent ce chemin ; l’environnement de livraison utilise `/usr/bin/chromium` sous Linux.

```sh
python annexes/generer-atelier.py
python annexes/verifier-application-v3-17.py --chromium CHEMIN --write-report
python annexes/verifier-atelier-v3-17.py --chromium CHEMIN --write-report
python annexes/verifier-composants-v3-17.py --write-report
python annexes/verifier-documentation.py
python annexes/generer-lecteur.py
python annexes/verifier-lecteur-v3-17.py --chromium CHEMIN --write-report
```

Les écritures de rapports modifient les empreintes du dossier : contrôler l’intégrité de la livraison originale avant toute régénération. `verifier-integrite.py --regenerate` prépare un manifeste d’une nouvelle livraison ; ce n’est pas un contrôle de qualité des modifications.

## Limites conservées

Tests de prototype HTML via `page.set_content`, pas de qualification de l’ouverture directe `file://`, bloquée par la politique du navigateur de test. Ni tests natifs SwiftUI/MapKit/VoiceOver, ni données réelles, serveur, sécurité multitenant, publication App Store, batterie, GPS, réseau réel ou route. Les 434 scénarios métier et 68 scénarios mobiles restent NOT_EXECUTED. Les profils légaux et les objectifs DM06/DM07 ne sont pas clos. Les anciens contrôles spécialisés non mentionnés dans le tableau ne sont pas revendiqués comme rejoués.
