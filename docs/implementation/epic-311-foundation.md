# #311 — socle du premier aperçu

Le 28 octobre 2026, le porteur réduit le jalon immédiat à **une seule page Modifier les accès**, déployée pour décider de la direction artistique. Ce lot ne prétend pas réaliser toutes les variantes de R03, la navigation complète R05 ou la galerie R06.

## Reprise après le premier retour visuel

Le porteur indique « c'est déjà bien mieux », puis « continue ». La page d'accès reste la référence visuelle ; le socle peut maintenant relier les trois pilotes. `PortalFrame` active `active` et `onNavigate` pour Agenda, Élèves et Équipe. Un seul arbre de navigation devient un rail de 208 px à partir de 1024 px et une barre basse à trois destinations en dessous. Les libellés restent visibles, les cibles mesurent au moins 44 px et la zone de sécurité mobile est respectée. La page et ses formulaires ne sont pas dupliqués selon la largeur.

Le callback demande la navigation au coordinateur, qui conserve les gardes de sortie et la commande en cours. Le shell ne change pas lui-même l'onglet avant cette décision ; un changement effectif de `active` remet le focus au contenu. Retour, liens profonds, accès retirés et périmètres scolaires restent des responsabilités du raccord métier. Aucune destination supplémentaire n'est affichée sans pilote réellement raccordé.

