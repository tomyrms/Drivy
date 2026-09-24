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

Sans contrôleur injecté, ce parcours n’émet aucun AP154 et ne propose aucun bouton de départ. Choix et diagnostic restent utilisables séparément. `SchoolAgendaView(client:workspace:captureController:)` accepte un contrôleur facultatif, `nil` par défaut ; il est créé et conservé par la racine, jamais par une feuille.

Avec ce contrôleur, le provider `journalProvider: @MainActor () async throws -> SQLCipherSchoolCaptureStore` utilise `controller.journal()`, donc le même journal et la récupération unique de lancement. La préparation ne récupère jamais elle-même un journal contenant une collecte active. Le bouton de départ n’apparaît qu’avec les callbacks d’adoption et de refus raccordés. Il exige un diagnostic courant `QUALIFIED`, un accord lié à la notice actuelle, un appareil disponible et aucune commande conflictuelle.

La feuille de départ est un instantané en lecture seule : élève, horaire/fuseau, rendez-vous, choix, notice et diagnostic. Sa confirmation est décochée. Avant AP154, ces faits sont relus et comparés, les droits de moniteur désigné, l’école active avec GPS et la permission système sont vérifiés. La commande est gravée avant émission avec If-Match de la leçon. Une reprise garde UUID, corps et version d’origine ; si les faits diffèrent, elle reste conservée et n’autorise aucun départ. AP72 ne démarre rien automatiquement.

La vérification d’une demande AP154 conservée relit AP72 et AP155. Si l’autorisation est terminale, elle récupère le résultat idempotent puis l’acquitte durablement, sans installer de bail. Si elle est encore autorisée mais que les préconditions du départ ont expiré ou changé, la demande reste visible ; elle n’est ni effacée ni réécrite. L’abandon explicite d’une autorisation encore active sans collecteur local nécessite un raccord dédié au journal, non livré dans cette préparation.

Le type `SchoolCaptureStartHandler` est `@MainActor (SchoolCaptureTransferCoordinator, any SchoolCaptureLocationProviding, SchoolCaptureStoredSession, SchoolCaptureLease, SchoolCaptureAuthorization, ContinuousClock.Instant) async throws -> Void`. Après AP154 contrôlé et durable, `takeDiagnosticSourceForCapture()` transfère la propriété avant tout `await` : la feuille abandonne sa référence et son coordinateur de transfert, et ne touche plus à `onEvent` ou au bail après adoption. Le contrôleur app-level appelle `adoptAndStart` ; il doit arrêter et sceller une autorisation refusée. Une autorisation reçue tardivement mais non transmise est scellée sous sa portée originale, sans collecteur ouvert. Les erreurs d’écriture conservent les faits dans le journal, sans prétendre qu’un trajet a démarré.

Le refus confirmé appelle immédiatement `controller.learnerRefused(learnerID:lessonID:)`. Les diagnostics sont bloqués tant que le contrôleur porte une capture qui n’est pas sauvegardée, y compris pendant arrêt ou échec de scellement. La racine reste responsable de surveiller la portée et de présenter le trajet en cours ; la fermeture d’une préparation après adoption ne révoque pas son bail. Aucun profil matériel n’est créé par cette UI ; une qualification physique reste nécessaire.

## Vérification

Contrôle statique des interfaces du transport, du journal, de la source et des routes serveur AP152/AP153/AP190/AP191 ; contrôle du diff. Aucun appel métier contre les comptes hébergés, aucune nouvelle donnée serveur et aucune campagne de tests. Compilation Apple, inspection native, permissions et comportement physique restent à qualifier après intégration.
