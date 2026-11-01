# Pilotage : restes de la passe #397 (issue #400)

1er novembre 2026, branche `claude/pilotage-400-restes`, base `master` `d4257f07`. Web seulement : aucune modification d'API, de contrat OpenAPI, de migration, de calcul ni de droit. Suite de [pilotage-397-ux.md](pilotage-397-ux.md), sections 7 et 8.

## 1. Défauts corrigés

- **Aide des libellés longs** (`components.tsx`, `pilotage.css`) : le libellé est coupé avant son dernier mot, et ce dernier mot porte l'icône « Comment ce chiffre est calculé » dans un conteneur sans retour à la ligne (`pilotage-row-tail`). Sur un téléphone, l'icône reste collée au dernier mot (« Heures réalisées (durées connues) », « Total attendu selon le planning ») au lieu de passer seule sous le libellé. Le nom accessible du bouton d'aide est inchangé.
- **Filtres de Statistiques** (`components.tsx`, `pilotage.css`) : Période et Moniteur restent visibles. Permis et prestation passent en second niveau derrière un bouton « Permis et prestation » (ou « Permis » / « Prestation » seul quand le catalogue n'en propose qu'un), `aria-expanded` et `aria-controls`, avec le nombre de filtres actifs en pastille et une annonce « filtre actif » pour les lecteurs d'écran. Ouvert d'office quand l'adresse porte déjà un permis ou une prestation, pour qu'un lien partagé ne cache jamais le filtre qu'il applique. Sur un écran large, le bouton n'existe pas et les quatre filtres restent sur une ligne (`display: contents`). Aucune valeur n'est tronquée : les listes gardent leur largeur pleine sur téléphone.
- **Mois sans donnée** (`measure-format.ts`) : `describeComparison` ne rend plus rien quand la valeur et la base valent zéro. La ligne garde sa valeur sans « 0 vs le 1er octobre ». La règle de comparaison du serveur est inchangée, seul l'affichage se tait. Une valeur égale non nulle garde son « 0 % », et une base nulle avec une valeur positive garde son « +3 ».

## 2. Ajouts liés aux vérifications

- **Mois sans droit financier** (`pilotage.css`) : le relevé du mois utilisait `auto-fit`, qui étire l'unique colonne restante sur toute la largeur quand « Finances du mois » est absent. Passé en `auto-fill` : la colonne d'activité garde sa demi-largeur, comme avec les deux relevés.
- **Aperçu synthétique** (`access-preview.tsx`) : `?droits=activite` ouvre l'aperçu comme un moniteur qui a le droit d'activité sans l'administration, sans le droit financier et sans l'export. C'est un moyen de regarder la vue, pas un contrôle d'accès : le serveur relit les droits.
- **Contraste accru** (`pilotage.css`) : il n'y avait aucune règle `prefers-contrast: more` dans Pilotage (seulement `forced-colors`), contrairement à ce que laissait entendre l'issue. Ajout d'un bloc qui donne aux filets décoratifs (relevé, listes, jours, graphiques, onglets) et aux axes la couleur de contrôle `--input`, lisible à 3:1, et un contour à la barre de répartition. Le mouvement du chevron des filtres est coupé avec `prefers-reduced-motion`.

## 3. Non exécuté

Aucun test, aucun typage, aucune capture n'a été lancé pour ce lot, à la demande du porteur. À qualifier à son ordre : typage et tests web (dont un test du libellé coupé et du bouton de filtres), captures à 390 px et 1440 px, clair et sombre, `?droits=activite`, `prefers-contrast: more` et `forced-colors` émulés dans Edge.

Les vérifications de l'issue qui exigent un tiers restent ouvertes : parcours authentifié en production avec une vraie école, lecteur d'écran réel (NVDA, VoiceOver), appareil physique et texte agrandi par le système. Le jugement à l'œil du porteur (relevé, signe + et filet de total, « Finances du mois » à côté de « Ce mois-ci », contrôle segmenté) lui revient.