Le Select officiel Base UI est ajouté via le même registre CLI 4.23.0 ; `Select`, `SelectTrigger`, `SelectValue`, `SelectContent`, `SelectItem`, `SelectGroup`, `SelectLabel` et `SelectSeparator` conservent leurs API officielles. Valeur et labels sont fournis à `Select` via `value`/`onValueChange`/`items`. Voir [Select officiel](https://ui.shadcn.com/docs/components/base/select). TypeScript client exécuté après le raccord navigation/Select : PASS. La vérification visuelle des trois pilotes attend leur intégration ; cette étape ne ferme pas R03/R05/R06.

### Sélection partagée des pilotes

Les besoins explicites des agents Agenda/Élèves ajoutent [Combobox](https://ui.shadcn.com/docs/components/base/combobox), [InputGroup](https://ui.shadcn.com/docs/components/base/input-group) et [Table](https://ui.shadcn.com/docs/components/base/table), distribués par `shadcn@4.23.0 add combobox table`. Les Button/Input/Textarea existants ne sont pas écrasés. Adaptations locales : `cn` utilise l'utilitaire déjà présent, directive RSC inutile retirée, commandes iconiques de Combobox nommées en français et cibles de 44 px. Le paquet `cn` transitoire du registre est retiré ; aucun nouveau paquet runtime final.

`portal/components/portal-select.tsx` compose Field/Label/Description/Error et Select ou Combobox. Ce composant ne crée ni option libre ni commande, et ne déduit aucun droit. Il préserve une valeur retirée des options en l'affichant désactivée comme « Sélection indisponible », sans écrire `null` automatiquement. Les listes longues se recherchent localement parmi les seules options fournies par le contrôleur ; les options désactivées restent non sélectionnables.

Contrat : `id`, `label`, `options: readonly { value: string; label: string; disabled?: boolean }[]`, `value: string | null`, `onValueChange(value: string | null)`. Options de présentation : `searchable`, `disabled`, `error`, `description`, `placeholder`, `emptyText`, `name`, `className`. Label permanent, erreur et description reliées par `aria-describedby`. Ne pas imbriquer ce pattern dans un second Field. Les erreurs métier et la couverture des résultats restent fournies par chaque contrôleur.

Usages destinataires : filtre d'annuaire et choix de formation/pays (Élèves), choix élève/moniteur (Agenda), choix courts (Équipe). Les détails command-store, la confirmation de départ et le panneau de commandes en attente appartiennent à `portal/runtime` du coordinateur ; aucun doublon n'est créé ici. Les autres compositions continuent d'utiliser directement Field/Dialog/Alert/Skeleton/Empty, déjà partagés, sans imposer une nouvelle enveloppe à la page Accès validée.

Contrôle après ces ajouts : TypeScript client PASS, audit npm 0 vulnérabilité. Les dimensions sont définies pour les petites largeurs (contrôles 44 px, input 16 px, listes limitées au viewport, textes longs à la ligne) ; recette de clavier et rendu des champs dans les pilotes à faire après intégration.

## Frontière neuve

`client/portal/portal.css` est une entrée indépendante, avec son reset Tailwind et les tokens Drivy explicitement conservés. Aucun import de `styles.css`, `ui.tsx`, `console/layout.tsx`, feuille Studio ou ancien shell. Au premier jalon, `PortalFrame` fournit seulement l'en-tête Drivy, le contexte scolaire, le menu d'apparence fonctionnel et le SHA de l'aperçu. La reprise autorisée ajoute ensuite les trois destinations ci-dessus.

La police Manrope locale, sa licence, le symbole Drivy et le contrôleur neutre de thème existant sont conservés. Seule la préférence d'apparence reste persistée. Aucun cache métier, appel tiers, stockage scolaire ou nouvelle dépendance runtime.

## Provenance réelle

Registre officiel `@shadcn`, CLI **4.23.0**, preset **base-nova**, moteur **Base UI 1.9.0**. `shadcn info --json` relit la configuration existante ; `shadcn docs` fournit les URL officielles, puis `shadcn add` distribue réellement les sources. Checkbox, Avatar, Tabs et DropdownMenu sont ajoutés pour cette page. Imports `cn` redirigés vers l'utilitaire local déjà présent, directives RSC retirées. Le paquet transitoire `cn` ajouté par le registre est retiré : aucun changement du manifeste ni du verrou final.

Button, Input, Textarea, Field, Dialog, Alert et autres primitives déjà distribuées officiellement dans #280 sont conservés comme contrôles, sans charger leur ancien dessin global. Button/Dialog utilisent directement Base UI ; le contexte de suspension du dialogue préserve le masquage pendant une relecture d'accès. Cela ne réintroduit ni `CheckField`, ni `SplitView`, ni ancien formulaire. Les wrappers de domaine #280 ne sont pas utilisés par la nouvelle page.

Références : [Checkbox](https://ui.shadcn.com/docs/components/base/checkbox), [Tabs](https://ui.shadcn.com/docs/components/base/tabs), [DropdownMenu](https://ui.shadcn.com/docs/components/base/dropdown-menu), [Dialog](https://ui.shadcn.com/docs/components/base/dialog). Licence MIT shadcn conservée dans `client/components/ui/LICENSE.md`.

## Contrats pour le coordinateur

- `PortalFrame` conserve le contrat décrit dans `epic-311-coordination.md` ; `active`/`onNavigate` pilotent maintenant les trois destinations raccordées par le coordinateur.
- Checkbox : `checked`, `onCheckedChange`, `disabled`, label externe lié par `id`/`htmlFor`.
- Tabs : `Tabs`, `TabsList`, `TabsTrigger`, `TabsContent`, `value`/`onValueChange` officiels ; `keepMounted` disponible pour garder un brouillon lors d'une commutation.
- Avatar avec `AvatarFallback`, aucune photo de personne réelle inventée.
- Dialog : titre obligatoire et description selon besoin, retour de focus Base UI ; contrôle de fermeture et d'attente appartient à la commande de la page.

Cibles de boutons et contrôles textuels ≥44 px. Champs 16 px pour éviter le zoom automatique mobile ; couleurs sémantiques clair/Soft Charcoal, cobalt réservé à l'action dominante. Formulaire en page, pas modalité administrative longue. Mouvement réduit et couleurs forcées pris en compte.

## Vérifications et limites

Installation verrouillée isolée Node24.22.1 : PASS ; audit npm : 0 vulnérabilité signalée. TypeScript client : PASS. Les captures et la compilation de l'entrée intégrée sont réalisées par le coordinateur avec la page réelle ; cette note ne revendique aucune recette de pixels ni authentification de production à partir du seul socle. Pas de campagne complète, publication ni mutation de données exécutée dans ce worktree.
