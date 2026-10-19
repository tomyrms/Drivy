# V3 : recette iOS à exécuter sur environnement Apple

18 octobre 2026. **Aucun parcours ci-dessous n'a été exécuté sur iPhone, iPad, simulateur ou runner Apple pendant V3.** Le poste est Windows. `xcodebuild`, `xcrun`, `swift` et `idevice_id` sont absents. Des workflows Apple existent dans le dépôt, mais leur présence n'est pas une exécution. Aucun workflow distant n'a été déclenché.

Les agents 03 à 07 ont relu les chemins et tests existants sans modifier Swift. Aucun nouveau bug natif n'est confirmé. Les tests API utilisant les contrats du client Swift ne remplacent pas une recette native.

## Protocole

Sur une école de test, noter commit, appareil, version iOS, version Xcode, réseau, thème et taille de texte. Utiliser deux comptes autorisés et un compte révoqué. Conserver captures et résultats sans secret ni trajet privé. Chaque ligne est **NON EXÉCUTÉE** et doit recevoir un résultat observé et une preuve avant de devenir PASS/FAIL.

| Domaine | Scénario à exécuter | Résultat à vérifier |
|---|---|---|
| Authentification | Connexion OIDC et retour dans l'app | Session autorisée après échange et stockage durable |
| Authentification | Déconnexion puis requête protégée | Données privées masquées, refresh tardif rejeté |
| Invitation | Lien valide, invalide, expiré, mauvais compte | Rattachement au bon périmètre ou refus explicite |
| Comptes | Basculer entre comptes et écoles | Aucun cache, brouillon, outbox ou dossier d'un autre compte exposé |
| Expiration | Session expirée pendant lecture et écriture | Reconnexion explicite, aucun faux succès ni doublon |
| Autorisations | Retrait d'accès pendant une feuille | Action refusée, retour à une destination autorisée |
| Leçon | Planifier avec élève, moniteur et créneau | Réservation durable, tarif et version corrects |
| Leçon | Modifier un créneau puis conflit concurrent | Horaire confirmé ou conflit explicite, saisie préservée |
| Leçon | Annuler avec motif et rejouer la demande | Annulation durable, opération idempotente |
| Leçon | Démarrer une leçon planifiée | Bonne leçon, état démarré après confirmation |
| Leçon | Démarrer spontanément, double action rapide | Une seule leçon créée, conflit expliqué |
| Leçon | Terminer, y compris après panne réseau | Temps réels conservés, état durable avant succès |
| Bilan | Saisir, enregistrer, rouvrir, corriger | Texte et compétences conservés, reprise après erreur |
| Historique | Consulter, rechercher, paginer, changer de mois | Ordre, fuseau et états cohérents |
| GPS | Première autorisation et acquisition | Aucun point avant permission et geste explicite |
| GPS | Permission refusée puis révoquée en cours | Leçon utilisable sans GPS, arrêt du collecteur, rupture visible |
| GPS | Perte puis retour du signal | Pas de point inventé, lacunes et segments explicites |
| GPS | Verrouillage et arrière-plan deux minutes | Politique native respectée, pas de collecte non autorisée |
| GPS | Retour premier plan après changement de permission | Permissions et droit relus, pas de double capture |
| GPS | Arrêt forcé puis relance | Faits durables conservés, reprise ou scellement cohérent |
| GPS | Enregistrer puis revoir trajet et observations | Bon trajet, chronologie et ancrages, absence d'interpolation inventée |
| Navigation | Aujourd'hui, Agenda, Élèves, dossier, leçon | Origine, sélection et période compréhensibles |
| Navigation | Bilan et retour par plusieurs origines | Pas de pile concurrente ni perte de brouillon |
| Modales | Ouvrir, fermer, annuler, confirmer, fermeture interactive | Une feuille dominante, protections d'écriture cohérentes |
| Formulaires | Clavier, Retour, Échap, rotation, iPad | Champs et actions accessibles, focus restauré |
| VoiceOver | Onglets, formulaires, carte, pause/reprise/fin | Noms, ordre, états et annonces appropriés |
| VoiceOver | Observation inline puis fermeture | Isolation et retour de focus au déclencheur |
| Dynamic Type | Taille standard puis accessibility3 et maximum | Pas de texte perdu ni commande inaccessible |
| Ergonomie | Cibles tactiles, contraste clair/sombre | Mesures et usage effectif, pas seulement lecture des tokens |
| États | Loading, empty, error et offline sur chaque écran clé | Message local, reprise utile, aucun résultat inventé |
| Animation | Réduire les animations, transitions, lancement et GPS | Politique de mouvement cohérente, pas de gêne observée |
| Performance | Instruments sur lancement, listes, carte et replay | Hitches, thread principal, allocations et mémoire mesurés |

## Mesures natives reportées

Comparer au minimum vingt répétitions du même parcours, mêmes données et appareil, avant toute optimisation de transitions ou calcul GPS. Consigner médiane, p95, hitches et mémoire. L'écart statique entre certaines animations brutes et DrivyMotion est une piste de convention, pas un défaut de fluidité démontré. Les éventuels gains iOS sont **non mesurés**.

## Décision de livraison

V3 ne contient aucun changement Swift. Une fusion limitée au web/API peut être examinée séparément. Ne pas annoncer une release iOS entièrement qualifiée avant cette recette, notamment permissions GPS, arrière-plan, VoiceOver et Dynamic Type.
