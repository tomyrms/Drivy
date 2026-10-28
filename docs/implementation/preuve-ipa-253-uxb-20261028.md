# Preuve IPA combinée #253 + audit UX B — 28 octobre 2026

**Compilation : PASS. Tests : NOT_EXECUTED. Qualification physique : NOT_EXECUTED.**

Cette preuve porte sur le commit combiné `77306e9882216688b3250c77f72047619c42ad04`, compilé par le workflow **IPA d’essai · iLoader**. Elle décrit l’archive téléchargée et contrôlée ; elle ne qualifie ni un déploiement du serveur, ni l’installation sur appareil, ni le fonctionnement des parcours.

## Exécution et artefact

| Élément | Valeur vérifiée |
|---|---|
| Run GitHub Actions | [40731165137](https://github.com/tomyrms/Drivy/actions/runs/40731165137), tentative 1 |
| Conclusion | `completed` / `success` |
| Commit du run, de `build-info.json` et de `qualification/identity.json` | `77306e9882216688b3250c77f72047619c42ad04` |
| Création du run | 28 octobre 2026, 16:58:18 UTC |
| Fin du job « Compiler l’IPA d’essai » | 28 octobre 2026, 17:07:57 UTC |
| Artefact principal | [Drivy-essai-77306e9882216688b3250c77f72047619c42ad04](https://github.com/tomyrms/Drivy/actions/runs/40731165137/artifacts/12835607749) |
| Identifiant de l’artefact | `12835607749`, non expiré lors de la lecture |
| Création de l’artefact | 28 octobre 2026, 17:07:50 UTC |
| Taille de l’archive d’artefact annoncée par GitHub | 17 893 520 octets |
| Fichier IPA téléchargé | `artifacts/simplification-253/77306e98/ios/Drivy.ipa` |
| Taille du fichier IPA local | 17 916 971 octets |
| Version / build | `0.7.0` / `441` |
| Configuration / système minimal | `Release` / iOS/iPadOS `26.0` |
| SDK / build Xcode consignés | `iphoneos26.5` / `17F113` |

L’étape « Construire et vérifier l’IPA pour iLoader » et le téléversement de l’artefact ont réussi. Les métadonnées indiquent `archiveCreated: true`, `signed: false` et `signatureVerification.status: PASSED` : le paquet est non signé, destiné à la signature et à l’installation par iLoader. Cette vérification n’est pas une installation physique.

## Intégrité locale

Téléchargement effectué avec `gh run download` dans `artifacts/simplification-253/77306e98`. Les trois empreintes de `ios/SHA256SUMS.txt` ont été recalculées localement avec SHA-256 ; **les trois correspondent**.

| Fichier | SHA-256 recalculé — résultat PASS |
|---|---|
| `Drivy.ipa` | `d2492bb299e0c64451e6f0c35399ed8258d40bf3fcd400911fa34838bb9def8e` |
| `build-info.json` | `0029f7f98dfccba42f5b81aca956dd7ad4bba115c9397d2c49c43570983417fa` |
| `Package.resolved` | `148758f718e69af9fc175c6307640dc3ab70850c3cdd8c90d2ae9e171ad94392` |

`build-info.json.ipaSHA256` correspond aussi à l’IPA téléchargé ; `packageResolvedSHA256` correspond au fichier de dépendances téléchargé. Le digest de l’archive ZIP annoncé par GitHub est `sha256:bb50751db48c1e3f7f0216020b864456f84cfcb1e9f825d3da3053ab94155abf` ; il est consigné comme métadonnée distante, distincte des empreintes de fichiers recalculées après extraction.

## Périmètre Messages et limites

Les métadonnées de cette IPA confirment :

- `messagingQualificationBuildRequested: true` : l’accès Messages de qualification physique est demandé dans ce build.
- `messagingGeneralQualification: NOT_CLAIMED` : aucune qualification générale de Messages n’est déclarée.
- `schoolConnectionConfigured: true` : la connexion scolaire est configurée dans le paquet ; cela ne prouve pas l’accessibilité du serveur ni une connexion réussie.
- `physicalQualification: NOT_EXECUTED`.

Ce run compile et vérifie l’archive ; il ne comporte pas de suite de tests Swift/UI/API exécutée. Les tests préparés dans le lot restent **NOT_EXECUTED** dans cette preuve. GPS réel, batterie, VoiceOver physique et essais iPhone/iPad restent à qualifier.

## Recette courte après installation

Utiliser des comptes et données de qualification, en conservant la séparation des écoles et des rôles.

1. **Cours** : ouvrir le cours, consulter les participants, parcourir l’inscription et sa confirmation, puis les présences avec le rôle autorisé. Vérifier retour, annulation, erreur et reprise sans inscription ni présence inventée.
2. **Replay** : sur un trajet connu contenant plusieurs observations, filtrer la liste et vérifier la cohérence du rail, des repères de chronologie, de la carte et du suivi automatique. Choisir une observation met en pause ; Précédente/Suivante conserve le comportement de lecture. Vérifier « Voir tout » sur un texte long, l’aide du tracé et « Position de l’appareil du moniteur » dans les détails.
3. **Messages** : retrouver une conversation autorisée, envoyer un message de qualification, relire l’ordre et les états confirmés, puis vérifier réponse, reprise et historique local sur les deux appareils. Aucun état en attente ne doit être présenté comme reçu ou lu.
4. **Accueil** : terminer avec accord, refus ou absence de décision GPS ; reprendre sans redemander un choix encore applicable. Aucune permission de position sur l’appareil élève. Une panne de lecture des conditions de départ bloque le nouveau départ ; le contrat historique reste compatible.
5. **Bilan** : retrouver les observations déjà saisies, accéder aux autres compétences sans niveau déduit, conserver/reprendre le brouillon, puis vérifier « Ce que verra l’élève ». Une note privée reste absente de la lecture élève.
6. **Formats et accès** : iPhone/iPad, rotation, clavier, grands textes, clair/Soft Charcoal et VoiceOver ; vérifier les commandes de fin, de fermeture et de retour. Ces résultats devront être consignés après exécution, sans les déduire de la compilation.
