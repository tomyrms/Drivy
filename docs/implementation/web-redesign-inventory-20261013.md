# Refonte du portail — inventaire et parcours

État examiné le 13 octobre 2026, avant puis pendant la refonte « Bureau de précision ». Cet inventaire provient du code et des références du dépôt. Il ne constitue pas une preuve navigateur, une recette d’auto-école ou une validation des parcours physiques. Les contrôles effectivement exécutés et les captures sont consignés séparément par l’intégration.

## Références et limites

Lecture de `AGENTS.md`, `Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md`, du contrat `04-technique/api.md`, des règles R86–R98 et du parcours J19, complétée par les décisions du 28 septembre et du 13 octobre, `realisation-onboarding-ecole-20261013.md` et `web-architecture-20260930.md`. Les décisions d’implémentation récentes priment sur les formulations historiques de publication du bilan ou de brouillon de confidentialité. Le contrat canonique OpenAPI 3.11.0 et le dossier livré restent intacts.

Le portail est le bureau de l’école. L’agenda y reste en lecture seule ; la leçon, sa planification terrain, le GPS et le replay natif ne sont pas reconstruits sur le web. Aucun indicateur, export, paiement ou cours collectif absent du portail actuel n’est ajouté à titre décoratif.

## Stack, données et accès

- React 19, TypeScript strict, Vite ; CSS commun et primitives dans `apps/web/client/ui.tsx`. Les racines de connexion, ouverture et console sont sélectionnées par `main.tsx`.
- BFF Fastify, OIDC, session serveur, cookies HttpOnly, protections CSRF. `protocol.ts` gère session et identité ; `school-api.ts` valide les réponses métier avec Zod.
- Le BFF autorise une liste explicite de routes dans `server/school-routes.ts`. Les services API et PostgreSQL relisent les droits ; afficher ou masquer un bouton ne les remplace pas.
- La console de cette livraison requiert le rôle ADMIN. La présence du rôle dans l’interface n’élargit jamais les lectures autorisées des traces ou bilans. Les grants, dont `CONFIGURE_CATALOG`, restent contrôlés séparément.
- Plusieurs écoles sont réellement prises en charge. Le changement d’école change le scope des lectures, des listes et des brouillons ; le contexte contient l’identifiant de personne, d’école, d’appartenance et son `accessEpoch`.
- Les commandes passent par `command-core.ts` et `command-store.ts` : version, idempotence, reçu, réponse inconnue et relecture durable. Le succès ne précède jamais la confirmation serveur. Une commande incertaine bloque une nouvelle mutation de l’école jusqu’à résolution.
- Le stockage persistant ne reçoit ni dossier, ni nom, ni recherche d’élève, ni texte de formulaire. Le thème est une préférence technique distincte. Les recherches et contextes de listes restent uniquement dans la mémoire scoped `context.drafts`.

## Pages et fonctions inventoriées

Les sections ci-dessous conservent leur adresse `/app/gestion/:schoolId/:section`. Une réorganisation du menu ne supprime pas les anciennes destinations.

