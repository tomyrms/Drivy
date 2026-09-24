# Drivy V3.17 : cohérence de l’application au-delà de la carte

> 20 septembre 2026 · Révision de conception et de prototype HTML. La source V3.16 reste intacte.

## Demande et principe retenu

Le porteur demande de poursuivre le benchmark et de décliner l’esthétique validée sur les autres écrans, sans deux composants concurrents pour une même fonctionnalité. Cette livraison étend la référence, sans changer la direction cartographique, la marque Drivy, la palette, le choix Swift natif ou le périmètre métier.

La [recherche](../01-recherche/coherence-application.md) distingue les références consultées, les images effectivement vues, les observations locales et les transpositions proposées. Fantastical éclaire l’agenda ; Cardhop la recherche et le dossier ; Bear la lecture et l’écriture du bilan ; Linear et Things la hiérarchie des listes. Les recommandations Apple encadrent les destinations stables et la différence entre sélectionner, naviguer et agir. Aucun de ces exemples ne prouve l’efficacité pédagogique de Drivy.

## Ce qui est effectivement réalisé

[APPLICATION.html](../DESIGN/APPLICATION.html) est l’entrée commune. Elle ajoute seize compositions hors carte : séance, agenda moniteur, élèves, dossier, leçon, planification, rédaction, aperçu, bilan partagé, documents, compte, notifications, école en lecture, leçons élève, agenda élève et parcours. Les quatre compositions carte/signalement/statut/replay de [LECON.html](../DESIGN/LECON.html) utilisent désormais la même source de composants et le même état en mémoire.

**Vingt compositions correspondent à dix-sept écrans métier existants.** La planche de composants n’est pas un écran du produit. Sur les 49 écrans du catalogue, six autres ne restent illustrés que dans la galerie complémentaire : **23 écrans ont au moins une illustration, 26 restent spécifiés sans rendu**. E13 ne montre pas l’administration complète ; E25 ne montre pas les offres et inscriptions aux cours. Les quatre vues de carte restent des variantes de E23/E24. La [matrice](../DESIGN/couverture-ecrans.json) distingue ces statuts sans transformer une correspondance de composant en couverture visuelle.

## Réutilisation réelle et variations justifiées

`DESIGN/atelier/ui.js` fournit les primitives partagées : bouton, bouton d’icône, champ, recherche, ligne de leçon, ligne d’entité, observation, choix de statut, sélecteur de formation, état, vide et présentation modale. `workspace.js` compose ces primitives et route les pages ; `app.js` conserve le métier fictif de la carte. Il ne s’agit ni d’une bibliothèque Swift compilée, ni d’un fichier Figma.

Une ligne de leçon garde sa structure dans Séance, Agenda et Mes leçons. La même ligne d’observation sert à la liste privée de la carte, à la sélection pour le bilan et à sa lecture. Sa variante de navigation porte un chevron ; la sélection porte une case ; la lecture ne porte pas de faux contrôle. Le choix de statut enregistre et n’a pas de chevron. Le même champ multiligne sert au commentaire privé et aux trois rubriques du bilan. L’en-tête et le conteneur des feuilles sont partagés avec le signalement.

**DS25** nomme la ligne d’entité commune utilisée pour les élèves, documents, réglages et notifications. Il n’ajoute ni table ni fonction métier. Le [registre d’usage](../DESIGN/composants-usage.json) associe les 49 écrans à leurs composants et motive les exceptions. Les primitives spécialisées qui ne sont pas encore rendues sont identifiées comme telles. La carte immersive, le choix d’une formation et une liste administrative ne sont pas forcés dans une géométrie identique lorsque leur rôle diffère.

## Parcours exercés et invariants préservés

La navigation conserve les destinations existantes : Séance, Agenda, Élèves, École côté moniteur ; Mes leçons, Agenda, Mon parcours côté élève. Le compte et les notifications restent dans l’en-tête. Chaque onglet retrouve son contexte ; la recherche d’un élève conserve son texte, tolère les accents et ne perd pas le focus. La fenêtre iPad large réutilise la liste et le dossier dans une composition à colonnes, non un nouvel ensemble de composants. La zone de défilement laisse libre la navigation inférieure et la zone sûre.

