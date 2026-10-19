# Audit V2 du 18 octobre 2026 : sélection et plan de validation

Base V1 `7c117cd`, branche `audit/intelligent-v2-20261018`, worktree distinct. Vingt explorateurs en lecture seule, 16 Luna et 4 Sol, deux vagues de dix, rapports de 300 mots maximum. Le coordinateur seul modifie le produit.

## Choix techniques du coordinateur

Corrections dans l’architecture existante, pas de design system nouveau, dépendance ou contrat externe modifié. Les protections existantes priment sur les propositions des agents : SectionHeading focalise déjà le titre, le menu mobile est une disclosure non modale, le BFF normalise les erreurs JSON, le changement d’école démonte PendingPanel.

### 1. Step-up lié au compte initial, P1 à reproduire

- Contrat existant : une authentification récente confirme un changement d’accès avec le même compte, mais le callback peut actuellement accepter un autre principal.
- Test rouge dans `apps/web/test/bff.test.ts`, en passant par login et callback HTTP du vrai BFF : autre compte refusé, session initiale conservée. Contrôles positifs : même compte accepté et login ordinaire libre de changer de compte.
- Correction minimale envisagée : sujet attendu optionnel dans la transaction serveur, fixé lors du step-up, comparé après le retour du fournisseur et avant rotation. Aucun sujet/jeton ajouté à la réponse navigateur.
- Risque modéré : ne pas empêcher une connexion ordinaire ou post-déconnexion, ni casser la rotation/CSRF.

### 2. Erreur de lecture d’accord GPS invisible, P2 à reproduire

- `GpsConsentLine` masque actuellement tout état autre que ready. Distinguer chargement, panne et refus d’accès volontairement masqué.
- Test rouge Edge sur dossier réel React avec transport synthétique : erreur 503 visible et réessayable, retry 200 rétablit le statut, 401 propose reconnexion, 403 ne révèle rien.
- Correction minimale envisagée : composants Notice/Loading/ReadRetry existants, sans changement CSS. Conserver le masquage du refus 403 et ne jamais fabriquer un consentement ni afficher une valeur périmée comme actuelle.
- Risque faible : UI locale, pas de droit ni d’état GPS modifié.

## Vérifications et limites

Baseline V2 rejouée : 135 tests unitaires API, 233 web, types/builds, cinq régressions V1 et 41 interactions existantes. Les tests navigateur synthétiques ne remplacent pas une recette OIDC/BFF/API/PostgreSQL réelle. Démarrage non interactif du Docker local installé tenté pour lever le blocage V1. Aucun serveur externe, déploiement, migration destructive ou reset de mot de passe autorisé. Apple/VoiceOver non qualifiés sans runner adapté.

Les alertes restantes sont arbitrées explicitement dans le [rapport final](audit-v2-20261018.md), sans remplir artificiellement le lot. Une alerte statique, une lacune de test ou une option de durcissement n’est pas un bug confirmé.

## Bilan réalisé

Les deux candidats ci-dessus ont été reproduits en rouge, corrigés puis vérifiés en vert. Trois nouveaux tests BFF portent la suite web à 236 succès. Les cinq scénarios GPS passent, les cinq régressions V1 et 41 interactions existantes aussi. Docker local démarré, PostgreSQL et SMTP isolés disponibles : 447 tests API réussis. La recette officielle étendue passe 82 contrôles avec Keycloak/BFF/API/PostgreSQL réels, dont le changement de compte refusé, le même compte accepté et une reprise GPS relisant le vrai serveur. Aucun reset de mot de passe, la récupération est déclarée exclue.

Types et builds réussis, intégrité des 556 fichiers canoniques conservée. Les limites Node 26 au lieu de 24 et l’absence de qualification Apple sont explicites. Commits produit `74038b3`, `131fb5a`, recette `00b6521`. Aucune fusion ni publication.
