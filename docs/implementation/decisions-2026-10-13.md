# Décisions du porteur du 13 octobre 2026 : textes de l’école

Prises après l’[analyse des textes de l’école](analyse-textes-ecole-20261013.md). Elles priment sur les règles contraires du dossier de conception 3.17 et des notes d’implémentation antérieures.

| Sujet | Décision | Règle remplacée |
|---|---|---|
| Textes proposés | Drivy propose les textes d’une nouvelle école : information, conservation, informations demandées, déroulement et annulation, conditions commerciales. L’administration les relit, les adapte et les adopte d’un geste ; rien n’est adopté sans ce geste. | « Aucun texte juridique n’est généré ou adopté par défaut » (`g1b-school-setup.md`) et « Aucun contenu ni consentement n’est proposé automatiquement » (`native-school-settings-design.md`). |
| Texte GPS | Un seul texte de confidentialité, sans texte GPS séparé. Une nouvelle version redemande l’accord GPS à chaque élève : l’administration en est prévenue avant de confirmer (lot 0). | Proposition B de l’analyse (texte GPS séparé), écartée. |
| Informations demandées | Effet immédiat, sans brouillon ni date d’effet. Chaque version reste conservée par le serveur. | Brouillon puis publication à une date d’effet (G1D). |
| Motif d’approbation | Supprimé de l’interface pour les compétences, le déroulement et les conditions ; l’API l’accepte encore, facultatif. L’auteur et l’heure restent dans l’audit. | Motif obligatoire à chaque version. |
| Durée de conservation | Aucune durée affichée dans l’app ni promise par les textes proposés tant qu’aucune suppression automatique ne l’applique. | — |

## Reste à faire

- Suppression automatique des trajets et durées paramétrées (parcours C de l’analyse), puis affichage de la durée.
- Élèves mineurs : mécanisme à concevoir après avis juridique.
- Relecture juridique des textes proposés avant l’accueil d’écoles réelles (droit suisse, mention de Mapbox, mineurs).
