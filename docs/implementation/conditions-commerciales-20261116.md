# Conditions commerciales, essai et début payant — R01-T04 (#456)

Décisions d'implémentation du quatrième lot de l'épic #452. Date : 20 novembre 2026. La migration porte la date 20261116 pour se classer après celle de R01-T03. Branche `tomyrms/r01-t04-conditions-commerciales`, issue de la tête de `tomyrms/r01-t03-offres-modules`. Rien n'est déployé, aucune PR n'est ouverte et aucun test n'a été exécuté : la règle du porteur du 13 novembre veut que les tests de l'épic R01 tournent une seule fois, à la fin.

## Périmètre

L'opérateur enregistre, pour la fiche d'une école :

- des conditions versionnées : montant initial, mensualité, remises, délai de paiement et sort d'une suspension ;
- un essai, avec son début, sa prolongation et sa fin anticipée ;
- la confirmation du début payant ;
- les demandes de changement d'offre et de résiliation, ainsi que leurs décisions.

La base en déduit le cycle commercial et un échéancier **prévisionnel**. Aucune facture n'est émise : c'est le rôle de #457. La suspension (#461), l'impayé et les relances ne sont pas traités ici.

## Unités et dates

- Montants : entiers en centimes de CHF, seule devise admise. La console saisit des francs (`centsOf`) ; l'API relit chaque borne.
- Dates commerciales (début payant, date d'effet, résiliation) : jours civils Europe/Zurich, qui commencent à minuit à Zurich (`drivy.zurich_today`, `drivy.zurich_day_start`). Les bornes de l'essai sont des instants.
- Période mensuelle à ancre stable : l'ancre est le jour du début payant. Si ce jour n'existe pas dans le mois, la période commence le dernier jour du mois. Exemple pour une ancre au 31 : 31 janvier, 28 ou 29 février, 31 mars, 30 avril. Pas de prorata.

## Cycle commercial

`lifecycle` est dérivé dans la base, jamais saisi. `platform_client.commercial_state` (R01-T03) garde son sens : une offre est en vigueur ou non.

| Cycle | Quand | Usage nouveau |
| --- | --- | --- |
| `NONE` | École pilote ou sans essai ni début payant | Inchangé, aucune restriction |
| `TRIAL` | Essai en cours | Selon l'offre |
| `TRIAL_EXPIRED` | Essai échu sans début payant | Fermé pour tous les modules (`WRITE_NEW`) |
| `PAID` | Début payant atteint | Selon l'offre |
| `TERMINATED` | Résiliation acceptée et date d'effet atteinte | Fermé pour tous les modules, sans retour |

Précédence : TERMINATED > PAID > TRIAL > TRIAL_EXPIRED.

En restriction, la projection rend chaque module non accordé, et `restriction.closes` vaut `WRITE_NEW`. La consultation de l'historique et la fin des engagements déjà pris restent permises. Le refus garde le même `403 MODULE_NOT_ENTITLED` ; seul le titre change pour indiquer la marche à suivre (« L'essai de cette école est terminé… » ou le texte de résiliation). Aucune dette ne naît d'un essai.

## Règles des commandes

Toutes les commandes passent par `POST /v1/platform/clients/:id/commercial/...`. Chacune exige une clé d'idempotence et `If-Match` sur la version du dossier ; une version périmée renvoie `412 VERSION_CONFLICT`. Toute personne opératrice active de la plateforme peut écrire (RLS sur `drivy.current_platform_operator()`), comme pour les offres de R01-T03. Le droit `MANAGE_OFFERS` est déclaré dans `platform-model.ts`, mais aucune route ne le vérifie encore : à trancher avant la fin de l'épic. L'action est journalisée ; les motifs et les textes libres restent dans le dossier, jamais dans le journal.

| Route | Action | Règles principales |
| --- | --- | --- |
| `terms` | `SET_COMMERCIAL_TERMS` | Chaque version redonne tout (`null` = à compléter). Avant le début payant, l'effet est immédiat ou à la date choisie. Après, l'effet a lieu au prochain début de période ; toute autre date exige un motif (`TERMS_EXCEPTION_REASON_REQUIRED`). Une date passée est refusée (`EFFECTIVE_DATE_PAST`). |
| `trial/start` | `START_TRIAL` | Un seul essai (`TRIAL_EXISTS`). Il est fermé après le début payant ou une résiliation (`TRIAL_CLOSED`), et sa fin doit être à venir (`TRIAL_END_PAST`). Le début proposé par défaut est l'activation de l'école. |
| `trial/extend` | `EXTEND_TRIAL` | Avec motif, et une fin postérieure à l'actuelle (`TRIAL_EXTEND_INVALID`). Prolonger un essai échu le rouvre. |
| `trial/end` | `END_TRIAL_EARLY` | Avec motif, seulement pour un essai en cours (`TRIAL_NOT_RUNNING`). |
| `paid-start` | `CONFIRM_PAID_START` | `confirm: true`, conditions complètes à cette date (`TERMS_INCOMPLETE`), date aujourd'hui ou plus tard. Un seul début payant actif (`PAID_START_EXISTS`). |
| `paid-start/cancel` | `CANCEL_PAID_START` | Avec motif, tant que le début n'est pas atteint (`PAID_START_STARTED`). |
| `requests` | `RECORD_COMMERCIAL_REQUEST` | `OFFER_CHANGE` ou `TERMINATION`. La date de réception ne peut pas être future (`REQUEST_DATE_FUTURE`). |
| `requests/:requestId/decision` | `DECIDE_COMMERCIAL_REQUEST` | `IN_PROGRESS`, `ACCEPTED`, `REFUSED` ou `WITHDRAWN`. Une demande close ne bouge plus (`REQUEST_CLOSED`). Une acceptation porte sa date d'effet. Si elle porte sur un changement d'offre, elle crée l'attribution de R01-T03 à cette date. Une résiliation acceptée est irréversible. |

