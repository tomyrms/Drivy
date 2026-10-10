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

## Seconde passe (même jour)

- **File des trajets GPS** : même cul-de-sac que la file des demandes, en plus dur (aucun retrait possible, blocage de tout l’appareil). Un diagnostic, un accord GPS ou un départ dont le reçu est inconnu de l’école peut maintenant être abandonné ; les faits de collecte (lots, arrêt, finalisation) ne s’abandonnent jamais. Un départ resté en file pour une autre leçon se vérifie depuis n’importe quelle préparation. L’accord GPS en attente reçoit « Vérifier auprès de l’école ».
- **Messages GPS** : formation ou élève inactif, trajet clôturé, appareil déjà lié à un autre compte disent leur cause ; ce dernier ne ferme plus la préparation.
- **Déconnexion pendant un trajet** : confirmation avant d’arrêter le trajet ; « Changer d’école » masqué tant qu’il tourne.
- **Agenda** : session expirée et panne réseau annoncées comme telles.
- **Élèves** : recherche API sans accents ni casse ; page suivante chargée en arrivant en bas de liste ; nom de l’élève affiché pendant un trajet au-delà de la première page.
- **Feuille d’observation** : la demande en attente est nommée, avec le renvoi vers la fiche de la leçon.
- **Web** : retirer une disponibilité ou une absence demande un second appui.
- **API redéployée** : release `771a13177c3e747e60b09071c7a2ad2da757a0ea`, sauvegarde vérifiée `…-20261010T004154Z-b9f89e8ea6a5.dump`.

Exécuté sur `771a131` : **420/420 tests Swift** ([run 38009266576](https://github.com/tomyrms/Drivy/actions/runs/38009266576)), IPA compilée ([run 38009257533](https://github.com/tomyrms/Drivy/actions/runs/38009257533)), vérifications serveur et web ([run 38009260066](https://github.com/tomyrms/Drivy/actions/runs/38009260066)).

### Constats GPS laissés au porteur

Ils touchent l’intégrité des trajets ou des règles de sécurité : aucun n’a été modifié sans décision.

- **Changement de droits pendant un trajet** : toute affectation ou tout changement de rôle incrémente l’époque d’accès, ce qui révoque le trajet en cours ; ses lots restent liés à l’ancienne portée et ne remontent plus, et tout nouveau départ est ensuite refusé (« dépend de tes anciens accès »). À décider : accepter les lots d’un trajet sous l’ancienne époque, et ne plus révoquer un trajet pour une nouvelle affectation.
- **Trajet clos par l’école avant l’arrêt local** : le premier lot postérieur à la coupure échoue à chaque essai, la finalisation n’est jamais tentée, le bandeau de synchronisation reste. À décider : écarter ce lot et finaliser en trajet partiel.
- **Deux comptes moniteur sur le même iPhone** : l’identifiant d’installation est lié à la première personne ; le second compte ne peut pas enregistrer. Le message est maintenant exact ; la correction (un identifiant par personne) reste à faire.
- **Départ refusé par l’école** : la demande reste en file jusqu’à « Vérifier », puis « Abandonner ». Deux gestes au lieu d’un retrait immédiat.
- **Rejoindre par code ou par lien** : une demande incertaine dont le code a expiré ne peut pas être quittée, et chaque vérification compte comme un essai raté. Le code actuel refuse volontairement de conclure sans rejeu du serveur ; à trancher.
- **Choix GPS de l’élève** : l’accueil lui dit qu’il peut refuser ou modifier son choix, aucun écran ne le permet. L’API l’accepte déjà.
- **Élève au dossier archivé** : accueil « Dossier pas encore ouvert » pour toujours, alors que son historique reste lisible côté école.
- **« Mon profil » sans politique de champs publiée** : message d’administration et « Réessayer » sans issue pour l’élève.

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
