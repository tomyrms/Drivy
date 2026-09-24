# Statistiques d’activité : définitions, portée et contrôle

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; choix détaillés proposés, à valider. [Index](../README.md).

<a id="f23"></a>
## F23 · Comprendre l’activité sans inventer de performances

**Besoins :** B12 B15. **Parcours :** J26. **Écrans :** E33, E45, E46. **Règles :** R92–R96. **Tests :** T215–T228. **Données :** les agrégats existants Lesson, ReportRevision, CourseSession/Enrollment, Account/PaymentEntry, Learner et readiness ; MetricsSnapshot pour un export éventuel.

L’utilisateur demande des statistiques dans l’espace web. Le cœur inclut des indicateurs opérationnels définis ici, pas une plateforme décisionnelle générale. Les statistiques avancées, prévisions, comparaisons de moniteurs et taux de réussite non documentés restent dans U06.

Les indicateurs ne changent pas la promesse principale : GPS et replay au service du bilan. Ils aident à gérer l’école ; ils ne mesurent pas automatiquement la qualité de l’enseignement.

## Écran et contrôles

Période par défaut proposée : mois civil courant dans le fuseau de l’école. L’utilisateur peut choisir des dates, une granularité jour/semaine/mois et, selon ses droits, le périmètre école ou ses propres leçons. Les filtres par site ou moniteur s’appliquent seulement aux indicateurs qui possèdent cette dimension de manière fiable. Un pack payé à l’école n’est pas ventilé artificiellement entre moniteurs.

Chaque carte affiche titre exact, valeur et unité, période ou mention « À présent », mise à jour et lien « Comment est-ce calculé ? ». La liste ou le tableau de détail utilise le même périmètre autorisé. La vue graphique est accompagnée d’un tableau accessible. Une mesure inconnue est « Données incomplètes », pas zéro.

## Dictionnaire de référence, version 1

<a id="m01"></a>
### M01 · Leçons individuelles réalisées

**Unité :** nombre de leçons. Compter une fois chaque Lesson dont le résultat courant est réalisé et dont `actualStart` appartient à la période. Exclure annulations, absences et sessions collectives. Une leçon révisée garde le même identifiant ; la correction de résultat peut modifier le total courant. Une leçon sans GPS compte de façon identique.

<a id="m02"></a>
### M02 · Temps de leçons réalisées

**Unité :** secondes en calcul, heures/minutes à l’affichage. Pour le même ensemble que M01, sommer `actualEnd - actualStart` validés. Le temps complet est rattaché à la date de début réel ; aucune découpe cachée d’une séance traversant minuit. La durée contractuelle facturée et la durée GPS ne sont pas utilisées. Signaler le nombre d’enregistrements exclus pour horaire réel manquant ou invalide ; ne pas remplacer par la durée prévue.

<a id="m03"></a>
### M03 · Élèves accompagnés

Nombre distinct de learnerId dans le même ensemble que M01, dans l’école. Un élève présent sur deux permis compte une fois ; une personne dans deux écoles ne crée pas une statistique globale inter-écoles. Les élèves archivés **aujourd’hui** restent comptés pour leurs leçons réalisées dans la période ; l’archive ne réécrit pas l’activité passée.

<a id="m04"></a>
### M04 · Annulations et absences de leçons

Afficher séparément les nombres d’annulations et d’absences. Cohorte : leçons dont `plannedStart` est dans la période et dont l’état courant est un résultat terminal réalisé, annulé ou absence. Le dénominateur du taux d’annulation est la taille de cette cohorte terminale ; le numérateur est le nombre annulé. Le taux d’absence utilise le même dénominateur. Les leçons encore planifiées et non conclues sont exclues et leur nombre est indiqué.

Cette métrique utilise la date **prévue**, contrairement à M01/M02. Son libellé précise « sur les leçons clôturées prévues dans la période ». Ce n’est pas un taux de faute de l’élève : une annulation peut venir de l’école. L’auteur/motif ne sert pas à classer les personnes.

<a id="m05"></a>
### M05 · Places réservées des cours à venir

**Instantané à présent**, par série publiée non commencée, dont la première occurrence se situe dans la période future sélectionnée. Numérateur : inscriptions occupant une place, y compris celles qui nécessitent reconfirmation et conservent la place. Dénominateur : capacité courante validée de la série. Compter une inscription une fois pour la série, pas une fois par occurrence.

Exclure séries annulées/non publiées et inscriptions annulées. Aucun taux si capacité nulle/invalide ; le cas devient une anomalie. Un agrégat utilise somme des places occupées / somme des capacités, pas la moyenne simple de pourcentages. Les séries passées ne sont pas présentées comme une courbe historique de remplissage sans snapshots appropriés.

<a id="m06"></a>
### M06 · Encaissements enregistrés nets

