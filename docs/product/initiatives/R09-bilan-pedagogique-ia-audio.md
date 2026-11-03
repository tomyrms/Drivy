# R09 — Bilan pédagogique IA à partir des échanges audio de la leçon

Idée premium à très long terme, conservée à la demande du porteur pour ne pas l'oublier. Elle vient de l'ancienne issue [#63](https://github.com/tomyrms/Drivy/issues/63), fermée le 3 novembre 2026 au profit de cette fiche.

**Statut : idée à conserver, pas un développement à lancer.** Périmètre exploratoire, sans échéance, sans sprint, sans priorité de réalisation ni dépendance bloquante pour les fonctions actuelles. Cette fiche n'est ni un cahier des charges validé ni une autorisation d'enregistrer des utilisateurs réels.

## Intention

Proposer, au début d'une leçon, une option audio qui conserve les échanges entre l'élève et le moniteur dans la voiture. Transcrire ensuite cet audio, puis utiliser une IA pour préparer un bilan pédagogique : ce qui s'est bien passé, les difficultés exprimées ou relevées, les conseils donnés et les points à retravailler.

Il ne s'agit ni d'un simple résumé de conversation, ni d'une note vocale dictée après la leçon : l'idée repose sur les échanges de la séance elle-même. « Bilan vocal IA » est un nom de travail ; une restitution par voix de synthèse n'est pas décidée.

## Parcours envisagé, à préciser

- Fonction proposée dans une offre premium (voir [R03](R03-modules-et-offres.md)), avec activation volontaire de l'audio pour la leçon.
- Enregistrement identifiable, avec pause et arrêt accessibles ; arrêter l'audio n'empêche pas de poursuivre la leçon ordinaire.
- À la fin : transcription, puis préparation d'un brouillon de bilan IA.
- Le moniteur relit, corrige et valide avant intégration dans le bilan de l'élève ou partage. Aucune publication ni évaluation de compétence automatique.
- Les signalements manuels et les objectifs pourraient apporter du contexte, mais ce rapprochement reste une piste, pas une liaison obligatoire à réintroduire après la dissociation des signalements et des compétences (#56, #57).

## Garde-fous à examiner dès le cadrage

- Information claire et accord explicite des personnes enregistrées, notamment l'élève et le moniteur ; la permission du microphone est distincte du consentement des participants. Pas d'écoute cachée ou systématique au simple démarrage d'une leçon.
- Refus, retrait, pause, arrivée d'un tiers et arrêt effectif de l'enregistrement à la fin de la séance. Un refus n'empêche pas l'usage normal de Drivy.
- Qui accède à l'audio, à la transcription et au bilan ; protection, durée de conservation, suppression, choix d'hébergement et de traitement. Cadre juridique applicable, mineurs et prestataires à examiner avant tout essai réel.
- Distinguer les propos réellement transcrits des interprétations. L'IA n'invente pas un événement de conduite non étayé, n'attribue pas avec certitude une phrase ambiguë et ne déduit pas une compétence acquise d'un silence.
- Pouvoir vérifier les passages qui ont servi au brouillon ; gérer le bruit du moteur, les phrases inaudibles, les langues, les accents et l'attribution incertaine des intervenants.
- Pas de profilage biométrique ni d'identification vocale par défaut : distinguer les intervenants ne veut pas dire créer des empreintes vocales.

## Questions ouvertes

Enregistrement continu ou par séquences ; traitement local ou serveur ; moment de la transcription ; fonctionnement hors connexion ; langues ; coûts, autonomie et stockage ; droits premium de l'école ou du moniteur ; contenu exact du bilan ; visibilité de la transcription côté élève.

## Limites

Aucun fournisseur, modèle d'IA, prix, quota, durée de conservation ni architecture n'est choisi. La première étape éventuelle sera un cadrage produit et confidentialité, puis une étude de faisabilité avec des données synthétiques ou explicitement consenties, pas une implémentation immédiate.

Aucune issue de développement n'est créée automatiquement depuis cette fiche.
