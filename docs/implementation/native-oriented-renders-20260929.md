# Captures natives avec orientation réelle — 29 septembre 2026

La campagne visuelle propose désormais `visual_orientations` dans `refonte-ios.yml` : `portrait`, `landscape` ou `portrait landscape`. Ce paramètre sélectionne `build-for-testing`, puis `VisualOrientationTests` sur les appareils et apparences demandés. Lorsqu’il reste vide, les écrans existants conservent leur voie `simctl` et leur nom de fichier historique.

Deux variantes passent toujours par XCTest, en portrait par défaut :

- `live-signal` lance la fixture `live`, puis touche le vrai bouton `capture-signal-observation`.
- `signal-status` ouvre ce même panneau, puis touche `live-observation-theme-Priorité à droite`. Aucun enregistrement n’est effectué par cette variante.

Ces parcours couvrent le panneau réellement présenté au-dessus de la carte. La fixture `signal` reste disponible pour le panneau isolé.

## Production et contrôle des originaux

`capture-screens.sh` copie la configuration `.xctestrun` à côté de l’original pour préserver ses chemins `__TESTROOT__`, puis injecte les paramètres dans `EnvironmentVariables` de `DrivyUITests`. Les configurations v1 et v2 sont prises en charge. Chaque paire appareil/apparence lance seulement la classe visuelle ; celle-ci boucle sur les écrans et orientations. La suite ordinaire exclut explicitement cette classe, qui possède aussi un garde `XCTSkip` hors mode visuel.

L’application reçoit `AppleLanguages=(fr)` et `AppleLocale=fr_CH`. XCTest demande l’orientation à `XCUIDevice`, attend une fenêtre dont largeur et hauteur correspondent, puis vérifie aussi les dimensions de la capture `XCUIScreen.main.screenshot`. Le paysage est `landscapeLeft` ; aucun fichier n’est tourné après capture.

`visual_compact_ipad`, désactivé par défaut, demande un Air 11 pouces, sinon un Air 10,9 pouces (4e/5e génération), sinon un Pro 11 pouces. L’absence de ces modèles fait échouer la sélection : aucun repli silencieux sur 13 pouces. `visual-device-iPad.json` conserve le nom exact choisi, sans identifiant machine. Il s’agit d’un contrôle du format disponible en simulateur, pas d’une qualification physique de l’iPad Air 5 du porteur.

La prochaine campagne **complète de tests natifs** préfère systématiquement l’Air 11 puis le Pro 11, et refuse l’absence de ces deux formats. Son nom réel est conservé dans `test-device-iPad.json`. Les anciennes preuves sur Pro 13 restent distinctes ; le choix iPhone n’est pas modifié.

Le drapeau de grand texte règle aussi la **taille système** du simulateur : `accessibility-extra-large` (AX3), sinon `large`. Le script lit immédiatement la valeur et refuse toute différence. L’aide `simctl help ui` de l’Xcode exécuté est conservée ; une commande ou valeur non reconnue échoue explicitement. La catégorie relue rejoint le manifeste d’appareil. La taille est remise à `large` avant fermeture et lors du nettoyage d’erreur. Cela couvre les présentations qui n’héritaient pas de l’environnement SwiftUI de la fixture ; les anciens rendus de ces modales ne sont pas rétroactivement qualifiés en AX3.

L’export rapproche les noms du manifeste d’attachments de la liste attendue. Il rejette capture manquante, doublon, chemin hors du dossier d’export et dimensions affichées incompatibles. `scripts/ios/png_geometry.py` lit l’entête PNG et l’orientation TIFF du bloc `eXIf`, sans décoder ni modifier les pixels. Un PNG de stockage 2064 × 2752 avec EXIF 8 s’affiche en paysage 2752 × 2064 : le contrôle utilise cette géométrie affichée. Les métadonnées ambiguës ou tronquées sont rejetées. Les octets du PNG exporté sont copiés sans réencodage. Le nom stable est `iPad-live-signal-light-landscape-synthetic.png` ; un fichier `visual-orientation-iPad-light.json` conserve dimensions stockées et affichées, orientation EXIF, orientation demandée et SHA256 de chaque original. Les `.xcresult`, journaux et attachments restent dans l’artefact de la campagne.

## Vérifications locales et limites

Exécuté localement : syntaxe Bash des deux scripts et de tous les blocs shell du workflow ; syntaxe YAML ; **21 contrôles isolés** de l’injection `.xctestrun` v1/v2, de l’export, des choix d’appareil visuel et complet, et de la catégorie de texte relue. Les cas positifs exportent de vrais PNG déjà disponibles, dont un paysage EXIF 8, sans changer leurs octets ; les cas négatifs rejettent mauvaise orientation, manque, doublon, sortie de répertoire, tablette de mauvais format et catégorie de texte différente. Ces contrôles de scripts ne remplacent pas les tests de l’application.

La compilation puis le test orienté ont réussi sur le runner Apple au commit `e720c4579d8e12c6d0aedb7d0ada6f2f529f30a0`, run `36584370257` : 1 test, 0 échec, 16 captures exportées. Le run global a échoué après cela, dans l’ancien validateur qui ignorait EXIF. Les [16 originaux ont été réellement examinés](ui-review-field-renders-20260929.md) en portrait et paysage ; ils restent attachés à ce run en échec, avec sa cause exacte. L’extension de sélection compacte, la taille système et la correction EXIF n’appartiennent pas à ce commit. Les contrôles locaux ne prouvent pas leur exécution sur Apple ni l’accessibilité physique. Chaque campagne produite doit garder son commit exact et ses images réellement ouvertes ; elle ne valide pas les modifications postérieures.
