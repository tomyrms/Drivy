# Profil de l’élève : identité, permis en liste, Paramètres (11 octobre 2026)

## Ce qui change

Le Profil empilait une grande carte par permis (six lignes chacune), puis « Trajets », l’accord GPS et le compte. Il tient maintenant en trois blocs :

1. **Identité** : initiales, nom, école (et « École archivée » ou « École en préparation » seulement si c’est le cas), puis la ligne « Mes informations ».
2. **Mes permis** (« Mon permis » s’il n’y en a qu’un) : une ligne par permis, nom puis synthèse (« 12 leçons terminées · 14 h 30 »). Un état inhabituel précède la synthèse (« En pause · … »). Sans permis, une phrase : dossier pas encore ouvert, ou aucune formation.
3. **Accord GPS**, seulement s’il attend une réponse (« À donner ») ou une vérification (« À vérifier »).

« Paramètres » est dans la barre supérieure.

## Où va chaque détail

| Détail | Emplacement principal |
| --- | --- |
| Séances, bilans, trajet d’une leçon | onglet Leçons |
| Compétences et niveaux | onglet Progression |
| Leçons terminées et temps, par permis | Profil, ligne du permis |
| État, début, moniteurs affectés, dernière leçon | Profil → permis |
| Mes informations | Profil (bloc identité) et Paramètres → Compte |
| Changer d’école, rejoindre une école | Paramètres → Compte |
| Accord GPS, liste des trajets | Paramètres → Enregistrement GPS |
| Face ID | Paramètres → Sécurité |
| Déconnexion | Paramètres, dernière ligne |

Profil → permis ouvre un écran court : « Leçons » et « Progression » y basculent sur l’onglet correspondant avec ce permis sélectionné (`chosenPermit` de `SchoolHomeView`, le même filtre que le menu « Permis » des deux onglets). Rien n’y est recalculé : les chiffres viennent de `SchoolTrainingOverview`, sur les modèles partagés avec Leçons et Progression.

## Arbitrages

- **« En autonomie »** devient « 8 sur 31 compétences en autonomie », sous « Progression » dans l’écran du permis. C’est un décompte du référentiel ; aucun statut « obtenu » n’en est déduit.
- **« Moniteur »** listait les moniteurs que l’école affecte aujourd’hui à la formation (`/trainings/{id}/assignments`), nommés d’après leurs leçons et joints par des virgules. Le libellé devient « Moniteur affecté » ou « Moniteurs affectés », un nom par ligne, dans l’écran du permis. Aucun moniteur référent n’est introduit.
- **« Trajets »** quitte la racine du Profil. Le trajet d’une leçon se revoit depuis sa fiche (« Revoir le trajet ») ; la liste de tous les trajets reste accessible dans Paramètres → Enregistrement GPS, à côté de l’accord dont elle dépend.
- **« Dernière leçon »** n’ouvre plus la fiche depuis le Profil : la date se lit dans l’écran du permis, la fiche s’ouvre depuis Leçons.
- **Paramètres** réutilise les lignes de `SchoolAccountActions` (feuille « Compte », Profil du moniteur), désormais découpées en `accountRows`, `lockRow` et `signOutRow`. `rows` garde le même ordre pour les autres écrans.

## Le message « Le choix n’a pas pu être vérifié »

Il concernait l’accord GPS. Le texte était le repli de `SchoolRecordingChoiceWorkspace.fail` pour toute erreur sans description. Le seul cas réel : une lecture **annulée**. La ligne de l’accord vivait en bas d’une longue liste ; quand elle sortait de l’écran (défilement, changement d’onglet) pendant la lecture, la tâche était annulée, le client relançait `CancellationError`, et l’annulation s’affichait comme une panne. La ligne ne relisait ensuite jamais : le message restait.

Corrections :

- une lecture annulée n’est plus une erreur : rien n’est affiché, `needsReload` reste vrai, et la ligne reprend la lecture à son retour à l’écran ;
- une vraie panne de lecture nomme son objet : « L’accord GPS n’a pas pu être lu », avec la cause quand l’école est injoignable, et « Réessayer » à côté de l’accord, dans Paramètres ;
- le Profil lit l’accord à part : une panne ne bloque ni l’identité ni les permis, et n’y affiche rien ;
- les états restent distincts : attente (squelette), panne (message et « Réessayer »), demande en file ou portée ancienne (« Accord GPS à vérifier »), information de l’école changée (question reposée), absence de réponse (question).

La file chiffrée et les envois ne sont pas modifiés : une demande sauvegardée reste en file, un nouvel envoi reste refusé tant qu’une demande est incertaine.

## Non vérifié

Écran jamais vu tourner sur cette machine (pas de toolchain Swift). VoiceOver, grandes tailles de texte, iPad, barre d’onglets flottante et transitions sont à valider sur appareil ou par captures (`learner-profile`, `learner-profile-multi`).