| Entrée | Contenu et actions existants | Source principale |
|---|---|---|
| `/app/` | Connexion, déconnexion, écoles liées, école absente, invitation en attente, ouverture console selon accès | `App.tsx` |
| `/app/invitation` | Identité utilisée, adresse vérifiée, aperçu invitation, notice et conservation, confirmation personnelle, changement de compte, remise à plus tard, reprise du résultat inconnu | `App.tsx` |
| `/app/ouvrir` | Lien secret retiré de l’URL, OIDC, coordonnées école et responsable, choix explicite du rôle moniteur, création et suite du guide | `school-opening.tsx` |
| `/app/operateur` | Émission, copie et révocation des liens d’ouverture, état et expiration ; autorisation opérateur distincte d’ADMIN | `school-opening.tsx` |
| `agenda` | Semaine, aujourd’hui, filtre moniteur, recherche élève, leçons regroupées par date, états inhabituels, ouverture dossier avec contexte de retour | `console/agenda.tsx` |
| `disponibilites` | Choix moniteur, règles hebdomadaires, jours, heures, début de validité, ajout/retrait, lien agenda et retour membre | `console/availability.tsx` |
| `absences` | Choix moniteur, période début/fin, ajout/retrait, lien agenda et retour membre | `console/availability.tsx` |
| `eleves` | Recherche nom/e-mail, actifs/archivés/tous, liste/détail, invitation, formations, moniteurs, permis, progression et bilans, archivage/restauration | `console/learners.tsx` |
| Dossier élève | Données administratives réellement manquantes, enregistrement, lecture du choix GPS, ouverture de formation, affectation/retrait moniteur, transitions motivées | `profile-completion.tsx`, `gps-consent.tsx`, `learners.tsx` |
| Suivi formation | Compétences, niveau, derniers constats, bilans chargés à la demande, filtres année/mois, historique partiel signalé | `console/dossier.tsx` |
| `trajets` | Inventaire administratif, recherche dans page chargée, pagination, filtre élève, durée, retour dossier | `console/trips.tsx` |
| `equipe` | Recherche, affichage optionnel élèves, rôle/grants, motif, revue des changements, retrait d’accès, accès propre et dernier ADMIN contrôlés au serveur | `console/people.tsx` |
| `invitations` élèves | Code, permis et moniteur, copie code/message, email si disponible, recherche/statut, renouvellement, révocation motivée, invitation acceptée/expirée | `console/people.tsx` |
| `invitations` équipe | Invitation email, choix moniteur/administration, lecture capacités de messagerie, renvoi/révocation, états | `console/people.tsx` |
| `formations` | Vue par permis, liens vers offre/programme/procédure/prix, préparation formation complète, autres prestations | `console/formations.tsx` |
| `offres` | Liste/détail/version, catégorie, référentiel, procédure, durée, validité, activation, liens de référence | `console/catalog.tsx` |
| `referentiels` | Programmes, compétences et descriptions, création/version, approbation | `console/catalog.tsx` |
| `procedures` | Déroulement, conditions d’annulation, sources, textes proposés, version/approbation | `console/catalog.tsx` |
| `prestations` | Prix CHF, unité, type, catégorie, durée, période, conditions, activation, version/historique ; entrée guidée tarif de leçon | `console/commerce.tsx` |
| `conditions` | Conditions commerciales, texte, validité et versions ; dates commerciales conservées car elles portent sur une offre | `console/commerce.tsx` |
| `configuration` | Nom, email, téléphone, fuseau ; statut et poursuite préparation en DRAFT | `console/configuration.tsx` |
| `confidentialite` | Notice, conservation, contact, adoption explicite, impact GPS lu au serveur avant remplacement, accès conditions école | `console/privacy.tsx` |
| `champs-profil` | Informations demandées, caractère facultatif/requis, étape, explication, aperçu élève et publication immédiate | `console/privacy.tsx` |
| `signalements` | Activation et ordre des thèmes, déplacement au pointeur et au clavier, aperçu, sauvegarde | `console/observation-themes.tsx` |
| `apercu` DRAFT | Guide école, confidentialité, profil, formations, tarifs, revue ; brouillon serveur, reprise, report, conflit, sauvegarde avant départ, activation | `console/school-setup.tsx` |
| `apercu` ACTIVE | Actions de préparation calculées au serveur, reprise formations différées, accès agenda | `console/overview.tsx` |
| `apercu?from=formations/prestations` | Même compositeur limité au catalogue, sans réadoption de confidentialité | `console/school-setup.tsx` |

Les préférences personnelles et la recherche des paramètres constituent les nouvelles destinations/outils de la refonte, en complément de cet inventaire initial. Elles ne représentent pas de nouveaux paramètres de l’école côté API.

## Parcours, action finale et retour

