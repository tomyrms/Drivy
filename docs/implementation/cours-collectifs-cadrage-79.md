# Cours collectifs : cadrage #79

Epic #37. Mis à jour le 23 octobre 2026. Ce document consigne les règles confirmées par le porteur et les seules propositions restantes. Il ne relance aucune question déjà tranchée.

## 1. Règles confirmées (23 oct. 2026)

| Domaine | Règle confirmée |
| --- | --- |
| Types | Sensibilisation et Premiers secours prédéfinis. Types personnalisés : nom et description. |
| Organisation | Cours internes à l'école. Aucun partenaire externe, aucune inscription publique. |
| Gestion | Depuis l'agenda iOS, iPadOS et web. |
| Droits | Administrateur et moniteur avec le droit `MANAGE_COURSES` (déjà présent dans `membership.grants`). Droits relus au serveur. |
| Série | Une série compte plusieurs séances. L'élève s'inscrit à toute la série. |
| Présence | Séances à présence obligatoire configurées par série. |
| Capacité | Pas de surréservation. Pas de chevauchement pour l'élève ni pour le formateur. |
| Déjà accompli | L'élève voit l'offre. Il ne peut pas s'inscrire au même type déjà validé. |
| Paiement | Sur place. Aucun paiement en ligne. |
| États | Inscription, présence, paiement et validation sont distincts. |
| Notifications | Push avec préférences individuelles. Aucun e-mail automatique. |
| Annulation (#41) | Autonome jusqu'à 24 h avant la première séance par défaut. |
| | Délai modifiable (ex. 48 h) par l'admin ou le moniteur habilité. |
| | Version des conditions conservée par inscription. Aucun durcissement rétroactif. |
| | Après l'échéance : l'élève contacte le personnel (e-mail ou message volontaire). Ce contact n'annule rien et ne libère aucune place. Le personnel décide. |
| | Aucun frais, barème ni remboursement automatique. |
| Liste d'attente (#40) | Ordre d'entrée dans la liste. |
| | Proposition exclusive au premier élève admissible, avec un délai. |
| | Refus ou expiration : proposition au suivant. |
| | Aucune inscription automatique. Pas de push à toute la liste. |
| | Retenue de capacité pendant la proposition. Ce n'est pas une inscription. Elle ne bloque pas l'agenda de l'élève. |
| | Une réservation concurrente ne prend pas la place retenue. |
| | Les alertes « prochaines sessions » sont indépendantes de la file. |

Ces règles remplacent les anciennes propositions « 48 h par défaut », « annulation tardive autonome » et « push à tous, premier servi ».

## 2. Propositions restantes

> **PROPOSITION non approuvée.** Valeurs proposées par Claude. Le porteur ne les a pas choisies.

| Sujet | Proposition |
| --- | --- |
| Délai d'acceptation (#40) | 12 h par défaut. Paramètre école `offerResponseMinutes`. |
| Activation de la file | `offerResponseMinutes = null` : file prioritaire non activée. Activation explicite requise avant #40. |
| Près du début | Échéance = min(proposition + 12 h, début de la première séance - 2 h). |
| | Si moins de 30 min restent : aucune proposition. La place reste libre pour une inscription directe. |
| Refus ou expiration | L'élève quitte la file. Il peut se réinscrire en fin de file. |
| Rappels (#43) | 24 h et 2 h avant la séance, réglables. |
| Minimum de participants | Alerte au personnel 72 h avant la première séance. Aucune annulation automatique. |
| Validation finale (#82) | Explicite, par une personne habilitée (`VALIDATE_REQUIREMENT`). Après les présences obligatoires. Jamais sur le seul paiement. |
| Formation inconnue (#39) | Affichée « à confirmer sur place ». Contrôle documentaire sur place. |
| Inscription manuelle (#39) | Par le personnel, à la demande de l'élève. Source `STAFF` tracée. |
| Inscriptions équivalentes | Une seule inscription active par type et par élève. |
| Modification d'une série publiée | Relève de #41. |
| | Déplacement de la première séance : l'échéance est recalculée pour les nouvelles inscriptions seulement. |
| | Les inscriptions existantes gardent leur échéance, sauf si la nouvelle est plus favorable. |
| | Une proposition active n'est pas raccourcie. |
| | Pas de reconfirmation obligatoire ni d'annulation tardive générale. |

## 3. Vérification réglementaire

Texte des articles lu le 23 octobre 2026 dans les versions consolidées officielles. Source : Fedlex, OAC (RS 741.51).

- Version au 1er janvier 2026 : https://fedlex.data.admin.ch/filestore/fedlex.data.admin.ch/eli/cc/1976/2423_2423_2423/20260101/fr/html/fedlex-data-admin-ch-eli-cc-1976-2423_2423_2423-20260101-fr-html-3.html
- Version au 1er janvier 2027 : https://fedlex.data.admin.ch/filestore/fedlex.data.admin.ch/eli/cc/1976/2423_2423_2423/20270101/fr/html/fedlex-data-admin-ch-eli-cc-1976-2423_2423_2423-20270101-fr-html-2.html

### Ce que dit le droit

- **Art. 10, premiers secours aux blessés.** Attestation d'un institut reconnu par l'OFROU. Délivrée seulement à qui a suivi tout le cours. Au plus six ans au moment de l'annonce à l'examen théorique. Programme approuvé par l'OFROU.
- **Art. 18, théorie de la circulation (sensibilisation).** Catégories A, B, A1 et B1. Huit heures au total. Auprès d'un moniteur de conduite, qui remet une attestation.
  - En 2026 : la participation suppose le permis d'élève.
  - Au 1er janvier 2027 : possible au plus tôt six mois avant l'âge minimal. Les cantons fixent et contrôlent les moyens didactiques.
- La durée « 10 heures sur 2 jours » des premiers secours vient d'instructions OFROU. **Non vérifiée** dans cette intervention.

### Choix produit (pas du droit)

- Drivy n'impose aucune durée.
- Drivy ne délivre aucune attestation officielle.
- Drivy ne vérifie pas la reconnaissance OFROU.
- Drivy affiche le total horaire des séances. Le personnel décide.

## 4. Parcours

Chaîne : agenda → brouillon → publication → inscription → attente → proposition → acceptation, refus ou expiration → annulation dans le délai ou contact → appel → règlement sur place → accomplissement.

| Étape | Élève | Moniteur habilité | Moniteur non habilité | Admin |
| --- | --- | --- | --- | --- |
| Agenda, brouillon | Rien | Crée la série et les séances | Voit ses séances | Comme habilité |
| Publication | Voit l'offre | Publie | Non | Publie |
| Inscription | S'inscrit à toute la série | Inscrit sur demande (`STAFF`) | Non | Comme habilité |
| Complet | Rejoint la liste d'attente | Voit la file | Non | Voit la file |
| Proposition | Voit l'offre dans l'app, même sans push. Accepte ou refuse | Voit l'état | Non | Voit l'état |
| Annulation | Seul avant l'échéance. Après : contact | Annule et trace | Non | Annule et trace |
| Appel (proposition #42) | Rien | Note les présences | Formateur de la séance ou droit `TAKE_ATTENDANCE` | Note |
| Règlement | Paie sur place | Enregistre le paiement | Non | Enregistre |
| Accomplissement | Voit le résultat | Valide si `VALIDATE_REQUIREMENT` | Non | Valide |

Une notification ne vaut ni inscription ni lecture. La liste d'attente n'expose aucune donnée privée des autres élèves.

### Erreurs et reprise réseau

- Chaque écriture porte un `operationId`. Un renvoi après coupure ne crée pas de doublon.
- Les modifications portent `If-Match`. Une version périmée renvoie un conflit. L'écran recharge et explique.
- Aucun succès affiché avant l'écriture durable.
- Erreurs visibles : complet, chevauchement, échéance passée, proposition expirée, droit manquant, type déjà validé.

## 5. Responsabilités transmises

| Issue | Responsabilité |
| --- | --- |
| #80 | Socle : migration 042, `apps/api/src/courses.ts`. Modèle série, séances, inscriptions, retenues, conditions versionnées. |
| #38 | Création et publication depuis l'agenda. |
| #39 | Inscription, formation inconnue, inscription `STAFF`, unicité par type. |
| #40 | File prioritaire, proposition exclusive, `offerResponseMinutes`. |
| #41 | Annulation, délai, contact hors délai, modifications de série. |
| #42 | Présences et appel. |
| #81 | Règlement sur place. |
| #82 | Validation finale explicite. |
| #43, #44 | Rappels, alerte minimum, préférences push. |

Hors périmètre : paiement en ligne, organisme externe, attestation officielle, dépendance à la messagerie #65.
