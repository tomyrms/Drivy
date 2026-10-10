# Déblocage des demandes en attente et recherche d’élève — 10 octobre 2026

Branche `claude/deblocage-demandes-20261010`, partie de `codex/stabilite-parcours-20261009`.

## Incident signalé

Commencer une leçon affichait « Demande à vérifier » ; « Vérifier auprès de l’école » répondait « Ce contenu n’est pas disponible avec tes droits actuels. » ; « Leçon sans rendez-vous » restait bloquée sur « Une demande attend sa confirmation. ».

## Cause

1. L’app installée (départ explicite, `POST /lessons/{id}/start`) parlait à l’API `ef0ea21` du homelab (migrations 001–022), qui ne connaît pas cette route : réponse 404. Constaté en lecture sur le conteneur avant toute correction.
2. Côté iOS, un 404 à l’envoi n’était pas un refus définitif : la demande restait dans la file chiffrée comme « incertaine ».
3. La vérification (`GET operations/{id}`) répondait elle aussi 404, présenté comme un problème de droits, et vidait la fiche. Aucune action ne retirait la demande.
4. La file ne garde qu’une demande par école et par personne : toute autre écriture, dont « Leçon sans rendez-vous », était donc bloquée sans explication. Les deux symptômes ont la même cause.

Les droits d’administration n’étaient pas en cause.

## Corrections

- **API déployée** : release `040c8ed8ca43280208cb37d976a06eab8b1c991b`, migration 023, après sauvegarde vérifiée `/root/drivy_refonte-before-040c8ed…-20261009T234740Z-ee739c29a959.dump` (CT113). 23 empreintes de migration conformes, services actifs, `/health/ready` 200, la route de départ répond (400 sans corps valide, plus 404).
- **iOS, file des demandes** : un 404 au premier envoi retire la demande et dit que rien n’a été enregistré, la fiche reste lisible. Un reçu 404 à la vérification devient « l’école n’a pas enregistré cette demande » : renvoi comme une demande neuve, ou « Abandonner la demande » avec confirmation, puis relecture. Fiche de leçon, démarrage immédiat, planification, préférences, profil, accueil et invitations. L’abandon n’est offert qu’après cette réponse de l’école. Un compte ou des accès changés gardent la demande, comme avant.
- **iOS, explication** : le panneau nomme la demande et son heure. Toute demande en file se vérifie depuis « Démarrer une leçon » et les préférences de planification, même partie d’un autre écran.
- **iOS, choix de l’élève** : liste avec recherche (accents, casse et ordre des mots ignorés) dans « Démarrer une leçon » et « Planifier une leçon », élèves triés par nom.
- **iOS, audit** : « Déplacer » et « Annuler » suivent les droits de l’école (administration ou moniteur de la leçon) ; « Permis vu » n’exige plus le grant retiré par la migration 017 ; annuler depuis la fiche arrête d’abord le trajet GPS en cours ; plus de « Réessayer » ni d’« Actualiser » sans effet après un accès retiré ; leçon introuvable distinguée d’une panne ; message exact pour une leçon déjà commencée ; moniteur présélectionné quand un seul est affecté.
- **Web** : même sortie pour une demande introuvable (renvoi, abandon confirmé, relecture), refus 4xx définitif au premier envoi (sauf 408, 429 et conflit d’idempotence), « Arrêter le suivi » quand le reçu est illisible ou refusé, « Réessayer » sur les lectures du dossier, recherche d’élève dans l’agenda, recherche et filtre d’état des invitations.

## Exécuté

- `5c719d2` : **419/419 tests Swift** (`unit_only`, [run 38006931024](https://github.com/tomyrms/Drivy/actions/runs/38006931024)), IPA Release compilée ([run 38006921179](https://github.com/tomyrms/Drivy/actions/runs/38006921179)), contrats, droits, PostgreSQL et web ([run 38006921148](https://github.com/tomyrms/Drivy/actions/runs/38006921148)).
- Web en local : typage et **138/138 tests**.
- Six tests Swift nouveaux (`SchoolPendingRequestResolutionTests`) : départ que l’école ne route pas, demande inconnue abandonnée depuis la fiche et depuis le démarrage immédiat, abandon refusé avant la réponse de l’école, texte du panneau, recherche d’élève.

## Non vérifié

- Aucun écran iOS de cette passe n’a été vu tourner : ni parcours UI ni capture. La liste de recherche, la feuille qui s’agrandit et le dialogue d’abandon sont compilés et testés par leur logique seulement.
- Aucune leçon réelle n’a été démarrée sur l’école hébergée après le déploiement : à faire par le porteur avec la nouvelle IPA. Avec l’ancienne IPA, la demande restée en file doit d’abord être résolue (vérifier, puis renvoyer ou abandonner n’existent que dans la nouvelle).
- Web : pas de capture, pas d’essai avec l’API et l’identité réelles.

## Laissé pour plus tard

- Feuille d’observation : une demande venue d’un autre écran y reste seulement signalée.
- Planifier lit encore tous les élèves avant d’afficher le formulaire ; recherche serveur sensible aux accents ; onglet Élèves par ordre de création et pagination manuelle.
- Historique des leçons relu en entier à chaque fermeture de fiche ; « À terminer » enfoui.
- Moniteur dont l’affectation a pris fin encore traité en auteur de ses leçons.
- Nom de l’élève absent du trajet en cours au-delà de la première page d’élèves ; lieu du rendez-vous non prérempli à la planification ; compétence choisie dans un menu.
- Web : le panneau ne nomme pas la personne visée (règle « identifiants seulement »), retrait d’une disponibilité sans confirmation.
