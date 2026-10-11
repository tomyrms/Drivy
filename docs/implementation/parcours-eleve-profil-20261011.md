# Parcours de l’élève : Profil, prochaine leçon, Progression — quatrième passe (11 octobre 2026)

Suite de [l’élève et l’agenda](parcours-eleve-agenda-20261011.md). Audit du parcours de l’élève, réalisation, relecture QA par un agent dédié, puis deux retours du porteur sur son iPhone (compte `eleve`, 174 leçons, trois permis).

## Trois onglets

- **Leçons, Progression, Profil.** Le compte passe dans Profil, comme chez le moniteur ; l’avatar de la barre disparaît pour l’élève.
- **Profil**, pour chaque permis : leçons terminées, temps en leçon (horaires réels déclarés par le moniteur, jamais le GPS), compétences en autonomie sur le total, date de début, dernière leçon (elle s’ouvre). Le moniteur affecté n’est nommé que si l’une de ses leçons donne son nom : aucun annuaire de l’équipe n’est lu. Puis « Trajets » (ouvre le replay), l’accord GPS général, Mes informations, Face ID, Changer d’école, Se déconnecter.
- **Accord GPS** : le choix général se modifie désormais depuis Profil, même sans leçon planifiée. Cela lève la limite notée à la passe précédente.

## Leçons

- Carte « Prochaine leçon » en tête (« Dans 25 min », « Aujourd’hui », « Demain », « Dans 3 jours »), ouverte en zoom. Puis un seul groupe « À venir », puis le passé par mois.
- À l’heure du rendez-vous, tant que le moniteur n’a pas commencé, la leçon du jour reste la prochaine (« Maintenant ») jusqu’à la fin de son créneau : même règle que le souhait.
- L’élève ne termine pas de leçon : une leçon restée sans résultat se lit « En attente », en encre neutre, dans la liste comme dans la fiche.
- **Bug corrigé** : au-delà de 100 leçons par formation, la prochaine leçon restait derrière « Afficher d’autres leçons », et une relecture ramenait la liste à sa première page. L’app lit maintenant toutes les leçons de l’élève (200 pages au plus), et une relecture ne tronque plus ce qui est montré.

## Progression

Retours du porteur : trop d’informations, puis pas assez intuitif (pas de vue d’ensemble ; une compétence ouvrait une leçon sans prévenir).

- **Un permis à la fois** : celui du filtre, sinon la formation en cours. « Tous les permis » n’existe plus sur cette page (il reste sur Leçons).
- **Où j’en suis** : « 4 sur 9 en autonomie », puis les autres niveaux en une ligne. Un décompte en mots, jamais un score, un pourcentage ou une barre.
- **Prochaine étape** du dernier bilan, puis la leçon d’où elle vient en une ligne qui l’ouvre.
- **Une ligne = un libellé et sa jauge.** La toucher déplie son détail sur place : niveau en mots, date, situation notée par le moniteur, et « Voir la leçon ». Une seule ligne ouverte à la fois.
- « En autonomie » et « Pas encore vues » sont repliés avec leur nombre ; « En autonomie » s’ouvre seul quand il ne reste rien à travailler.
- La même page sert au dossier de l’élève chez le moniteur.

## Fluidité

- **Cause des ralentissements** vus par le porteur : chaque lecture d’une date de leçon construisait un formateur ISO 8601, et chaque ligne ou titre de mois un `DateFormatter`. Avec l’historique entier, trié et filtré à chaque rendu, cela faisait des milliers de formateurs par image. `SchoolDateCache` garde les instants déjà analysés, un formateur par fuseau et modèle, un calendrier par fuseau. Le porteur confirme sur son iPhone : « beaucoup plus fluide ».
- Les trois onglets partagent un modèle par formation et ne le relisent pas plus d’une fois par 30 s ; une sortie de feuille, tirer pour actualiser, une leçon modifiée ou une erreur affichée relisent tout de suite.
- Une lecture annulée avec l’onglet qui l’a lancée est attendue puis reprise par l’onglet qui apparaît, au lieu de laisser un squelette ou une liste vide.
- Transitions de l’accueil guidé, de la progression et des replis en fondu ou en glissement ; Réduire les animations respecté.

## Autres corrections

- Un élève dont le dossier est archivé retrouve son historique au lieu de « Dossier pas encore ouvert ».
- Le replay titre sur le moniteur, plus sur le nom de l’élève lui-même.
- Une ligne désactivée se voit comme telle ; la carte « Prochaine leçon » se désactive comme les lignes.
- La fiche d’une leçon passée garde un seul fond pendant son chargement.

## Relecture QA (agent dédié)

Aucun défaut bloquant : ni donnée privée montrée à l’élève, ni droit décidé par l’interface, ni succès avant écriture durable, ni position journalisée. Corrigés : la prochaine leçon qui disparaissait pendant son créneau, le chargement bloqué après un changement d’onglet, « À terminer » dans la fiche de l’élève, la fenêtre de 30 s qui masquait une erreur, le plafond de pages, la carte non désactivée, la lecture des affectations non annulée avec l’écran.

Laissés : la carte « Prochaine leçon » ne se recalcule qu’au rendu suivant quand l’heure passe ; les affectations sont relues à chaque apparition de Profil ; au très grand texte, les deux libellés de la carte peuvent se tronquer ; aucun écran `learner-profile` dans les captures de la CI ; côté équipe, un filtre de période demande ensuite l’historique complet à chaque relecture du dossier.

## Points ouverts (au porteur)

- **Identifiants d’appareil du moniteur envoyés à l’élève.** `GET /captures` et `GET /captures/:id` renvoient `deviceId` et `deviceAssessmentId` à tout lecteur autorisé, élève compris. Le contrat canonique les rend obligatoires et l’app installée les décode comme tels : les retirer côté serveur casserait les trajets de l’app actuelle. Ordre proposé : livrer une app qui les accepte absents, puis changer le contrat et l’API, puis déployer.
- **Objectifs d’une leçon visibles par l’élève avant qu’elle ait lieu** : à trancher (la décision du 28 septembre parle d’une leçon réalisée).
- **Fiche d’une leçon passée** : une douzaine de lectures réseau, à réduire.

## Vérification

- IPA d’essai compilée sans avertissement Swift à chaque lot.
- Campagne « Refonte · iOS » complète sur `4e1b594` : 452 tests métier, 12 parcours UI sur iPhone, 12 sur iPad. Tests métier relancés sur la dernière version (`941ea06`) : 453 passent ; les parcours UI n’y ont pas été rejoués.
- Le script de la campagne échouait avant le premier test iPhone quand aucun filtre n’était donné (tableau vide sous `set -u`, bash 3.2 du runner) ; corrigé dans `4e1b594`.
- Vu par le porteur sur iPhone : la fluidité des trois onglets. Non vu : la dernière version de la Progression, le zoom de la carte, VoiceOver, les très grandes tailles de texte.
- Aucune modification d’API, aucun déploiement.