**Unité :** centimes CHF, somme signée. Ce chiffre est issu du journal interne, sans rapprochement bancaire. Il n’est pas nommé chiffre d’affaires, bénéfice, revenu acquis ou déclaration comptable.

Pour les écritures connues au moment du calcul : RECEIPT vaut +amountCents, REFUND vaut -amountCents. REVERSAL inverse le signe de l’écriture d’origine référencée, selon la contrainte d’annulation F10 ; aucune chaîne de reversal libre. Pour filtrer la période, un encaissement/remboursement utilise `occurredOn`. La contre-écriture de correction utilise la date économique de l’écriture d’origine pour corriger cette période ; `recordedAt` indique quand la correction a été connue. Une correction ultérieure peut donc réviser un total ancien, ce que l’interface explique.

Sommer une seule fois par id d’écriture de compte, indépendamment des routes API utilisées. Le paiement d’un pack appartient à son compte Purchase ; les leçons couvertes par ces droits ne produisent pas un deuxième encaissement. Un remboursement réellement effectué n’est pas une simple correction de saisie et porte sa propre date.

Pas de ventilation d’un pack entre sites/catégories/moniteurs sans règle comptable spécifiée. Pour ces filtres, M06 est indisponible avec une explication, plutôt que calculé de façon arbitraire. Une période peut avoir un montant négatif si les remboursements dépassent les encaissements.

<a id="m07"></a>
### M07 · Reste dû enregistré

**Instantané à présent**, non filtré par la période d’activité. Somme des `balanceCents` positifs des comptes uniques autorisés, fondés sur les charges réellement inscrites et les règlements nets. Un prix proposé sans charge ne constitue pas une dette. Un achat et ses prestations couvertes ne sont pas comptés deux fois. La métrique conserve le nom « enregistré » ; aucune récupération automatique de relevés bancaires n’est supposée.

Une ventilation par moniteur/site n’est pas disponible au pilote. Le détail financier exige la permission correspondante. Sur une période passée, la carte reste explicitement marquée « À présent » ; l’app ne simule pas un historique des encours sans événements suffisants.

<a id="m08"></a>
### M08 · Dossiers à compléter pour un engagement à venir

Nombre de dossiers actifs distincts présentant au moins un prérequis manquant pour leur prochaine leçon ou inscription déjà confirmée. Le calcul utilise les règles de readiness de l’action et la politique en vigueur, pas le nombre total de champs vides. Un avatar absent, un refus GPS ou une notification refusée n’y contribue jamais.

Une absence de naissance ne bloque que les actions qui nécessitent effectivement ce renseignement. Le détail explique le document ou champ attendu sans afficher ses valeurs personnelles dans la carte de synthèse.

<a id="m09"></a>
### M09 · Bilans à publier

Nombre de leçons réalisées dont le bilan initial reste à publier, dans le périmètre autorisé. Une correction volontaire en brouillon après une publication valide apparaît dans une file séparée, pas comme absence de tout bilan. Le filtre de période porte sur actualStart ; la file « tous à traiter » annonce explicitement son périmètre différent.

Ce compteur n’expose pas le contenu des notes au personnel administratif. Il sert à ouvrir les tâches autorisées, pas à mesurer la vitesse de rédaction de chaque moniteur.

## Fenêtres temporelles et disponibilité

L’API reçoit `fromDate` incluse et `toDateExclusive`, dates civiles de l’école. Les dates-heures des leçons sont comparées après conversion correcte des bornes en instants, y compris changements d’heure. Une date de paiement `occurredOn` est une date civile, non minuit UTC. La fin affichée dans l’interface est le jour précédent la borne exclusive.

Les métriques sont calculées dans une lecture cohérente des données et portent `computedAt`, `dataAsOf`, `definitionsVersion` et les filtres effectifs. La V3 ne promet pas un moteur de voyage dans l’historique de toutes les versions : les résultats décrivent l’état connu à ce calcul. Les filtres incompatibles sont refusés ou la carte concernée est NOT_APPLICABLE ; pas de suppression silencieuse d’un filtre.

Une granularité n’autorise pas une somme de comptages distincts : M03 sur un mois est recalculé sur le mois, pas additionné sur les jours. M05 et M07 sont des instantanés ; leur absence d’historique n’est pas comblée par des points inventés.

## Droits et données exclues

INSTRUCTOR peut lire ses M01/M02/M03/M04/M09. La vue école non financière exige ADMIN ou VIEW_SCHOOL_METRICS. M06/M07 exigent ADMIN ou VIEW_FINANCIAL_METRICS : ce dernier grant seul suffit pour ces deux métriques SCHOOL, sans donner accès aux autres. M08 exige l’accès administratif aux dossiers concernés. Les contrôles du détail restent indépendants des compteurs ; l’autorisation d’un agrégat n’accorde pas celle de chaque document.