Après une résiliation, toute commande est refusée (`CLIENT_TERMINATED`).

## Lecture

`GET /v1/platform/clients/:id/commercial` rend :

- le cycle, la restriction et les jalons de la fiche ;
- l'essai et ses changements ;
- les conditions (en vigueur, programmées, historique, champs manquants) ;
- le début payant et son historique ;
- la résiliation et les demandes ;
- `nextPeriodStart` et l'échéancier prévisionnel : le montant initial, puis au plus 12 périodes ;
- `today` (jour de Zurich) et la version du dossier.

La fiche et l'annuaire portent un résumé : `lifecycle`, `trialEndsAt`, `paidStartsOn`, `terminationOn`, `billingReady` et `dueDates` (au plus 4 instants, jamais un montant).

`GET /v1/schools/:schoolId/entitlements` ajoute `lifecycle`, `restriction`, `trialEndsAt`, `paidStartsOn` et `terminationOn`. Ces champs n'exposent ni montant, ni motif, ni auteur.

Contrats : `apps/api/contracts/platform-commercial.json` est nouveau ; `platform-clients.json` et `school-entitlements.json` sont étendus. Tous sont générés par `scripts/generate-platform-contract.ts`. L'OpenAPI canonique 3.11.0 n'est pas modifié.

## Web

- Relais BFF `/app/bff/platform/clients/:id/commercial` (lecture et huit commandes) à liste fermée. Les corps sont stricts et bornés comme dans l'API, et les identifiants passent en minuscules. Les schémas de réponse restent tolérants : une API antérieure sans cycle reste lisible.
- Console, fiche d'une école : rubrique « Contrat ». Elle affiche le cycle, avec le badge « Usage nouveau fermé » seulement en restriction, puis l'essai, les conditions en vigueur, le début payant, la prochaine période et la résiliation. Viennent ensuite les conditions programmées, les demandes ouvertes avec « Traiter », l'échéancier prévisionnel replié et l'historique replié. Chaque commande s'ouvre dans une boîte de dialogue. Le formulaire contrôle la forme ; l'API reste juge de chaque règle. L'écran ne calcule ni montant ni période.
- Annuaire : une école en essai terminé ou résiliée porte ce badge à la place de celui du code. La fiche montre la ligne « Cycle » et « Prochaine échéance ».
- Espace école : `schoolEntitlementsSchema` lit les nouveaux champs en option. Le comportement ne change pas, puisque les modules sont déjà rendus non accordés.

## iPhone et iPad

`SchoolEntitlements` décode les nouveaux champs. Ce sont des `var` optionnelles avec défaut : l'initialiseur par membres utilisé par les tests reste valide. L'app n'affiche rien de plus ; le refus nommé de R01-T03 couvre déjà le cas, avec le titre envoyé par le serveur. Ce code a été écrit sans compilateur Swift : il n'a jamais été compilé.

## Limites

- Aucune facture, aucun rappel, aucun courriel à l'école (pas de SMTP). L'échéancier est indicatif.
- La suspension `CONTINUE`/`PAUSE` est seulement enregistrée ; #461 l'appliquera.
- Pas de prorata. Pas d'autre devise que le CHF.
- Le passage de TRIAL à TRIAL_EXPIRED se fait à la lecture, par l'horloge de la base, sans tâche planifiée. `nextChangeAt` annonce l'échéance pour que les clients relisent.
- Aucune étape de recette navigateur n'a été ajoutée.
- Droits fins des personnes opératrices non appliqués (voir « Règles des commandes »).

## À savoir pour #457 (factures)

La version de conditions applicable à un jour donné et le début de chaque période sont calculés dans la base (`drivy.is_billing_period_start` et la projection de l'échéancier). Une facture devra reprendre ce calcul, pas le refaire. `billingReady` indique qu'un début payant confirmé dispose de conditions complètes.