| Parcours | Étapes et résultat durable | Retour et point d’attention |
|---|---|---|
| Retrouver un élève | Élèves → recherche/filtres → dossier → corriger ou consulter | Recherche, filtre et tri mémoire conservés en revenant ; sélection partageable par identifiant |
| Compléter un profil | Signal dans liste → dossier → champs indiqués par action-readiness → enregistrement | Relecture après confirmation, disparition du signal si résolution ; erreur de lecture visible et réessayable |
| Gérer la formation | Dossier → formation concernée → gestion/affectation/permis/transition → confirmation | Même élève, données relues ; archivage du dossier distinct du retrait d’accès |
| Consulter une leçon | Agenda semaine/moniteur/recherche → élève → bilan | Retour à la semaine et au moniteur ; recherche mémoire conservée |
| Consulter un trajet | Trajets page N → dossier → retour trajets | Page et recherche conservées ; filtre élève distinct des pages globales |
| Inviter | Élèves/Équipe → audience correspondante → code ou email → confirmation serveur | Code secret uniquement dans réponse/mémoire ; email envoyé et invitation acceptée restent deux états distincts |
| Modifier un accès | Équipe → membre → rôles/grants/motif → revue → confirmation | Même membre après relecture ; réauthentification si nécessaire, refus dernier ADMIN présenté |
| Organiser un moniteur | Membre → horaires/absences → ajout/retrait → confirmation | Retour membre ou agenda avec moniteur sélectionné |
| Préparer une formation | Formations → compositeur → formation/prix/conditions → revue → application | Retour catalogue ; références/version conservées, prix jamais inventé |
| Maintenir les textes | Paramètres → confidentialité → modifier → relire l’impact → adopter | Textes durables immédiatement ; aucun nouveau brouillon administratif/date d’effet |
| Définir les données requises | Paramètres → informations élèves → choisir/justifier → aperçu → confirmer | Publication immédiate et conséquence sur planification annoncée |

## Navigation et préservation du contexte

`console/route.ts` autorise les identifiants de sélection/élève/moniteur, la catégorie, l’origine, l’audience et la semaine. Les valeurs ambiguës, doublons et UUID invalides sont ignorés. Noms, emails, texte des recherches, brouillons et secrets sont exclus. Les liens existants, l’ouverture dans un nouvel onglet et l’historique précédent/suivant restent à qualifier au navigateur après chaque modification du shell.

`console/list-state.ts` conserve recherche, filtre et tri des élèves ; recherche et portée de l’équipe ; recherche/statut de chaque audience d’invitation ; recherche agenda ; recherche et curseurs des trajets. Ce cache ne sort pas du scope authentifié de l’école, n’effectue aucune lecture réseau ni écriture durable, et disparaît au rechargement, à la déconnexion ou au renouvellement du scope d’accès. Les liens directs continuent d’ouvrir l’entité nommée même lorsqu’un filtre mémoire l’écarte de la liste.

Le retour dossier issu des trajets retrouve les curseurs mémoire. Le retour d’un trajet filtré depuis un dossier conserve également le contexte agenda s’il existait. Les résultats de recherche affichent seulement les lignes réellement chargées. Une liste partielle ne prétend jamais couvrir toute l’école.

## États et confirmations

- `LoadState` conserve les anciennes données d’une même ressource pendant une relecture ; un changement d’école ou d’entité masque immédiatement l’ancien scope. Échec = message et reprise/reconnexion, jamais résultat vide inventé.
- `OutcomeNotice` et le panneau de commande incertaine distinguent succès durable, refus, réauthentification, conflit et réponse inconnue. Les erreurs serveur restent près de la tâche en cours.
- Les dialogues métier existants couvrent adoption des textes/impact GPS, rôles et retrait d’accès, renouvellement/révocation d’invitation, archivage/restauration, retrait moniteur, contrôle permis et transition formation. Ils réutilisent le dialogue natif et son focus.
- Les modifications non enregistrées enregistrent un garde de navigation ; le formulaire n’est pas effacé avant le choix de quitter. Annuler explicitement le formulaire abandonne sa saisie. Les recherches/filtres n’activent jamais ce garde.
- Aucun accès ADMIN de navigateur ne remplace la décision du serveur ; aucun écran visuel simulé ne prouve le cloisonnement PostgreSQL.

