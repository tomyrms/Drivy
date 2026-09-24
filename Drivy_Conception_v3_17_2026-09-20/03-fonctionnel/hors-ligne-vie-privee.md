# Hors ligne, archivage et droits sur les données

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Mode d’emploi

Les règles ne sont pas redéfinies ici : les identifiants R renvoient à leur [référence principale](regles-etats.md). Les séquences suivantes spécifient les fonctions du cœur proposé, avec préconditions, variantes, données et critères observables. L’[autorisation](roles-permissions.md) s’applique à tous les appels, même lorsqu’un bouton n’est pas affiché.

<a id="f12"></a>
## F12 · Brouillons natifs et réconciliation

**Besoins :** B02 B05. **Parcours :** [J05](../02-experience/parcours.md#j05), [J09](../02-experience/parcours.md#j09). **Écrans :** [E17](../02-experience/ecrans.md#e17), [E21](../02-experience/ecrans.md#e21), [E08](../02-experience/ecrans.md#e08).

**Règles et dépendances :** [R11](regles-etats.md#r11), [R12](regles-etats.md#r12), [R27](regles-etats.md#r27), [R28](regles-etats.md#r28), [R34](regles-etats.md#r34), [R37](regles-etats.md#r37), [R39](regles-etats.md#r39), [R40](regles-etats.md#r40). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Éviter la perte d’un bilan sans faire croire qu’un engagement a été confirmé quand seul un appareil a enregistré sa copie.

### Rôles, autorisations et préconditions

App native, connexion antérieure, lease valide et stockage chiffré prêt. La projection contient seulement les formations autorisées et les données nécessaires aux leçons préparées. La version web initiale n’offre pas de dossiers hors ligne.

### Parcours nominal et conséquences

Éditer localement un brouillon dans une transaction SQLite chiffrée. Afficher « Sur cet appareil » puis « En attente d’envoi » si une commande est mise en file. Au retour réseau, valider session et epoch avant de lire/écrire le métier. Envoyer les opérations dans l’ordre des dépendances avec version et identifiant stable. Une réponse confirmée remplace la projection puis marque l’opération ACKNOWLEDGED. Aucun bouton de publication ne simule un succès hors ligne.

### Variantes, interruptions et cas limites

App arrêtée pendant la saisie : rouvrir le dernier brouillon effectivement persisté. Perte réseau après commit : retrouver l’opération avant renvoi. Conflit : écran comparatif de champs autorisés, aucun écrasement automatique ; possibilité de reprendre les notes dans un nouveau brouillon. Lease expirée : verrouillage, reconnexion nécessaire. Retrait d’affectation : ne pas montrer la copie serveur ou autoriser export de la copie locale.

### Données, validations et cycle de vie

Projection locale par compte/école, clé de coffre système, DraftStore et OutboxItem(operationId,baseVersion,payloadHash,state,dependencies,attempts). Les documents binaires de permis ne sont pas mis en cache offline par défaut. Les brouillons locaux sont privés à l’auteur et excluent les données d’autres écoles.

### Erreurs, événements et reprise

401 REFRESH_REQUIRED, 403 ACCESS_REVOKED, 412 VERSION_CONFLICT, 409 OUTCOME_CONFLICT, 507 LOCAL_STORAGE_FULL. L’échec de sauvegarde locale doit être visible avant de quitter ; « enregistré » n’est jamais affiché après une écriture disque échouée.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T045](../05-realisation/tests-recette.md#t045) | Fermer de force l’app après une sauvegarde locale confirmée. | Le brouillon réapparaît à la réouverture du même compte autorisé. |
| [T046](../05-realisation/tests-recette.md#t046) | Un bilan offline est envoyé après annulation serveur. | Aucune réactivation automatique ; conflit visible et notes conservées verrouillables. |
| [T047](../05-realisation/tests-recette.md#t047) | L’app reste hors ligne au-delà de la durée autorisée. | La projection est verrouillée ; aucune lecture ou commande métier nouvelle. |
| [T048](../05-realisation/tests-recette.md#t048) | L’écriture locale échoue. | Aucun faux succès ; avertissement et prévention de perte avant navigation. |

<a id="f14"></a>
## F14 · Archivage, accès aux données et effacement instruit

**Besoins :** B05. **Parcours :** [J10](../02-experience/parcours.md#j10). **Écrans :** [E18](../02-experience/ecrans.md#e18), [E13](../02-experience/ecrans.md#e13).

**Règles et dépendances :** [R01](regles-etats.md#r01), [R29](regles-etats.md#r29), [R30](regles-etats.md#r30), [R32](regles-etats.md#r32), [R34](regles-etats.md#r34). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Permettre une sortie maîtrisée et des droits exercés sans détruire des preuves utiles ou conserver tout indéfiniment.

### Rôles, autorisations et préconditions

Demande authentifiée ou identité vérifiée hors app selon procédure ; ADMIN pour la relation scolaire, responsable de traitement identifié. Les durées et motifs de conservation doivent être approuvés avant données réelles.

### Parcours nominal et conséquences

La personne choisit accès, rectification ou demande d’effacement et reçoit un numéro de dossier. L’école vérifie identité et portée, examine les données de tiers et obligations de conservation, prépare une réponse. L’export est généré dans un espace privé, limité à la portée autorisée, disponible par lien court authentifié. Une suppression approuvée masque immédiatement les données concernées et planifie la purge, en conservant seulement les preuves nécessaires sous accès restreint.

### Variantes, interruptions et cas limites

Personne membre de plusieurs écoles : chaque demande a une portée scolaire explicite ; fermer une école ne supprime pas son identité dans les autres. Dossier avec leçons futures : organiser annulation/réaffectation avant archivage. Mouvement financier à conserver : expliquer la conservation limitée plutôt que promettre un effacement total. Sauvegarde restaurée : réappliquer les tombstones avant ouverture du service.

### Données, validations et cycle de vie

PrivacyRequest, décision, scope, identityVerificationMethod, exportManifest, retentionHold, DeleteJob et tombstone. Export proposé JSON structuré et pièces autorisées ; bilan lisible en Markdown/HTML documentaire, pas nécessité de PDF au pilote. Révocation des liens après clôture.

### Erreurs, événements et reprise

409 FUTURE_LESSONS_EXIST, 409 RETENTION_REVIEW_REQUIRED, 403 REQUEST_SCOPE_INVALID. Une demande n’entraîne pas automatiquement l’effacement. Délais de réponse légaux et responsables de validation à confirmer, et visibles dans le dossier sans valeur fictive.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T053](../05-realisation/tests-recette.md#t053) | Un élève possède une leçon future. | L’archivage direct est refusé et présente un traitement explicite. |
| [T054](../05-realisation/tests-recette.md#t054) | La suppression vise l’école A seulement. | Les données de B ne sont ni exposées ni effacées. |
| [T055](../05-realisation/tests-recette.md#t055) | Un export d’élève est produit. | Aucun autre élève ni note privée non communicable sans examen n’est inclus. |
| [T056](../05-realisation/tests-recette.md#t056) | Une sauvegarde antérieure à une purge est restaurée. | Les tombstones sont réappliqués avant accès utilisateur ; les données supprimées ne réapparaissent pas. |

## Continuité V2

La capture déjà autorisée dispose d’une outbox locale de chunks indépendante des brouillons. Elle peut continuer sans réseau dans la borne R42 ; démarrage entièrement hors ligne différé. Les inscriptions, annulations de places, présences finales, achats et validation d’exigences restent des commandes serveur. Un état d’offre mis en cache n’est jamais présenté comme une place garantie.

Le mode sans GPS ne collecte pas de points en réserve pour les montrer plus tard. Une révocation reçue localement arrête et verrouille immédiatement ; une révocation distante ne peut être connue instantanément d’un appareil déconnecté. Les autorisations bornées et refus de données post-cutoff limitent l’exposition sans promettre un effacement physique inviolable.

Les demandes d’accès/effacement couvrent captures et dérivés, inscriptions, preuves de cours et droits, avec des finalités et durées distinctes. Les nouvelles règles complètes sont R41–R72 ; les recettes vérifient aussi caches, exports et restauration de sauvegarde.


## Révision V3 du cycle de dossier

R29 est précisée par R87–R91. Archiver un Learner n’est pas révoquer Membership. L’ancien compte peut consulter son historique publié si l’appartenance reste active ; les offres et nouvelles opérations sont retirées. Révocation F01, effacement F14 et fermeture d’une formation F03 restent séparés. Les captures/brouillons tardifs non connus du serveur sont traités comme conflits, jamais comme motif de restauration silencieuse.

Le parcours d’archivage complet, les blocages, le lot de 50 dossiers maximum et la restauration sont la référence [F22](gestion-web-archivage.md). Un export de gestion ne remplace pas une demande de droits : purpose et colonnes sont distincts. Les fichiers restent soumis aux durées de conservation, y compris dans un dossier archivé.

L’onboarding web reste connecté, sauvegardé après confirmation serveur et repris par compte/école. Il n’utilise pas la file locale native de capture. Sur tablette, redimensionnement et rotation ne créent pas une nouvelle capture ; la file existante reste liée à l’appareil collecteur.

<a id="cycle-local-et-compte-global-v34"></a>
## Cycle local et compte global
Les [règles d’intégration mobile](../04-technique/integration-mobile-transverse.md) détaillent protection des clés/fichiers, sauvegardes, réinstallation, arrêt et update. Elles n’étendent pas les opérations métier permises hors ligne. La capture exige toujours le départ autorisé selon sa référence.

F14 inclut désormais le [parcours global](compte-suppression-globale.md) en plus des demandes scolaires. AP193–AP198 ne donnent pas au personnel scolaire le droit de supprimer l’identité d’autrui. DM06 conserve un gate opérationnel et juridique avant publication ; le contrat documentaire seul ne le franchit pas.

## Copies techniques et copies volontaires

La lecture hors ligne du cache autorisé utilise le magasin chiffré défini ; les caches HTTP implicites ne constituent pas un second cache indépendant de sa purge. Images, PDF, exports temporaires et snapshots de scènes doivent faire partie des essais de confidentialité. Une copie explicitement sauvegardée dans Fichiers ou partagée vers une autre application ne peut pas être rappelée par Drivy ; le parcours l’explique au moment de cette action. [Détails natifs](../04-technique/architecture-client-swift.md#confidentialite-transports).
