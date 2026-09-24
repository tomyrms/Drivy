# Wireframes documentaires du cœur GPS et des cours

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

**Référence visuelle actuelle :** [application unifiée](../DESIGN/APPLICATION.html) et [carte](../DESIGN/LECON.html). Ces schémas restent des descriptions fonctionnelles ; les nouveaux rendus et composants priment pour les variantes déjà reprises, selon la [matrice de couverture](../DESIGN/couverture-ecrans.json).

Ces compositions sont des schémas textuels de conception, pas des captures de Drivy ni une application développée. Personnes, horaires et soldes sont fictifs. Les états et actions exacts sont décrits dans [E01–E31](ecrans.md). La direction A, Cartographie native, est choisie par le porteur ; voir le [dossier design](../DESIGN/README.md).

**Parcours carte central :** depuis la séance, le moniteur ouvre « Signaler », choisit un thème puis un statut explicitement enregistrable. Le moment et l’ancre candidate sont ceux de l’ouverture ; rien n’est créé à l’annulation. Les repères sont retrouvables dans le replay privé et repris au bilan après sélection, sans publication ni note automatique. Les détails de [E23/E24](ecrans.md#e23) et de [R46](../03-fonctionnel/regles-etats.md#r46) prévalent sur les schémas anciens plus généraux. Pas de bouton photo live ni de remplacement par une saisie uniquement après la leçon.

## E22 : avant une leçon

```text
┌────────────────────────────────────────┐
│ École Exemple             Notifications│
│ Séance                                 │
│ Lucas · Permis B                        │
│ Aujourd’hui 14:00–14:45 · Gare          │
│                                        │
│ Objectifs                              │
│ Anticiper les intersections             │
│ Reprendre le dernier giratoire          │
│                                        │
│ Enregistrement du trajet                │
│ Information et choix de l’élève    Voir │
│ [ Commencer avec enregistrement ]       │
│ [ Commencer sans enregistrement ]       │
│                                        │
│ Séance   Agenda   Élèves   École        │
└────────────────────────────────────────┘
```

L’absence de permission ne grise pas toute la séance. Aucune capture ne démarre à l’heure du rendez-vous. Le choix est explicite ; le consentement système n’est pas substitué au choix métier.

## E23 : capture dans le contexte de séance

```text
┌────────────────────────────────────────┐
│ Fermer      Lucas · B                   │
│ Enregistrement en cours                │
│ ┌────────────────────────────────────┐ │
│ │                                    │ │
│ │          CARTE DE LA SÉANCE         │ │
│ │       segments réellement acquis  │ │
│ │                                    │ │
│ └────────────────────────────────────┘ │
│ Temps de séance 22:10                  │
│ Trajet disponible 19:42 · Partiel      │
│ Points sauvegardés sur cet appareil    │
│ [ Pause ]              [ Arrêter ]     │
└────────────────────────────────────────┘
```

Les commandes sont préparées avant le départ et utilisées à l’arrêt. Fermer une vue n’est pas arrêter silencieusement ni laisser tourner sans indication : une capture active garde son accès visible et demande un choix explicite de retour/arrêt.

## E24 : revoir et expliquer

```text
┌────────────────────────────────────────┐
│ Retour      Leçon du 5 octobre          │
│ Trajet partiel · 1 interruption         │
│ ┌────────────────────────────────────┐ │
│ │ CARTE   · observation sélectionnée │ │
│ │        [Recentrer]                 │ │
│ └────────────────────────────────────┘ │
│ 00:00 ━━━━━●━━━━  lacune  ━━━━━ 41:12   │
│ [Lire]    x1       Instant 12:38        │
│                                        │
│ Intersection · passage de 12:38        │
│ Anticipation à travailler              │
│ Commentaire du moniteur                │
│ Prochaine étape                        │
│ Refaire cette approche                 │
└────────────────────────────────────────┘
```

Deux passages au même lieu restent distingués. Le zoom manuel désactive le suivi caméra, pas la lecture. Les observations non publiées ne sont pas présentées à l’élève.

## E25 : calendrier élève, rien d’automatique

```text
┌────────────────────────────────────────┐
│ Agenda                Octobre 2026      │
│ [Mes rendez-vous] [Cours disponibles ✓] │
│                                        │
│ Lundi 5                                │
│ ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │
│ ┃ 14:00 Conduite · Confirmée          ┃ │
│ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │
│ ┌ - - - - - - - - - - - - - - - - - ┐ │
│   18:00 Sensibilisation · Bloc 1       │
│   Disponible · NON INSCRIT · 3 places │
│ └ - - - - - - - - - - - - - - - - - ┘ │
│ Mardi 6                                │
│   18:00 Sensibilisation · Bloc 2       │
│   Même série · NON INSCRIT             │
│                                        │
│ Mes leçons     Agenda     Mon parcours │
└────────────────────────────────────────┘
```

Le cours disponible ne bloque pas le calendrier personnel. Le nombre de places affiché est indicatif jusqu’à confirmation du serveur.

## E26 : inscription à une série complète

```text
┌────────────────────────────────────────┐
│ Retour          Sensibilisation        │
│ École Exemple · Salle principale       │
│                                        │
│ Toutes les dates du cours              │
│ 5 octobre   18:00–20:00   Bloc 1       │
│ 6 octobre   18:00–20:00   Bloc 2       │
│ 8 octobre   18:00–20:00   Bloc 3       │
│ 9 octobre   18:00–20:00   Bloc 4       │
│                                        │
│ 3 places disponibles                   │
│ Couvert par votre pack                 │
│ 1 droit sera réservé, pas encore utilisé│
│ Conditions d’annulation           Voir │
│                                        │
│ [ S’inscrire à toutes ces dates ]      │
└────────────────────────────────────────┘
```

Ces dates sont un exemple fictif de structure, pas l’annonce d’un cours réel de Luc’s. La dernière place peut être prise pendant la consultation ; l’erreur laisse droits et calendrier inchangés.

## E26 : cours plein et confirmation

```text
Plein                                 Confirmé
───────────────────────────           ──────────────────────────
Sensibilisation                       Inscription confirmée
COMPLET                               Vous disposez d’une place
Aucune place disponible               Pour les 4 dates indiquées
[S’inscrire : désactivé]               [Voir dans mon agenda]
Aucune inscription créée              Droit du pack : réservé
```

Pas de liste des autres participants, pas d’attente ni de débit implicites. Les notifications de confirmation restent distinctes de l’annonce de disponibilité.

## E28 : formateur et présences

```text
┌──────────────────────────────────────────────────────┐
│ Sensibilisation · Bloc 2 · 6 octobre                  │
│ 9 inscrits / capacité approuvée                       │
│ Élève       Inscription       Présence de ce bloc     │
│ Lucas       Confirmée         [Présent ▼]             │
│ Ana         Confirmée         [Absent ▼]              │
│ Sam         À reconfirmer     [Non renseigné ▼]       │
│                                                      │
│ [Enregistrer les présences]                          │
│ Accomplissement du cours : validation séparée         │
└──────────────────────────────────────────────────────┘
```

Les données sont réservées au personnel habilité. Le tableau ne donne aucun droit d’accès aux trajets GPS des inscrits.

## E30 : achat composite

```text
Mon pack
Conduite 45 minutes    7 disponibles · 1 réservée · 2 utilisées
Sensibilisation       1 droit réservé · présence à renseigner
Examen                1 disponible
Paiement du pack      Réglé
[Voir les conditions et les mouvements]
```

Les chiffres sont fictifs. Les solde et paiement proviennent de deux registres liés, pas d’un booléen unique.

## E31 : dates modifiées

```text
Votre cours change de date
Ancien bloc 3 : 8 octobre 18:00–20:00
Nouveau bloc 3 : 12 octobre 18:00–20:00
Votre place reste réservée pendant votre réponse.
[Accepter ces dates]    [Demander une annulation]
```

Le moteur vérifie préalablement les conflits internes à l’école. Une absence de réponse ne supprime pas automatiquement la place. Les états de confirmation, disponibilité et reconfirmation restent textuels et accessibles.

## V3 · Tablette, séance préparée puis captation

```text
DRIVY   École choisie           Élève / permis B       État : enregistrement actif
┌─────────────────────────────────────┬───────────────────────────────┐
│                                     │ Séance de 45 minutes          │
│  CARTE DU TRAJET                     │ Objectifs préparés            │
│  position / segments réels           │ · Anticiper aux giratoires    │
│  pas de précision inventée           │ · Préparer les insertions     │
│                                     │                               │
│                                     │ Qualité du signal : à jour    │
│                                     │ [Pause] [Arrêter]              │
└─────────────────────────────────────┴───────────────────────────────┘
  Commentaires détaillés à l’arrêt ou après la séance.
```

Sur fenêtre étroite : la carte reste prioritaire ; un panneau repliable rend objectifs et commandes accessibles. Le service de capture ne dépend pas du composant de carte. Appareil non qualifié : même préparation, action Commencer sans enregistrement, pas fausse capture.

## V3 · Workspace élèves

```text
Drivy / École       [Changer d’école]                 [Compte]
Vue d’ensemble  │ Élèves                [Inviter] [Exporter selon droits]
Agenda          │ [Rechercher] [Actifs ▾] [Formation ▾] [Moniteur ▾]
Élèves          │ □ Nom          Formation   Référent   Prochaine action
Cours           │ □ Élève A      B           Moniteur   Pièce à vérifier
Offres et packs │ □ Élève B      A / B       Moniteur   Aucune
Activité        │
Paramètres      │ 2 sélectionnés  [Vérifier avant archivage]
```

Les valeurs sont fictives. Le détail administratif n’inclut pas automatiquement la lecture pédagogique privée. Les actions de lot ouvrent une preview avant toute mutation.

## V3 · Onboarding élève

```text
Votre dossier chez [École]                 Étape 1 sur 3 utiles maintenant
Identité
Prénom [                     ]  Nom [                         ]
Photo de profil (facultatif)       [Ajouter] [Passer]

Coordonnée demandée pour cette action
[Téléphone, seulement si la politique justifiée le nécessite]
Pourquoi ? [Finalité et destinataires]

[Retour]                   [Enregistrer et continuer]
Dernière sauvegarde confirmée : ...
```

La naissance/adresse apparaît seulement au stade et pour la finalité requis. Un écran expliquant le GPS ne demande pas de signer l’autorisation de toutes les futures leçons.

## V3 · Activation école

```text
Configuration de votre école               [Reprendre plus tard]
1 Identité  2 Organisation  3 Permis/offres  4 Données  5 Vérification

Prêt pour le bureau : oui
Prêt pour planifier : offre B et moniteur confirmés
Prêt pour enregistrer : appareil à préparer lors du premier usage
Cours collectifs : non utilisé actuellement

[Revoir un réglage]          [Activer l’espace]
```

La préparation du matériel de chaque moniteur est séparée de l’activation du workspace. Les capacités affichées sont calculées par le serveur.

## V3 · Archive et indicateurs

```text
Archiver 3 dossiers
Élève A : prêt ; historique consultable tant que l’accès reste actif
Élève B : bloqué ; cours futur à résoudre [Ouvrir]
Élève C : prêt ; 2 droits non réservés conservés [Voir conditions]
[Annuler]   [Confirmer les 2 dossiers éligibles et avertissements]

Activité : septembre   Scope : école   Calculé à ...
Séances réalisées : 3           Durée réelle renseignée : 185 min
Élèves accompagnés : 2          Places séries à venir : 9/20 = 45 %
Encaissements enregistrés nets : 1 470 CHF (journal, pas bénéfice)
[Définitions] [Voir données manquantes] [Export autorisé]
```

Ces chiffres sont la fixture fictive de F23 et non les statistiques d’une vraie école.

## Maquettes de la direction retenue

Ces wireframes décrivent encore les structures. La référence visuelle courante est maintenant le [dossier DESIGN](../DESIGN/README.md), avec [maquettes HTML](../DESIGN/MAQUETTES.html) et captures. Les règles de ce fichier ne prouvent pas une validation native ; les dessins du prototype ne remplacent pas les états métier.
