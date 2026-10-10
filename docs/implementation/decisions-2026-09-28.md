# Décisions du porteur du 28 septembre 2026

Après une revue de l’app installée, le porteur a jugé l’app difficile à utiliser : trop de texte, une administration de l’école sur l’iPhone, une connexion web répétée, un élève qui ne voit ni son trajet ni ses erreurs. Il a validé la [carte cible](carte-cible.md) et les décisions ci-dessous. Elles priment sur les règles contraires du dossier de conception 3.17, qui reste une livraison conservée et n’est pas modifié.

| Sujet | Décision | Règle remplacée ou précisée |
|---|---|---|
| Partage avec l’élève | Trajet, erreurs et points positifs notés, bilan et objectifs sont visibles par l’élève **automatiquement**, dès la fin de la leçon ou l’enregistrement du bilan. Le moniteur peut garder pour lui le bilan, le trajet ou une observation précise (« Pour moi »), et revenir sur ce choix. | R46 et AGENTS.md « pas de publication implicite » ; AP54 « sélection explicite ». « Visible » veut dire visible par l’élève et l’école, jamais publié sur internet. |
| App et web | L’app sert au terrain : séance, trajet, bilan, agenda, élèves (moniteur) ; leçons et progression (élève). Le site web sert au bureau : ouverture et configuration de l’école, textes légaux, catalogue, tarifs et conditions, disponibilités, équipe, invitations, champs du profil, formations. Le moniteur garde dans l’app « Inviter un élève » et « Planifier ». | Écrans d’administration de l’iPhone (configuration G1B, catalogue, équipe, politique de champs, réglages de planning). |
| Trajets | Plus de trajets « perso » : un trajet se lance toujours avec un élève, depuis sa leçon ou en choisissant l’élève. Le laboratoire G0 et ses trajets d’exemple locaux disparaissent de l’app. | AGENTS.md « Le laboratoire G0 est local et explicitement séparé ». |
| Connexion | Une seule connexion par appareil : session hors ligne de 30 jours d’inactivité (180 jours au plus), Face ID ou code pour rouvrir l’app, page de connexion aux couleurs de Drivy, connexion par e-mail. Pas de formulaire natif de mot de passe. | Session de 30 minutes / 2 heures ; « sans `offline_access` ». Voir [connexion unique](connexion-unique.md). |
| GPS | L’iPhone 14 Pro Max du porteur est déclaré en **profil d’essai**, pour toutes les versions 26.x d’iOS et tous les builds de l’app. Ce profil reste explicitement `NOT_QUALIFIED` : aucune précision, autonomie ni tenue en arrière-plan n’est revendiquée. | Aucun profil déclaré (`CAPTURE_QUALIFICATION_PROFILES_JSON=[]`), donc aucun trajet scolaire possible. |
| Ajouter un élève | Depuis l’app, l’invitation porte directement la formation Permis B et le moniteur qui invite ; le dossier et la formation existent dès l’acceptation. | L’acceptation ne créait qu’un dossier minimal, sans formation. |
| Disponibilités | Réglées sur le web uniquement. | Réglages de planning dans l’iPhone. |
| Écriture | Moins de texte : un titre sans sous-titre explicatif, pas de note sous les sections, un badge seulement pour l’inhabituel, les mots de l’auto-école (terminer, bilan, leçon, tarif). Une explication n’apparaît qu’en cas d’erreur, avec ce qu’il faut faire. | Notes de bas de section, badges d’état systématiques, vocabulaire du serveur (constat, brouillon, révision, prestation). |
| Déploiement | Le porteur autorise les déploiements sur le homelab au fil de la phase 2, chacun précédé d’une sauvegarde de la base. | AGENTS.md « aucun déploiement du service public n’est implicite » : l’autorisation couvre cette phase, pas les suivantes. |
| Données d’essai | Luc auto école reçoit des données fictives complètes, marquées « exemple ». Le compte `luc` devient administrateur **et** moniteur. | Voir `infra/deploy/provision-example-lessons.sql`. |

## Ordre de réalisation (phase 2)

1. Connexion unique : faite (serveur d’identité appliqué, app compilée).
2. Partage automatique et écran « Ma leçon » : faits et déployés ([partage avec l’élève](partage-eleve.md)).
3. Trajet toujours avec un élève, suppression du laboratoire G0, profil GPS d’essai : faits.
4. Administration sur le web : console complétée (élèves, formations, affectations, disponibilités) et déployée ; écrans retirés de l’iPhone.
5. Onglets par rôle et passe « moins de texte » : app compilée ; le web et les écrans profil/accueil restent à alléger.

Chaque étape se termine par une sauvegarde, un déploiement sur le homelab et un IPA à installer avec iLoader.

## Reste à décider plus tard

- Relais e-mail externe : nécessaire pour les invitations et « mot de passe oublié ».
- Sauvegardes automatiques du homelab : aucune tâche vzdump ni sauvegarde planifiée de `drivy_refonte` n’existe.
