# Q9 — pièce locale au refus du repère de planification

5 novembre 2026, dispatch `ctx_52bc29e0f488`. Base conservée :
`5aa037ca765943967f92fe2ec70670c967c7c63e`. Instrumentation uniquement, pas de réparation
de la sélection ni de nouveau run. Les budgets et preuves Q6/Q8/Q9 sont conservés.

## Pourquoi cette mesure

Le diagnostic `artifacts/q9-anchor-diagnostic/RAPPORT.md` établit que les treize archives
automatiques du run 42047210389 sont des racines sans descendants et précèdent l'instantané
refusé. Le grand texte iPhone s'arrête avant Planifier, après deux mouvements réels ; zéro
candidat, types exclus, intersection et doublons ne sont pas départagés. L'iPad et les cas
standards verts ne prouvent pas la cause de cet échec historique.

## Contrat du delta

Seul `SchoolPlanningCancellationUITests.swift` change en code. Le résultat de la même
sélection `anchors.first` est nommé `selectedAnchor`. Quand il est nil, le helper privé
`attachMissingAnchor` construit une pièce texte, puis le **même `XCTUnwrap` avec le même
message** échoue. Quand il existe, le formateur n'est pas appelé. Filtre, tri, unicité,
viewport, fenêtres, gestes, limites, saisie, assertions, délais et lancement restent identiques.

Le helper reçoit exclusivement snapshot/nodes/content/form/windowSnapshot/viewport déjà
en mémoire, ainsi que direction et numéro de geste. Il n'interroge ni app ni element et
n'appelle ni snapshot(), exists, isHittable, debugDescription, screenshot ou pause. Les
attributs lus appartiennent aux `XCUIElementSnapshot` locaux. La méthode est privée au
test qui lance explicitement la fixture L2 synthétique ; la collecte est gardée par
`#if DEBUG && targetEnvironment(simulator)`. Hors de cette configuration, seule une pièce
signalant l'indisponibilité est produite. Aucun produit, Set, admission ou transport modifié.

## Contenu et bornes

La pièce **« L2 — snapshot local au refus du repère (sans value) »** est un
`XCTAttachment(string:)`, `lifetime = .keepAlways`, ajouté avant l'unwrap :

- Descendants du Form dans le préordre existant : index, chemin local `Form/indice/...`,
  type AX numérique (`elementType.rawValue`), identifier, label, frame. **Jamais value**.
- Pour chaque ligne émise : type accepté, label non vide, intersection, nombre exact de
  correspondances `sameAnchor` dans **tout content**, y compris hors viewport, et statut
  candidat. Les comparaisons utilisent les chaînes intégrales, avant toute troncature.
- Totaux exacts des descendants, candidats et candidats uniques sur tout content ; direction
  et numéro du geste à préparer dans la direction courante. La sélection/tri reste celle du
  code existant ; le rapport des descendants conserve leur ordre structurel.
- Frames de l'instantané, du Form et de la Window sélectionnés, viewport. Dans `nodes`
  seulement : fenêtres, formulaires, navigation, clavier, footer, témoin et cible Q9
  `planning-confirm`, avec nombre de correspondances, index local et absence explicite.
  Cette cible est nommée pour Q9 : aucune lecture de l'élément demandé n'est ajoutée pour
  identifier une autre requête appelante. Aucun dump de l'application entière.

Limites : **200 descendants détaillés**, **8 nœuds par chacun des 7 rôles contextuels**,
**256 scalaires Unicode par chaîne émise** (chemin/id/label). Au plus 256 lignes de nœuds ;
les chemins sont construits uniquement pour les 200 premiers descendants. Guillemets,
antislashs et retours/tabulations sont échappés. Les totaux et les calculs d'unicité ne sont
jamais limités aux nœuds imprimés. Le coût du calcul complet, quadratique en descendants,
est réservé au chemin déjà en échec et ne consomme aucune fenêtre d'annulation nominale.

Nœuds omis, chaînes tronquées et scalaires omis sont comptés ; toute troncature est marquée
**LIMITE DIAGNOSTIQUE**, jamais comme un succès. XCTest ne fournit pas ici d'accusé de
persistance de la pièce : une ligne du journal indique qu'elle a été demandée et que son
absence dans le résultat signifie une preuve indisponible. L'échec initial demeure dans
tous les cas ; l'existence effective de la pièce doit être contrôlée dans le futur résultat Apple.

## Préflight et contrôles locaux

Reçu initial `ctx_03e2318e5896` relu : effective **Codex gpt-6-astra/high**, incarnation
`structured:1bfdfca6-7879-485f-8a8c-426c16376122`, sans substitution. Skills chargés dans
cette même session, réutilisés et références pertinentes relues :
`C:/Users/jtoma/.codex/skills/systematic-debugging/SKILL.md`,
`verification-before-completion/SKILL.md`, `impeccable/SKILL.md` (4.8.0),
`uncodixfy/SKILL.md`, et craft-floor Impeccable avant édition. AGENTS, COMMENCER_ICI,
DESIGN et contrat L2 restent applicables. Pas de prétention TDD sur ce formateur.
Impeccable/Uncodixfy : préservation stricte des interactions et du rendu natif, preuve fondée
sur les données locales réelles, aucune décoration ni transposition de règles CSS.

Codebase Memory : projet
`C-Users-jtoma-orca-workspaces-Drivy-issues-annulation-planification-ui-106`, racine exacte,
HEAD 5aa037ca, ready/watched, génération `2026-11-05T14:27:09Z`. `search_graph` sur
reveal/sameAnchor/descendants ; couverture du test metadata_match sans anomalie enregistrée.
Source et rapport Q9 relus ; conventions `XCTAttachment(string:)`/keepAlways existantes
de MessagingLatencyUITests vérifiées. Pas de réindexation générale ou index voisin.

Contrôles effectués, codes 0 :

- `git diff --check` ; diff des blobs hors deux chemins autorisés contre 5aa037ca vide.
- Comparaison de source par Python : retirer le hook et le helper diagnostiques restitue
  exactement le source de base (fins de lignes normalisées). Les expressions AX distantes,
  timeouts et borne `0..<10` gardent leurs occurrences ; aucune lecture interdite dans le helper.
- Revue des déclarations/appels : paramètres uniquement locaux, méthodes et fonctions locales
  dans le contexte MainActor existant ; même unwrap et message ; API d'attachement déjà utilisée
  par le dépôt. Aucun test automatique supplémentaire ni validation simulée du formateur.

## État de livraison et preuve restante

**NON COMPILÉ / NON EXÉCUTÉ Apple pour ce delta.** Aucun screenshot nouveau, GREEN Swift,
preuve VoiceOver physique ou verdict sur la cause historique. Commit local et commandes finales
consignés dans `artifacts/q9-anchor-capture/RAPPORT.md`. Aucun push, CI, rerun, merge,
déploiement, installation, dépendance ou autre fichier suivi modifié.

Après revue/intégration par le coordinateur, l'exécution ciblée doit soit retrouver le même
refus et conserver cette pièce avec ses totaux/troncatures, soit passer sans pièce : ce dernier
cas ne prouverait pas la cause du rouge historique. Seule une pièce complète permettra de
choisir une réparation fondée. L'iPad vert, le Set, les 25 s, les verdicts durables et la limite
de 20 gestes restent à préserver ; cette mesure n'autorise aucune correction automatique.
