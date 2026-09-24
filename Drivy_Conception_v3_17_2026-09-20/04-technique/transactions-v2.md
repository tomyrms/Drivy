# Transactions critiques : GPS, packs et places de cours

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

## Observation live et clôture sous le même verrou

AP162, AP163, AP164 et AP49 revalident les habilitations puis sérialisent leurs effets sur la leçon selon l’ordre de verrous canonique. Si AP162 commite avant AP49, AP49 rattache l’observation privée du même auteur ; s’il arrive après, AP162 utilise seulement le brouillon initial encore modifiable. Après publication, OBSERVATION_REVIEW_REQUIRED préserve une reprise explicite sans mutation d’une révision. Rattacher incrémente la version ; AP54 doit relire et vérifier ses sélections. Une erreur roll back ne crée ni observation à moitié rattachée, ni charge séparée du constat. Aucun repère MARKER n’est publiable. Ces invariants de service ne sont pas prouvés par JSON Schema. Voir [R46](../03-fonctionnel/regles-etats.md#r46).

## Autorité et périmètre

Ce document décrit l’application technique des [règles R41–R72](../03-fonctionnel/regles-etats.md#r41). Il ne constitue ni du SQL déployé ni la preuve que les transactions fonctionnent déjà. Le contrat [OpenAPI](openapi.yaml) et les [tests](../05-realisation/tests-recette.md) doivent rester alignés.

## Discipline globale de verrouillage

La référence unique est la section [Autorisation et frontière de commit](#autorisation-et-commit). Toute commande prend d’abord les verrous d’accès des identités concernées dans l’ordre des ID, puis le verrou de coordination scolaire si son chemin le nécessite ; ensuite appartenances/délégations, agrégats, occupations, droits, comptes et horloge de sync. Aucun chemin court ne prend ultérieurement un verrou plus large déjà sauté. Les lectures de résolution de scope avant les verrous sont provisoires et revalidées.

## Transaction d’inscription

```text
Authentifier et vérifier école
Lire/rejouer l’opération déjà commitée si même clé et même charge
BEGIN
  prendre SchoolSchedulingLock
  verrouiller série et contrôler publication/profil/délais
  contrôler acceptedOfferRevision (pas le compteur de places)
  résoudre l’unicité élève/série
  verrouiller occupations de toutes les dates de la série
  contrôler admissibilité et conflits leçons/cours
  contrôler capacité actuelle (CONFIRMED + RECONFIRMATION_REQUIRED)
  verrouiller le droit compatible ou préparer le compte unitaire
  créer/réactiver inscription avec accord explicite
  créer occupations + HOLD ou charge de compte
  écrire OperationResult et OutboxEvent
COMMIT
répondre avec inscription confirmée et état courant
```

L’unicité porte sur school/session/learner. Une relation annulée peut être réactivée par nouvelle commande avec nouvelle acceptation ; elle ne crée pas deux places et conserve les événements historiques. Deux appareils ou une saisie manuelle simultanée convergent vers la même relation. La répétition exacte de la commande originale restitue son ancien résultat ; elle ne réinscrit pas une relation annulée entre-temps.

La dernière place n’est pas réservée au simple affichage de la fiche. La projection remainingSeats peut changer sans invalider la version commerciale des autres élèves. La transaction décide ; COURSE_FULL ne laisse pas de HOLD, de charge ou d’occupation orpheline.

## Déplacement d’une série

Verrou école, version de série, ensemble des occurrences et participants, occupations et capacités. Contrôler tous les nouveaux créneaux avant mutation ; si un inscrit possède une leçon incompatible, refuser et ne pas divulguer cette leçon aux autres élèves. Le personnel résout l’impact avec la personne, puis recommence avec une version actuelle.

Sur succès, remplacer atomiquement les occupations, incrémenter offerRevision, conserver un snapshot ancien/nouveau, marquer les inscriptions actives à reconfirmer, invalider les rappels périmés et écrire un avis par inscrit. Une série partiellement tenue ne déplace pas ses occurrences historiques ; les compensations et rattrapages demandent une procédure explicite.

La reconfirmation vérifie l’inscription et la version d’offre ; elle ne reprend ni place supplémentaire ni droit supplémentaire. Le pilote ne libère pas automatiquement une place à expiration d’un délai de réponse implicite.

## Annulation, absence et consommation

L’annulation d’une inscription future libère ses occupations et son HOLD sous la même transaction, avec événement financier si charge prévue à compenser. Si une présence a déjà consommé le droit, l’annulation automatique ne s’applique plus : décision staff et mouvements RESTORE/ajustement motivés. Les faits historiques restent présents.

À première présence confirmée, convertir le HOLD de série en CONSUME une seule fois. Les autres blocs ne consomment pas de nouveau droit. À la dernière présence nécessaire, la validation de l’exigence reste une commande habilitée distincte, avec preuve. Une absence ne devient jamais une présence simplement parce que le compte est réglé.

À CompleteLesson, consommer le HOLD de leçon et créer le compte de charge prévu ; si ENTITLEMENT, charge de cette utilisation nulle. L’achat du pack reste l’unique charge de vente. L’idempotence est conservée de bout en bout.

## Ingestion GPS et finalisation

Le serveur autorise une capture liée à une leçon/personne/appareil. Il vérifie version de choix, permissions métier et absence d’autre capture active. Le client ne collecte qu’après action explicite. Les contrôles OS sont locaux et leur succès n’est pas un consentement juridique.

Les chunks sont écrits en privé avec identités déterministes, hash et métadonnées validées. Deux uploads identiques ne créent qu’un chunk ; une collision de contenu est rejetée. L’acquittement est retourné seulement après stockage durable confirmé. Les transactions de métadonnées et le stockage objet nécessitent état STAGED/COMMITTED et reprise : un objet orphelin de staging est purgé, une métadonnée ne devient pas READY sans objet vérifié.

La finalisation compare segments, bornes et manifeste. Un chunk manquant produit PARTIAL ; une arrivée tardive valide peut compléter la reconstruction privée ; une publication existante reste figée jusqu’à une nouvelle révision explicite. Le replay utilise les mesures disponibles, pas un remplissage de route supposé. Capture terminée et collecte autorisée sont distinctes de la période permise de transfert.

## Notifications et lecture de calendrier

Une publication écrit un CampaignIntent dans la transaction ; le fanout est paginé et reprenable. La sélection relit besoin et appartenance avant envoi. Unicité campaign/learner/kind, puis tentative par canal. La livraison peut être au moins une fois chez un fournisseur ; le clic déclenche un GET authentifié courant, jamais une inscription.

Le calendrier retourne engagements autorisés et offres séparées, avec window/timeZone et generatedAt. Les offres ne génèrent pas des réservations par élève. Une série réservée est dédupliquée par occurrenceId au rendu. La fenêtre est bornée par R71, avec reprise/cursor si le nombre de résultats est élevé ; aucune troncature silencieuse.

## Erreurs attendues et observabilité

| Cas | Code | Effet durable |
|---|---|---|
| Dernière place occupée | COURSE_FULL / 409 | Aucun effet de la commande refusée. |
| Leçon ou autre cours incompatible | SCHEDULE_CONFLICT / 409 | Aucun engagement perdu ; conflit anonymisé selon droits. |
| Version de prix/dates périmée | OFFER_CHANGED / 412 | Relecture et acceptation nécessaires. |
| Droit absent/insuffisant | INSUFFICIENT_ENTITLEMENT / 409 | Aucune place provisoire invisible. |
| Preuve/admissibilité non validée | REQUIREMENT_UNVERIFIED / 422 | Pas de faux statut de présence. |
| Chunk identique rejoué | 200 / résultat déjà acquis | Pas de duplication. |
| Chunk même identité contenu différent | CHUNK_HASH_MISMATCH / 409 | Ancienne donnée conservée, incident traçable sans coordonnées dans logs. |
| Points postérieurs au cutoff | CAPTURE_REVOKED / 409 | Rejet des points concernés et purge locale instruite. |
| Publication trajet non prête | CAPTURE_NOT_READY / 409 | Bilan sans trajet toujours possible par commande distincte. |

Mesurer compteurs de conflits, temps de confirmation, nombre de chunks en attente, ancienneté d’outbox et erreurs d’autorisation. Ne pas mesurer des trajets bruts, positions ou textes de bilan dans les outils d’analytics.

### Annulation et remboursement encore à effectuer

Libérer une place ne doit pas attendre l’exécution d’un remboursement. Si une compensation immédiate ferait descendre la charge sous l’encaissé net, la transaction annule l’inscription et libère ses occupations, mais conserve le compte inchangé avec `financialFollowUp=REFUND_REQUIRED` et le montant de compensation à instruire dans l’audit. Elle n’invente ni remboursement ni diminution incompatible avec R24. Le compte est affiché « Remboursement à traiter », et non « Solde final accepté ».

Après le mouvement réel, ADMIN enregistre RefundCommand et son éventuel `chargeAdjustmentSignedCents` sous le même verrou de compte. Les bornes du net, la charge cible, la justification et l’actualisation de financialFollowUp sont atomiques. En l’absence d’encaissé, la compensation de charge peut être immédiate. Une politique de retenue doit être explicitement autorisée ; une absence de réponse du prestataire ne justifie jamais de créer un remboursement fictif.

## TX2-PUB · Publication GPS atomique

Après la porte d’accès commune, verrouiller école, leçon/publication, capture et observations dans un ordre stable. Revalider droits, état terminal publiable et versions de la sélection. Figer le manifeste des chunks/segments inclus dans un GeometrySnapshot et copier les annotations dans CapturePublication ; insérer la ReportRevision et déplacer le pointeur de publication dans le même commit avec audit/outbox. Un conflit de version renvoie `CAPTURE_REVIEW_CHANGED`, aucun snapshot visible ni bilan partiel. Un nouveau chunk incrémente la version de la reconstruction privée, sans toucher le snapshot publié. Révocation, retrait et purge invalident aussi tous les dérivés et tickets liés.

### Autorisation de transfert

AP156 valide signedUploadAuthorization, distincte du droit temporaire de collecte, puis la session et les droits courants. Valider l’expiration d’envoi et les bornes de capture des mesures avant toute écriture durable ; aucune nouvelle mesure après cutoff n’est acceptée, même si le jeton de transfert reste valide. Une réponse perdue rejouée ne réactive jamais le collecteur.

<a id="autorisation-et-commit"></a>
## Autorisation et frontière de commit

**Ordre commun proposé :** lignes Person servant de porte d’accès globale par ID ; coordination scolaire par ID si nécessaire ; appartenances/délégations par ID ; agrégats de planning/publication/cours et sources de preuve (inscription/cycle, occurrence, relevé de présence, document, par type puis ID) ; décisions d’exigence dépendantes par ID ; occupations et ressources ; lots de droits et mouvements source ; comptes ; SchoolSyncClock en dernier. Déclarer dès le départ le mode le plus fort nécessaire à chaque ligne, sans promotion concurrente d’un verrou de lecture.

Les commandes ordinaires prennent FOR SHARE sur l’accès de l’acteur et des personnes dont la relation est engagée ; le passage global à PROCESSING prend FOR UPDATE sur Person, contrôle accessState puis passe ACTIVE→CLOSING atomiquement avec révocation et tâches. Une modification du profil global prend son mode d’écriture dès l’entrée. Résoudre les ID avant l’acquisition puis vérifier les liaisons sous verrou ; si une identité supplémentaire est découverte, rollback et reprise bornée depuis le début, jamais verrou tardif hors ordre. Les participants à l’occupation ne sont pas une seconde porte d’accès acquise après le planning.

Si une commande gagne avant PROCESSING, ses effets sont inclus dans l’inventaire actualisé ; si la suppression gagne, les nouvelles commandes ordinaires sont refusées. Les corrections/effacements de tâches internes disposent d’un mandat étroit audité, pas d’un contournement global donné au support. Les lignes d’école pour la continuité du dernier ADMIN sont verrouillées après les identités, dans le même ordre ; aucun appel fournisseur n’a lieu sous ces verrous. Ce protocole doit être éprouvé sur PostgreSQL avec deux connexions, délais et reprises [S108](../06-gouvernance/sources.md#s108).

Les uploads GPS gardent leur chemin sans verrou de planning, mais vérifient appartenance/choix/capture sous leurs verrous avant publication de métadonnées ; un objet de staging refusé est purgé. Cette discipline exploite les mécanismes de verrouillage documentés par PostgreSQL [S60](../06-gouvernance/sources.md#s60). Elle est une proposition d’implémentation à vérifier avec deux connexions réelles, pas un résultat d’un test SQL effectué ici.

## Révision commerciale et retour de prépaiement insuffisant

AP42 revalide sous le chemin large la version de leçon, produit, anciens/nouveaux lots et éventuel compte. Si `commercialChange` est requis et manque, la commande s’arrête sans déplacer. Sinon contrôler la quantité contractuelle, l’augmentation nette de droits, les sommes, la version de compte et R24, puis écrire ancienne/nouvelle révision, mouvements compensatoires, nouveaux engagements et outbox au même commit. Il ne suffit pas de déplacer d’abord puis de réécrire le prix.

Un mouvement financier sur un achat prend ce même chemin pour calculer son effet sur les droits selon [R53](../03-fonctionnel/regles-etats.md#r53). Si une réservation gagne avant la correction, son HOLD reste un engagement confirmé à traiter ; si la correction gagne, la réservation suivante voit les droits suspendus. Il n’existe aucun interstice où l’API confirmerait des droits nouveaux sur un paiement déjà invalidé. Les prestations déjà réalisées ne sont pas effacées.

## Présences et révisions de série

Le déplacement valide en un ensemble les dates et échéances R62. AP192 versionne l’offre future mais ne modifie pas les snapshots des inscrits. La présence vérifie le cycle courant sous verrou ; sa première création conditionnelle est atomique avec la conversion unique du HOLD. Un cycle annulé n’est pas ressuscité par un relevé en attente. Un marqueur d’absence n’entraîne jamais à lui seul la validation pédagogique.

<a id="publication-textuelle"></a>
## TX2-TEXT · Publication d’annotations autonomes

Après la porte d’accès commune, verrouiller école, leçon/publication, brouillon et ensemble des observations sélectionnées par ID. Pour chaque texte : contrôler auteur/droits, même brouillon et leçon, version attendue, absence de tout ancrage et absence de doublon d’ID. Vérifier la sélection GPS séparément s’il y en a une ; au plus 100 références au total. Copier PublishedTextObservation dans ReportRevision en même temps que ses autres champs, puis Operation, audit et outbox au commit. Une seule version périmée refuse l’ensemble. Les textes copiés ne relisent jamais le brouillon mutable. La publication sans capture ne construit pas de GeometrySnapshot.

## TX2-DELIVERY · Remise de droit non planifié

AP199 suit identité→école→appartenances→dossier/achat→lot→compte si recontrôle financier requis→horloge. Vérifier produit vendu EXTERNAL_SERVICE/EXAM_SUPPORT, dossier actif, prépaiement, expiration et quantité utilisable. Persister CONSUME et son évidence minimale de remise, version du lot, preuve d’opération et invalidation ENTITLEMENT dans un commit. Le hash d’opération distingue un simple rejeu d’une nouvelle intention. Ne pas appeler le prestataire, ne pas encaisser, ni créer un GRANT compensatoire. AP114 utilise les plafonds et unicités RESTORE existants.

## TX2-CLOSE · Clôture collective avec libérations explicites

AP138 verrouille la série, les cycles et présences, puis tous les lots impliqués par ID selon le chemin commun. Calculer l’ensemble complet des HOLD sans PRESENT ; comparer exactement la sélection explicite du client (IDs/cycles/versions), après vérification des droits supplémentaires de libération. Chaque RELEASE référence le HOLD, sans le dépasser ; inscrire CLOSED et l’outbox dans le même commit. Une absence manquante, un changement concurrent ou une sélection partielle refusent tout. La relecture d’une série CLOSED avec la même opération n’ajoute aucune libération. Les obligations financières ne sont ni inventées ni soldées par clôture.

## TX2-PRICE · Achat au total réellement accepté

Relire version d’offre, lignes de base et prix de chaque option ; contrôler l’égalité des sommes, bornes de calcul et correspondance exacte des clés. ADMIN seul peut appliquer priceOverride avec motif et accord explicite. Produire les snapshots et une écriture INITIAL au total convenu, puis les seuls lots sélectionnés, atomiquement. Le client ne fournit pas une somme autoritaire de composants. Toute mutation de l’offre pendant la revue donne OFFER_CHANGED ; aucun prix historique n’est recalculé à partir d’un catalogue modifié.

<a id="presence-preuve-reglement"></a>
<a id="v37-présence-preuve-et-régularisation"></a>
## Présence, preuve et régularisation
**AP146.** Appliquer l’ordre de verrouillage commun : identités, écoles, appartenances/délégations, puis inscriptions/cycles, occurrences/présences/documents, décisions dépendantes, lots/mouvements source et comptes selon l’ordre canonique. Les groupes sans objet concerné sont simplement omis, jamais inversés. Les lectures préalables ne sont pas une autorisation au commit. Revalider la source de crédit et les décisions liées ; corriger le fait, ouvrir ou classer le suivi de droit, invalider les exigences dépendantes, incrémenter les versions et écrire l’outbox au même commit. Aucun mouvement financier n’est créé. Dépendance apparue entre prélecture et verrou : relecture puis reprise bornée, pas oubli du nouvel objet.

**AP201.** ADMIN et If-Match inscription, settlementVersion et mouvement source concordants ; verrouiller mêmes objets et relever le fait PRESENT courant. Si la source/quantité/lot ne correspond plus, refuser avec RIGHT_SETTLEMENT_CHANGED. CONSUME_FROM_ORIGINAL_LOT exige reliquat utilisable suffisant ; append d’un seul mouvement lié et clôture du suivi atomiques. WAIVE_CONSUMPTION ne passe pas par GRANT/RESTORE. Rejouer l’opération identique retrouve le résultat autorisé ; une autre intention ne double pas une résolution déjà faite. Un remboursement pendant l’attente se coordonne par le lot/compte et peut rendre la consommation impossible, pas effacer la présence.

**AP122 et invalidation de preuve.** Le service de validation et celui de correction utilisent le même ordre de verrous sur les sources et les RequirementRecord impactés. Ils relisent les versions de présence et de document avant d’écrire une décision. Une correction commise d’abord invalide l’ancienne demande de validation ; une validation commise d’abord est invalidée par la correction suivante. Un worker seul ne doit pas laisser une validation obsolète admise pendant une fenêtre d’attente : l’état courant/invalidation et l’outbox sont synchrones ; les notifications peuvent être différées. Des conflits complexes nécessitent une reprise bornée de la transaction entière, pas un commit partiel.

Cette stratégie doit être essayée sur deux connexions PostgreSQL réelles ; l’ordre documentaire ne prouve ni absence d’interblocage ni atomicité implémentée. [Verrous](../06-gouvernance/sources.md#s115). Les modes incompatibles nécessaires sont acquis dès le départ et jamais promus de façon opportuniste.

AP122 compare aussi les versions explicitement vues par le valideur (sourceEnrollmentVersion, attendanceVersionChecks, documentVersionChecks), pas seulement les versions lues au début de la transaction. Sans cette précondition, un premier contrôle TO_DO pourrait approuver des présences modifiées depuis la revue humaine. Le serveur vérifie l’ensemble complet requis et refuse un cycle/version/ensemble changé.
