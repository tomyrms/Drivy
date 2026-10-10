# Choix GPS natif pour une leçon

Implémentation du 24 septembre 2026, limitée à AP152/AP153 et à la lecture de la notice effectivement adoptée. Les deux nouveaux fichiers sont dans `apps/ios/Drivy/SchoolCaptureUI`. Aucun raccord à Root, Home, Report ou au collecteur n’est effectué par ce lot.

## Entrée injectable

`SchoolRecordingChoiceEntryView(client:reader:agenda:schoolWorkspace:lessonID:onRefusalConfirmed:store:)` ouvre sa propre pile de navigation et construit un workspace lié au compte, à l’appartenance, à l’epoch et à la leçon. Les clients injectés doivent désigner la même origine API configurée et la même session d’identité. `store` est facultatif pour injecter un journal existant ; sinon le magasin SQLCipher spécialisé est ouvert.

`SchoolRecordingChoiceView(model:)` permet également l’injection directe d’un `SchoolRecordingChoiceWorkspace(scope:lessonID:client:reader:agenda:onRefusalConfirmed:store:)`. Dans ce cas, l’appelant doit invalider le modèle lors d’un changement de compte, d’école ou de droits. L’entrée ci-dessus le fait à chaque changement de portée.

Le callback synchrone obligatoire `onRefusalConfirmed(learnerID, lessonID?)` est appelé **avant le premier await** d’une confirmation de refus ou de son renvoi. Le futur raccord live doit arrêter l’admission et le collecteur scolaire concerné immédiatement, indépendamment du réseau. Une portée de leçon `nil` désigne un choix général repris du journal. Sans collecteur scolaire, une action vide peut être fournie explicitement. Cet écran n’instancie aucun `CLLocationManager`, ne démarre aucun bail et n’importe aucune séance G0 ni aucun exemple.

## Parcours et droits

- Lecture de `/me`, de la leçon réelle, du dossier, de la notice et du choix effectif, puis revalidation de `/me` avant affichage. L’élève propre utilise `SELF` ; le moniteur utilise `RECORDED_VERBAL`, dont les droits de dossier sont vérifiés par le serveur. ADMIN seul ne peut pas utiliser cet écran pour écrire un choix.
- Notice et conservation sont affichées en texte intégral, avec le contact de l’école. Les dates de leçon utilisent son fuseau. Les deux choix, avec ou sans GPS, ont la même présentation ; aucun n’est présélectionné. `UNKNOWN` ou l’absence de choix restent des lectures, jamais un accord implicite.
- Une feuille de relecture conserve notice, choix précédent, leçon et source. La confirmation explicite reste décochée. Avant la première écriture, un changement de notice, de choix ou de source impose une nouvelle relecture.
- Un refus `SELF` ne peut pas être levé par le moniteur. La permission système et l’autorisation de capturer restent séparées de ce choix.

## Persistance et reprise

Chaque intention canonique contient un UUID d’opération, la leçon, le statut, la notice et la source. `stage` committe les octets chiffrés, puis `markAttempted` relit exactement ces octets et grave la tentative avant l’envoi. `acknowledge` est requis avant tout message de confirmation. Le choix courant est ensuite relu avec AP152 ; la confirmation d’une ancienne opération ne prétend pas qu’elle est encore le choix effectif.

Le journal verrouille atomiquement les nouveaux choix pour le même élève tant qu’une demande reste non acquittée. Les autres consultations restent possibles. Une reprise renvoie le même UUID et le même corps ; elle ne reconstruit pas la demande avec la notice courante. « Vérifier auprès de l’école » commence par AP72 : seul un reçu correspondant autorise le rejeu idempotent destiné à récupérer le résultat original et son accusé durable. Une absence de preuve ne déclenche aucun envoi.

Une ancienne portée reste visible mais n’est jamais réaffectée ni renvoyée sous de nouveaux droits. Fermer l’écran ne supprime pas le journal. Les refus métier, erreurs réseau et réponses invérifiables ne produisent aucun faux succès ni retrait automatique de demande. **Limite du journal actuel :** une demande refusée qui ne possède pas de preuve de commit reste conservée, même lorsqu’une nouvelle saisie serait souhaitée ; l’écran ne présente pas une résolution qu’il ne peut pas prouver. Le rapprochement administratif de ces demandes n’est pas livré ici.

## Validation et limites

Lecture statique des routes serveur `captures.ts`, des DTO/transport spécialisés, des règles F15/R41–R45/R101 et du journal SQLCipher. Contrôle de diff effectué ; aucun appel métier contre un compte réel, aucune nouvelle donnée serveur, aucun test ajouté ou exécuté. Compilation Apple et inspection native restent à réaliser après intégration. Ce lot ne qualifie ni permissions GPS ni collecte physique, arrière-plan, autonomie ou partage de traces.
