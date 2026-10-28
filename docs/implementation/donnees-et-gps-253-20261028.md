# Données et GPS — décision de mise en service S14/S15

État au 28 octobre 2026. Lecture du code issu de `e5166404`, des décisions conservées et des sources officielles ci-dessous ; **aucune lecture de données de production**, aucun audit physique et aucune certification juridique. Le porteur confirme que le homelab est en Suisse. Il n’a pas encore précisé l’identité juridique de l’exploitant, les personnes ayant accès à l’hébergement, les lieux des sauvegardes ni les durées et procédures d’effacement.

## Faits, limites et informations manquantes

| Traitement | Faits constatés dans le dépôt | Limite avant mise en service réelle |
|---|---|---|
| Identité et appartenance | OIDC ; identité personnelle distincte des appartenances scolaires ; droits relus au serveur. `auth.ts`, `database.ts`, commandes et politiques PostgreSQL. | Identifier l’exploitant et contractualiser les rôles école/exploitant ; pas de qualification juridique déduite du nom d’un rôle informatique. |
| Dossier et rendez-vous | Proposition minimale : prénom/nom à l’inscription, contact facultatif ; pas d’AVS, dossier médical ou pièce d’identité par défaut. Les règles scolaires et les prérequis restent versionnés. | Les coordonnées déjà connues ne sont réutilisées que dans les droits existants. Âge/capacité et prérequis ne se déduisent pas d’une photo ou d’un code d’invitation. |
| Observations et bilan | Partage automatique des éléments d’une leçon réalisée ; notes privées séparées. Les évaluations ne sont pas fabriquées à partir des observations. | Les publics, droits et traitements secondaires doivent figurer dans l’information de l’école. Aucun accès général du support au contenu n’est établi. |
| Positions | `captures.ts` autorise la collecte après accord effectif, notice, affectation et diagnostic. L’appareil source est celui du moniteur. Les points sont chiffrés au serveur ; ce chiffrement n’est pas une promesse de chiffrement de bout en bout. | Nécessité et proportionnalité du GPS obligatoire à documenter. En moto, la position du moniteur ne prouve pas celle de l’élève. Le nouveau départ de qualification est limité à B/BE tant que la provenance des autres catégories n’est pas qualifiée. |
| Retrait | Choix versionné par école ; révocation serveur et arrêt local lorsqu’un refus est connu. Bail monotone non sérialisé, nouveau contrôle après relance. L’autorisation courante est bornée au maximum à trois heures (`SchoolCaptureAuthorizationVerifier`, `captures.ts`). | Un appareil distant hors réseau ne reçoit pas instantanément un retrait. La borne maximale et les contrôles périodiques doivent être mesurés sur appareils avant activation ; ne pas promettre un arrêt distant immédiat. |
| Messagerie | Chaîne de chiffrement et destinataires spécifiques, indépendante des droits de lecture des bilans. Les notifications de mention documentées sont génériques. | Ne pas confondre métadonnées, contenu chiffré et possibilité réelle de lecture. Les preuves physiques de qualification demeurent celles du dossier messagerie, pas celles de cette compilation. |
| Cartographie | Apple Plans ; recalage OSRM ou Mapbox selon configuration (`text-proposals.ts`, configuration du serveur). Le texte ne cite un prestataire de recalage que s’il est configuré. | Homelab suisse ne signifie pas que tous les sous-traitants, cartes, identité, courriels, notifications et sauvegardes restent en Suisse. Inventaire des contrats et transferts à compléter. |
| Conservation et suppression | Pas de purge générale à échéance prouvée. Des mécanismes de retrait/visibilité de trajet existent ; ils ne constituent pas à eux seuls une procédure complète d’effacement des comptes et sauvegardes. | Définir durées par finalité, sort des sauvegardes, export, demandes d’accès/effacement et responsable du traitement des demandes. Retrait GPS et effacement historique sont distincts. |
| Sauvegarde et exploitation | Le compte rendu du 27 octobre documente un dump avant déploiement, permissions 0600 et lecture du catalogue. Il ne revendique pas de restauration d’essai. | Chiffrement effectif, calendrier, copie distante, accès administrateur, restauration et traitement d’incident non attestés par cette lecture. |

Les durées et garanties inconnues ont été retirées des propositions de texte. Le modèle de conservation contient désormais un élément **à compléter**, bloquant son adoption par le guide. Les notices déjà publiées ne sont ni remplacées ni réadoptées par une lecture ou par l’ajout d’un tarif.

