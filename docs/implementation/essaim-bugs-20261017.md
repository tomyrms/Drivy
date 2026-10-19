# Essaim de recherche de bugs — 17 octobre 2026

À la demande du porteur, 20 agents (Haiku 5.5) ont audité chacun une zone du dépôt sur `origin/master` (`0c50f3c`) : 9 côté API et base, 6 côté web, 5 côté iOS. Chaque constat a été relu dans le code avant d’être corrigé ; les corrections ont été faites par les agents, chacune sur sa branche, puis fusionnées dans `claude/essaim-bugs-20261017`.

## Corrigé

| Lot | Zone | Correction |
|---|---|---|
| 01 | API invitations | Créer une invitation ADMIN ou moniteur exige une réauthentification récente, comme un changement de rôle. Les invitations d’élèves ne changent pas. |
| 03 | API ouvertures | Modifier une ouverture ne transforme plus toute erreur en « rendez-vous à traiter » : seules les erreurs métier de `ensureOpen` le font. |
| 04 | API trajets | Un arrêt reçu après finalisation ne peut plus resserrer la borne : il effaçait des lots déjà reçus, de façon irréversible. Arrêt refusé sur un trajet supprimé ou retiré. Tolérance de 10 s sur l’horloge du téléphone (mesures, départ, arrêt) : un téléphone légèrement en avance voyait son arrêt refusé et ses trajets suivants bloqués jusqu’à 3 h. |
| 05 | API recalage | Une géométrie illisible renvoyée par le moteur est une erreur (réessayée), et non plus un « aucune route » définitif. |
| 07 | Base | Migration `034` : les motifs de retrait d’un bilan ne sont plus lisibles par l’élève dans la base (aucune route ne les lui servait). |
| 08 | API dossier élève | Un téléphone fait d’espaces ne compte plus comme renseigné (saisie, SQL et TypeScript alignés) ; date de naissance antérieure à 1900 refusée. |
| 09 | API Signaler | Le rafraîchissement quotidien du classement ne peut plus faire échouer la lecture ; ordre de lecture des usages déterministe. |
| 10 | BFF web | Le limiteur d’entrée ne compte plus un visiteur déjà connecté ni une requête sans jeton CSRF, et regroupe une adresse IPv6 par préfixe /64. En-tête HSTS hors développement. |
| 12 | Web agenda | Une recherche gardée n’affiche plus « aucune leçon » pendant que l’annuaire charge ou en cas d’erreur. Nom accessible de « Confirmer le retrait ». Erreur visible si la préparation à la planification ne peut pas être lue. |
| 13 | Web listes | Le focus reste sur « Précédent / Suivant » en bout de pagination (`aria-disabled`). |
| 14 | Web formations | Un permis déjà ajouté au brouillon ne peut plus l’être deux fois ; date de départ du tarif dans le fuseau de l’école (et non en UTC) ; message de prix exact ; boutons « Retirer » et « Insérer » distincts au lecteur d’écran. |
| 15 | Web réglages | « Enregistrer » n’est plus actif sans modification dans Informations demandées (comparaison faussée par l’ordre des clés jsonb) ; libellés « Pourquoi » distincts. |
| 18 | iOS bilan | Une relecture qui échoue ne vide plus le bilan, les objectifs, les bilans partagés ni les observations affichés. |
| 19 | iOS Aujourd’hui | Une leçon non démarrée et dépassée reste en tête, « En attente », au lieu de « Aucune autre leçon aujourd’hui ». Côté élève, une leçon non démarrée se lit « En attente », jamais « Maintenant ». |
| 20 | iOS trajets | Une requête de trajet interrompue (écran fermé) n’est plus présentée comme une panne réseau. |

## Exécuté

Sur la branche d’intégration : typage API et web, 138 tests API sans base, 260 tests web, build web. **Non exécutés ici** : les tests d’intégration PostgreSQL ajoutés ou modifiés (lots 01, 03, 04, 07, 08 ; aucune base locale) et tous les tests Swift (pas de toolchain Apple). Ils sont à qualifier par la CI de la PR. Aucun déploiement.

## À trancher par le porteur

- **Démarrer en retard** : l’API accepte un départ les jours suivant le rendez-vous ; seul le départ anticipé est refusé (`lessons.ts`).
- **« Commencer maintenant »** ignore les fermetures que le moniteur a posées.
- **Trajet masqué** : l’élève reçoit encore l’ancrage (trajet, segment, rang du point) des observations d’un trajet que le moniteur a masqué.
- **Objectifs** : visibles par l’élève avant la leçon ; la note administrative n’est masquée que par l’API, pas par la base.
- **Bilan « Pour moi »** : publier un brouillon lève le privé sans trace.
- **Politique de données** : l’API adopte un nouveau texte sans exiger la confirmation de son impact (accords GPS, trajets en cours) ; seul le web la montre. De même, `impactAcknowledged` est envoyé d’office pour les informations demandées, sans compter les élèves bloqués, et l’adoption des textes publie aussi ces informations.
- **Prix à 0** accepté pour une formation appliquée.
- **Déconnexion iOS** : les commandes en attente restent chiffrées sur l’appareil.
- **Fin de leçon iOS** : annuler la feuille du permis après l’arrêt du GPS laisse la leçon sans moyen de reprendre le trajet.
- **Peu de texte** : plusieurs notes explicatives restent sous les sections de la fiche formation.

## Différé (constaté, non corrigé)

- **Base** : un élève lit dans la base toutes les formations et affectations de son école (`school_current` sans filtre de rôle ; l’API filtre) ; la politique `invitation_membership_update` ne borne ni rôles ni droits (latent ; un `WITH CHECK roles <@ i.roles` casserait l’union des rôles d’un membre déjà actif, il faut un déclencheur) ; le rôle du worker d’e-mails lit toutes les invitations. Passe dédiée avec PostgreSQL nécessaire.
- **API** : rejeu idempotent d’une création d’invitation par code = code perdu sans signal ; double envoi d’e-mail si l’écriture « envoyé » échoue ; bail de recalage de 180 s sans renouvellement (appels Mapbox doublés sur un long trajet) ; troncature à 80 lots sans indicateur ; rejeu d’un lot de trajet après échéance = erreur au lieu du reçu ; heure répétée du passage à l’heure d’hiver absente de `next-slot` ; `ready` de `action-readiness` révèle un champ masqué ; ouvrir une école réécrit le nom global de la personne.
- **Web** : la déconnexion efface une demande incertaine sans avertir ; brouillons perdus au retour par l’historique ; liste d’invitations tronquée sans avis au-delà de 1 000 ; homonymes et invitations indiscernables ; chevauchement d’horaires de disponibilité accepté ; refresh perdu après rotation du jeton Keycloak.
- **iOS** : carte recréée au changement de disposition pendant un trajet ; agenda non prévenu après un démarrage ; rappel « à terminer » limité à la première page ; renouvellement sur 401 absent de plusieurs clients ; écriture du Trousseau à chaque jeton ; un lot de positions après un trou de signal perd ses premiers points ; une capture mal formée bloque l’ouverture du coffre ; ordre d’envoi des lots selon l’horloge murale ; `cipher_status` à confirmer sur le SQLCipher lié.

Écartés après relecture : réveil GPS « non arrêté » (arrêt voulu à la première position), limiteur d’essais en mémoire et `NODE_ENV` par défaut (couverts par l’instance unique et le script de déploiement), autorisation « pendant l’utilisation » (iOS continue un trajet démarré au premier plan avec le mode arrière-plan ; à confirmer physiquement), contrat OpenAPI du dossier de conception (livraison figée).
