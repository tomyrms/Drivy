# R07 — Revue finale de l’application native Swift

[← Roadmap produit](../ROADMAP.md) · [Prérequis : revue finale web](R06-revue-finale-web.md)

**Maturité :** Idée — intention validée, lancement différé.  
**Horizon :** après achèvement et validation de R06, et lorsque les fonctionnalités du périmètre natif retenu sont quasiment terminées et stabilisées. Aucune date fixée.  
**Ordre :** web d’abord, application Swift ensuite ; pas deux refontes globales simultanées.  
**Suivi :** roadmap uniquement, aucune epic ni sous-issue de réalisation créée pour cette initiative.

## Intention

Revoir **chaque écran et sous-écran de l’application Swift/SwiftUI sur iPhone et iPad**, pour tous les rôles disponibles. Affiner la cohérence, la hiérarchie, les espacements, les composants, les textes, les gestes, les transitions et les détails trop génériques, tout en conservant l’identité Drivy et une expérience réellement native.

La revue ne consiste pas à copier le portail web dans l’application ni à remplacer SwiftUI par une webview. Les enseignements de R06 servent à harmoniser le vocabulaire et les intentions, pas à imposer les mêmes contrôles sur toutes les plateformes.

## Trois skills obligatoires

Au lancement, installer ceux qui manquent, vérifier la version et le chargement effectif, puis utiliser réellement :

1. **Impeccable** pour la critique et la finition dans les limites de ses capacités réellement applicables au natif.
2. **Uncodixfy** comme grille de revue des compositions génériques, adaptée aux conventions Apple plutôt qu’appliquée mécaniquement.
3. **« Swift native composant »**, le skill personnel créé par Tomas, pour guider les composants natifs et leur adaptation à la DA de l’application.

Le troisième nom est celui communiqué par le porteur. **Retrouver le vrai fichier/package de son skill** dans l’environnement autorisé ou le lui demander au moment du lancement s’il manque. Ne pas inventer de dépôt, de commande d’installation ou de contenu, et ne pas le remplacer silencieusement par un skill public au nom voisin.

Chaque agent participant doit charger ces instructions. Documenter leur usage par écran, les choix retenus et les exceptions justifiées. Une commande exclusivement web ne devient pas un audit Swift : utiliser les parties pertinentes, l’inspection du code natif et les captures réellement exécutées ; signaler toute limite de capacité.

## Couverture et méthode futures

Inventorier la version native la plus récente réellement intégrée, et relever branche, SHA, build et IPA. Couvrir les écrans principaux, navigation, feuilles, menus, formulaires, confirmations, clavier et états vides/chargement/erreur, y compris messagerie, agenda, cours, dossiers, leçon/GPS, replay, bilans et paramètres **selon les fonctions présentes à ce moment-là**.

Comparer avant/après avec données synthétiques ; iPhone/iPad, clair/sombre, Dynamic Type, orientations, zones sûres, focus et VoiceOver. Séparer ce qui est vérifié en simulateur de ce qui a été essayé sur appareil physique ; ne pas prétendre qualifier GPS, batterie ou confort terrain sur la seule compilation.

Réutiliser les composants et la logique sains. Les éventuelles bibliothèques suggérées par le skill personnel sont évaluées, pas toutes installées systématiquement. Préserver performances, chiffrement, brouillons, permissions, consentements, règles métier et synchronisation. Ne pas retirer une information utile ou une protection pour alléger visuellement l’écran.

## Avant de lancer

Attendre R06 validée et l’accord du porteur sur la maturité du périmètre natif. Établir alors l’inventaire et créer seulement à ce moment les tickets utiles. Fournir une IPA identifiable pour son essai, puis les vérifications pertinentes et corrections selon le cadre du projet.

Cette initiative ne rouvre pas l’ancien lot annulé #340, ne relance pas #311 et ne retarde pas les correctifs fonctionnels ou de sécurité nécessaires maintenant. **Aucun skill installé, écran modifié, test/build ou déploiement autorisé par l’ajout de cette fiche.**
