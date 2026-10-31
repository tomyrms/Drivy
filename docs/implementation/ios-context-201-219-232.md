# États de l’école, profil commun et fin de leçon — 29 octobre 2026

Issues : #201, #219, #232. Branche d’intégration `codex/ios-suite-19-20261029`, hors EPIC #311.

## Décisions

- #201 : les états scolaires connus expliquent le rôle de l’administration et maintiennent l’accès au compte. Seuls les rôles déjà autorisés voient le portail et uniquement si son URL existe ; le sélecteur d’école reste conditionnel. Une erreur de première lecture porte le titre « École indisponible ». Actualiser relit l’état, sans promettre une activation ou restauration. Aucun contact fictif ajouté.
- #219 : avant les champs, une entrée « Profil commun à tes écoles » donne à la demande la portée compte, y compris sans école. Les aides du nom affiché et de l’e-mail distinguent consultation autorisée et identité de connexion. Les exigences et notices scolaires restent contextuelles ; aucun droit de partage changé.
- #232 : la confirmation décrit l’arrêt du trajet, la poursuite possible de son envoi et le bilan après confirmation serveur. La fiche de leçon reprend le même sens ; sans capture elle n’annonce aucun arrêt GPS. Le chemin de repli sans ouverture de fiche promet seulement l’arrêt du trajet et renvoie à la fiche pour terminer. Les gestes d’annulation, la collecte, l’arrêt durable et le constat serveur ne changent pas.

Références relues : `COMMENCER_ICI.md`, règles R01–R04, R15/R18/R29/R46, parcours GPS/replay et identités/formations, contrat AP05, règles d’archivage et scénarios de recette. Les décisions du 28 septembre 2026 restent prioritaires pour le partage automatique du bilan. Le parcours réel `stopAndSynchronize` → `finishForLesson` → constat confirmé a été relu avant rédaction.

## Vérification

- Relecture ciblée des routes et conditions de droits ; `git diff --check`.
- Pas de tests ajoutés pour ces changements de texte. Aucun test Swift/UI exécuté pendant ce lot.
- Compilation Release et IPA : voir la livraison du lot de 19 issues.
- À qualifier après essai : école en préparation ADMIN/moniteur/élève, archivée et multi-écoles ; portail absent/refus d’ouverture ; profil sans école ; fin de leçon en route/pause, réseau lent et échec de sauvegarde ; Continuer sans effet. VoiceOver, Dynamic Type et comportement GPS physiques restent à mesurer.