La planification est une simulation explicite : revoir ne réserve rien ; confirmer vérifie les collisions des fixtures, la pause et les indisponibilités simulées. Un conflit n’ajoute aucune leçon et préserve la saisie. Un déplacement abandonné laisse l’ancienne réservation intacte. Les tarifs proviennent d’options fictives de catalogue, jamais de la durée GPS.

Le brouillon de bilan concerne la leçon terminée du **18 septembre** ; la capture active concerne le **21 septembre**. Les observations de ces deux leçons sont des fixtures séparées. Le prototype n’implémente pas encore la transformation de n’importe quelle capture terminée en nouveau bilan. La prévisualisation n’est pas une publication ; seules les observations explicitement sélectionnées sont copiées dans la projection. Une publication de démonstration conserve un instantané ; modifier le brouillon ensuite ne modifie pas cet instantané. Aucun trajet n’est partagé par le nouveau parcours de bilan. Les événements live restent privés.

Les formations B et A ne récupèrent pas les bilans ni les documents l’une de l’autre. Le statut de fichier Prêt/En analyse reste distinct d’un contrôle humain du permis. Un ajout de fichier ne lit ni n’envoie son contenu : seul le nom est conservé en mémoire avec un état d’analyse non exécutée. Le niveau Non observé n’est pas un zéro et ne renvoie pas à un faux bilan source.

## Vérifications et preuves

Les [rapports courants](revue-coherence.md) indiquent l’environnement, le mode de chargement et les assertions exécutées. L’archive source a été comparée à ses 496 empreintes avant modification. Les suites d’application et de carte sont rejouées sur les mêmes sources compilées ; le lecteur, les liens et les invariants de composants font l’objet de contrôles séparés.

Les 55 assertions de l’application et ses 256 combinaisons de disposition HTML ne sont pas des tests métier serveur. La régression carte comprend 65 assertions et 128 dispositions. Les scènes sont examinées en clair/sombre, téléphone compact/standard et fenêtres tablette, avec texte normal/agrandi. Les captures livrées sont dérivées de l’HTML réellement exécuté, pas d’un dessin décoratif.

Le chargement `file://` demeure bloqué dans l’environnement Chromium de test ; les contrôles utilisent `page.set_content`. Le blocage est conservé comme limite, pas compté comme succès. Les anciennes suites spécialisées non rejouées restent historiques. Le simple succès d’un script ne requalifie pas les rapports antérieurs.

## Ce qui ne change pas, et ce qui reste à faire

OpenAPI **3.11.0**, les tokens **3.8** et les registres métier restent inchangés octet pour octet par rapport à V3.16. Aucune nouvelle route, table ou écran métier. Les 434 scénarios métier et 68 scénarios mobiles restent **NOT_EXECUTED** sur l’application.

Tout est local et volatil : recharger remet les données fictives. Ni comptes réels, ni autorisation serveur, ni notification push, ni stockage hors ligne durable, ni synchronisation, ni GPS/MapKit, ni build Swift. La séparation visuelle des rôles n’est pas une barrière de sécurité : les fixtures sont publiques dans le code du prototype. Aucun entretien, essai routier, import Figma, test Safari/Windows, VoiceOver natif ou mesure de batterie. L’apparence, les animations et les contrôles natifs seront à qualifier dans SwiftUI.

Les cours, packs, achats, contrôle financier, onboarding complet, exports, administration détaillée et suppression de compte complète ne sont pas redessinés dans cette passe. L’entrée E49 de Mon compte ouvre seulement une explication des limites : elle ne simule pas une réauthentification ou une procédure déjà validée. Les autres pages de référence restent nécessaires. Les détails de V3.17 sont proposés au porteur, non validés automatiquement par son appréciation de V3.15.
