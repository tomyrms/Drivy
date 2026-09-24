# Roadmap : décisions et critères par tranche

> Drivy · Référence de conception 3.14 · 20 septembre 2026. [Mandat de refonte](../COMMENCER_ICI.md). Les gates ci-dessous sont des critères de sortie, pas des résultats acquis ni des dates promises.

<a id="gates-de-non-régression-v31"></a>
<a id="gates-de-non-régression-v32"></a>
<a id="intégration-des-gates-mobile-et-qualité-v34"></a>
<a id="non-régression-swift-v34"></a>
<a id="compléments-et-non-régression-v35"></a>
<a id="compléments-de-recette-v36"></a>
<a id="dépendances-corrigées-v37"></a>
<a id="non-régression-visuelle-v39-dans-les-tranches-existantes"></a>
<a id="conditions-ajoutées-par-la-revue-v310"></a>
## Trois périmètres distincts

**Incrément interne :** G0 puis le chemin G1/G2 qui permet une leçon avec observations et bilan, avec jeux fictifs. **Pilote complet visé :** G1 à G4, puis conditions G5 ; web de gestion, tablette, onboarding, catalogue et cours collectifs restent inclus. **Extensions :** Android après décision de lancement propre, et capacités U explicitement différées. Une étape interne n’est pas un prétexte pour retirer les fonctions demandées du pilote complet.

Le [registre de périmètre logique](perimetre-premiere-livraison.md) donne le premier usage de chaque objet décrit. Il ne transforme pas un DTO ou une projection en table. Avant d’implémenter un objet, rattacher sa création à une commande et sa lecture à un parcours de la tranche ; expliquer sa durée de vie, ses droits et ses tests. Aucun ajout d’entité pour une hypothétique plateforme future seule.

<a id="dm07"></a>
## DM07 · Budgets non fonctionnels et preuves de qualité

Les performances, l’autonomie, la reprise et la capacité ne sont pas déclarées satisfaisantes simplement parce que le parcours fonctionne. **Avant de mesurer, fixer une cible provisoire et son environnement de mesure** ; après mesure, conserver cible, résultat, appareil/build, jeu de données, percentile ou méthode, et décision. Une cible modifiée après observation doit garder l’ancienne valeur et sa justification.

| Domaine | Gate concernée | Mesure minimale à obtenir avant fermeture |
|---|---|---|
| Démarrage et navigation Apple | G0/G1 | ouverture à froid/chaud, transition des écrans prioritaires, mémoire et absence de blocage perceptible sur appareils pilotes |
| Capture GPS | G0/G2 | continuité, précision utile, consommation batterie, chauffe, stockage par durée de séance, comportement écran verrouillé/interruption |
| Saisie live et bilan | G0/G2 | temps entre action et persistance locale, reprise après fermeture/interruption, charge de relecture et erreurs d’usage observées |
| Synchronisation | G1/G2 | reprise après perte réseau, backlog, doublons, conflits, temps de convergence et purge après révocation |
| API et planning | G1–G3 | latence des commandes/lectures prioritaires sous jeu représentatif et concurrence de réservation |
| Fichiers/exports | G1/G4 | temps, mémoire et limites de traitement sur tailles autorisées ; échec fermé sur dépassement |
| Sauvegarde/restauration | G4/G5 | restauration isolée, cohérence base/objets, tombstones et durée observée par rapport aux objectifs approuvés |
| Accessibilité et rendu | G0–G5 | Dynamic Type/grand texte, VoiceOver/clavier selon client, contraste, rotation/fenêtrage et erreurs sans couleur seule |

**Règle de gate :** l’absence de seuil approuvé ou de mesure requise vaut `NOT_QUALIFIED`, pas `PASSED`. Les objectifs d’exploitation proposés dans [déploiement](deploiement-exploitation.md) restent des budgets à approuver, non des performances déjà obtenues. Cette matrice ferme le trou documentaire « performance à mesurer » sans inventer de chiffres avant prototype.



<a id="definition-ready"></a>
## Définition d’une tranche prête à développer

Une tranche G1/G2 est **READY** uniquement si les six éléments suivants sont identifiés avant création de migrations ou d’écrans :

