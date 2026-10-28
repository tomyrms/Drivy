# #311 — coordination de la reconstruction

Base locale : `24a946bc` (produit publié `be8a0245`), contenant master `c94ec2bb`. Le produit #280 est rejeté visuellement ; son historique et ses garanties fonctionnelles restent des sources de travail. Production inchangée durant la construction des pilotes.

## Jalon obligatoire

Trois pilotes réels : accès d'un membre, agenda et fiche élève. Desktop 1440 / mobile 390, clair/sombre, lecture/édition avec confirmation, erreur et attente. Présenter le même SHA dans un aperçu synthétique accessible. **Ne pas généraliser les nouveaux écrans avant validation visuelle du porteur.** La suite R08–R22 conserve des propriétaires prévus, pas un statut réalisé. Tests étendus après essai ; contrôles indispensables, builds et typage maintenus.

## Propriétaires et frontière

- Coordinateur : R01/inventaire, R02/jalon, pilote R07 accès, raccord runtime/fixtures, contrôle des imports et livraison. Worktree `codex/epic-311-rebuild`.
- Agent socle : seul propriétaire primitives `client/components/ui`, dépendances/configuration shadcn, `client/portal/portal.css`, `client/portal/frame.tsx`, `client/portal/components/*`, `client/portal/format.ts` et DESIGN.md. Branche/worktree dédiés `codex/311-foundation`.
- Agent agenda : `client/portal/agenda/*` exclusivement et sa note. Branche/worktree `codex/311-agenda`. R11, extraction contrôleurs leçon/agenda sans JSX ancien.
- Agent élève : `client/portal/learners/*` exclusivement et sa note. Branche/worktree `codex/311-learners`. R13, extraction contrôleurs dossier/progression/profil sans JSX ancien.

Chaque agent commit uniquement ses fichiers. Le coordinateur intègre les commits, les autres agents ne fusionnent pas les branches de leurs pairs sans instruction. Aucun push déclenchant une campagne étendue avant le jalon. Aucune écriture backend/API/contrats/migrations/Swift/CI dans cette étape.

## Contrat de composition des pilotes

Les nouveaux rendus vivent dans `client/portal`. Ils peuvent lire les modules métier purs existants : `protocol`, `school-api`, `command-*`, modèles, `console/context.ts`, `console/list-state.ts`, `console/route.ts`, caches et projections sans JSX. Ils ne doivent importer directement ou transitivement ni `ui.tsx`, ni `console/layout.tsx`, ni une ancienne vue, ni `styles.css`, `*-studio.css`, `people-workspace.css`, `portal-shell.css`. Si une fonction de formatage est liée au vieux rendu, l'extraire dans le domaine propre ou utiliser `Intl` ; ne pas importer le rendu pour une fonction pure.

Primitives existantes réellement shadcn dans `client/components/ui` réutilisables et complétées par le propriétaire socle ; aucune copie d'un second kit. Base UI est conservé. Champs génériques via FieldGroup/Field/FieldLabel et contrôles shadcn ; états via Alert/Skeleton/Empty ; icônes lucide. Checkbox pour les choix validés plus tard. Les modèles et commandes restent uniques.

Points d'entrée attendus : `AccessPilot` dans `portal/access/access-page.tsx` (coordinateur), `AgendaPilot` dans `portal/agenda/agenda-page.tsx`, `LearnerPilot` dans `portal/learners/learner-page.tsx`. Composants sans props obligatoires, nourris par le même `ConsoleContext` métier. Ils gèrent leurs vues lecture/édition et retour ; toutes les commandes réelles réutilisent le moteur existant. Les fixtures interceptent le réseau uniquement dans l'entrée d'aperçu distincte ; aucun faux succès dans la version raccordée.

Shell unique `PortalFrame` exporté depuis `portal/frame.tsx` : props `children: ReactNode`, `active: 'agenda' | 'eleves' | 'equipe'`, `onNavigate: (destination: 'agenda' | 'eleves' | 'equipe') => void`, `schoolName: string`, `userName: string`, `build: string`. École et compte accessibles, destinations nommées. Le coordinateur gère la portée/session et les gardes ; le socle gère le chrome et la navigation visuelle. Les écrans ne montent pas un second shell.

Direction : organisation orientée tâche Cal.com, hiérarchie Untitled UI, identité Drivy cobalt/Soft Charcoal. Couches claires, séparations et whitespace utiles ; éviter cartes dans cartes et panneaux imbriqués. Lecture d'abord, édition distincte, résumé des changements avant confirmation. Aucun KPI, export, chat ou droit inventé.