## Analyse des exigences

La Suisse ne transforme pas tout traitement privé en demande de consentement universelle. Le consentement invoqué doit néanmoins être libre et informé ; un bouton ne résout pas une dépendance ou un traitement disproportionné. La nécessité pédagogique du GPS systématique n’est pas démontrée par la seule décision produit. Préserver le compte, les messages et rendez-vous et laisser l’enseignement hors Drivy possible réduit les conséquences du refus, sans constituer à lui seul une conclusion de licéité. [PFPDT, 7 questions](https://www.edoeb.admin.ch/fr/7-questions).

Une école qui emploie un moniteur doit examiner le suivi de ce salarié séparément du choix de l’élève : finalité, nécessité, proportionnalité, information et interdiction d’un dispositif destiné à surveiller son comportement. Le consentement d’un élève ne couvre pas le salarié. [PFPDT, surveillance au travail](https://www.edoeb.admin.ch/fr/moyens-techniques-de-surveillance-sur-le-lieu-de-travail).

L’AIPD est requise en présence d’un risque potentiellement élevé, pas automatiquement pour tout logiciel. Il faut consigner l’examen du risque de la géolocalisation systématique, des mineurs, de la durée et des accès. Si un risque résiduel élevé subsiste, les conditions de consultation prévues par la LPD doivent être examinées. Cette note prépare cet examen ; elle ne prétend pas être une AIPD terminée. [PFPDT, AIPD](https://www.edoeb.admin.ch/fr/analyse-dimpact-relative-a-la-protection-des-donnees-personnelles).

Pour les mineurs, aucun seuil arbitraire de consentement autonome n’est ajouté. La capacité, la représentation et la compréhension effective restent à établir. La source PFPDT consultée souligne une information compréhensible pour le public mineur ; son contexte cookies ne valide pas le GPS de Drivy. [Guide PFPDT 2025, p. 19](https://www.edoeb.admin.ch/dam/fr/sd-web/brLL9rM3ny9d/Leitfaden%20des%20ED%C3%96B%20betreffend%20Datenbearbeitungen%20mittels%20Cookies%20und%20%C3%A4hnlichen%20Technologien%20V.%201.1%20vom%2006.10.2025_FR.pdf).

Le RGPD n’est pas déclaré applicable ou inapplicable sur la seule localisation suisse du serveur. Une offre vers l’Union ou une observation du comportement de personnes dans l’Union peut modifier l’analyse ; ces circonstances ne sont pas établies ici. [FAQ PFPDT, champ du RGPD](https://www.edoeb.admin.ch/fr/faq-protection-des-donnees).

## Décision technique de cette livraison

- **Autorisé dans la branche** : code, contrats, recherche, compilation et qualification synthétique. Aucun nouveau paramètre juridique n’est ajouté au formulaire du moniteur.
- **Non activé** : nouveau départ GPS obligatoire dans des écoles réelles. `GPS_ONLY_QUALIFICATION_SCHOOL_IDS` est vide par défaut. L’inclure dans la configuration d’exploitation requiert un accord distinct ; cette liste n’est pas un feu vert juridique.
- **Blocages réels** : identité/rôles de l’exploitant ; durées/sauvegardes/effacement ; analyse de nécessité du GPS, mineurs et salariés ; examen AIPD ; qualification de la provenance hors B/BE et délai de propagation du retrait.
- **Compatibilité** : anciens historiques sans trace lisibles ; captures déjà actives conservées ; ancien mode présent seulement tant que le serveur annonce `LEGACY`. Pour une école de qualification, les anciens endpoints de départ sont refusés au serveur, l’accord doit venir de l’élève et une acceptation obsolète ne peut remplacer un choix plus récent.
- **Pas de déploiement effectué**. Une future bascule exige présentation des services, configuration, sauvegarde, migrations et retour arrière au porteur. Aucun changement de cette livraison ne purge des données.

## Références de fonctionnement

- `docs/implementation/decisions-2026-09-28.md` : partage du bilan.
- `docs/implementation/decisions-2026-10-13.md` : propositions, adoption et impact des notices.
- `docs/implementation/deploiement-messagerie-20261027.md` : déploiement antérieur documenté, distinct de cette livraison.
- `apps/api/src/captures.ts`, `capture-crypto.ts`, `text-proposals.ts` ; `apps/ios/Drivy/SchoolCaptureAPI/SchoolCaptureAuthorizationVerifier.swift` ; journal SQLCipher et contrôleur de capture.
