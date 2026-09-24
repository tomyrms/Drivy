# Drivy : passage vers Figma

> Livraison V3.17 · Huit SVG de carte V3.16 conservés · Aucun fichier .fig ni espace Figma créé.

Les nouvelles compositions hors carte sont disponibles dans [APPLICATION.html](APPLICATION.html), leurs sources communes dans `atelier/ui.js` et leurs captures dans `assets/application-v3-17/`. Les huit vecteurs ci-dessous ne représentent pas ces nouvelles pages. Une bibliothèque Figma unifiée doit encore être construite à partir du [registre de composants](composants-usage.json), sans recréer chaque écran indépendamment.

La passe précédente indiquait une intégration Figma disponible mais non connectée. Cette révision n’a pas interrogé la connexion ni écrit dans un compte Figma. La production continue avec un prototype interactif et des exports vectoriels.

## Contenu à importer

Dans un fichier **Figma Design** ouvert, déposer les fichiers SVG du dossier `vecteurs/` sur le canevas, plutôt que d’utiliser l’import de fichier .fig du navigateur de fichiers. L’aide officielle explique que les SVG sont convertis en calques vectoriels modifiables : [Ajouter des images et des vidéos](https://help.figma.com/hc/fr/articles/360040028034-Ajouter-des-images-et-des-vid%C3%A9os-aux-designs), consultée le 20 septembre 2026. [Copie d’assets entre outils](https://help.figma.com/hc/en-us/articles/360040030374-Copy-assets-between-design-tools), même consultation.

Les sources livrées comprennent formes, traits, carte schématique et éléments SVG textuels. Aucun bitmap n’est encapsulé dans ces vues. **L’import Figma n’a pas été exécuté ici** : la manière exacte dont le texte est converti, les polices substituées et les calques regroupés reste à vérifier dans le compte destinataire. Aucun fichier de police n’est inclus.

| Vue | Clair | Sombre |
|---|---|---|
| Carte | [SVG](vecteurs/01_capture_light.svg) | [SVG](vecteurs/01_capture_dark.svg) |
| Catégories | [SVG](vecteurs/02_categories_light.svg) | [SVG](vecteurs/02_categories_dark.svg) |
| Statut | [SVG](vecteurs/03_status_light.svg) | [SVG](vecteurs/03_status_dark.svg) |
| Replay privé | [SVG](vecteurs/04_replay_light.svg) | [SVG](vecteurs/04_replay_dark.svg) |

## Ce qui n’est pas transféré automatiquement

Les SVG sont des instantanés de composition. Ils n’incluent ni Auto Layout configuré, ni bibliothèque de composants Figma, ni variables Figma, ni liens de prototype, ni gestion de l’état. Les ombres CSS sont omises ; les tracés, aplats et textes sont prioritaires. Ils ne remplacent pas le [prototype interactif](LECON.html).

Pour un travail Figma natif, reconstruire ensuite les éléments réutilisables : en-tête de leçon, déclencheur Signaler, catégorie, ligne de statut, observation, contrôle du replay. Les textes, variantes et contraintes doivent suivre les documents canoniques, pas seulement le dessin.

Les contrôles dans le navigateur, les SVG vérifiés en XML et leurs rendus locaux ne sont pas des tests Figma. Les interfaces SwiftUI restent à développer et à qualifier séparément.
