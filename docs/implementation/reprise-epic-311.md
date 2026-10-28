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

### Interruption du 28 octobre, vers 22 h 20

Les trois agents ont été arrêtés par la limite d’usage (reprise possible après 2 h 50, heure de Zurich). Rien n’est intégré de leur côté ; leurs travaux sont sur disque :

- Équipe : non commité — `portal/access/access-controller.ts`, `access-page.tsx` modifiés ; `access-summary.tsx`, `members.ts`, dossier `portal/team/` créés.
- Planning : commit `ff5cd95b` (retour vers l’agenda, focus sur le titre de la leçon) ; non commité : `agenda/lesson-workspace.tsx`, dossier `portal/availability/` (modèle pur des horaires en cours).
- Catalogue : non commité — dossiers `portal/formations/` et `portal/pricing/`.

À reprendre dans le même worktree par le même propriétaire, sans recommencer. Défaut relevé pour Planning : dans la vue semaine, le nom de l’élève est illisible (texte écrasé) dans les leçons du jour et dans la leçon terminée ; les autres jours s’affichent bien.

### Intégration du 28 octobre, 23 h

Intégrés dans `codex/epic-311-rebuild` puis publiés (`e2a0d5e6`) : Équipe `ecfa33bf..83eaa7f8` (annuaire, fiche membre, retrait d’accès, invitations, données fictives) ; Planning `ff5cd95b..b4dee986` (focus de retour, nom lisible dans la semaine, #323 horaires et absences) ; Catalogue `6deb1c44..983b592e` (logique, contrôleurs, fiches permis/historique/tarifs, données fictives). Seuls conflits : `pages.tsx` et `preview/families.ts`, résolus par union.

Restes par agent (à reprendre par SendMessage après la limite, annoncée levée à 3 h 20) :
- Équipe : `preview/families/team.ts` modifié non commité ; note `epic-311-team.md` et rapport final à produire.
- Planning : `agenda/lesson-workspace.tsx` modifié non commité ; note #323 en cours ; #328 cours collectifs non commencé.
- Catalogue : finir #326/#327 et les notes ; finitions vues sur captures : contenu décalé de 8 px par rapport à la rangée d’onglets, page Prestations avec retour « Formations » et titre « Prestations » redondants avec l’onglet, carte « Prestations sans permis » en bas de Formations redondante avec l’onglet.

Les agents reprennent sur leur branche `claude/311-*` ; le coordinateur réintègre ensuite seulement les nouveaux commits (`git cherry-pick <dernier intégré>..claude/311-*`).

## Vagues suivantes prévues

- Vague 2 : école (#320 ouverture/guide, #321 accueil, #330 réglages/confidentialité/GPS, #331 signalements), trajets (#332), participants et appel des cours (#329, même propriétaire que #328), entrée et compte (#319, #333).
- Raccord authentifié (#316/R05) : fait côté code, voir ci-dessous ; reste à l’exécuter contre une vraie BFF (homelab ou CI navigateur).
- Fin : #334 retrait de l’ancien rendu après parité prouvée, #335 qualification écran par écran, #336 aperçu vérifiable puis campagnes.

## Corrigé par le coordinateur depuis la passation

- Variantes `data-horizontal` / `data-vertical` absentes du socle (onglets du dossier élève côte à côte).
- Ouverture de formation et affectation : la revue reste ouverte après un refus.
- Exécution de la console extraite dans `console/management-runtime.ts` (`useManagementConsole`) ; la console historique la consomme sans changement de comportement (427 tests web inchangés).
- `PortalConsole` (`portal/portal-console.tsx`) : même runtime, mêmes URL `/app/gestion/...`, pages du registre, sections non reconstruites renvoyant explicitement à l’ancienne présentation. Activation par navigateur avec `?presentation=nouvelle`, retour avec `?presentation=ancienne` ; défaut inchangé.
- Les feuilles historiques ne sont plus liées par `index.html` : `legacy-styles.ts` les charge pour les seules surfaces historiques.
- `test/portal-boundary.test.ts` interdit au portail d’atteindre l’ancien rendu ou l’aperçu synthétique, même transitivement.
