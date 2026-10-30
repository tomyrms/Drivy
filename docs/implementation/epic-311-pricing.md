# #311 / R16 #327 : tarifs et conditions communes

> Note héritée de `backup/311-catalogue-20261029-2050` (`dd37e256`), relue lors de la reprise du 29 octobre. Les anciennes recettes et captures citées ne sont pas revendiquées comme rejouées. Voir les preuves et corrections nouvelles dans [epic-311-catalogue-participants-reprise.md](epic-311-catalogue-participants-reprise.md).

Même branche et mêmes règles que `epic-311-formations.md`. Nouveau code dans `apps/web/client/portal/pricing/` ; les tarifs liés à un permis vivent dans la fiche du permis (vue `tarifs`), les prestations sans permis dans la section `prestations`, les conditions dans la section `conditions`. Validations et corps de commande repris de `console/formation-model.ts` (`tariffProblems`, `createTariffBody`, `updateTariffBody`, `tariffChanged`, `parseCents`), sans copier l'ancien rendu.

## État ligne par ligne de l'inventaire

| Ligne | État | Ce qui est fait | Ce qui reste à qualifier |
| --- | --- | --- | --- |
| `pricing.list` Tarifs liés au permis | Fait | Une ligne par tarif : nom, type et durée, prix et unité, état effectif (badge seulement pour « Jusqu'au… », « Non proposé », « À partir du… », conditions à revoir / expirées / à venir). Les tarifs non proposés ou terminés passent dans « Archives ». Le prix 0 s'affiche « Offert » ; un prix absent s'affiche « Prix non défini » et n'est jamais confondu avec 0. | Tri et regroupement avec beaucoup de tarifs. |
| `pricing.editor` Créer / modifier un tarif | Fait | Page entière. Cas courant en trois champs : nom, durée, prix CHF (clavier décimal, virgule acceptée, retour « 95.00 CHF par leçon »). « Autres options » (type, unité, début, fin, proposé à la réservation, conditions) s'ouvre seul en cas d'erreur. Relecture : création = résumé et date de début ; révision = valeur avant et après, « applicable dès le … sans effet rétroactif, les réservations déjà confirmées gardent leur prix et leurs conditions ». Conditions modifiées = conditions propres au tarif, les autres tarifs gardent les communes. Prix vide : erreur, jamais 0. | Le début d'une révision n'est pas saisissable : il est fixé par le serveur (aujourd'hui, ou la date déjà prévue d'un tarif pas encore commencé) et annoncé dans la relecture ; la règle n'est vérifiée que contre l'aperçu. |
| `pricing.unscoped` Prestations sans permis | Fait | Même liste, même fiche, même éditeur sans catégorie ; création, révision, « Ne plus proposer » et « Proposer à nouveau » (avec relecture), archives, consultation d'une ancienne version, lien vers les conditions commerciales. Une référence d'un tarif rattaché à un permis ouvre la fiche du permis. | Pas de suppression ni d'archivage dur : l'archive est l'état « non proposé ». Un tarif terminé se corrige par « Modifier le tarif » (date de fin), pas par réactivation. |
| `pricing.terms` Conditions commerciales | Fait | Liste des versions (recherche, filtre d'usage, « Sans tarif actuel »), lecteur confortable du texte, validité, liste des tarifs concernés avec lien vers chacun. Fiche d'un tarif : conditions affichées en entier, jamais derrière une icône, avec la portée (communes à N autres tarifs). Versions d'un tarif consultables. | Pas de vue dédiée « exceptions » : l'exception se lit sur le tarif (conditions propres) et dans la liste des tarifs concernés. Aucune création de conditions isolée (elles naissent avec un tarif, comme avant). |
| `pricing.shared-terms` Réviser les conditions communes | Fait | Édition en page entière, relecture avec texte avant / après et tarifs impactés, case « J'ai relu… » obligatoire avant « Adopter les nouvelles conditions », message « les réservations existantes gardent leurs conditions ». Après confirmation, la nouvelle version s'ouvre ; l'ancienne reste consultable et est signalée « Plus utilisées par un tarif actuel ». Vérifié : version 6 créée, version 2 conservée. | Rejeu avec une liste de tarifs modifiée entre-temps (`TERMS_USAGE_CHANGED`) : traité comme conflit (relecture), vérifié seulement contre l'aperçu. |

## Décisions

- **Aucun prix inventé.** `priceLabel(null)` = « Prix non défini », `priceLabel(0)` = « Offert ». Un parcours ancien sans prix de référence n'obtient aucun prix. La donnée d'aperçu contient volontairement un tarif offert (0) et un permis sans tarif de leçon.
- **Aucune rétroactivité implicite.** La relecture annonce la date d'effet (jamais avant aujourd'hui, ou la date déjà prévue d'un tarif qui n'a pas commencé) ; le serveur de l'aperçu crée une nouvelle version sans toucher aux anciennes (vérifié : v3 à 99,50, v1 inchangée à 90,00).
- **Pas de facturation, de paiement ni de pénalité.** Aucun élément de cette famille n'en introduit ; les textes d'aperçu ne décrivent aucune pénalité.
- **Commandes.** `saveTariff` et `reviseSharedTerms` par le moteur existant, avec les mêmes garanties que la famille Formations : pas de succès avant la confirmation, saisie conservée au refus, vérification par reçu, relecture au conflit (`TARIFF_CHANGED`, `VERSION_CONFLICT`).
- **Le focus ne bouge plus pendant la saisie** : une première version reprenait le focus à chaque rendu et coupait la frappe ; corrigée et couverte par un test de saisie caractère par caractère.

## Vérifications exécutées (dans `apps/web`)

Mêmes commandes et mêmes résultats que dans `epic-311-formations.md` (typage, build d'aperçu, `vitest` complet 446 tests, 85/85 + 8/8 vérifications navigateur). Propres à cette famille : 6 tests (`pricing.test.ts`) sur le récapitulatif de tarif, le prix vide et les groupes ; parcours réels de création, révision, proposer ou non, création de prestation, réactivation d'une archive, révision des conditions communes, conflit de tarif (saisie conservée, message « Ce tarif a changé pendant votre modification »). Captures 1440×900 et 390×844 en clair et en sombre examinées ; mesures mobiles sans cible sous 44 px.

## Reste à qualifier

Aperçu synthétique seulement : aucune qualification contre l'API, les droits ou l'authentification réels. Les montants et conditions de l'aperçu sont fictifs. Recette clavier décimal sur appareil réel à faire. Aucune issue n'est close.

## Demandes au socle

Mêmes demandes que `epic-311-formations.md`. En plus : un champ de type `date` stylé par le socle (le champ natif est utilisé tel quel, 16 px, cible de 44 px).
