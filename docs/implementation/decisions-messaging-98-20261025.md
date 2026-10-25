# Messagerie iOS/iPadOS : refonte #98 (25 octobre 2026)

Base : `origin/master` `fcfdfde` (intègre `openai/65-messagerie` et la qualification #84). Branche : `claude/98-messagerie-refonte`.

## Décisions

- **Navigation (rouvre #66).** Onglet Messages explicite, visible seulement quand l'entrée Messages est fournie pour le contexte :
  élève `Leçons · Progression · Messages · Profil`, moniteur/administration `Aujourd'hui · Agenda · Élèves · Messages · Profil`.
  Aucun onglet existant supprimé. Le bouton Messages de la barre d'outils d'Agenda disparaît (redondant). Le bouton
  « Envoyer un message » du dossier élève reste. La garde trajet actif est conservée, le GPS n'est jamais touché.
- **Chronologie.** Le serveur renvoie chaque page en séquence décroissante. Le client normalise en séquence croissante
  (départage par identifiant), fusionne pages et rechargements par identifiant. Aucun tri sur l'heure locale.
  Fil : anciens en haut, récents en bas près du composeur. Accueil : discussions récentes en tête.
- **Accueil.** Liste de discussions : avatar, nom, aperçu, date, non-lus, sourdine. Aperçu issu uniquement de la mémoire
  de session ou de l'historique scellé local, jamais du réseau en clair. Repli « Message chiffré ». Général une seule fois.
  Contacts autorisés derrière « Nouvelle conversation », membres dans les informations du général.
- **Fil et composeur.** Séparateurs de jour, regroupement par auteur, envois en attente intégrés comme bulles avec état
  (attente, échec + réessayer). Composeur compact multiligne, actions secondaires derrière `+`.
- **Réactions.** Réactions rapides en tête du menu contextuel, agrégats rattachés à la bulle, sélection personnelle
  distinguée autrement que par la couleur, alternative VoiceOver par actions d'accessibilité.
- **iPad.** Liste + conversation en deux colonnes en largeur régulière.

## Hors périmètre

Backend, protocole, E2EE, médias (#97), appels, vocal, indicateur de saisie, web. Aucun déploiement homelab.

## Benchmark

Voir l'issue #98 (huit références, distinction observation visuelle / documentation). Aucune capture concurrente
n'est reproduite ici.
