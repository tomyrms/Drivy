# Audit V3.10 : fichiers fiables, exports cohérents et confidentialité native

> **19 septembre 2026 · Dossier 3.10 / contrat 3.10.0.** Remplace la V3.9. [Index](../README.md) · [Fonctionnalités](../01-fonctionnalites-prevues.md).
> Revue de documentation et de contrats, pas audit d’une application exécutée. Swift natif, GPS central et facultatif, tablette, web, Android futur et direction A restent conservés.

## Résultat et périmètre effectivement examiné

Cette passe traite **six ensembles de constats**, mêlant contradictions vérifiables de contrat et fonctionnalités techniques insuffisamment précisées. Les corrections sont intégrées aux références actives, pas laissées dans ce seul rapport. Les 23 fonctions de haut niveau et les 49 références d’écrans sont conservées. Aucune nouvelle route n’a été ajoutée ; les 201 opérations existantes reçoivent des contrats cohérents pour les pièces et exports.

La base est le ZIP V3.9 complet de la conversation, extrait puis copié. Les **six contrôles hérités ont été exécutés sur la source et passent** : [résultats avant correction](../annexes/controle-v3-9-avant-correction/results.json). Leur réussite ne détectait pas les lacunes ci-dessous. Les [preuves](../annexes/preuves-audit-v3-10.json) contiennent les lignes, extraits et hashes source ; ces lignes désignent la V3.9, pas le document corrigé. Les [schémas source](../annexes/schemas-base-v3-9.json) sont conservés pour comparer exactement les mêmes valeurs.

Le contrôle structurel couvre tous les Markdown, liens, registres et contrats. La **revue sémantique approfondie de cette passe** cible fichiers/photos/logos, finalisation et workers, téléchargements/exports, sessions réseau, caches et cycle des scènes Apple. Les parcours GPS/cours/packs existants sont recontrôlés par leurs cas hérités et le prototype, sans prétendre avoir réaudité chaque politique commerciale ou chaque API Apple. Aucun test S3, antivirus réel, réseau natif, serveur ou base SQL n’est réalisé.

## Constats et corrections

<a id="v310-01"></a>
### V310-01 · Le fichier analysé doit rester celui qui est servi

