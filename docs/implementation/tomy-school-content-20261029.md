# Tomy School — contenu pour l’essai personnel

Le 29 octobre 2026, le porteur demande de remplir largement son école de test, avec des contenus naturels sans suffixe « test » dans l’interface. Cette opération ne constitue ni une qualification produit, ni une activité réelle d’élèves. Elle reste distincte des fixtures de développement interdites sur la base homelab.

## Exécution

Réalisée le 29 octobre à 22:47 Europe/Zurich, sur l’école active dont le nom exact est Tomy School, avec vérification de son identifiant et de son ADMIN sous verrous. Une seule transaction de population ; aucune migration ou modification de service. Les contacts et réglages existants sont préservés ; seul le module de cours collectifs est activé avec nouvel instantané de configuration.

Sauvegarde PostgreSQL préalable : CT113, `/root/drivy-tomy-school-20261029T214721Z/before.dump`, 1 923 244 octets, répertoire 0700 et archive 0600. Catalogue et tous les blocs de l’archive relus avec `pg_restore`, sans répétition de restauration. SQL et reçu restent dans ce répertoire privé ; aucune donnée réelle n’est exportée dans le dépôt.

Empreinte du SQL exécuté : `2123d55b37f92ab07cd14ef908ad03fbb0d7f15bd3eaa3e8b2dd0881d7580d8a`.

## Contenu enregistré

| Surface | Contenu après ajout |
| --- | --- |
| Élèves | 24 dossiers, identité/contact/adresse, 24 formations actives et souhaits pédagogiques |
| Équipe | 3 moniteurs ajoutés ; membre propriétaire conservé, 28 membres au total |
| Catalogue | 4 permis B/A/A1/BE et 14 prestations au total ; offres B/A déjà présentes conservées |
| Agenda | 36 leçons : 17 prévues, 16 réalisées, 2 annulées et 1 absence |
| Pédagogie | 16 bilans, dont 14 révisions partagées et 2 privés ; 48 observations temporelles sans GPS |
| Horaires | 7 plages de disponibilité au total et 3 absences ; affectations aux moniteurs, plus 8 dossiers affectés au propriétaire déjà moniteur |
| Cours | 8 séries, 18 séances, 32 inscriptions dont 2 annulées, 3 places en liste d’attente |
| Suivi des cours | 40 états d’appel, 22 écritures de règlement dont 2 annulées, 9 validations de cours |

Personnes synthétiques sans compte OIDC, invitation ou appareil push. Adresses de contact sur le domaine réservé `example.com`. Aucun consentement ni contrôle physique de permis inventé ; aucune position GPS. Les préférences de notifications sont désactivées pour les seules nouvelles personnes ; aucun événement d’envoi créé. Les données confidentielles du moniteur restent dans leur portée privée.

## Contrôles exécutés

- Préflight en lecture seule, puis sauvegarde et première population en transaction annulée : contraintes PostgreSQL, clés étrangères, réservations et garde de capacité réussies.
- Vérification par comparaison JSON des lignes métier existantes et des identités/appartenances : aucune réécriture ou suppression. Tous les autres établissements sont conservés.
- Population validée durablement, puis lecture sous le rôle applicatif `drivy_app` et contexte de l’ADMIN : 24 élèves, 28 membres, 36 leçons, 8 cours, 32 inscriptions, 4 offres et 14 prestations visibles.
- Rejeu complet en transaction annulée après commit : mêmes totaux, aucun doublon et aucune remise à zéro. Une transaction annulée peut laisser un trou dans une séquence PostgreSQL ; ce contrôle n’est pas présenté comme strictement sans écriture.
- Lecture finale : 16 bilans, 14 révisions partagées, 48 observations, 40 états d’appel et 9 validations ; zéro événement de cours ou push en attente pour l’école.

L’outil `scripts/homelab/populate-tomy-school.py` affiche un plan par défaut. `--validate` prend une sauvegarde puis annule la transaction ; `--execute` prend une nouvelle sauvegarde et valide. Les identifiants attendus sont des arguments opérateur, pas des identifiants réels stockés dans le code. UUID déterministes au format RFC ; les relances conservent les modifications de l’utilisateur et refusent les contextes devenus incompatibles. En cas de réponse perdue après commit, relire le reçu et les compteurs avant toute reprise.

La web app reste au commit `4af4b0e6748081f90201169132cccd5c9fd6cfdb`. Essai personnel et retour utilisateur toujours attendus avant les campagnes complètes, la fusion de #311 et les clôtures.
