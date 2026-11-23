# Mise en service et recette de l'épic R01 (#463)

Préparé le 23 novembre 2026 sur la branche `tomyrms/r01-t11-qualification`, issue de T10 (`60229833`). **Rien de ce document n'a été exécuté.** Aucun test, aucune migration R01 non déployée, aucun aperçu, aucun envoi et aucun déploiement n'ont été lancés pour T11. L'issue reste ouverte tant que la recette ci-dessous n'est pas remplie.

## Paramètres à fournir

Aucune de ces valeurs ne va dans le dépôt, la CI ou les journaux.

| Paramètre | Où | Décision du porteur |
| --- | --- | --- |
| Opérateurs initiaux | Console, invitation | Qui, en sachant que tout opérateur actif a les mêmes droits |
| Émetteur et compte bancaire | Console, facturation | Raison sociale, adresse, IBAN ou QR-IBAN réels |
| Fiscalité | Console, facturation | Mode TVA, numéro, taux, prix TTC ou HT, à faire valider |
| Prix et remises | Offre et conditions de chaque école | Montant initial, mensualité, remise, délai de paiement |
| Essai | Conditions de chaque école | Durée |
| Relances | Politique | Paliers (défaut 3, 15, 30 jours), délai de suspension (défaut 2 mois), avertissement (défaut 14 jours) |
| Pendant une suspension | Conditions | Facturation poursuivie ou en pause |
| Service de facturation | Hôte | Rôle de connexion membre de `drivy_billing_worker`, `BILLING_WORKER_DATABASE_URL` |
| Envoi des factures | Hôte | Rôle membre de `drivy_billing_mailer`, `BILLING_MAIL_DATABASE_URL`, `BILLING_OUTBOX_KEY` (64 caractères hexadécimaux), `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, identifiants SMTP, `BILLING_MAIL_FROM` |

Le homelab n'a pas de SMTP. Sans lui, les factures restent téléchargeables et l'envoi est refusé (`BILLING_MAIL_NOT_CONFIGURED`). Aucun script ne prépare encore les rôles de connexion de ces deux services, contrairement à `prepare-invitation-mailer.sql`.

## Mise en service progressive

Chaque étape attend l'accord du porteur et se contrôle avant la suivante.

1. Sauvegarder la base, relever le SHA déployé et la liste des migrations appliquées.
2. Rejouer les migrations sur une copie de la base. Contrôler : aucune facture, aucune fiche créée pour une école existante, `school.status` inchangé, politique de relance désactivée.
3. Déployer API et web, **sans** `billing:worker` ni `billing:mail`.
4. Inviter les opérateurs, renseigner l'émetteur, rattacher explicitement les écoles existantes.
5. Sur une école d'essai : conditions, début payant, brouillon, émission manuelle, PDF, règlement.
6. Lancer `billing:worker`. Politique toujours désactivée, il ne traite que les fiches dont la facturation planifiée est activée. Activer une seule fiche et contrôler un passage.
7. Activer les rappels, sans suspension automatique. Observer au moins un cycle.
8. Activer la suspension automatique en dernier, après relecture des écoles annoncées dans le tableau de bord.
9. Lancer `billing:mail` seulement quand un SMTP de test a validé l'envoi, la reprise et l'état incertain.

## Surveillance et arrêt

- Les journaux du service ne donnent que des compteurs. Un `en échec` non nul ou « passage temporairement indisponible » répété demande un contrôle.
- Le tableau de bord et les alertes commerciales montrent retards, envois en échec et suspensions à venir.
- Arrêter les nouveaux effets, du plus ciblé au plus large : exception `HOLD` sur une école, arrêt de sa facturation planifiée, désactivation de la suspension automatique, désactivation des rappels, arrêt de `billing:worker` et `billing:mail`.
- Reprise : relancer le service. L'unicité par facture, cycle et palier empêche un double rappel, et un verrou empêche deux passages simultanés.

## Sauvegarde et retour arrière

- Les migrations sont additives et sans script inverse. Un retour de code laisse les tables en place.
- Une restauration efface tout ce qui a été écrit depuis la sauvegarde, y compris factures et règlements. Elle ne se fait pas sans décision du porteur.
- Un retour arrière n'annule ni une facture émise, ni un courriel ou une notification envoyés, ni un QR transmis. Une facture émise se corrige par avoir.

## Recette

Statuts possibles : PASS, FAIL, BLOCKED, NOT_EXECUTED. Prérequis : deux écoles et deux opérateurs synthétiques, une horloge contrôlable, un SHA d'aperçu identifié.

| # | Parcours | Support | Statut |
| --- | --- | --- | --- |
| 1 | Second opérateur : invitation, acceptation, droits, révocation | API, web | NOT_EXECUTED |
| 2 | Code d'ouverture, compte, école, reprise après fermeture et réponse perdue | Runner Apple ou appareil | NOT_EXECUTED |
| 3 | Offre, modules, conditions, essai, début payant | API, web | NOT_EXECUTED |
| 4a | Facture initiale, mensualité, PDF, QR, téléchargement | API, web, lecteur QR | NOT_EXECUTED |
| 4b | Envoi de test | SMTP de test | BLOCKED : aucun SMTP |
| 5 | Paiement partiel, solde, correction, réconciliation école et tableau de bord | API, web | NOT_EXECUTED |
| 6 | Retard, relance, exception, suspension, règlement, réactivation, paiement concurrent | PostgreSQL, horloge | NOT_EXECUTED |
| 7 | Module désactivé puis réactivé, engagement en cours, ancien client | API, iOS | NOT_EXECUTED |
| 8 | Résiliation demandée puis confirmée, arrêt des périodes, documents conservés | API, web, iOS | NOT_EXECUTED |
| 9 | Autorisations et isolation, opérateur distinct des rôles scolaires | PostgreSQL | NOT_EXECUTED |
| 10 | Concurrence, double commande, réponse perdue, fin de mois, reprise des jobs | PostgreSQL | NOT_EXECUTED |
| 11 | Web sur mobile et ordinateur, clavier, lecteur d'écran | Navigateur | NOT_EXECUTED |
| 12 | PDF contrôlé à l'œil, QR décodé et comparé aux exemples SIX | PDF, lecteur QR | NOT_EXECUTED |
| 13 | Migration sur une copie de la base du homelab | PostgreSQL | NOT_EXECUTED |

## Points connus avant la recette

- Des tests anciens figent un nombre de tables à RLS forcée, par exemple `capture-observations.integration.test.ts:90` attend 67. Les tables de R01 les feront échouer sans régression réelle : le compteur est à mettre à jour.
- Les droits `MANAGE_OFFERS` et voisins sont déclarés sans être vérifiés par route : tout opérateur actif peut écrire.
- Le code Swift de R01 n'a jamais été compilé.
- Le rappel par courriel avec QR au solde n'est pas réalisé.