1. **Action et utilisateur** : commande ou consultation réelle, rôle concerné et résultat observable.
2. **Source de vérité** : donnée autoritaire, invariants, unicités et propriétaire scolaire/global.
3. **Échec et concurrence** : comportement hors ligne, reprise, doublon, conflit et perte de droits.
4. **Persistance minimale** : objets indépendants justifiés ; projections/DTO/sous-objets ne deviennent pas des tables par défaut.
5. **Contrat et UI** : opération/API ou lecture locale nécessaire, état vide/chargement/erreur, accessibilité pertinente.
6. **Preuve attendue** : scénarios T/MOB/UX associés et mesure DM07 si la qualité concernée peut bloquer la gate.

Une tranche qui ne remplit pas ces conditions reste **NOT_READY**. Le but n’est pas d’écrire davantage de spécification, mais d’empêcher une implémentation horizontale où toutes les entités, routes ou vues sont créées avant qu’un parcours n’en ait besoin.

## G0 · Lever les risques avant d’étendre le produit

**Inclure :** prototype Swift iPhone/iPad de capture volontaire, refus GPS et diagnostic matériel ; capture interrompue, arrêt local, données de mauvaise précision, journal chiffré et reprise. Étudier la portabilité des contrats sans chantier Android obligatoire. Prototype de saisie pendant la leçon : repère, thème/statut à l’arrêt adapté, récupération au bilan. Aucune conclusion de sécurité en mouvement à partir de la simplicité d’un bouton.