**Nature : lacune de conception à risque élevé.** La V3.9 vérifiait checksum, type et scan, mais le modèle gardait surtout une clé objet : ni génération scellée ni frontière de promotion du worker n’étaient matérialisées. AWS indique qu’un ticket présigné est réutilisable et peut remplacer une même clé [S128](sources.md#s128). Cela ne prouve pas une exploitation de Drivy : aucun stockage de l’application n’a été attaqué.

**Scénario :** le worker contrôle A ; un PUT remplace le contenu de la clé par B avant lecture. Ou le fichier est supprimé pendant le scan, puis un résultat tardif le remet à READY.

**Correction proposée :** staging privé à écriture conditionnelle, puis version ou copie scellée inaccessible en écriture au ticket client ; scan de cette génération précise, dérivés indépendants et promotion par comparaison de version/génération. Une suppression ou un résultat périmé empêche READY ; les dérivés obsolètes sont purgés. Une recréation de staging après nettoyage ne remplace jamais le canonique. La condition de clé courante n’est pas confondue avec une immuabilité éternelle [S129](sources.md#s129).

Le modèle distingue désormais `UploadIntent`, `FileGeneration` et `FileArtifact`. Une intention appartient exactement à un document élève ou à un logo, ce qui évite aussi un faux propriétaire élève pour l’asset. Les hashes source et dérivé restent distincts. Les limites de décodage, ressources et traitement complètent la limite en octets comprimés [S130](sources.md#s130).

**Références corrigées :** [R22](../03-fonctionnel/regles-etats.md#r22), [pipeline](../04-technique/fichiers-temps-communications.md#scellement-fichiers), [modèle](../04-technique/modele-donnees.md), [sécurité](../04-technique/securite-vie-privee.md), [exploitation](../05-realisation/deploiement-exploitation.md), AP61/AP86 et F09/F13. **Recettes :** [T383–T387](../05-realisation/tests-recette.md#t383), [T396–T397](../05-realisation/tests-recette.md#t396), non exécutées sur application.

<a id="v310-02"></a>
### V310-02 · Transfert complet, expiration et secrets de session

**Nature : contrat incomplet et choix de profil explicités. Importance élevée.** `UploadTicket` et `AssetUploadTicket` avaient une URL, des headers arbitraires et une expiration, sans méthode HTTP. Les URLs de transfert n’imposaient pas HTTPS dans leur forme. « Reprendre » une pièce interrompue ne précisait pas quoi faire lorsque le ticket idempotent était déjà expiré.

**Correction :** `method=PUT`, corps binaire complet, headers limités et URL HTTPS. Le client applique en plus une politique d’origine exacte et refuse userinfo, fragment et redirect ; une regex de schéma ne remplace pas cette politique. Session API et session objet sont séparées, sans bearer Drivy/cookie transmis au stockage. Les tickets de lecture restent sur la passerelle authentifiée et non sur un bucket autonome.

**Reprise concrète :** après timeout, lire/réconcilier puis finaliser les octets déjà reçus, même si l’URL expire tant que l’intention existe et que les droits le permettent. Un 412 de PUT n’est pas la preuve que le document est valide : il peut simplement refléter la première réception. Sans octets finalisables, proposer une nouvelle intention explicite après réconciliation, en conservant le brouillon et en nettoyant l’ancienne. Un rejeu idempotent ne renouvelle pas une URL. La reprise byte-range/multipart n’est pas promise pour les pièces ; le protocole spécialisé des points GPS reste distinct.

**Références corrigées :** [transport et reprise](../04-technique/fichiers-temps-communications.md#reprise-depot), [API](../04-technique/api.md), [client Swift](../04-technique/architecture-client-swift.md#confidentialite-transports), synchronisation, F09 et microtextes DESIGN. **Recettes :** [T388–T392](../05-realisation/tests-recette.md#t388), [T403–T404](../05-realisation/tests-recette.md#t403), [MOB061–MOB062](../05-realisation/qualification-mobile-ui-ux.md#mob061), MOB066. Tous restent à exécuter sur client/serveur.

Le fournisseur et son profil effectif restent à qualifier. La condition PUT est un choix de réalisation proposé, pas une décision commerciale de l’utilisateur ni une capacité certifiée de tous les stockages compatibles S3.

<a id="v310-03"></a>
### V310-03 · READY autorisait encore des fichiers sans type ou vides

**Nature : contradiction de forme démontrable. Importance élevée.** Le schéma `Document` autorisait READY avec `detectedMime=null`, zéro octet, un type non permis ou un code de rejet. Le retour `SchoolAsset` avait le même manque. La règle spécifique de photo de profil existait dans la commande d’entrée mais n’était pas imposée au retour READY.

**Correction :** conditions de schéma sur READY : MIME autorisé, taille non nulle et plafond propre à la finalité ; photo de profil JPEG/PNG, sans rattachement de leçon/formation et sous audience de l’élève. Un logo READY est également une image admissible. Un objet REJECTED peut encore décrire un type ou une taille réellement incorrects : on ne falsifie pas ces métadonnées pour satisfaire le schéma.

La projection de taille/type READY désigne le contenu canonique servi, tandis que les métadonnées de l’original sont conservées séparément au modèle. Cette précision évite de comparer un dérivé réencodé au checksum de l’original.

**Références corrigées :** OpenAPI `Document`/`SchoolAsset`, [R22](../03-fonctionnel/regles-etats.md#r22), F09 et modèle. **Vérification :** cas SC230–SC247 dans le [registre de schéma](../annexes/cas-contrats-v3-10.json) exécutés ; [T393–T395](../05-realisation/tests-recette.md#t393) restent à exécuter sur l’application. Un schéma qui rejette une projection invalide n’est pas un antivirus.

<a id="v310-04"></a>
### V310-04 · Exports CSV annoncés, endpoint ZIP et catalogue Ack

**Nature : contradiction établie et métadonnées manquantes. Importance élevée pour l’intégration.** Les textes prévoyaient CSV pour les exports de gestion, mais AP91 ne déclarait qu’`application/zip`. Le catalogue humain AP90/AP91/AP92 annonçait même un `Ack` alors que leurs réponses étaient des flux binaires. `Export` n’identifiait pas précisément le fichier disponible.

**Correction :** AP91 expose `text/csv` pour STUDENT_LIST/METRICS et `application/zip` pour PRIVACY. Les trois lignes du catalogue indiquent leurs flux, non un JSON fictif. `Export` READY porte type, nom technique sûr, taille, SHA-256, expiration et métadonnées de colonnes/lignes adaptées. Hors READY, les quatre métadonnées de contenu projetées sont nulles. La réponse, le nom, la taille et les octets doivent correspondre ; ne pas renommer un ZIP pour le présenter comme CSV.

Les droits de tout le manifeste sont relus au téléchargement, pas seulement la délégation générale d’export. En cas de perte d’affectation, refuser l’ancien fichier et proposer une nouvelle génération, sans troncature cachée. Le flux complet ne promet pas de reprise 206/Range ; une copie externe volontaire reste non révocable. Le schéma OpenAPI distingue les media types, mais ne valide ni le contenu d’un CSV ni un checksum calculé [S133](sources.md#s133).

**Références corrigées :** [export binaire](../04-technique/fichiers-temps-communications.md#export-binaire), [R96](../03-fonctionnel/regles-etats.md#r96), F14/F22/F23, API, modèle et contenu DESIGN. **Recettes :** [T398–T402](../05-realisation/tests-recette.md#t398), MOB068. Les cas JSON correspondants sont exécutés ; aucun export réel de données scolaires n’est généré.

<a id="v310-05"></a>
### V310-05 · Le coffre chiffré ne couvre pas les copies implicites

**Nature : complément de sécurité native, pas fuite reproduite. Importance élevée.** Le dossier prescrivait SQLCipher/Keychain et des règles de purge, mais ne traitait pas explicitement le cache HTTP du client ni la couverture des scènes privées dans le sélecteur d’applications.

**Correction proposée :** pas de réponse sensible dans un cache HTTP disque implicite, sessions configurées séparément, inspection des caches d’aperçu et fichiers temporaires. Le cache métier hors ligne autorisé reste conservé dans son magasin chiffré : cette correction ne supprime pas F12. `no-store` n’est pas une promesse de retrait des copies applicatives/externes [S131](sources.md#s131).

Avant snapshot de chaque scène sensible, surface opaque neutre sans animation ; au retour, recontrôler la génération de compte/école et le droit de lecture locale. La couverture ne détruit ni capture ni brouillon et n’impose pas une nouvelle biométrie. La source Apple consultée est **archivée** : elle explique le risque et ne certifie pas le hook SwiftUI/iOS 26/27 [S132](sources.md#s132). Ce hook et les fichiers réellement créés doivent être éprouvés sur appareils. Les captures d’écran volontaires ou photos de l’écran ne sont pas prétendues empêchées.

**Références corrigées :** [client Swift](../04-technique/architecture-client-swift.md#confidentialite-transports), iOS/iPadOS, intégration transverse, sécurité, F12/F14 et livraison design. **Recettes :** [T405–T406](../05-realisation/tests-recette.md#t405) et [MOB063–MOB068](../05-realisation/qualification-mobile-ui-ux.md#mob063), non exécutées sur appareil.

<a id="v310-06"></a>
### V310-06 · Statuts de référence et contrôles ne doivent pas mentir

**Nature : cohérence documentaire et couverture du vérificateur. Importance moyenne.** Le registre structuré actif portait encore un statut V3.6 et une version générale V3.7, malgré `documentVersion=3.9`. Un guide Swift comptait 370 schémas là où le contrat en avait 374 ; le guide API arrêtait sa plage de règles à R108 alors que R112 était défini. Les contrôles existants ne confrontaient pas les exemples READY ni les deux formats d’export à leur règle. L’index actif renvoyait aussi encore vers des scripts V3.8 et un registre d’arbitrage dit courant V3.6 ; leurs liens sont corrigés sans effacer les historiques.

**Correction :** versions actives harmonisées, nouveaux cas positifs/négatifs et contrôles sémantiques de média, nouveaux registres mobiles et scénarios. Les anciennes éditions et leurs chiffres restent historiques. Les adaptateurs de tests changent explicitement les versions/comptages/provenances attendus et conservent les assertions métier antérieures ; ils ne réécrivent pas les historiques pour les faire passer.

Les nouvelles références d’écran et de règle des tests ont aussi été relues : les scénarios de changement de compte se rattachent à l’autorisation courante R02, pas à l’archivage R29 ; les exports pointent vers E18/E46. Une relation formellement valide mais sémantiquement erronée ne serait pas une traçabilité utile.

**Références :** [registres et contrôles courants](revue-coherence.md), [diff](../annexes/corrections-v3-9-vers-v3-10.patch), lecteur régénéré. Le nombre de fichiers ou tests n’est pas une mesure de qualité produit.

## Recherche et preuve

Sept références primaires ont été consultées/reconsultées : AWS, OWASP, RFC 9111, Apple (dont une note archivée) et OpenAPI. [Registre de recherche](../annexes/recherche-v3-10.json). Le tableau Xcode a été reconsulté sans modifier une matrice en NOT_QUALIFIED ni déclarer de build réussi [S134](sources.md#s134). Les offres commerciales des écoles et leurs profils réglementaires n’ont pas été toutes recherchées à nouveau.

Les pages DocC de certaines configurations URLSession ne donnaient pas de texte exploitable complet ici : les réglages précis restent des candidats d’implémentation à vérifier à la compilation. L’installation du validateur intégral OpenAPI a de nouveau échoué faute de résolution réseau ; elle n’est pas présentée comme exécutée. Les contrôles JSON Schema, références, contrats et exemples sont séparés de cette limite.

<a id="decisions"></a>
## Arbitrages et preuves restant nécessaires

| Sujet | Statut courant et prochaine preuve utile |
|---|---|
| Swift natif / DA A | Décisions conservées, pas remises en concurrence. Détails de rendu et intégration à tester. |
| Stockage et scellement | Profil proposé à qualifier sur le fournisseur réel : PUT conditionnel imposé, copies/versions, taille/quota, nettoyage, scan et concurrence. Aucun abonnement AWS imposé par l’exemple. |
| Limites des fichiers | Taille de contrat conservée ; plafonds de décodage/mémoire/pages/temps, durée d’intention et purge à fixer avant données réelles. Pas de valeurs légales inventées. |
| Cache et snapshot | Preuve par inspection du build, de ses fichiers et de ses scènes sur appareils, y compris verrouillage et capture active. Aucun test navigateur ne la remplace. |
| GPS et interruptions | Autorisation initiale en ligne et une capture par publication restent limites explicites ; préautorisation/fusion nécessitent arbitrage avant modification. |
| Droits et conditions commerciales | Les politiques de régularisation/renonciation, frais et conservation restent proposées aux écoles ; aucun nouveau prélèvement automatique. |
| DM06 | Suppression globale contractualisée ; responsabilités, délais, rétentions et dernier ADMIN restent à qualifier avant publication publique. |
| Écrans non dessinés | Toujours 15 compositions pour 16 références sur 49 ; les nouveaux états de fichiers/exports sont spécifiés, pas tous illustrés. |
| Android | Client futur distinct ; aucun essai Apple ne qualifie Android. |

## Contrôles et compatibilité

Le contrat passe de 3.7.0 à **3.10.0 avant implémentation** : 201 opérations, 376 schémas. Ce n’est pas une migration de serveur effectuée. Clients et exemples doivent utiliser la version complète ; ne pas inventer des métadonnées sur d’anciens READY. [Migration](../05-realisation/migration.md).

La comparaison exécute **49 nouveaux cas de schéma** ; **18 mêmes valeurs indésirables**, acceptées par le schéma source, sont refusées par le nouveau. Le total atteint **278 cas de schéma** avec les 229 antérieurs. Les **22 cas de modèle isolé** testent décisions de reprise, promotion et origine avec données synthétiques. Ce ne sont ni des requêtes S3 ni des tests de stockage du produit. [Rapport détaillé](../annexes/verification-fichiers-v3-10.json).

Les **406 scénarios métier et 68 scénarios mobiles restent NOT_EXECUTED**. La galerie, ses données et sa palette ne changent pas de direction ; ses essais sont rejoués pour détecter une régression documentaire. Les rapports finaux font foi pour leurs résultats exacts. [Commandes et rapports](revue-coherence.md).

**Conclusion :** les contradictions identifiées sont corrigées et les cas incomplets explicités dans la référence. La sécurité réelle, le GPS et la qualité d’usage restent à démontrer par des services/appareils exécutés ; une revue documentaire ne certifie pas une application prête ni parfaite.
