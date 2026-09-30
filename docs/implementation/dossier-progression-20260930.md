# Dossier, progression et composants de leçon — 30 septembre 2026

Les demandes du porteur concernent ici des composants et comportements ciblés de l’app native. La refonte générale de direction artistique concerne exclusivement la webapp. Aucun token, thème, architecture d’onglets ni écran d’accueil natif n’est remplacé par ce lot.

Références : `COMMENCER_ICI.md`, R17/R19/R20, parcours dossier et bilan, scénarios T029–T032 et décision de partage automatique du 28 septembre. Le canon livré et OpenAPI 3.11.0 restent intacts.

## Changements

- Le menu des leçons du dossier conserve statut et tri, et ajoute une période : mois, année précise, ou les deux. Le calendrier utilisé est celui de la leçon, y compris aux changements d’année UTC. Les choix sont conservés dans la scène.
- La sélection de période charge toutes les pages autorisées de l’historique. Une panne garde la page acquise et un curseur réessayable ; aucun « aucune leçon » définitif n’est affiché tant que l’historique est incomplet. Le chargement est détenu par le modèle, pour survivre à un changement de mois ou à la fermeture du sélecteur. Une nouvelle génération annule l’ancienne et reprend l’historique.
- Après reçu serveur et retrait durable de la commande chiffrée, le bilan annonce le changement aux écrans du dossier et de l’agenda. Un résultat réseau incertain n’annonce aucun succès. Une commande récupérée d’une autre leçon provoque une relecture non ciblée lorsque sa formation n’est pas connue. Le dossier et la leçon relisent aussi leurs données au retour au premier plan ; la politique existante conserve les saisies et empêche d’écraser une version concurrente.
- Le dossier et le bilan partagent trois points de niveau avec un libellé textuel. Le menu d’une compétence permet de retirer son évaluation de cette leçon. Le champ de situation s’ouvre à la demande, sans supprimer son contenu existant.
- Les observations utilisent une ligne compacte partagée : symbole de statut, texte et métadonnées utiles. Le menu de confidentialité remplace les cadenas répétitifs ; « Pour moi » reste visible pour une observation privée. Le menu de modification/suppression garde une cible de 44 points. Le bilan lu emploie moins d’encadrements et d’espace.
- La lecture d’une révision accepte une situation vide, autorisée depuis la migration019. L’ancien client rejetait à tort ces bilans.

## Retour à « Pas encore vu »

« Pas encore vu » représente l’absence d’évaluation, pas un quatrième niveau. Retirer une sélection accidentelle retire l’évaluation de cette leçon. Après sauvegarde, la progression retrouve l’évaluation antérieure s’il en existe une ; sinon la compétence est non observée. Cela conserve R20 : l’absence dans une nouvelle leçon ne doit jamais effacer un acquis antérieur. Le libellé « Avant cette leçon » indique ce retour lorsque la progression actuelle provient de la leçon ouverte.

## UI Skills appliqués

- `ui-skills-root` : lecture du routeur et inventaire des catégories SwiftUI, systèmes et finition ; contexte élargi conformément à la demande du porteur.
- `swiftui-ui-patterns` : modèles conservés, états de feuilles stables, composants partagés, lecture asynchrone protégée par génération.
- `better-layout` : divulgation progressive de la situation et des filtres de période, regroupement des commandes secondaires.
- `better-accessibility` et `interactive-hit-areas` : commandes natives, zones de 44 points, niveaux textuels, indicateurs décoratifs exclus de VoiceOver.
- `better-typography` : styles sémantiques natifs, hiérarchie courte, texte multiligne sans taille fixe imposée au contenu.
- `better-writing` : commandes concrètes, suppression des métadonnées techniques inutiles, distinction entre retour à l’état antérieur et suppression de tout l’historique.

Les guides complémentaires du web et des cartes sont détaillés dans leurs livraisons respectives. Employer davantage de guides ne justifie aucune refonte native générale.

## Vérification

Tests ajoutés dans `SchoolTrainingRefreshTests` : période dans le fuseau de la leçon, pagination complète et reprise après actualisation, erreur/réessai, course avec ancienne page suspendue, révision sans situation, notification seulement après confirmation durable. Les tests existants du bilan couvrent déjà le retrait d’une sélection et le maintien d’un niveau antérieur. Exécution Apple et revue visuelle à reporter avec leurs preuves dans `STATUS.md` ; aucun essai VoiceOver physique n’est revendiqué.
