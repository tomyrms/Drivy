# Livraison iOS — 19 issues supplémentaires, 25 au total

29 octobre 2026. Branche `codex/ios-suite-19-20261029`, construite sur `9293059c` du premier lot. Les trois branches de travail spécialisées partent de `origin/master` (`c94ec2bb`) ; leurs commits sont intégrés sans fusion dans master.

## Périmètre et audit

Le porteur a demandé les quatre issues annoncées (#207, #211–213), puis quinze supplémentaires et une seule IPA à la fin. Les 19 issues ont été relues via GitHub : toutes ouvertes, aucun commentaire, aucune assignation au moment de la relecture. Les écarts ont été vérifiés dans les vues et modèles réellement accessibles, les historiques et les PR ; les réalisations déjà présentes ne sont pas comptées comme travail nouveau.

L’inventaire initial des 155 issues ouvertes et les exclusions restent dans `ios-independent-triage-20261029.md`. L’EPIC #311, ses sous-issues et les travaux web associés sont exclus. Sa coordination a été relue : les propriétaires travaillent dans les vues web et excluent Swift à cette étape. Aucun fichier web, API, contrat, migration, dépendance ou workflow n’est modifié par ce lot. Aucun déploiement homelab.

## Bilan des 25 issues implémentées

« Implémenté » signifie présent dans la branche d’essai ; les issues restent ouvertes jusqu’à validation, tests pertinents puis fusion.

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
- `git diff --check` ; vérification des fichiers par rapport à master et de l’absence d’empiètement sur #311.
- Tests unitaires et UI ciblés préparés, **non exécutés**. Les cibles de tests ne sont pas qualifiées par une compilation Release de l’application. Aucune grande suite lancée.
- Compilation Release et IPA finale : **EN ATTENTE** ; les preuves et le lien seront ajoutés après le workflow dédié.

## Essai demandé avant les tests

Installer l’IPA non signée avec iLoader. Vérifier en priorité le cours du jour, la résolution d’un conflit de préférences, les notifications hors ligne, la recherche et les détails de progression, les invitations homonymes/expirées et le filtre Non lus après lecture d’une conversation. Les notes de chaque lot décrivent les cas précis, notamment erreurs, contexte, pagination, annulation et perte de réseau.

La sauvegarde des clés doit être essayée depuis Notifications après avoir ouvert Messages, puis depuis Messages, pour confirmer le même état. Aucun secret ne doit être joint au retour ou aux artefacts.

Les mesures physiques GPS/batterie/VoiceOver et l’essai iPhone/iPad restent **NOT_EXECUTED**. Après retour du porteur : lancer les tests pertinents, corriger, puis fusionner dans master et fermer uniquement les issues effectivement terminées. La poursuite demandée aujourd’hui ne constitue pas une validation de l’IPA précédente.
