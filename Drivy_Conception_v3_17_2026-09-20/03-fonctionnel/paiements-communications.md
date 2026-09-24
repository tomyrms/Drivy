# Journal de règlements et communications

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Mode d’emploi

Les règles ne sont pas redéfinies ici : les identifiants R renvoient à leur [référence principale](regles-etats.md). Les séquences suivantes spécifient les fonctions du cœur proposé, avec préconditions, variantes, données et critères observables. L’[autorisation](roles-permissions.md) s’applique à tous les appels, même lorsqu’un bouton n’est pas affiché.

<a id="f10"></a>
## F10 · Journal interne des charges et règlements

**Besoins :** B06. **Parcours :** [J08](../02-experience/parcours.md#j08). **Écrans :** [E11](../02-experience/ecrans.md#e11), [E04](../02-experience/ecrans.md#e04).

**Règles et dépendances :** [R11](regles-etats.md#r11), [R12](regles-etats.md#r12), [R23](regles-etats.md#r23), [R24](regles-etats.md#r24), [R25](regles-etats.md#r25), [R32](regles-etats.md#r32). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Donner une réponse fiable à « combien reste-t-il pour cette leçon, cet achat ou cette inscription ? », sans se substituer à une comptabilité ni traiter des cartes bancaires.

### Rôles, autorisations et préconditions

Compte appartenant à l’école et accès financier autorisé. Charge de leçon à réalisation, charge d’achat à vente, charge d’inscription unitaire à confirmation selon conditions. ADMIN ou délégation financière explicitement compatible avec le propriétaire du compte. Correction, remboursement et frais d’absence restent réservés à ADMIN.

### Parcours nominal et conséquences

L’écran sépare prix prévu, charge actuelle, encaissements nets et restant. Enregistrer un montant, un mode réel (espèces, virement, terminal externe, autre) et une date, puis confirmer. L’API verrouille le compte concerné et ajoute une écriture. Un paiement partiel garde un solde. L’élève consulte le journal et peut contacter l’école pour contester, sans pouvoir le modifier.

### Variantes, interruptions et cas limites

Erreur de montant : contre-écriture liée puis bon mouvement. Prix convenu modifié après réalisation : ajustement de charge motivé, jamais réécriture de la réservation. Frais d’annulation : proposition manuelle contractuellement justifiée, par défaut zéro. Deux employés encaisseraient le solde en même temps : l’un réussit, l’autre reçoit le nouveau solde. Les packs prépayés à droits affectés sont inclus via F17 ; aucun portefeuille monétaire global non affecté n’est proposé.

### Données, validations et cycle de vie

ChargeEntry et PaymentEntry append-only par accountId (propriétaire unique Lesson/Purchase/Enrollment), amountCents, currency CHF, type, postedAt, occurredOn, recordedBy, reversalOfId, operationId et reason. Pas de facture fiscale, taux de TVA, référence bancaire secrète ou donnée de carte stockés. Un justificatif « enregistrement interne » ne doit pas être nommé facture.

### Erreurs, événements et reprise

409 AMOUNT_EXCEEDS_BALANCE, 409 REFUND_EXCEEDS_NET_RECEIVED, 409 ALREADY_REVERSED, 412 VERSION_CONFLICT, 422 INVALID_AMOUNT. Un reçu terminal externe reste la preuve du prestataire, pas une preuve de transaction exécutée par Drivy.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T037](../05-realisation/tests-recette.md#t037) | Charge 9 000 centimes ; encaissement de 4 000. | Reste dû 5 000 ; état partiel distinct de réalisé. |
| [T038](../05-realisation/tests-recette.md#t038) | La même commande d’encaissement est renvoyée. | Un seul mouvement, même solde et même identifiant de résultat. |
| [T039](../05-realisation/tests-recette.md#t039) | Le remboursement demandé dépasse l’encaissé net. | Refus sans écriture ni changement du solde. |
| [T040](../05-realisation/tests-recette.md#t040) | Un encaissement erroné a été enregistré. | Contre-écriture traçable ; aucun effacement de l’entrée d’origine. |

<a id="f11"></a>
## F11 · Confirmations et avis fiables

**Besoins :** B03 B04. **Parcours :** [J01](../02-experience/parcours.md#j01), [J02](../02-experience/parcours.md#j02), [J04](../02-experience/parcours.md#j04), [J08](../02-experience/parcours.md#j08). **Écrans :** [E03](../02-experience/ecrans.md#e03), [E04](../02-experience/ecrans.md#e04), [E14](../02-experience/ecrans.md#e14), [E13](../02-experience/ecrans.md#e13).

**Règles et dépendances :** [R12](regles-etats.md#r12), [R13](regles-etats.md#r13), [R26](regles-etats.md#r26), [R32](regles-etats.md#r32), [R40](regles-etats.md#r40). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Distinguer clairement un engagement enregistré de la capacité à prévenir son destinataire.

### Rôles, autorisations et préconditions

Événement métier validé, coordonnées vérifiées et fournisseur email configuré dans l’environnement. Les notifications push de service sont incluses, selon permission ; les SMS restent différés. Le calendrier et l’in-app fonctionnent même en cas de refus push. Les messages de service ne sont pas une inscription marketing.

### Parcours nominal et conséquences

Après commit, une entrée in-app devient visible au destinataire. Un worker traite les transports email/push autorisés et enregistre tentative, acceptation fournisseur ou échec, séparément pour chaque canal. Le lien amène à une ressource authentifiée dans l’école correcte. Un déplacement envoie ancien et nouvel horaire autorisés, sans détail pédagogique. Un bilan publié déclenche un avis générique. L’école voit les échecs persistants et peut utiliser un contact externe.

### Variantes, interruptions et cas limites

Fournisseur indisponible : réessais bornés, pas d’annulation du rendez-vous. Rôle retiré avant expédition : recalcul des destinataires et du contenu autorisé. Plusieurs déplacements rapides : regrouper les avis non encore envoyés pour informer de l’état final tout en gardant l’audit de chaque changement ; ne pas modifier un email déjà accepté. Un lien devenu obsolète ouvre l’état actuel avec avertissement.

### Données, validations et cycle de vie

OutboxEvent, InAppNotification, DeliveryAttempt et providerMessageId. États livraison QUEUED, PROCESSING, SENT, FAILED ; DELIVERED seulement si webhook authentifié du fournisseur l’atteste, jamais assimilé à READ. Les identifiants techniques peuvent subsister sans texte sensible.

### Erreurs, événements et reprise

Le worker conserve cause normalisée, compteur de tentatives et prochaine échéance. L’utilisateur voit « Rendez-vous enregistré. Avis à l’élève en attente » au lieu de « Échec de réservation ». Un webhook est authentifié et idempotent ; le transport reste susceptible de doublon et le contenu doit l’assumer.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T041](../05-realisation/tests-recette.md#t041) | La réservation commit mais le fournisseur email échoue. | La leçon reste confirmée ; état d’avis en attente/échec visible. |
| [T042](../05-realisation/tests-recette.md#t042) | Un avis de publication est envoyé. | Il ne contient ni compétence, ni note personnelle, ni pièce jointe sensible. |
| [T043](../05-realisation/tests-recette.md#t043) | Un avis est en file puis les droits changent. | L’envoi est annulé ou recalculé, sans fuite de contenu. |
| [T044](../05-realisation/tests-recette.md#t044) | Le fournisseur envoie deux fois un accusé de livraison. | Un seul changement d’état de livraison ; aucun nouvel événement métier. |

## Intégration des comptes d’achat et d’inscription

F10 s’applique désormais à Account, propriétaire unique Lesson, Purchase ou Enrollment selon [R23–R25](regles-etats.md#r23). Les routes de compte de leçon sont des accès contextuels au même journal, pas un deuxième registre. Un pack est facturé une fois sur Purchase ; les utilisations couvertes conservent leur prix catalogue à titre de référence mais la charge locale est nulle. Les encaissements enregistrés sur un achat ne se répètent pas dans les comptes des leçons.

La création d’une inscription unitaire porte le compte prévu par ses conditions ; annuler impose libération de place et compensation de charge explicites. Un remboursement n’est saisi qu’après mouvement réel ; une correction de saisie n’en constitue pas un. Les droits pédagogiques (disponibles/réservés/consommés) sont décrits dans [F17](catalogue-packs.md), et ne sont pas calculés depuis le booléen « payé ».

F11 reçoit les événements de publication, inscription, modification et présence, ainsi que de bilan GPS publié. La publication crée une intention de campagne et non un email par élève dans la transaction HTTP. Le worker applique le ciblage [F19](calendrier-notifications.md) et déduplique séparément les canaux. Les preuves de livraison ne démontrent jamais la lecture réelle d’un message.

## Contre-écriture et droits de pack

Un remboursement réel, un REVERSAL ou un ajustement portant sur un achat applique [R53–R54](regles-etats.md#r53) au même commit : le compte et l’utilisabilité des droits ne peuvent diverger. Le journal reste append-only. Une dette redevenue ouverte n’efface pas la prestation déjà réalisée. Le suivi financier et les prochains rendez-vous sont exposés séparément ; toute annulation ou compensation demeure explicite.

## Prix de pack et remise de service

Les lignes de base, frais inclus et options R108 expliquent le total ; le compte reçoit INITIAL au total convenu une seule fois. La remise R107 ne crée pas un nouveau reçu. Les libérations R106 ne restituent pas automatiquement de l’argent : toute retenue ou compensation passe par les contrôles de F10 et les conditions acceptées. Des frais conditionnels automatiques, un échéancier ou une ventilation fiscale ne sont pas déduits de ces champs.

## Éviter les effets comptables d’une correction pédagogique

La correction AP146 et le suivi AP201 de [R109](regles-etats.md#r109) ne créent aucun paiement, remboursement ou ajustement de charge. Une renonciation à consommer un droit n’est pas une remise du prix du pack. Les décisions sur frais restent motivées et suivent le compte F10. Le droit et l’argent peuvent donc garder chacun un suivi distinct.

Les tokens push ne remplacent ni une préférence ni une identité. [R112](regles-etats.md#r112) sépare environnement fournisseur, installation et abonnement scolaire, et limite l’information externe même lorsque l’envoi ne peut plus être rappelé.
