# Benchmark observé et enseignements de conception

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Question de départ

Comment relier le travail du moniteur, l’organisation de l’école et l’apprentissage de l’élève sans demander à chacun de parcourir tous les modules ? Les références ont été recherchées avant de fixer navigation et architecture. La comparaison distingue un outil de gestion, une place de marché de réservation et un carnet pédagogique. Ces catégories ont des contraintes différentes.

L’étude comprend cinq références principales : deux offres suisses, deux références étrangères du secteur et un outil de gestion pédagogique adjacent. DRIVUP et PermisClick servent de repérage complémentaire. Les sources et limites figurent dans le [registre](../06-gouvernance/sources.md). Pas de compte de test, entretien, mesure de performance ou parcours de paiement réel. Les scores commerciaux ne sont pas utilisés.

## B01 · Quick Drive, gestion suisse

**OBS.** La capture de facturation montre une liste et un détail simultanés, avec une chronologie et des actions de règlement. La capture calendrier montre une large grille hebdomadaire sombre et plusieurs modes de vue. Les dates affichées appartiennent à des exemples de 2024. Ce ne sont pas des preuves de la version actuellement livrée. Sources : [S02](../06-gouvernance/sources.md#s02), [S03](../06-gouvernance/sources.md#s03).

**EDI.** L’éditeur présente suivi des élèves, documents, paiements, agenda et fonctions GPS. Le catalogue de tutoriels distingue plusieurs tâches de facturation et d’inscription. Sources : [S01](../06-gouvernance/sources.md#s01), [S04](../06-gouvernance/sources.md#s04).

**Interprétation pour Drivy.** Le contexte élève doit rester visible lors d’une action financière ; un calendrier peut servir à examiner la semaine sans devenir l’écran d’entrée unique. La séparation liste/détail paraît adaptée à une tablette ou un navigateur large. Elle ne doit pas être comprimée sur téléphone. La présence d’un outil comptable suisse ne démontre pas que Drivy doive reconstruire la comptabilité dès son lancement.

**À ne pas reprendre.** La multiplication des modes de calendrier, un cockpit de facturation en accueil élève et le thème sombre comme choix imposé. La densité doit être évaluée par tâche, pas par ressemblance au logiciel professionnel.

## B02 · Simy, école et organisation

**OBS.** La capture consultée montre une semaine, des zones grisées et des blocs de leçons ou de cours de durées très différentes. La démonstration publique indique que certains temps de trajet sont des exemples. Aucune vérification d’un calcul réel de trajet n’a été faite. Sources : [S05](../06-gouvernance/sources.md#s05), [S06](../06-gouvernance/sources.md#s06).

**EDI.** La page auto-écoles met en avant réservation, points de rendez-vous, cours et portail élève. Ce sont des capacités annoncées, pas un inventaire testé.

**Interprétation pour Drivy.** La disponibilité est une combinaison de contraintes, pas une case vide dans un agenda. Les temps de déplacement sont un besoin plausible, mais leur calcul automatique ajoute une dépendance cartographique et des incertitudes. Un tampon manuel explicite est une première solution plus contrôlable. Les cours collectifs et listes d’attente relèvent d’une autre unité métier que la leçon individuelle.

**À ne pas reprendre.** Le mélange du suivi de conduite, du marketing et de la construction de sites dans le premier produit. Le gris des indisponibilités ne doit pas être le seul indicateur, notamment pour les lecteurs d’écran.

## B03 · Total Drive, moniteurs et élèves au Royaume-Uni

**OBS.** La capture du dossier élève organise leçons, paiements et progression autour de la même personne. Une ligne de leçon distingue réservation et règlement. Le contenu est dense, avec onglets horizontaux, statistiques et sous-sélections. Source : [S08](../06-gouvernance/sources.md#s08).

**EDI.** Le site décrit des espaces pour moniteurs, élèves et parents et des outils de gestion d’activité. Source : [S07](../06-gouvernance/sources.md#s07).

**Interprétation pour Drivy.** Leçon et paiement sont des dimensions indépendantes. Le dossier élève est un point de rassemblement, mais la formation sélectionnée doit être visible pour éviter de confondre permis moto et voiture. L’existence d’un espace parent ailleurs ne justifie pas un rôle parent généralisé en Suisse sans analyse du besoin et des droits.

**À ne pas reprendre.** Les concepts fiscaux britanniques, les métriques d’activité en tête du parcours élève et l’empilement de rangées d’onglets sur petit écran. Une synthèse utile n’a pas besoin de présenter simultanément tous les totaux disponibles.

## B04 · Ornikar, agenda et modifications

**OBS/documentation.** L’aide présente des vues mois, semaine et jour, ainsi qu’une légende associant état et couleur. La légende a été consultée ; aucune navigation interactive du calendrier n’a été réalisée. Sources : [S09](../06-gouvernance/sources.md#s09), [S11](../06-gouvernance/sources.md#s11).

**Règle documentée par l’éditeur.** La procédure de déplacement précise que proposer une nouvelle heure annule la leçon initiale, indépendamment de l’acceptation ultérieure de l’élève. Source : [S10](../06-gouvernance/sources.md#s10).

**Interprétation pour Drivy.** Cette conséquence illustre pourquoi le déplacement est une transition métier, pas seulement un glisser-déposer. Pour Drivy, la recommandation inverse est de conserver le rendez-vous tant que le déplacement complet n’a pas réussi. La proposition d’une nouvelle heure à accepter serait un objet séparé en phase ultérieure.

**À ne pas reprendre.** Les modalités d’indemnisation et le fonctionnement d’une place de marché française. L’organisation du travail et le contrat entre élève, école et plateforme ne sont pas présumés identiques.

## B05 · Teachworks, domaine pédagogique adjacent

**EDI/documentation.** La page officielle décrit calendriers de personnes et de lieux, disponibilités, déplacement par glisser-déposer et contrôle détaillé des conflits. Une image de conflit était liée mais n’a pas pu être récupérée. Source : [S12](../06-gouvernance/sources.md#s12).

**Interprétation pour Drivy.** Une erreur « créneau indisponible » doit expliquer la contrainte résoluble sans exposer le nom d’un autre élève. Le glisser-déposer peut être un accélérateur secondaire sur grand écran, mais une action clavier/tactile équivalente reste nécessaire. Les salles et classes collectives ne doivent pas être introduites sous prétexte qu’elles existent dans un logiciel de cours.

**À ne pas reprendre.** La paie des enseignants et la gestion de familles. Les cours collectifs simples sont désormais inclus selon les exigences V2, avec comptes internes plutôt que facturation fiscale. L’élargissement du modèle doit suivre des besoins validés.

## Références de repérage non utilisées comme preuves d’interface

DRIVUP et PermisClick confirment, dans leurs présentations commerciales, la diversité des fonctions proposées aux écoles. Les espaces authentifiés n’étaient pas accessibles. Ils ne fondent donc aucune affirmation sur la rapidité de leurs interactions ou leur lisibilité. Leurs règles françaises ne sont pas transposées. Sources : [S13](../06-gouvernance/sources.md#s13), [S14](../06-gouvernance/sources.md#s14).

## Synthèse comparative originale

| Besoin | Enseignement | Décision de conception proposée | Vérification à mener |
|---|---|---|---|
| Préparer une journée | Les calendriers sont utiles mais souvent denses. | Liste chronologique mobile par défaut ; semaine sur grand écran. | Retrouver une leçon sans assistance sur téléphone. |
| Déplacer sans perdre le rendez-vous | Les conséquences varient fortement selon produit. | Mutation atomique, ancien créneau conservé si échec. | Deux moniteurs réservent simultanément ; une seule confirmation. |
| Comprendre une progression | Le dossier rassemble plusieurs dimensions. | Formation explicite, observations datées, prochaine action. | L’élève explique ce qu’il travaillera, sans interpréter une note globale. |
| Enregistrer un règlement | Statut de cours et paiement ne se confondent pas. | Journal simple et solde calculé, pas de booléen. | Paiement partiel puis correction par contre-écriture. |
| Gérer les contraintes réelles | Un créneau libre visuellement n’est pas forcément possible. | Disponibilités, pauses et tampon examinés côté serveur. | Collision avec congé ou changement de durée. |
| Faciliter la conduite | L’existence de cartes ailleurs ne prouve pas leur nécessité. | Préparer à l’arrêt, conduire sans interaction obligatoire, compléter après. | Entretien et test en situation stationnaire, jamais sollicitation en circulation. |

## Recherche utilisateur à réaliser avant le pilote

**HYP.** Recruter quelques moniteurs aux organisations différentes, un responsable d’école et des élèves ayant des niveaux et appareils variés. Un premier cycle de 4 à 6 moniteurs et 5 à 8 élèves serait un objectif pratique, pas un échantillon représentatif ni une ressource acquise. Inclure une personne utilisant de grandes tailles de texte et un cas multi-permis.

Demander de reconstituer la dernière leçon et son organisation réelle. Observer une préparation, un changement de créneau et la rédaction d’un bilan à l’arrêt. Ne pas demander seulement « trouvez-vous cela joli ? ». Relever la source du rendez-vous, les outils parallèles, les données recopiées et la personne responsable de chaque correction. Comparer les trois directions sur les mêmes tâches et contenus.

Critère de validation du concept : chaque rôle sait retrouver la prochaine action ; aucun ne confond état d’envoi, validation du permis et réussite pédagogique. Le GPS est désormais prioritaire par demande explicite du porteur ; éprouver son utilité pédagogique sans imposer un taux minimal de capture. Les résultats de cette recherche devront être ajoutés, pas simulés dans le présent dossier.
