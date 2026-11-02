# Corrections et retraits d'observations après la leçon (#112)

Lot du 2 novembre 2026, branche `claude/signalements-112`.

## Le problème

Après la leçon, corriger ou retirer un signalement passait par la file des commandes de l'école, qui n'admet qu'une demande à la fois : l'écran attendait la réponse de l'école, aucune autre observation ne pouvait être corrigée pendant ce temps, et une demande restée sans réponse bloquait toute la liste jusqu'à sa vérification.

## Ce qui change

- Une **correction** ou un **retrait** est écrit dans un coffre chiffré (`SchoolObservationCorrections.swift`, distinct de la file des commandes) avant son envoi, puis part sans retenir l'écran. La fiche se ferme aussitôt ; la ligne de l'observation dit « Modification en cours d'envoi » ou « Retrait en cours d'envoi ».
- **Indépendance** : deux observations de la même leçon se corrigent sans s'attendre. Deux demandes sur la **même** observation restent ordonnées (la seconde est refusée tant que la première n'a pas reçu sa réponse), parce que la version attendue de l'observation change avec la réponse.
- **Rien n'est présenté comme confirmé avant la réponse de l'école** : le texte corrigé s'affiche avec la mention « en cours d'envoi », et un retrait laisse la ligne en place avec sa mention. La liste se relit une seule fois, quand plus aucune demande ne part.
- **Réponse perdue** : la demande passe « non confirmée » (« Retrait non confirmé », « Modification non confirmée ») avec « Réessayer » (même opération : l'école ne l'enregistre pas deux fois) et « Abandonner ». Elle reste conservée.
- **Arrêt de l'app** : une demande sans réponse revient « non confirmée » à l'ouverture de la leçon ; elle n'est jamais renvoyée d'elle-même.
- **Refus de l'école** (conflit de version, bilan déjà publié, refus motivé) : la demande s'arrête, la ligne de cette observation dit pourquoi, les autres demandes continuent, l'observation se relit.
- **Un geste que l'appareil ne peut pas conserver n'est pas envoyé** (« Cet appareil ne peut pas conserver cette demande : elle n'a pas été envoyée. »).
- **Isolation** : un autre compte, une autre leçon ou une autre école ne voit rien ; une affectation de plus (époque d'accès) fait suivre la portée actuelle aux demandes conservées ; des accès révoqués arrêtent l'affichage et n'acceptent plus rien.

## Ce qui n'a pas changé

- La **création** d'une observation de relecture (« Ajouter une observation ») reste une demande à la fois par la file des commandes, comme la fin de leçon.
- Les signalements **en direct** pendant la leçon gardent leur file (#112, lot du 28 octobre).
- « Signaler » depuis l'écran sans GPS ne se rouvre pas tant qu'une file attend sans réseau : prudence conservée.
- **Palette, thèmes et classement** (organisation, restauration des défauts, réponses anciennes qui écrasent) : non examinés dans ce lot.

## Fichiers

`SchoolObservationUI/SchoolObservationCorrections.swift` (coffre chiffré et en mémoire, demande et projection), `SchoolObservationWorkspace.swift` (envoi indépendant par observation, reprise), `SchoolObservationView.swift` (état sur chaque ligne, Réessayer, Abandonner), `SchoolConfigurationAPI/SchoolCommandOutbox.swift` et `SchoolCommandScheduling.swift` (deux corrections d'observations différentes ne se bloquent plus) ; tests : `DrivyTests/SchoolObservationCorrectionTests.swift` (12 tests).

## Qualification

Voir `STATUS.md`. Non exécuté : iPhone ou iPad physique, arrêt réel de l'app pendant un envoi, latence réelle de 15 s, VoiceOver, texte agrandi, captures des lignes « en cours » et « non confirmé ».
