# #311 — socle du premier aperçu

Le 28 octobre 2026, le porteur réduit le jalon immédiat à **une seule page Modifier les accès**, déployée pour décider de la direction artistique. Ce lot ne prétend pas réaliser toutes les variantes de R03, la navigation complète R05 ou la galerie R06.

## Frontière neuve

`client/portal/portal.css` est une entrée indépendante, avec son reset Tailwind et les tokens Drivy explicitement conservés. Aucun import de `styles.css`, `ui.tsx`, `console/layout.tsx`, feuille Studio ou ancien shell. `PortalFrame` fournit seulement l'en-tête Drivy, le contexte scolaire, le menu d'apparence fonctionnel et le SHA de l'aperçu. Aucune destination inactive n'est simulée pour remplir une navigation. Les liens vers les autres pilotes attendent la décision visuelle.

La police Manrope locale, sa licence, le symbole Drivy et le contrôleur neutre de thème existant sont conservés. Seule la préférence d'apparence reste persistée. Aucun cache métier, appel tiers, stockage scolaire ou nouvelle dépendance runtime.

## Provenance réelle

Registre officiel `@shadcn`, CLI **4.23.0**, preset **base-nova**, moteur **Base UI 1.9.0**. `shadcn info --json` relit la configuration existante ; `shadcn docs` fournit les URL officielles, puis `shadcn add` distribue réellement les sources. Checkbox, Avatar, Tabs et DropdownMenu sont ajoutés pour cette page. Imports `cn` redirigés vers l'utilitaire local déjà présent, directives RSC retirées. Le paquet transitoire `cn` ajouté par le registre est retiré : aucun changement du manifeste ni du verrou final.

Button, Input, Textarea, Field, Dialog, Alert et autres primitives déjà distribuées officiellement dans #280 sont conservés comme contrôles, sans charger leur ancien dessin global. Button/Dialog utilisent directement Base UI ; le contexte de suspension du dialogue préserve le masquage pendant une relecture d'accès. Cela ne réintroduit ni `CheckField`, ni `SplitView`, ni ancien formulaire. Les wrappers de domaine #280 ne sont pas utilisés par la nouvelle page.

Références : [Checkbox](https://ui.shadcn.com/docs/components/base/checkbox), [Tabs](https://ui.shadcn.com/docs/components/base/tabs), [DropdownMenu](https://ui.shadcn.com/docs/components/base/dropdown-menu), [Dialog](https://ui.shadcn.com/docs/components/base/dialog). Licence MIT shadcn conservée dans `client/components/ui/LICENSE.md`.

## Contrats pour le coordinateur

- `PortalFrame` conserve le contrat décrit dans `epic-311-coordination.md` ; `active`/`onNavigate` restent disponibles pour la suite mais ne créent aucun lien factice dans cette page unique.
- Checkbox : `checked`, `onCheckedChange`, `disabled`, label externe lié par `id`/`htmlFor`.
- Tabs : `Tabs`, `TabsList`, `TabsTrigger`, `TabsContent`, `value`/`onValueChange` officiels ; `keepMounted` disponible pour garder un brouillon lors d'une commutation.
- Avatar avec `AvatarFallback`, aucune photo de personne réelle inventée.
- Dialog : titre obligatoire et description selon besoin, retour de focus Base UI ; contrôle de fermeture et d'attente appartient à la commande de la page.

Cibles de boutons et contrôles textuels ≥44 px. Champs 16 px pour éviter le zoom automatique mobile ; couleurs sémantiques clair/Soft Charcoal, cobalt réservé à l'action dominante. Formulaire en page, pas modalité administrative longue. Mouvement réduit et couleurs forcées pris en compte.

## Vérifications et limites

Installation verrouillée isolée Node24.22.1 : PASS ; audit npm : 0 vulnérabilité signalée. TypeScript client : PASS. Les captures et la compilation de l'entrée intégrée sont réalisées par le coordinateur avec la page réelle ; cette note ne revendique aucune recette de pixels ni authentification de production à partir du seul socle. Pas de campagne complète, publication ni mutation de données exécutée dans ce worktree.
