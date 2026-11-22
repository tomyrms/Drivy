# R01-T08 — Espace abonnement, factures et demandes de l'école (#460)

Branche `tomyrms/r01-t08-espace-ecole`, issue de la tête de `tomyrms/r01-t07-factures-pdf`. Rien n'a été poussé, fusionné ni déployé.
Règle du porteur du 13 novembre : aucun test n'est exécuté avant la fin de l'épic R01. La migration, les routes et l'écran n'ont donc jamais tourné.

## Périmètre

- Rubrique web « Abonnement » du portail de gestion, responsive, ouverte depuis le compte de l'école sur iPhone et iPad. Aucune copie du back-office en Swift.
- Offre, modules, essai, conditions initiales et mensuelles, changements à venir, prochaine période et prochaine échéance.
- Factures et avoirs émis, solde, règlements confirmés, téléchargement du document déjà conservé.
- Demandes de changement d'offre ou de modules, de résiliation et de régularisation, avec suivi séparé de la demande, de la décision et de la fin effective.
- Côté équipe Drivy : réponse, confirmation, changement de date ou reprise, boîte des demandes.

## Autorisation

- Le responsable est un membre actif de rôle `ADMIN`. `drivy.current_school_commercial` ne dépend pas de l'état de l'école : une école archivée, suspendue ou résiliée garde ses documents, son contact et sa demande de régularisation, sans se réactiver.
- Élèves, moniteurs et personnes extérieures sont refusés au serveur. Une facture d'une autre école répond 404, y compris pour une personne responsable ailleurs.
- Une demande ne modifie ni l'offre ni les modules. Seule une décision de l'opérateur le fait.

## Modèle

Migration `20261120_school_commercial_space.sql`. Aucune donnée n'est créée.

- `platform_commercial_request` : source, auteur, modules demandés, type `REGULARIZATION`, statut `REVOKED`, une seule demande ouverte par type et par fiche.
- `platform_termination_decision` : journal append-only des changements de date et des reprises, RLS forcée.
- `platform_commercial_notice` : un avis par événement, version et destinataire, donc aucun doublon au rafraîchissement ou à la reprise.
- `push_notification` : catégorie `COMMERCIAL`, texte générique sans montant, envoyée aux responsables à chaque réponse de Drivy.

## Routes

Sous `/v1/schools/:schoolId/subscription` :

- `GET /` : vue de l'école, avec ETag.
- `POST /requests` : demande, idempotente.
- `POST /requests/:requestId/withdraw` : retrait tant que la demande est ouverte, avec `If-Match`.
- `POST /notices/read` : avis marqués lus.
- `GET /invoices/:invoiceId/document` : PDF conservé. Cette route n'en génère jamais.

Côté plateforme :

- `POST /v1/platform/clients/:id/commercial/requests/:requestId/revision` : nouvelle date ou reprise.
- `GET /v1/platform/commercial-notices` et `POST /v1/platform/commercial-notices/read`.

Contrats `school-subscription.json` et `platform-commercial.json` générés. L'OpenAPI canonique 3.11.0 n'est pas modifié. Les routes appelées par le web sont déclarées dans la passerelle.

## Règles de résiliation

- Une résiliation envoyée reste « En attente de confirmation », sans date d'effet.
- Une fois confirmée, elle ne se retire plus. Changer la date ou reprendre le service est une nouvelle décision de l'opérateur, visible par l'école, possible seulement avant la date d'effet.
- Une reprise après la date d'effet est refusée, car elle relancerait le rattrapage des périodes et créerait des factures.
- Accepter une régularisation ne réactive rien.

## Limites

- Une école résiliée de façon effective ne peut pas être reprise par cette voie. Le parcours de réactivation reste à décider.
- La lecture des avis est partagée entre les responsables d'une même école.
- Aucun courriel n'est envoyé : le homelab n'a pas de SMTP.
- Avancer une résiliation à aujourd'hui peut laisser une facture de la période du jour, à corriger par un avoir.
- L'index d'unicité fait échouer la migration si des demandes ouvertes en double existent déjà. À contrôler avant le déploiement.
- Sur une décision déjà close, la route opérateur peut répondre 404 si le verrou masque la ligne. Comportement antérieur, l'`If-Match` répond normalement 412 avant.
- L'aperçu de la rubrique est en lecture seule, avec des données synthétiques.

## Tests écrits, jamais exécutés

- `apps/api/test/school-subscription.integration.test.ts` : accès, demandes, concurrence, retrait, résiliation, révision, factures, document, école archivée, avis, garde-fous.
- `apps/web/client/subscription-model.test.ts` : libellés, étapes, actions possibles, alerte prioritaire, corps des demandes.

## Reste à qualifier

- Migration et scénarios sur PostgreSQL.
- Rubrique dans un navigateur, sur mobile et ordinateur, avec clavier et lecteur d'écran.
- Accès depuis l'app iPhone et iPad : le code Swift n'a pas été compilé.
- Notification push réelle au responsable.