**Sortie :** matériel/OS/build exacts, mesures et traces de prototype, dépendances choisies, risque de perte/consommation établi, retours exploratoires documentés. MOB041–MOB044 et MOB053–MOB056 selon capacité ; critères natifs et [protocole terrain](../01-recherche/vision-perimetre.md#validation-produit). Les mesures de capture n’ouvrent pas l’accès aux données réelles avant politiques/permissions applicables.

## G1 · Identité, école et entrée utilisable

**Inclure :** F01/F02/F03/F09/F13/F20/F21, catalogue minimal utile ; web authentifié et app native adaptative. Provision contrôlée, scopes, dernier ADMIN, invitation web→app sans doublon, formation demandée puis validée, documents privés et photos facultatives. Entrée Compte accessible sans école ; suppression globale conçue dès cette frontière d’identité, non confondue avec archivage. Le parcours mineur doit être qualifié avant son ouverture, sans inventer un accès parental automatique.

**Sortie :** activation/profils/droits/configuration applicables de T001–T012, T163–T187, T190–T191, T233–T235, T239–T242, T259 ; T283 pour permissions effectivement présentes. Reprise de formulaires et variante de rôle correctes (UX21–UX32 selon écran). Préférences initiales, langue de secours et absence de choix GPS précoché. T383–T396/T403 pour dépôt/scellement/droits ; T404 dès l’apparition des routes de lecture. MOB041–MOB052 pour session/liens/client HTTP, et MOB057–MOB060 lorsque le push est activé. T188–T189 attendent G3.

**Hors périmètre de G1 :** provision SaaS publique, paiement de l’abonnement Drivy, formulaire arbitraire. L’absence de facturation automatisée n’exonère pas de définir l’hypothèse commerciale.

## G2 · Une leçon, ses observations et son bilan

**Inclure :** F04–F12/F15/F16, consommations simples F17. Planifier sur web/app, préparer les repères, retrouver la séance sur iPad, capturer ou continuer sans GPS, conserver des observations avant clôture, constater, revoir et publier. Une panne réseau n’efface pas une saisie acquittée. Les modalités de démarrage GPS totalement hors ligne restent une décision distincte, non changée par l’ajout d’observations hors ligne.

**Sortie métier :** planning/concurrence et clôture T013–T113 selon capacité ; T192–T199 et T246–T253 pour capture/publication ; T258 et les variantes disponibles de T272, T278–T284. Les tests T285–T382 s’appliquent à la première capacité correspondante : refus GPS, repères privés, bilan sans trace, segments vides, provenance et callbacks. R46 exige T407–T422 : hors ligne, absence de point, idempotence, rattachement concurrent, version périmée, arrivée après publication, isolement et retrait des données. Aucun niveau de compétence automatiquement calculé depuis les observations.

**Sortie native :** qualification de capture/replay sur iPhone/iPad, rotation, arrêt, persistance et interruption ; T397/T405–T406, MOB061–MOB068 pour capacités déjà livrées (exports attendent G4). La couverture de scène n’arrête pas le GPS. UX21–UX32 : bilan complet, retrait du niveau, temps du replay et reprise de capture. La galerie ne valide aucun de ces comportements natifs.

## G3 · Offres, packs et cours collectifs

**Inclure :** F17/F18/F19, séries multi-dates, offre distincte d’engagement, inscription volontaire, dernière place transactionnelle, présences et validation d’exigences. Packs composites, options d’achat, remise de service et régularisation. Accès élève web personnel sans installation imposée. Ni liste d’attente, ni rattrapage autonome, ni tarif recompté à la consommation.

**Sortie :** T114–T162, T188–T189, T243–T245, T256–T257 ; T261–T263 et T265–T278 applicables aux packs/cours/finance ; T282 pour options et variantes transactionnelles T283. Scénarios T285–T382 concernés : langue et préférences de notification, droits/services, preuves et invalidations, correction tardive AP201/R109. Profil réglementaire, conditions commerciales et règles de présence approuvés avant activation réelle. Résultat d’inscription inconnu maintenu en attente (UX). Push non livré n’empêche pas le centre interne utilisable.

## G4 · Gestion durable, données et indicateurs

**Inclure :** F14/F22/F23 : archives/restauration, lots bornés, délégations, métriques définies et exports. Exécuter le parcours global E49/J29/AP193–AP198 : pages d’aperçu, décision explicite, dernier ADMIN et suivi. La possibilité de demander la suppression n’est pas repoussée à une école active.

**Sortie :** T200–T232, T236–T238, T254–T255, T260 ; T264, purge T280 et procédures globales T285–T382 selon registre. T398–T402 pour octets d’export, portée et droits modifiés ; T404/MOB068 dès accès aux exports. Restauration et tombstones testés, sélection/focus/filtres conservés dans la gestion, rétentions de preuves et journaux appliquées. Les politiques d’expiration, nettoyage et budgets de décodeur sont approuvées, pas inventées par une maquette.

## G5 · Pilote réel contrôlé puis élargissement

**Préconditions :** capacités annoncées réellement implémentées et testées ; écoles volontaires identifiées ; notice, responsabilités, fournisseurs, mineurs et conservation qualifiés ; suppression globale et continuité dernier ADMIN éprouvées ; restauration, appareil perdu, incident et assistance testés. DM06 bloque cette sortie tant que ses procédures manquent, même si le contrat existe.

Observer utilité de l’observation au moment de la leçon, charge de relecture, compréhension des offres et du partage, accès sur tablette et effort d’onboarding. Aucun objectif de taux d’acceptation GPS. Commencer avec données nouvelles ou migration approuvée M0/M1/M2. Aucun résultat utilisateur ni calendrier n’est affirmé dans ce dossier.

## GA0 · Android, chantier indépendant

Démarrer lorsque les ressources Android sont engagées : connexion, leçon, carte, collecte native bornée, arrêt et persistance sur téléphone/tablette. Kotlin/Compose reste une recommandation à approuver, pas un changement de choix Apple. SDK/OS/build et essais propres obligatoires avant promesse de support. Une compilation Swift ou une galerie HTML ne qualifie pas Android. L’ajout de cette cible ne conditionne pas implicitement G0 Apple.

## Estimation et pilotage de charge

Aucune estimation de charge fiable n’a été produite à partir du dépôt ou d’un prototype mesuré. Le nombre de mots, de schémas ou d’objets logiques ne permet pas de déduire des années-personnes. **Ce manque reste ouvert**, au lieu d’être remplacé par un chiffre non dérivé.

Pour chaque tranche, le développeur renseigne : tâches et dépendances, travail réutilisable effectivement testé, charge optimiste/probable/pessimiste, capacité hebdomadaire disponible, risques de capteurs/fournisseurs et effort de recette. Calibrer les fourchettes après G0 et la première tranche intégrée. Une estimation agrégée doit afficher ses hypothèses et être révisée après observation ; elle n’est pas un calendrier garanti.

## Définition d’un incrément terminé (DONE)

Parcours utilisable + permissions serveur + états vide/erreur/hors ligne + contrats/migrations + tests réels + journaux minimisés + reprise et assistance. Pas de faux boutons, de compteurs de démonstration dans la production ou de succès affiché avant persistance/commit. Les scénarios T/MOB restent NOT_EXECUTED tant que leurs preuves produit ne sont pas jointes.

## Extensions explicitement différées

[U01–U13 et X01–X05](../03-fonctionnel/extensions.md). Chat, encaissement en ligne, comptabilité fiscale, réservation individuelle autonome, liste d’attente, rattrapage autonome, BI avancée, relais GPS entre appareils. Cela ne reporte pas les cours, le web, les tablettes ou l’onboarding déjà inclus au pilote. Les notes d’aptitude déduites du GPS restent exclues, non simplement reportées.
