# R06 — Revue finale de chaque page web

[← Roadmap produit](../ROADMAP.md) · [Étape suivante : application Swift](R07-revue-finale-swift.md)

**Maturité :** Idée — intention validée, lancement différé.  
**Horizon :** lorsque les fonctionnalités du périmètre web retenu sont quasiment terminées et suffisamment stabilisées. Aucune date fixée.  
**Ordre :** première passe de finition globale ; R07 vient après son achèvement et sa validation.  
**Suivi :** roadmap uniquement, aucune epic ni sous-issue de réalisation créée pour cette initiative.

## Intention

Repasser sur **chaque page du portail desktop et de la web app mobile**, une fois le produit presque complet, pour affiner l’interface et l’expérience utilisateur. Corriger les espacements, alignements, hiérarchie, densité, typographie, textes, interactions et compositions trop génériques donnant l’impression d’un design généré mécaniquement.

Conserver la refonte appréciée issue de #311 et toutes les améliorations intégrées depuis, dont les futurs écrans de tableau de bord et de statistiques lorsqu’ils seront livrés. **Ce n’est ni un redémarrage de zéro, ni un retour à l’ancien portail.**

## Outils obligatoires au moment de la réalisation

Utiliser **Impeccable et Uncodixfy**, tous les deux. Retrouver leurs sources authentiques, vérifier les instructions et la version alors applicables ; installer ceux qui manquent et vérifier leur chargement réel dans chaque agent intervenant. Leur simple présence dans une liste ou dans un prompt ne vaut pas utilisation.

Pour chaque page et sous-vue, conserver une trace de la critique issue des deux outils, des retouches retenues et des recommandations écartées avec leur motif. Les règles génériques ne priment pas sur la DA Drivy, l’accessibilité, les usages métier ou la lisibilité. Aucun score ne peut certifier qu’un design est « sans IA ».

## Couverture et méthode futures

Inventorier les écrans **sur le dernier code et le build réellement examinés**, avec branche et SHA ; ne pas figer l’ancien inventaire de #311. Couvrir navigation, listes, fiches, formulaires, dialogues, écrans secondaires, états vides/chargement/erreur et différences de rôle. Examiner mobile et desktop, clair et sombre, clavier, textes longs et parcours réels avec données synthétiques.

Comparer avant/après sur la même version de départ. Une page peut être conservée sans changement si la revue le justifie. Réutiliser shadcn et le design system actuel ; ne pas changer arbitrairement couleurs, police ou composants pour satisfaire un guide.

Préserver API, données, permissions, confidentialité, GPS, règles métier et synchronisation. Les défauts fonctionnels ou de sécurité urgents ne doivent pas attendre cette passe de finition.

## Avant de lancer

Le porteur confirme que le périmètre fonctionnel web est suffisamment stable, puis valide le lancement. Faire alors l’inventaire actuel et le découpage utile, sans créer les tickets à l’avance. Livrer un aperçu pour son essai, puis les vérifications pertinentes et les corrections selon le cadre de livraison du projet.

L’ancien lot **#340, #341–#346 et #348–#369 reste annulé**. Cette fiche conserve l’intention pour plus tard ; elle ne le rouvre pas et n’autorise ni installation immédiate, ni modification d’écran, ni déploiement.
