# Installer et essayer le premier IPA

Ce build est un laboratoire privé de la refonte. Il sert à qualifier les fondations avant de connecter les données d'une école. Il n'envoie pas les trajets ou observations à un serveur.

## Installation

1. Ouvrir l'exécution réussie du workflow **Refonte · iOS** correspondant au commit communiqué.
2. Télécharger l'artefact `Drivy-unsigned-<commit>` et extraire le ZIP.
3. Importer `Drivy.ipa` dans iLoader, signer avec son compte Apple puis installer sur l'iPhone ou l'iPad.
4. Ouvrir **Drivy Essais** et commencer par une séance sans GPS.

Conserver le commit, le modèle d'appareil et la version exacte d'OS pour associer un résultat au bon build. Un problème de signature/installation reste distinct d'un échec du parcours dans l'application.

## Parcours sans GPS

Commencer une séance sans GPS ; ajouter une observation avec thème, statut et commentaire. Vérifier qu'elle apparaît après sauvegarde. Arrêter la séance et la retrouver dans l'historique. Fermer complètement puis rouvrir l'app : la séance et son observation doivent rester présentes. Écrire un bilan local et vérifier sa conservation après relance.

## Capture volontaire

À l'arrêt, commencer une nouvelle séance d'essai avec GPS et accepter la permission. Vérifier que les premières mesures apparaissent seulement après réception. Verrouiller l'écran pendant un déplacement comme passager ou à pied, puis rouvrir. Arrêter : aucun nouveau point ne doit être accepté ensuite. Les périodes sans mesure doivent rester visibles comme des ruptures, sans segment inventé.

## Refus et interruptions

Essayer avec permission refusée : la séance sans GPS doit rester utilisable. Fermer l'app durant une capture puis rouvrir : l'interruption doit être reconnue, sans prétendre avoir enregistré durant la fermeture. Après redémarrage de l'appareil, ne pas attribuer de continuité à une période où l'app ne pouvait pas fonctionner.

## Lisibilité et données

Essayer clair/sombre, grand texte, orientation et fenêtre iPad ; contrôler lecture et commandes avec VoiceOver. Supprimer une séance depuis l'historique et vérifier son absence après relance. Ne pas exporter de positions réelles dans une issue publique ou dans les logs CI.

## Résultats à relever

| Test | Appareil / OS / commit | Résultat | Observation |
|---|---|---|---|
| Installation iLoader | À renseigner | NOT_EXECUTED | |
| Sans GPS, observations, relance | À renseigner | NOT_EXECUTED | |
| Capture écran verrouillé, arrêt | À renseigner | NOT_EXECUTED | |
| Refus permission et interruption | À renseigner | NOT_EXECUTED | |
| Suppression, grand texte, VoiceOver | À renseigner | NOT_EXECUTED | |

La durée, le nombre de mesures et la variation de batterie observés servent au diagnostic. Aucune promesse d'autonomie ou de fiabilité routière n'est acquise par ce protocole seul.
