# Passe « Bugs » du 18 octobre 2026

Reprise de la section « Différé » de `essaim-bugs-20261017.md`. Aucune base PostgreSQL ni toolchain Apple dans cet environnement : les tests d'intégration et tous les tests Swift restent à qualifier par la CI.

## Corrigé

| Zone | Correction |
|---|---|
| Web, déconnexion | Se déconnecter avec une demande à vérifier (résultat inconnu) demande d'abord une confirmation : le suivi de la demande serait sinon effacé sans avertir. |
| Web, brouillons | Un retour par le cache de navigation (bfcache) sur une console qui porte des saisies non envoyées ne recharge plus la console : seule la valeur anti-falsification est renouvelée. Une session échue se voit à la prochaine écriture (401). |
| Web, invitations | Une liste de plus de 1 000 invitations affiche un avis « Liste partielle ». |
| Web, disponibilités | Un horaire qui chevauche un horaire existant du même moniteur (jour, heure et période communs) est refusé côté client, avec le message. L'API ne l'interdit pas : voir plus bas. |
| iOS, 401 | Le renouvellement forcé du jeton puis un seul nouvel essai (déjà présent dans `DrivyAPIClient` et `SchoolCaptureClient`) existe aussi dans les clients agenda, planning, catalogue, invitations, profil, formation, bilan, observations, thèmes et classement. Même opération et même clé d'idempotence au nouvel essai. |
| iOS, Aujourd'hui | Le rappel « à terminer » lit jusqu'à cinq pages d'historique (500 leçons) au lieu de la première seule. Une panne après la première page garde ce qui a été lu. |
| iOS, agenda | Une leçon démarrée sans rendez-vous prévient l'agenda et la liste des formations (`drivyLessonsDidChange`), y compris quand la feuille est déjà refermée. |
| API, next-slot | Les deux occurrences d'une heure répétée au retour à l'heure d'hiver sont proposées (`wallClockInstants`). Avant, seule l'une des deux l'était. |

## Non corrigé

- **Carte recréée au changement de disposition (iOS)** : `SchoolCaptureLiveView` choisit entre trois dispositions (`accessibleContent`, `wideContent`, `compactContent`) qui instancient chacune leur `SchoolCaptureLiveMap`. Son état (`SchoolLiveTrace`, mouvement, boussole) et la `MKMapView` sont recréés à chaque bascule. Une correction sûre sort cet état et la vue UIKit de la hiérarchie conditionnelle, ce qui dépasse ce qui peut se relire sans compilateur. À faire avec un simulateur.
- **Troncature à 80 lots sans indicateur (API)** : `matchTrack` s'arrête silencieusement au-delà de `MAXIMUM_BATCHES`. Un indicateur demande de changer le résultat du recalage, donc le format chiffré de la route et l'API de lecture (`matched-route`). Décision de contrat à prendre.
- **Chevauchement d'horaires côté API** : `POST availability-rules` n'interdit pas le chevauchement. Le contrôle client ne protège que la console web, pas l'app iOS ni un appel direct. Un refus serveur (409) est la suite logique.
- **Refresh perdu après rotation du jeton Keycloak (web)** : `accessToken` du BFF remplace `session.tokens`, mais une rotation des refresh tokens avec requêtes concurrentes de plusieurs onglets n'est couverte que par `session.refresh` (un seul vol par session). Pas de cas reproductible sans fournisseur : non touché.
- **Homonymes et invitations indiscernables (web)** : décision produit (quel libellé distinctif).
- **Écriture du Trousseau à chaque jeton, lot de positions après un trou de signal, capture mal formée qui bloque le coffre, ordre d'envoi des lots, `cipher_status`** : nécessitent un appareil ou SQLCipher, non qualifiables ici.