## Constats du code avant refonte et corrections ciblées

1. Recherches et filtres locaux se perdaient dès que la section était démontée. Le cache mémoire scoped préserve maintenant le contexte sans inscrire de données personnelles dans l’historique ou le stockage du navigateur.
2. Les listes élèves/équipe n’avaient ni en-têtes de colonnes ni décompte, et le retour explicite de détail était essentiellement mobile. Elles utilisent des tables compactes, des compteurs réels et une action de retour. Les élèves disposent du tri A–Z/Z–A et du filtre « À compléter ».
3. Une panne de lecture de `ProfileCompletion` retournait `null`, laissant un badge sans action de résolution. La lecture affiche désormais chargement, erreur/réessai, ou champs manquants ; la validation est placée près des champs. Si la readiness ne fournit aucun champ administratif corrigeable, le portail l’explique au lieu de masquer la situation.
4. La pagination des trajets était perdue après ouverture du dossier. Elle est conservée en mémoire et le dossier propose un retour explicite à cet inventaire.
5. Le guide protégeait sa saisie, contrairement à plusieurs formulaires locaux. Les pages concernées enregistrent désormais leurs modifications auprès du garde commun.
6. Les éditeurs de référentiels, procédures, offres, conditions et prestations vérifient le départ avant de réinitialiser leur brouillon. Ils affichent explicitement une version non enregistrée, son enregistrement ou un résultat à vérifier. L’historique des offres/tarifs est conservé en mémoire. Les formations sont désignées par leur permis ; leur référence technique reste consultable dans le détail.

## Limites existantes à préserver et à qualifier

- `readAll` est borné. Le filtre élève des trajets porte sur les 1 000 derniers trajets autorisés : l’API ne fournit pas encore ce filtre serveur. L’avertissement et la pagination globale demeurent nécessaires.
- Le lien d’une invitation acceptée ouvre la liste équipe/élèves ; le DTO de ce parcours ne garantit pas l’identifiant du dossier à sélectionner. Aucun rapprochement par nom/email n’est inventé.
- Les profils requérant une étape personnelle non corrigeable administrativement ne deviennent pas complets grâce à une écriture fictive.
- Les réglages des modules GPS, packs et cours ne sont pas ajoutés implicitement. Choix GPS individuel, permission système et activation scolaire restent distincts.
- Ces changements frontend ne qualifient pas GPS, batterie, VoiceOver physique, messagerie de production, procédures juridiques ou recette avec une vraie école.

## Scénarios de recette associés

À exécuter dans la recette d’intégration avec données synthétiques : filtrer/trier élèves → ouvrir dossier → trajets → retourner ; ouvrir page suivante des trajets → dossier → retour ; rechercher dans agenda → dossier → retour semaine/moniteur ; basculer audiences d’invitations sans mélanger recherches ; modifier coordonnées/profil/rôles puis tenter navigation/retour navigateur ; provoquer refus et erreur réseau ; ouvrir une URL de sélection directement ; changer école et constater l’absence du contexte précédent ; vérifier lecture ADMIN et refus du rôle non autorisé. Contrôler clavier, focus, mobile, zoom et les deux thèmes sur les mêmes données.

## Vérifications de ce lot exécutées

Le 13 octobre, `npm run typecheck` passe sur le client, le BFF et les tests. Les cinq fichiers ciblés `profile-completion-model`, `dossier-model`, `agenda-model`, `invitation-model` et `console-route` passent : **45 tests**. Ils couvrent leurs règles et les routes existantes ; ils ne prouvent pas les nouveaux allers-retours visuels ou le fonctionnement du garde dans un navigateur. La [preuve de vérification finale](web-redesign-verification-20261013.md) consigne séparément les interactions exécutées ensuite et les limites de la recette synthétique. La suite web complète atteint 233 tests réussis.
