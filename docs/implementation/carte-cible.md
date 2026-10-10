# Carte cible de l’app et du web

Validée par le porteur le 28 septembre 2026 ([décisions](decisions-2026-09-28.md)). Version illustrée publiée pour lui : https://claude.ai/artifact/AHt53mmiuysHqeHNCmmYaF.

## Qui fait quoi, où

| iPhone et iPad · terrain | Site web · bureau |
|---|---|
| Voir sa journée et démarrer la leçon | Ouvrir et configurer l’école, textes légaux |
| Enregistrer le trajet et signaler une erreur | Offres, tarifs, conditions, disponibilités |
| Terminer la leçon et écrire le bilan | Équipe, rôles et invitations |
| Planifier, inviter un élève | Formations des élèves et affectations |
| Élève : ses leçons, trajets, erreurs, bilans | Champs demandés aux élèves |

## Écrans par rôle

**Moniteur** : trois onglets.
- **Aujourd’hui** : carte en fond et prochaine leçon avec « Démarrer ».
- **Agenda** : semaine et « Planifier ».
- **Élèves** : fiche, leçons, progression et « Inviter ».

Le compte (Face ID, école, déconnexion) est derrière l’avatar.

**Élève** : deux onglets.
- **Leçons** : chaque leçon ouvre sa carte, ses erreurs, son bilan et ses objectifs.
- **Progression** : niveau par compétence.

Le profil est derrière l’avatar.

**Administrateur qui enseigne** : les écrans du moniteur, plus « Gérer l’école » vers le web depuis le compte.

## Parcours

- **Démarrer un trajet** : Aujourd’hui → Démarrer la leçon → carte et signalement → Terminer → bilan prérempli, enregistrer → l’élève voit tout. Sans leçon prévue, « Démarrer » demande l’élève et crée une leçon de 50 minutes qui commence maintenant.
- **Ajouter un élève** : Élèves → + → prénom, nom, e-mail → Permis B, moi comme moniteur → Inviter. Le dossier et la formation existent dès l’acceptation.
- **Se connecter** : première ouverture → page Drivy (e-mail, mot de passe) → Face ID proposé → ensuite l’app s’ouvre directement.

## Ce que voit l’élève

| Élément | Visible par l’élève | Le moniteur peut le garder pour lui |
|---|---|---|
| Trajet GPS de la leçon | Dès la fin de la leçon | Oui, en masquant le trajet |
| Erreurs et points positifs notés | Dès la fin de la leçon | Oui, une par une (« Pour moi ») |
| Bilan | Dès qu’il est enregistré | Oui, en passant le bilan en privé |
| Objectifs de la leçon | Dès qu’ils sont écrits | Non (la note administrative reste privée) |
| Progression par compétence | Toujours à jour | Non, elle découle des bilans visibles |

## Ce qui reste, part ou disparaît de l’iPhone

- **Reste** : carte, séance, signalement ; agenda et planifier ; fiche élève, leçons, progression ; bilan ; inviter un élève ; compte.
- **Part sur le web** : configuration et ouverture de l’école ; textes légaux ; offres, référentiels, procédures ; tarifs, conditions, disponibilités ; équipe, rôles, invitations ; champs du profil, formations.
- **Disparaît** : trajets perso et trajets d’exemple locaux ; « Trajets de l’école » dans l’onglet École ; « Fonctions de l’école », « Actualiser la vérification » ; références techniques des demandes en attente ; numéros de version côté élève.

## Règles d’écriture

Un titre suffit (pas de sous-titre explicatif) ; pas de note sous les sections ; un badge seulement pour l’inhabituel ; les mots de l’auto-école (terminer, bilan, leçon, tarif). Une explication n’apparaît qu’en cas d’erreur, et elle dit quoi faire.

## Réalisation (28 septembre 2026)

Les onglets par rôle, le compte derrière l’avatar et le retrait des écrans d’administration sont compilés (release `6c03c02`). Écarts assumés par rapport à la carte :

- **Ajouter un élève** demande l’e-mail et la formation, pas le prénom ni le nom : l’élève les saisit en créant son compte, l’API d’invitation ne les porte pas. Un administrateur qui n’enseigne pas invite sans formation ; celle-ci s’ouvre ensuite sur le web.
- **Trajets de cet appareil** reste dans le compte du moniteur : c’est le seul endroit pour renvoyer un trajet resté sur l’iPhone après une coupure réseau.
- **Invitations** reste dans le compte du moniteur pour vérifier ou renvoyer une invitation en attente, tant que l’envoi d’e-mails n’est pas raccordé.
- **Démarrer sans leçon prévue** planifie une leçon qui commence dans deux minutes, avec le formulaire de planification (élève, prestation), au lieu d’une leçon de 50 minutes créée d’un geste.

