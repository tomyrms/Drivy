# Préparation GPS d’une leçon scolaire

Le 24 septembre 2026 : entrée native dans Agenda → Leçon → Préparer le GPS. La feuille reçoit immédiatement un `SchoolCapturePreparationWorkspace` complet via `sheet(item:)`. Le moniteur désigné ou l’élève propre peuvent l’ouvrir ; ADMIN seul ne dispose pas de cette entrée. L’accès est relu avec `/me`, la leçon réelle et le dossier, puis `/me` de nouveau avant projection. Un changement de compte, école ou epoch masque le contenu et ferme la source de diagnostic.

## Parcours livré

- Notice réellement adoptée, conservation et contact ; choix courant AP152. L’entrée AP153 existante assure la relecture et la confirmation explicite, sans accord présélectionné.
- Diagnostic réservé au moniteur désigné d’une leçon planifiée. La permission OS et la mesure ponctuelle sont deux actions explicites. Ouvrir l’écran ne demande aucune permission et ne prend aucune position.
- AP190 reçoit les paramètres réellement relevés sur cet appareil. `freeBytes` est toujours `null` sur iOS ; ni la capacité locale ni les coordonnées du diagnostic ne sont transmises. `networkAvailable: true` est fixé après un aller-retour réussi de revalidation `/me` et leçon, pas à partir d’un statut inventé.
- La réponse serveur est relue avec AP191 avant son affichage comme diagnostic actuel. `NEEDS_CHECK`, `UNSUPPORTED` et `QUALIFIED` sont rendus tels que reçus ; les blocages ne sont pas fabriqués ni remplacés par une qualification client. L’expiration visible invalide la présentation « qualifié ».
- L’élève peut lire et choisir ; le diagnostic du téléphone du moniteur ne se fait pas sur son appareil. Aucun point de séance locale ni exemple n’est converti en capture scolaire.

## Commandes conservées

AP190 utilise le magasin SQLCipher spécialisé : `stage` → `markAttempted` → `send` → `acknowledge`. L’UUID et les octets restent identiques lors d’un renvoi. Un résultat validé est acquitté sous sa portée originale même si la feuille a été fermée ; il n’est pas reprojeté sous une autre portée. Toute erreur conserve la demande. Une demande sauvegardée sans accusé apparaît en attente ; aucune nouvelle demande de diagnostic n’est créée tant qu’elle n’est pas rapprochée.

« Vérifier auprès de l’école » commence par AP72. Seul un reçu correspondant permet le rejeu idempotent destiné à récupérer le résultat original et son accusé. « Reprendre cet envoi » demande une confirmation et conserve le diagnostic original, sans nouvelle mesure. Une ancienne portée reste visible, sans réaffectation ni renvoi. Un refus sans preuve reste conservé, conformément à la limite du journal existant.

## Raccord de collecte suivant

Ce lot n’émet **aucun AP154**, ne crée aucun segment et ne propose aucun bouton de départ. Le texte indique que le démarrage scolaire n’est pas encore disponible. Choix et diagnostic restent utilisables séparément.

Le futur callback proposé est `onCaptureAuthorized: @MainActor (SchoolCaptureTransferCoordinator, any SchoolCaptureLocationProviding, SchoolCaptureStoredSession, SchoolCaptureLease, SchoolCaptureAuthorization, ContinuousClock.Instant) async throws -> Void`. Il doit appeler le propriétaire app-level après autorisation durable, sans que la feuille garde la responsabilité de la source. `takeDiagnosticSourceForCapture()` transfère cette propriété avant tout `await` : la feuille abandonne sa référence, et sa fermeture ne modifie plus le delegate/`onEvent` de la source transférée. Le receveur doit arrêter la source s’il refuse ou échoue l’adoption.

Le verrou restant est le raccord à la session app-level qui conserve source et coordinateur local hors des feuilles, arrête l’admission synchroniquement aux changements de portée/lifecycle/refus et scelle durablement avant transfert. Le callback du choix doit alors fermer cette capture scolaire, et non seulement le diagnostic ponctuel comme dans ce lot. Aucun profil matériel n’est créé par cette UI ; une qualification physique reste nécessaire.

## Vérification

Contrôle statique des interfaces du transport, du journal, de la source et des routes serveur AP152/AP153/AP190/AP191 ; contrôle du diff. Aucun appel métier contre les comptes hébergés, aucune nouvelle donnée serveur et aucune campagne de tests. Compilation Apple, inspection native, permissions et comportement physique restent à qualifier après intégration.