Les permissions sont évaluées au serveur avant les requêtes. Aucune requête ne charge une école entière pour filtrer ensuite dans le navigateur. Le web ne reçoit pas de coordonnées brutes, photos, dates de naissance ni noms d’élèves dans les séries agrégées.

Sont exclus : classement des élèves, score global de conduite, classement de moniteurs, géolocalisation de flotte, taux de consentement GPS comme objectif et taux de réussite à l’examen sans collecte fiable des tentatives et dénominateur. Les diagnostics techniques GPS appartiennent à l’exploitation, avec données minimisées, pas aux indicateurs commerciaux du responsable.

## Exemples fictifs de contrôle

Pour 3 leçons réalisées de 45, 50 et 90 minutes concernant deux élèves : M01 = 3, M02 = 185 minutes, M03 = 2, même si une des leçons n’a aucune capture. Deux séries de capacité 8 et 12 avec 6 et 3 places occupées donnent 9/20 = 45 %, pas la moyenne de 75 % et 25 %.

Un pack payé 1 460 CHF, une leçon hors pack payée 110 CHF et un remboursement réel de 100 CHF dans la même période donnent 1 470 CHF nets enregistrés. Consommer deux leçons du pack ne change pas ce montant. Une contre-écriture annulant ensuite l’encaissement erroné de 110 CHF corrige la période d’origine à 1 360 CHF, sous réserve que ces écritures soient les seules du fixture.

Ces exemples sont des **jeux arithmétiques documentaires**, pas les résultats d’une école. Les recettes T215–T228 vérifient bornes, refus d’accès, archive, doublons et données incomplètes. Un contrôle de calcul du fixture ne remplace pas l’intégration réelle au journal.

## Technique, coût et erreurs

Au pilote : requêtes SQL typées/projections limitées dans le monolithe, pas d’entrepôt analytique ni de copie des traces. Période maximale proposée 366 jours et chaque série temporelle bornée à 400 points, cinq métriques en courbe au plus (M01/M02/M03/M04/M06), soit 2 000 points au total ; agrégation appropriée ou refus explicite au-delà. Les index et temps de réponse sont à mesurer, pas garantis ici.

Erreurs : METRIC_SCOPE_FORBIDDEN, METRIC_FILTER_UNSUPPORTED, PERIOD_TOO_LARGE, METRICS_INCOMPLETE, EXPORT_TOO_LARGE, ACCESS_REVOKED. Afficher une carte indisponible sans faire disparaître le reste des fonctions de l’école. Le GPS continue d’être un parcours autonome si les statistiques sont indisponibles.

L’export reprend les définitions, bornes, unités, fraîcheur et scope appliqués ; la fonction F22 protège sa génération et son téléchargement. Les données déjà exportées ne peuvent pas être rappelées ; la conservation côté destinataire reste à encadrer.

M09 reste un compteur filtré par période au pilote, pas une série temporelle retournée par MetricPoint. M05/M07/M08 sont des instantanés, sans courbe historique fabriquée. `definitionsVersion` est le nom exact du champ dans ManagementMetrics.


## Limite de périmètre clarifiée

U06 concerne les analyses de gestion avancées à cadrer, pas un classement automatique des élèves ou une aptitude à l’examen déduite des trajets. Les scores automatiques visés par X01 demeurent exclus. Les neuf indicateurs M01–M09 du cœur gardent leurs unités, droits et sources existants ; aucun nouvel indicateur n’est ajouté par cette revue.

## Prestations hors leçon et nouveaux snapshots

Les remises EXAM_SUPPORT/EXTERNAL_SERVICE du registre F17 ne sont pas des Lesson et n’entrent pas dans M01/M02/M03/M04/M09. Elles ne génèrent aucune recette supplémentaire dans M06 : les encaissements viennent toujours du journal F10. Un prix exceptionnel modifie la charge initiale selon le total accepté, pas une série artificielle de paiements. La libération d’un HOLD ne représente aucun remboursement ; M05 reste une mesure de places, non de crédits consommés.

<a id="effets-des-corrections-v37"></a>
## Effets des corrections sur les indicateurs
Corriger une présence peut modifier les vues de présence, mais ne crée pas une leçon individuelle, un paiement M06 ou une place supplémentaire M05. Une régularisation de droit AP201 n’ajoute aucun encaissement. Un état d’exigence repassé à vérifier entre uniquement dans les suivis dont la définition inclut réellement cet état ; ne pas changer silencieusement les définitions M01–M09 ni recalculer une compétence depuis le paiement.

## Export et contrôle du résultat

L’export METRICS utilise CSV UTF-8, avec version des colonnes/définitions et sources de période déjà prescrites. Les métadonnées READY identifient le contenu immuable remis ; elles ne prouvent pas que les données sources sont complètes. [Formats et droits d’export](../04-technique/fichiers-temps-communications.md#export-binaire). Ne pas afficher un téléchargement ZIP comme CSV ni une erreur de permission comme un rapport contenant zéro donnée.
