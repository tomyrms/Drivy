# R01-T07 — Factures PDF avec QR-facture suisse et envoi (#459)

Branche `tomyrms/r01-t07-factures-pdf`, issue de la tête de `tomyrms/r01-t06-reglements`. Rien n'a été poussé, fusionné ni déployé.
Règle du porteur du 13 novembre : aucun test n'est exécuté avant la fin de l'épic R01. Le rendu du PDF et le décodage du QR n'ont donc jamais été observés.

## Périmètre

- PDF d'une facture émise, généré depuis son instantané, conservé et identifié par révision et empreinte SHA-256.
- Section de paiement QR suisse pour une facture à payer. Aucun ordre de paiement sur un avoir, une facture à zéro, créditée ou déjà réglée en partie.
- Téléchargement authentifié par l'équipe de plateforme.
- Aperçu puis envoi au contact de facturation de l'école, par une file durable et chiffrée, avec renvoi explicite.
- Hors périmètre : rappel avec QR au solde (#461), espace de l'école (#460), envoi planifié du PDF.

## Référentiel QR

Directives SIX QR-facture v2.4, valables depuis le 14 novembre 2026.

- Compte CH ou LI de 21 caractères, adresses structurées, créancier égal au titulaire.
- QR-IBAN (IID 30000 à 31999) avec référence QRR, IBAN ordinaire avec référence SCOR. Aucun QR-IBAN n'est supposé.
- Montant et référence du QR identiques à la facture. Ils sont relus en base, sous le verrou de la fiche, au moment de conserver le document.
- Une donnée absente ou incohérente refuse le document à payer et indique ce qu'il faut corriger.

## Modèle

Migration `20261119_platform_invoice_documents.sql`. Aucune donnée n'est créée.

- `platform_invoice_document` : le PDF conservé, sa révision, son mode de paiement, sa référence, son montant et son empreinte. Une garde refuse toute réécriture et toute suppression.
- `platform_invoice_delivery` : une demande d'envoi, son contenu chiffré, son adresse masquée, ses tentatives et son issue.
- RLS forcée sur les deux tables. L'application ne reçoit aucun droit de lecture sur le contenu chiffré.
- Le rôle `drivy_billing_mailer` n'a aucun droit de table. Il peut seulement prendre un envoi et en écrire l'issue.

## Routes

Sous `/v1/platform/clients/:id` :

- `POST /invoices/:invoiceId/document` : génère ou rend le document.
- `GET /invoices/:invoiceId/document?revision=` : télécharge le PDF.
- `GET /invoices/:invoiceId/delivery/preview` : destinataire, objet, texte, pièce jointe et problèmes bloquants.
- `POST /invoices/:invoiceId/delivery` : met l'envoi en file, avec `operationId`, `confirm` et `resend`.

Les commandes sont versionnées et idempotentes. Le contrat `platform-billing.json` est régénéré, l'OpenAPI canonique 3.11.0 n'est pas modifié.

## États d'envoi

- `QUEUED`, `PROCESSING` : en attente ou en cours.
- `ACCEPTED` : accepté par le serveur SMTP. Ce n'est ni une preuve de livraison ni une preuve de lecture.
- `FAILED` : refus définitif ou tentatives épuisées (cinq au plus).
- `UNCERTAIN` : issue inconnue après une coupure ou un bail expiré. L'envoi n'est jamais rejoué automatiquement, un renvoi reste une décision de l'opérateur.
- `CANCELLED` : le règlement a changé avant l'envoi et le QR n'a plus d'objet.

Seul `ACCEPTED` marque la facture envoyée. Aucune issue ne modifie un paiement ou une échéance, et ni la génération, ni l'envoi, ni un scan ne confirment un règlement.

## Web

- Onglet Factures : création du document, téléchargement, aperçu, envoi et renvoi.
- Relais BFF en liste fermée pour les quatre routes.

## Limites

- Un règlement saisi juste après la prise en charge d'un envoi n'arrête pas cet envoi.
- Un PDF ou un QR déjà transmis ne peut pas être invalidé. Le rapprochement manuel traite un éventuel trop-perçu.
- Le homelab n'a pas de SMTP. Aucun envoi réel n'a eu lieu.
- Au déploiement, il faudra créer un rôle de connexion membre de `drivy_billing_mailer`, lancer le service `billing:mail` et fournir `BILLING_MAIL_DATABASE_URL`, `BILLING_OUTBOX_KEY` et la configuration SMTP. `prepare-invitation-mailer.sql` n'a pas d'équivalent pour ce rôle.

## Tests écrits, jamais exécutés

- `platform-invoice-qr.test.ts` : références, comptes, champs QR, montants et rendu.
- `billing-mail.test.ts` : chiffrement, masquage, classement des erreurs SMTP et configuration.
- Section « documents PDF / envoi des factures / garde-fous » de `platform-billing.integration.test.ts`.

## Reste à qualifier

- Migration et scénarios sur PostgreSQL.
- Rendu du PDF sur ordinateur, mobile et papier, dimensions de la section de paiement.
- Décodage réel du QR, comparaison aux valeurs de la facture et aux exemples officiels SIX.
- Envoi par un serveur SMTP de test, reprise et état incertain.
- Interface dans un navigateur.
