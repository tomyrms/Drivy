# Audit à quatre agents — 18 octobre 2026

Branche d’intégration : `claude/audit-4agents-20261018`, partie de `claude/essaim-bugs-20261017` (qui contient `origin/master`). Une branche par agent, aucun fichier partagé entre agents, aucun push, aucune fusion sur `master`, aucun déploiement.

| Agent | Modèle | Branche | Résultat |
|---|---|---|---|
| UI/UX | Sonnet 5, effort bas | `claude/audit-ui-20261018` | 4 commits, intégrés |
| Bugs | Sonnet 5.5 | `claude/audit-bugs-20261018` | 10 commits, intégrés ; détail dans [audit-bugs-20261018.md](audit-bugs-20261018.md) |
| Architecture | Sonnet 5, effort bas | `claude/audit-archi-20261018` | aucun commit : rien de sûr à corriger |
| QA | Haiku 5.5, effort bas | intégration | référence, relecture de chaque lot, tests |

## UI/UX

- Web : le menu de `choice-field` prend l’ombre de superposition commune (`--shadow-menu`, nulle en sombre) ; les petites ombres de contrôle du déclencheur et du segment choisi sont conservées (DESIGN.md, surfaces). Un rayon de focus en `px` passe en `rem`.
- iOS : Réduire les animations est respecté dans `SchoolProfileView` (défilement vers un champ, point « à renseigner ») et `DrivyFormField`, via `DrivyMotion`.
- Vérifié sans correction : focus visible, `prefers-reduced-motion`, icônes masquées aux lecteurs d’écran, états chargement/erreur/vide des 25 écrans de la console, `@ScaledMetric` du code d’invitation. Glyphe de marqueur de carte à taille fixe gardé (géométrie du marqueur).
- Une première version retirait aussi les ombres de contrôle et renforçait celle du menu ; la QA l’a relevé et elle a été corrigée avant intégration.

## Bugs

Corrigés : confirmation avant déconnexion avec une demande à vérifier, saisies conservées au retour par le cache de navigation, avis « Liste partielle » au-delà de 1 000 invitations, horaire de disponibilité chevauchant refusé dans la console, renouvellement du jeton sur 401 dans dix clients iOS, rappel « à terminer » sur cinq pages, agenda prévenu d’un démarrage sans rendez-vous, deux occurrences d’une heure répétée dans `next-slot`.

Non corrigés : carte iOS recréée au changement de disposition (simulateur nécessaire), troncature à 80 lots (décision de contrat), refus serveur des chevauchements (suite logique, 409), constats exigeant un appareil, SQLCipher ou une décision produit.

## Architecture

Aucun export, module ou fonction Swift sans référence. `formatDate` (App.tsx) et `formatDateTime` (ui.tsx) produisent des formats différents : non fusionnés. `readError` complète `errorMessage`, ce n’est pas un doublon. Les mises à jour ligne par ligne de l’ancrage des observations et de l’envoi des captures sont bornées à une leçon et dans une transaction verrouillée.

## Exécuté

Sur la branche d’intégration : typage web (deux passes) et API, 264 tests web (référence 260) et 132 tests API sans base (référence 130), tous verts. **À qualifier par la CI** : tous les changements Swift (relus, non compilés), tests PostgreSQL. Aucun résultat d’appareil.
