# Pilotage de l'école : mode d'emploi

Pour la personne qui dirige l'auto-école. Les chiffres viennent du serveur de Drivy ; le portail ne recalcule rien. La méthode détaillée est dans [pilotage-373-indicateurs.md](pilotage-373-indicateurs.md).

## Où le trouver

Dans le portail de gestion, l'espace **Pilotage** est en tête du menu. Il contient deux pages :

- **Tableau de bord** : la journée. Leçons du jour et leur état, ce qui reste à traiter (leçons à finaliser, appels à renseigner, leçons à vérifier), les rendez-vous des sept prochains jours, le mois en cours avec son évolution jour par jour et, pour qui y a droit, les valeurs financières du mois. C'est la page d'accueil d'une école active.
- **Statistiques** : deux onglets, **Activité** et **Finances**, avec une période et des filtres.

## Qui peut voir quoi

- Le portail de gestion est réservé aux **administrateurs** de l'école. Un administrateur voit l'activité et les finances de toute l'école.
- L'**export en fichier** demande en plus le droit « Exporter les données de gestion », à accorder à l'administrateur concerné dans Équipe, Membres et accès. Sans lui, le bouton n'apparaît pas.
- L'API réserve aussi aux moniteurs leur propre activité, et leur ouvre celle de l'école ou les finances s'ils ont les droits « Consulter les indicateurs de l'école » ou « Consulter les indicateurs financiers ». Le portail n'est pas ouvert aux moniteurs : ces droits ne se voient donc pas encore dans cette interface.
- L'affichage suit les droits, mais c'est le serveur qui décide à chaque lecture : un droit retiré coupe l'accès à la lecture suivante.

## Choisir une période et filtrer

Période : ce mois, mois dernier, cette année, ou période libre (366 jours au plus). Filtres : moniteur, permis, prestation. La période et les filtres sont dans l'adresse de la page : on peut la copier ou la rouvrir, et elle garde le même résultat. Un filtre qui ne s'applique pas à une mesure la marque « Non applicable » au lieu de l'ignorer.

## Lire les chiffres

- Une **valeur absente** s'écrit « — » : elle n'est jamais remplacée par zéro. Un badge **Partiel**, **Indisponible** ou **Non applicable** dit pourquoi ; l'icône « i » de la tuile donne la formule de calcul et les parts exclues.
- **Comparaison** : seulement sur une base équitable. Une période écoulée est comparée à la précédente ; le mois en cours est comparé à la même plage du mois dernier, pour les seules mesures déjà réalisées. L'année en cours et une période libre qui va dans le futur n'ont pas de comparaison.
- **Heures** : programmées, réalisées (durées connues) et à venir sont trois chiffres séparés, jamais additionnés.
- **Élèves** : élèves distincts qui ont eu une leçon réalisée ou une présence à un cours. Ce n'est pas le nombre de comptes actifs.
- **Moniteurs** : la répartition est rangée par nom, jamais par volume. Elle ne sert pas à classer l'équipe.

## Les finances, en quatre notions

1. **Valeur des leçons réalisées** : le prix convenu à la réservation des leçons terminées, pas un encaissement.
2. **Valeur des leçons à venir** : les réservations futures confirmées.
3. **Total attendu selon le planning** : la somme des deux précédentes. Ce n'est ni une prévision garantie ni un revenu acquis.
4. **Règlements enregistrés** : les saisies de règlements de cours faites sur place, par date de saisie. Ce n'est pas un rapprochement bancaire, et annuler une saisie n'est pas un remboursement.

Le total attendu n'inclut jamais les règlements : un règlement de 500 CHF ne le fait pas monter. Les leçons commencées ou dont l'heure est passée sans constat restent à part, hors du total. Seules les leçons individuelles au tarif à l'unité sont valorisées : les cours collectifs n'ont pas de prix enregistré, la tuile le dit. Tout est en francs suisses ; aucun hors taxe ou toutes taxes comprises n'est calculé.

## Voir les lignes et exporter

« Voir le détail » sous une mesure ouvre les lignes qui la composent, avec la même période et les mêmes filtres : le total du serveur, le nombre de lignes affichées et, s'il en manque, la somme de celles qui sont affichées. « Ouvrir » mène à la fiche dans l'agenda. Si les données ont changé entre le chiffre et ses lignes, la page le dit et propose de relire.

« Exporter en CSV » produit un fichier de toute la sélection, pas seulement de la page vue, avec la période, le fuseau, la version de calcul et la couverture en tête. Il ne contient aucun nom d'élève, ne dépasse pas 10 000 lignes (au-delà, il est refusé plutôt que tronqué) et n'est pas une facture ni un document comptable.

## Ce que cette page ne fait pas

Pas de bénéfice, de marge, de coûts de moniteur, de solde bancaire, d'impayés, de remboursements ni de prévision de créneaux libres. Pas de taux d'occupation du planning : il n'a pas de dénominateur fiable.
