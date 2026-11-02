# Gestes de cours conservés sur l'appareil (#126, #127, #128, #129, #130)

Lot du 2 novembre 2026, branche `claude/dix-issues-gestes-cours`.

## Le problème

Sur iPhone, les gestes de cours étaient déjà rendus « sans attendre » (inscription, appel, règlement, validation, brouillon de cours), mais leur suivi vivait en mémoire. Si l'app s'arrêtait entre l'envoi et la réponse de l'école, la demande en cours disparaissait : la personne ne savait plus si son geste avait été reçu, et un nouvel essai partait avec une nouvelle opération, donc avec un risque de doublon (une seconde inscription, un second règlement, un second brouillon de cours).

## Ce qui est conservé

Un coffre chiffré, distinct de celui des commandes de l'école (`SchoolCourseIntentStore.swift`), garde ces gestes :

| Geste | Issue | Écran |
| --- | --- | --- |
| Présence, règlement, annulation d'un règlement, validation, retrait de la validation | #128, #129, #130 | feuille des participants d'un cours |
| Inscription, liste d'attente, acceptation ou refus d'une place, annulation | #126 | fiche d'un cours de l'élève |
| Création d'un type de cours, enregistrement d'un brouillon, publication | #127 | éditeur de cours |

Chaque geste est écrit **avant** son envoi et n'en sort qu'à la réponse de l'école (réponse ou refus définitif). L'identifiant du geste est l'`operationId` envoyé à l'école.

## Règles

- **Rien n'est renvoyé de soi-même.** Après un arrêt de l'app, le geste revient « non confirmé » (« Geste conservé sur cet appareil, pas encore confirmé par l'école. ») avec « Réessayer » et « Abandonner ».
- **Réessayer rejoue la même opération** (même `operationId`, mêmes octets, même version attendue figée au premier envoi) : l'école rend la réponse déjà enregistrée au lieu d'écrire une seconde fois.
- **Abandonner** retire le geste du coffre, puis la fiche est relue : l'école l'a peut-être reçu.
- **Un geste que l'appareil ne peut pas conserver n'est pas envoyé** (« Cet appareil ne peut pas conserver ce geste : il n'a pas été envoyé. »). Aucun faux « conservé ».
- **Isolation** : un geste d'un autre compte, d'une autre école ou d'un autre cours n'est jamais restauré. Une affectation de plus avance l'époque d'accès sans retirer de droit : le geste suit la portée actuelle plutôt que de rester bloqué.
- **Inscription disparue** : un geste conservé pour une inscription qui n'est plus sur la feuille est écarté.
- **Aucune dépendance entre gestes** : les gestes de cours ne bloquent aucune autre écriture, ni entre eux, ni les commandes de l'école. L'ordre par élève de la feuille est conservé (le premier geste de la ligne attend la personne, les suivants attendent derrière lui).
- **Éditeur** : l'opération et la saisie qui l'accompagne sont conservées ; une opération reprise garde sa saisie telle quelle (la changer changerait son identité, donc l'opération). Les valeurs par défaut du catalogue ne la modifient pas.

## Limites (dites, non cachées)

- **La saisie jamais envoyée n'est pas conservée** : un brouillon de cours modifié mais jamais enregistré se perd à la fermeture de l'app, comme avant. Seule l'opération déjà tentée l'est (#127).
- Rien n'est affiché comme confirmé avant la réponse de l'école, y compris après reprise.
- Le web n'est pas concerné (un envoi à la fois par feuille, sans reprise après rechargement).
- Aucune notification (#43, #44).

## Fichiers

`SchoolAgendaAPI/SchoolCourseIntentStore.swift` (coffre chiffré et en mémoire, enregistrements), `SchoolAgendaUI/SchoolCourseAttendanceWorkspace.swift`, `SchoolCourseEnrollmentWorkspace.swift`, `SchoolCourseEditorWorkspace.swift`, `SchoolCourseEditorView.swift` (bouton « Abandonner la demande »), `SchoolConfigurationAPI/SchoolCommandOutbox.swift` (genres `courseSheetIntent`, `courseLearnerIntent`, `courseEditorIntent`), `SchoolCommandScheduling.swift`, `SchoolPendingCommandText.swift` ; tests : `DrivyTests/SchoolCourseIntentPersistenceTests.swift`.

## Qualification

Voir `STATUS.md` pour ce qui a été exécuté. Non exécuté : iPhone ou iPad physique, arrêt réel de l'app pendant un appel, VoiceOver, texte agrandi, réseau dégradé réel.
