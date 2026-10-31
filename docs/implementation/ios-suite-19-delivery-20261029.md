# Livraison iOS — 19 issues supplémentaires, 25 au total

29 octobre 2026. Branche `codex/ios-suite-19-20261029`, construite sur `9293059c` du premier lot. Les trois branches de travail spécialisées partent de `origin/master` (`c94ec2bb`) ; leurs commits sont intégrés sans fusion dans master. [PR #338 en brouillon](https://github.com/tomyrms/Drivy/pull/338), empilée sur la branche du [premier lot #337](https://github.com/tomyrms/Drivy/pull/337).

## IPA finale

- **Drivy 0.7.0 (446)**, non signée, iOS/iPadOS 26 minimum ; décompresser puis signer et installer `Drivy.ipa` avec iLoader.
- [Télécharger l’artefact IPA](https://github.com/tomyrms/Drivy/actions/runs/40947705309/artifacts/12931460123) — expiration GitHub prévue le 12 novembre 2026.
- [Compilation Release réussie](https://github.com/tomyrms/Drivy/actions/runs/40947705309), source exacte `9e1769494f0d55e3eaf6cf9d1a6dca60d9d1cb55`, workflow manuel `ipa-essai.yml`, `messaging_qualification=true`.
- IPA : 18 032 056 octets ; SHA-256 `e21a5e6b08fbdf28b1c71fc4b9730fdca2eab1bee4b3db8af6b01f7abed8c50c`.
- Artefact téléchargé et contrôlé : les trois SHA-256 du manifeste (IPA, build-info, Package.resolved), CRC ZIP, version/build/identifiant/plateforme du plist, absence de signature et de profil de provisionnement, commit et run exacts. Package.resolved identique au dépôt ; signatureVerification PASSED dans les preuves du runner.
- Métadonnées : Release, archiveCreated=true, signed=false, schoolConnectionConfigured=true, messagingQualificationBuildRequested=true. Ceci ouvre la qualification Messages dans cette IPA, sans déploiement ni qualification générale du service.

## Périmètre et audit

Le porteur a demandé les quatre issues annoncées (#207, #211–213), puis quinze supplémentaires et une seule IPA à la fin. Les 19 issues ont été relues via GitHub : toutes ouvertes, aucun commentaire, aucune assignation au moment de la relecture. Les écarts ont été vérifiés dans les vues et modèles réellement accessibles, les historiques et les PR ; les réalisations déjà présentes ne sont pas comptées comme travail nouveau.

L’inventaire initial des 155 issues ouvertes et les exclusions restent dans `ios-independent-triage-20261029.md`. L’EPIC #311, ses sous-issues et les travaux web associés sont exclus. Sa coordination a été relue : les propriétaires travaillent dans les vues web et excluent Swift à cette étape. Aucun fichier web, API, contrat, migration, dépendance ou workflow n’est modifié par ce lot. Aucun déploiement homelab.

## Bilan des 25 issues implémentées

« Implémenté » signifie présent dans la branche d’essai. Mise à jour du 29 octobre, après livraison : le porteur a explicitement demandé de fermer les issues réalisées ; les 25 ci-dessous ont été fermées. Cette autorisation de clôture ne vaut ni retour d'essai ni validation des tests ni autorisation de fusion. Les PR #337 et #338 restent en brouillon et master est inchangé.

| Lot | Issues | Résultat |
| --- | --- | --- |
| Connexion, premier lot | #195, #197, #198, #199 | Erreurs de connexion exactes, validation après interaction, retour après récupération indisponible, collage sans troncature/perte du code |
| Messages, premier lot | #237, #241 | Envoi incertain distinct d’un échec et nouvelle tentative encadrée ; sélection stable des messages épinglés |
| Aujourd’hui | #207 | Cours attribués au moniteur dans la chronologie et la priorité du jour, occurrence exacte et état de lecture partielle |
| Planning | #211, #212, #213 | Tarifs durée/prix, choix incompatible expliqué, comparaison des versions avant résolution du conflit |
| Notifications | #202, #203, #204 | Périmètres cours/Messages, état visuel des intentions non confirmées, compte/école/appareil distingués |
| Progression | #206, #215, #216, #217, #218 | Attentes adaptées, recherche locale, plusieurs détails ouverts, dates d’évaluation et définitions du référentiel |
| Invitations | #228, #229, #230 | Recherche et filtres bornés, références non secrètes, échéances lisibles dans la liste |
| Contexte | #201, #219, #232 | États scolaires expliqués, identité commune aux écoles autorisées, conséquences de fin de leçon avant confirmation |
| Messages | #240 | Filtre Non lus combiné à la recherche, inconnus distincts de zéro et pagination explicite |

Total : **6 précédentes + 19 nouvelles = 25**. Les 19 nouvelles sont #201, #202, #203, #204, #206, #207, #211, #212, #213, #215, #216, #217, #218, #219, #228, #229, #230, #232 et #240.

## Relecture et vérifications

- Branches séparées, fichiers répartis entre trois agents et le coordinateur ; commits `[skip ci]` pour éviter les suites automatiques pendant le développement.
- Relecture croisée : préférences et conflits, droits et scopes, projection de progression, états de lecture Messages et lien vers ses paramètres. Le lien réutilise la même machine crypto que l’onglet Messages ; une deuxième instance aurait laissé diverger l’activation de la sauvegarde. Correction relue avant livraison.
- Départ de leçon immédiate conservé sous un cours futur ; pas de lancement GPS depuis un cours. Fin de leçon adaptée quand le trajet est déjà arrêté.
- `git diff --check` ; vérification des fichiers par rapport à master : aucun fichier iOS dans le delta de la branche #311. Le seul chemin commun est le journal `STATUS.md`, modifié dans nos branches séparées ; ses deux historiques devront être conservés lors des fusions ultérieures.
- Tests unitaires et UI ciblés préparés, **non exécutés**. Les cibles de tests ne sont pas qualifiées par une compilation Release de l’application. Aucune grande suite lancée.
- Compilation Release et IPA finale : **PASS**, voir les preuves ci-dessus. GitHub ne liste que ce workflow manuel pour la branche ; aucune suite n’a été lancée. Les commits de livraison postérieurs au SHA compilé ne modifient que la documentation.

## Essai demandé avant les tests

Installer l’IPA non signée avec iLoader. Vérifier en priorité le cours du jour, la résolution d’un conflit de préférences, les notifications hors ligne, la recherche et les détails de progression, les invitations homonymes/expirées et le filtre Non lus après lecture d’une conversation. Les notes de chaque lot décrivent les cas précis, notamment erreurs, contexte, pagination, annulation et perte de réseau.

La sauvegarde des clés doit être essayée depuis Notifications après avoir ouvert Messages, puis depuis Messages, pour confirmer le même état. Aucun secret ne doit être joint au retour ou aux artefacts.

Les mesures physiques GPS/batterie/VoiceOver et l’essai iPhone/iPad restent **NOT_EXECUTED**. Après retour du porteur : lancer les tests pertinents, corriger, puis fusionner dans master et fermer uniquement les issues effectivement terminées. La poursuite demandée aujourd’hui ne constitue pas une validation de l’IPA précédente.
