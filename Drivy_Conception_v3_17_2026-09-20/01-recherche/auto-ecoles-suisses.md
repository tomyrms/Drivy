# Dix auto-écoles suisses : observations et traduction dans Drivy

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

## Méthode et niveau de preuve

Relevé des pages publiques officielles consultées le **19 septembre 2026**, issu du complément demandé par le porteur et intégré dans la référence. Six établissements romands, trois opérateurs de Suisse alémanique et un établissement tessinois : échantillon de commodité, non statistiquement représentatif. Aucune école n’a été interrogée ou testée en compte privé. Les tarifs affichés ne sont pas des devis et peuvent être non datés.

Les offres ci-dessous sont des faits publiés. La colonne d’impact est une **inférence de conception**, pas un besoin exprimé directement par les écoles. Aucun montant n’est automatiquement importé comme paramètre de production. L’usage de WhatsApp chez Luc’s provient du porteur ; l’éditeur n’a pas observé ces échanges.

## Offres publiées

| École | Échantillon d’offres | Conséquence proposée |
|---|---|---|
| Luc’s (Cernier) | 110 CHF / 45 min ; Start 1’460 CHF (10 leçons, sensibilisation, accompagnement examen) ; Drive/heure 1’620 CHF avec premiers secours et app théorique. [S33](../06-gouvernance/sources.md#s33) | Packs composites et frais offerts séparés ; total déjà remisé. |
| Marterey (Lausanne) | 96 CHF / 55 min ; packs 3/6/9/12 : 280/520/770/990 CHF ; formule accélérée 1’690 CHF avec 15 leçons et autres prestations. [S34](../06-gouvernance/sources.md#s34) | Durées contractuelles variables, packs de conduite et formules combinées. |
| In-Town (Genève) | 90 CHF / 50 min ; packs 6/12/20 : 480/900/1’400 CHF ; accompagnement examen 220 CHF. [S35](../06-gouvernance/sources.md#s35) | Quantités libres et prestation examen distincte. |
| MY L (Fribourg) | Dès 100 CHF / 45 min ou 190 CHF / 90 min ; vente à la leçon sans forfait ; cash/TWINT. [S36](../06-gouvernance/sources.md#s36) | Mode sans packs et rendez-vous de durée double ; réservation en ligne proposée publiquement. |
| Elyon Academy (Fribourg) | 115 CHF / 60 min ; packs 2/5/10 : 220/525/999 CHF ; prise en charge flexible selon organisation. [S37](../06-gouvernance/sources.md#s37) | Lieu propre à chaque rendez-vous, distinct du siège. |
| Power-L (Sion/Leytron) | Voiture 95 CHF / 50 min et 100 CHF de frais uniques ; moto de base 12 h : 600 CHF. [S38](../06-gouvernance/sources.md#s38) | Catégories et prestations collectives différenciées ; pas de GPS individuel de groupe supposé. |
| Driving Team (Zürich/Lachen) | Première leçon confirmée 65 CHF / 45 min puis 95 CHF ; frais uniques 120 CHF ; sensibilisation 190 CHF Zürich, 250 CHF Lachen. [S39](../06-gouvernance/sources.md#s39) | Tarifs par site et conditions d’introduction explicites. |
| Gundeli (Bâle/Münchenstein) | 100 CHF / 50 min ; frais 100 CHF ; 5/10/30 leçons : 475/900/2’100 CHF ; paiement anticipé annoncé. [S40](../06-gouvernance/sources.md#s40) | Politique de prépaiement et solde de droits séparé du calendrier. |
| BLINK (Zürich) | Essai 59 CHF / 45 min ; 5 leçons 435 CHF, 10 leçons 840 CHF ; sensibilisation optionnelle +150 CHF ; frais 90 CHF dès la deuxième leçon. [S41](../06-gouvernance/sources.md#s41) | Options de pack, frais différés et continuité entre moniteurs ; myBLINK décrit réservation, paiement et progression. |
| Autoscuola 2000 (Viganello-Lugano) | AUTO : 620 CHF pour sensibilisation et « 5 ore » ; formule complète 1’025 CHF avec Theorie24 et « 10 ore ». [S42](../06-gouvernance/sources.md#s42) | Accès externe distinct et unité « ore » à confirmer, sans conversion implicite en minutes. |

Ne pas comparer une leçon de 45 minutes à une leçon de 60 minutes comme des unités équivalentes. Les prix ne sont pas présentés comme un classement des écoles. Les coûts administratifs publics et toutes les conditions du permis ne sont pas réputés inclus. Pour Luc’s, un rabais informatif déjà intégré au prix total n’est pas soustrait une seconde fois. Les pages non datées et le sens d’« ore » chez Autoscuola 2000 demandent confirmation avant saisie réelle.

## Ce que la recherche soutient

Un catalogue unique codant « une leçon = une heure » et « un pack = dix leçons » ne couvre pas cet échantillon. Des durées et quantités explicites, des droits composites, des prix par site et une option sans forfaits sont donc justifiés. La présence de cours et de réservations en ligne chez plusieurs opérateurs soutient le caractère plausible d’une inscription autonome à une série ; elle ne prouve pas que tous utilisent la même organisation.

Ce relevé ne prouve pas que le GPS est demandé par ces dix écoles, ni qu’une école adoptera Drivy. La centralité du GPS est une **orientation explicite du porteur**, à éprouver en situation. Les réservations collectives sont un **besoin explicite illustré par son expérience**. Ces deux sources de décision restent différentes du benchmark commercial.

## Trois profils de configuration à tester

| Profil fictif | Configuration à éprouver | Parcours qui doit rester simple |
|---|---|---|
| Indépendant avec packs composites | Un site, catalogue court, droits conduite/CTC/examen | Publier une sensibilisation, accepter une place avec le bon droit, puis faire une leçon GPS. |
| École sans forfaits | Tarifs unitaires, paiement à la séance | Planifier et enregistrer sans écran de packs imposé. |
| École à plusieurs moniteurs/sites | Prix par site, salles et horaires, capacités déléguées | Ne pas doubler un moniteur entre conduite et salle, sans accès global aux traces. |

Les exemples sont des fixtures, pas des configurations approuvées de Luc’s, MY L ou BLINK. Les traductions françaises, allemandes et italiennes sont à prévoir dans le modèle ; le pilote peut limiter les langues réellement relues plutôt que prétendre disposer de traductions validées.

## Sensibilisation : un profil réglementaire, pas un événement libre

Les instructions OFROU du 24 septembre 2020 applicables dès 2021 prévoient notamment huit heures, quatre parties de deux heures, au moins deux jours, au plus deux parties par jour et douze participants maximum. La première partie précède les suivantes. Les listes de contrôle signées avec les informations requises sont à conserver trois ans selon ces instructions. Ce constat daté ne valide pas à lui seul toute pratique cantonale ou transition ultérieure [S44](../06-gouvernance/sources.md#s44).

L’OFROU annonce qu’au **1er janvier 2027**, le CTC comprend l’usage sûr des systèmes d’aide/automatisation et devient préalable à l’inscription à l’examen théorique [S45](../06-gouvernance/sources.md#s45). Le détail complet du nouveau régime et ses dispositions transitoires n’a pas été qualifié ici. Le profil 2027 reste à approuver avant activation ; le dossier ne reprend pas des résumés commerciaux comme équivalents du texte officiel.

Un profil de cours contient donc règles applicables, période, capacité maximale, structure, critères et preuves. Il n’est pas modifiable librement comme une information de présentation. Une contrainte non vérifiée constitue un blocage ciblé de publication et une question précise, pas une règle inventée par le développeur.

## Hypothèses à vérifier auprès des écoles

Observer qui publie, qui encaisse, qui valide les preuves et qui peut déplacer une série. Faire expliquer les remboursements de packs, absences, rattrapages, frais ponctuels, réservations reçues par téléphone et élèves sans app. Tester que « visible » n’est pas interprété comme « inscrit ». Demander les modèles de documents existants avant de promettre une attestation ou une intégration officielle.

Le pilote évalue l’utilité du replay pour expliquer et préparer la prochaine séance, et l’utilité du calendrier de cours pour réduire les allers-retours. Il ne maximise ni l’enregistrement forcé, ni la fréquence de notification, ni des scores d’élèves.
