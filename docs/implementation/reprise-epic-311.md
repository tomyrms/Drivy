# Reprise du chantier #311

Note de passation tenue à jour pendant la reconstruction. Elle décrit l’état réel, pas l’objectif.

## État au 28 octobre 2026, soir

- Coordinateur : worktree `C:/Users/jtoma/Documents/Projects/Drivy-codex-epic-311-rebuild`, branche `codex/epic-311-rebuild` (locale, jamais poussée).
- Aperçu public : <https://shulker.ch/drivy-preview/>, version `0688868d` (Accès, Agenda, Élèves). Publication et retour arrière : [epic-311-preview-publication.md](epic-311-preview-publication.md).
- Le porteur a vu les trois pilotes et a répondu « continue » : jalon visuel des pilotes franchi, généralisation lancée.

## Socle d’extension (coordinateur)

- `portal/destinations.ts` : cinq espaces repris de la console (Planning, Élèves, Équipe, Formations et tarifs, Réglages), sections existantes comme clés. Le shell n’affiche que les sections présentes dans `portal/pages.tsx` ; une rangée locale montre les sections sœurs d’un espace.
- `portal/pages.tsx` : registre section → page sans props. Même registre pour l’aperçu et pour le futur raccord authentifié.
- `portal/preview/family.ts` / `families.ts` : chaque famille amorce ses données fictives et répond à ses routes sans toucher `transport.ts`.
- Primitives ajoutées : Card, Collapsible, Popover, RadioGroup, ScrollArea, Sheet, Switch, Tooltip (shadcn 4.23.0).
- Contrôle visuel : `C:/Users/jtoma/AppData/Local/Temp/p311/capture.py` (Playwright Python, tailles exactes, thème, erreurs console). Les volets navigateur Atrium ne savent pas émuler 1440/390 dans un volet étroit.

## Vague 1 en cours (agents, worktrees séparés, base `d9c85479`)

| Famille | Issues | Worktree / branche | Fichiers exclusifs | Port |
| --- | --- | --- | --- | --- |
| Équipe | #325, reprise #318 | `Drivy-claude-311-team` / `claude/311-team` | `portal/team`, `portal/invitations`, `portal/access` | 5191 |
| Planning | vérif #322, #323, #328 | `Drivy-claude-311-planning` / `claude/311-planning` | `portal/agenda`, `portal/availability`, `portal/courses` | 5192 |
| Catalogue | #326, #327 | `Drivy-claude-311-catalogue` / `claude/311-catalogue` | `portal/formations`, `portal/pricing` | 5193 |

Fichiers partagés autorisés : une entrée par page dans `pages.tsx`, un import dans `preview/families.ts`, un fichier `preview/families/<famille>.ts`. Le reste du socle n’est modifié que par le coordinateur. Les agents committent localement, sans push.

## Vagues suivantes prévues

- Vague 2 : école (#320 ouverture/guide, #321 accueil, #330 réglages/confidentialité/GPS, #331 signalements), trajets (#332), participants et appel des cours (#329, même propriétaire que #328), entrée et compte (#319, #333).
- Raccord authentifié (#316/R05) : monter `PortalFrame` + `portalPages` dans l’application réelle avec le même `ConsoleContext`, les mêmes gardes et le même store de commandes.
- Fin : #334 retrait de l’ancien rendu après parité prouvée, #335 qualification écran par écran, #336 aperçu vérifiable puis campagnes.

## Corrigé par le coordinateur depuis la passation

- Variantes `data-horizontal` / `data-vertical` absentes du socle (onglets du dossier élève côte à côte).
- Ouverture de formation et affectation : la revue reste ouverte après un refus.
