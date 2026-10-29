# #311 / R15 #326 : permis, programmes, compétences et règles

Famille reconstruite sur la branche `claude/311-catalogue` (base `d9c85479`). Nouveau code dans `apps/web/client/portal/formations/`, aperçu synthétique dans `portal/preview/families/catalogue.ts`. Aucun ancien rendu importé (garde de l'aperçu : `legacyPresentationImports: 0`), aucun fichier de l'ancienne console, backend, API, migration, Swift ou CI modifié. Fichiers partagés touchés : `portal/pages.tsx` (six sections enregistrées) et `portal/preview/families.ts` (un import).

## État ligne par ligne de l'inventaire

| Ligne | État | Ce qui est fait | Ce qui reste à qualifier |
| --- | --- | --- | --- |
| `formations.list` Catalogue des permis | Fait dans l'aperçu | Une ligne par permis (code, compétences, tarifs de leçon, élèves), badge seulement pour « À compléter » ou « Non proposée », recherche au-delà de 6 permis, état vide, erreur avec reprise. Le titre est porté par l'onglet du shell ; l'accès aux prestations reste l'onglet (la carte doublon est retirée). | Défilement et recherche avec une vraie liste de plus de 6 permis. |
| `formations.general` Fiche permis / programme | Fait | Lecture orientée usage : propositions, durée, prix d'une leçon lus depuis les tarifs, élèves sur version actuelle ou précédente, dernière modification. Éditeur Général (nom, nouvelles inscriptions, durée) en page entière, relecture des différences, confirmation. | Droits réels : seul le serveur décide, l'aperçu renvoie `canConfigureCatalog: true`. |
| `formations.competencies` Compétences | Fait | Lecture en liste numérotée. Éditeur : une ligne par compétence, une seule ouverte, menu Modifier / Monter / Descendre / Retirer, annonce vocale du déplacement, focus suivi. Relecture : ajoutées, retirées, reformulées, ordre modifié. Les clés des compétences reprises sont conservées, les nouvelles n'ont pas de clé. | Recette lecteur d'écran et clavier réelle. |
| `formations.rules` Déroulement et annulation | Fait | Lecteur confortable (68 caractères), sources en second niveau. Éditeur de deux textes + sources, exemple Drivy seulement si le champ est vide. Relecture avant / après par texte. | Rien de déduit juridiquement : le texte reste celui de l'école. |
| `formations.prepare` Préparer un permis | Entrée seulement | « Préparer un permis » (catalogue, fiche sans parcours, ancienne adresse `view=nouvelle`) appelle `navigate('apercu', { from: 'formations', category })`. | Le guide unique (#320) n'est pas reconstruit ici ; dans l'aperçu, `apercu` n'est pas servi et la navigation tombe sur la première page (comportement du socle). |
| `formations.history` Historique | Fait | Niveau secondaire (bouton « Historique »). Versions du programme (actuelle, non proposée, élèves), versions de chaque tarif, éléments non rattachés. Consultation en lecture seule, jamais de réécriture. | Plus de 100 versions : seul l'avertissement est affiché. |
| `formations.reference` Référence historique | Fait | Lecteur d'une version exacte (offre, compétences, règles, tarif) avec ses usages et un lien vers le parcours. Anciennes adresses `offres`, `referentiels`, `procedures` : la version désignée est retrouvée, une version actuelle ouvre sa rubrique, une ancienne ou partagée ouvre l'historique du permis. Référence inconnue : état « Référence introuvable ». | Liens profonds depuis l'application native. |
| `formations.reference-update` Mise à jour depuis la référence | Fait | Boîte de relecture : version de la référence et date des sources, couverture « à qualifier », compétences à ajouter, formulations différentes conservées (comparaison), collisions de noms qui suspendent l'ajout, évolution réglementaire jamais appliquée automatiquement. Envoie le programme complet : compétences de l'école dans leur ordre, puis seulement les clés absentes. Aucune certification déduite. | Contrôle côté serveur (`PROGRAMME_CUSTOMIZATION_PROTECTED`) vérifié seulement contre l'aperçu, qui reproduit la règle. |

## Décisions

- **Une seule section modifiée à la fois, en page entière.** Pendant l'édition, la fiche masque son en-tête, ses onglets et ses alertes ; l'annulation rend le focus au titre. Sur mobile, la barre d'action reste visible au-dessus de la navigation.
- **Lecture d'abord.** Aucune lecture n'est un formulaire. Les actions de rubrique (Modifier…) sont sur la rangée des onglets, sans titre répété.
- **Brouillons protégés.** L'état d'édition vit dans la rubrique montée ; changer de rubrique, de parcours ou de page passe par la garde de navigation (`registerUnsavedChanges`). Vérifié : « Quitter sans enregistrer ? » puis « Continuer la saisie » conserve la saisie.
- **Commandes.** Uniquement par `useCommandRunner` et le moteur existant (`saveFormationProgramme`). Aucun succès avant la confirmation durable. Refus : saisie conservée et erreur dans la relecture. Réponse perdue : la relecture se ferme pour laisser accessible « Vérifier le résultat » du panneau d'attente ; la confirmation par reçu ferme l'édition. Conflit (`FORMATION_CHANGED`, `VERSION_CONFLICT`) : la fiche est relue, la saisie est gardée et signalée, la version enregistrée entre-temps est consultable.
- **Parcours multiples.** Le sélecteur de parcours sert à consulter et modifier les parcours existants ; aucune création de variante (décision produit). Le parcours ouvert ne change plus de place après un enregistrement.
- **Parcours ancien sans prix de référence.** Signalé (« Prix de référence absent »), jamais présenté comme 0 ; l'enregistrement est refusé par le serveur, la saisie reste.

## Vérifications exécutées (dans `apps/web`)

- `tsc --noEmit` : sans erreur. `tsc -p tsconfig.check.json` : sans erreur.
- `vite build --config vite.preview-311.config.ts` : 3036 modules, `legacyPresentationImports: 0`.
- `vitest run` complet : 40 fichiers, 446 tests passés. Ciblé (`formations.test.ts`, `pricing.test.ts`, `formation-model`, `swiss-programme-update`, `console-route`) : 5 fichiers, 55 tests passés. 19 tests ajoutés : différences de compétences, règles et parcours, formatage (prix absent, durée, validité), routage des références.
- Parcours navigateur réel (Chromium, script hors dépôt) : 85 vérifications sur 85, plus 8 sur 8 pour la matrice d'écrans. Couvre lecture, édition, relecture, confirmation, état serveur après écriture (version 5, élèves existants conservés sur versions précédentes), référence (2 ajouts, 1 formulation conservée, puis « déjà complet »), historique, anciennes adresses, garde de navigation, scénarios Refus, Conflit de version et Réponse perdue (avec vérification par reçu), saisie caractère par caractère sans perte de focus.
- Captures 1440×900 et 390×844, clair et sombre : catalogue, fiche (Général, Compétences, Règles, Tarifs), historique, version consultée, prestations, conditions, permis A et BE, édition, relecture, refus. Examinées visuellement.
- Mesures mobile (390×844) : aucune cible interactive sous 44 px, aucun champ sous 16 px, aucun débordement horizontal ; seuls des champs masqués de Base UI (hors écran) sont signalés par la mesure.

## Reste à qualifier

Les données sont synthétiques et le réseau est intercepté : ni API réelle, ni droits réels, ni authentification ne sont qualifiés. Pas de recette clavier ou lecteur d'écran réelle, pas de calcul formel de contraste (jetons du socle). Le guide « Préparer un permis » appartient à #320. Aucune issue n'est close sur cette base.

## Demandes au socle

- Un emplacement d'actions dans la rangée d'onglets locale du shell (`portal-local-nav`) éviterait le portail React utilisé ici pour poser « Modifier… » sur la rangée d'onglets de la fiche.
- `Badge` : variantes de ton (avertissement, succès). Contournement : `data-tone` dans `formations.css`.
- `Tabs` : la variante « ligne » existe dans `tabs.tsx` mais n'a pas le rendu du shell ; recopiée en CSS de famille (comme Élèves).
- `Collapsible` : aucun indicateur d'ouverture ; chevron ajouté en CSS de famille.
- `Switch` : zone de 18 px ; la cible de 44 px vient de la ligne `Field`.
- `Dialog` : largeur fixe à 560 px ; surchargée par `cat-dialog` pour les relectures de textes.
