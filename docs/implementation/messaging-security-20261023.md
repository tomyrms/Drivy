# Messagerie #65 : architecture de sécurité proposée

Date de recherche : 23 octobre 2026. Lots #67, #68, #77, dépendances #50, #66, #69, #70.

**Statut : recommandation technique, non décision produit validée, non qualification de sécurité. Activation réelle interdite à ce stade.** Le 23 octobre 2026 à 01:26 UTC, le coordinateur a confirmé l'extension à `prototypes/messaging-crypto/**` : prototype synthétique officiel autorisé, compilation/check seulement selon #84. Bibliothèque téléchargée et verrouillée pour ce prototype, aucun fournisseur engagé, aucun protocole maison, aucun scénario exécuté. Le coordinateur conserve STATUS.md et les commits.

## 1. Réponse rapide au coordinateur

**Prototype de primitive livré séparément :** `matrix-sdk-crypto` 0.19.1, machine sans I/O réseau, compile et lie quatre scénarios synthétiques sans homeserver. Cela ne qualifie pas le SDK client complet. Pour une intégration produit, recommander ensuite **Matrix Rust SDK avec ses bindings Swift et un homeserver non fédéré**, si le modèle retenu est E2EE entre appareils des participants. Le SDK intégré réduit les mécanismes d'appareils, synchronisation et groupes à réinventer. Ce choix est une préférence de faisabilité, pas une preuve que Matrix respecte déjà les droits scolaires de Drivy. [S1, S2]

Conserver **MLS/OpenMLS comme alternative** si la confidentialité après compromission est une exigence déterminante ou si le coût d'un homeserver est refusé. Ne pas assembler dans cette tranche une messagerie complète autour d'une primitive MLS. Le service de distribution, l'identité des appareils, les pièces jointes et la récupération demanderaient encore une intégration et une revue propres. RFC 9420 vise explicitement FS et PCS pour groupes asynchrones, ce qui ne rend pas une application automatiquement sûre. [S4, S5]

Ne pas retenir libsignal pour le premier prototype Drivy : l'amont annonce explicitement l'absence de support hors Signal et des changements d'API possibles. Ce n'est ni un jugement négatif sur Signal, ni une interdiction juridique d'utilisation. [S3]

**Implémentation indépendante possible dès maintenant :** autorisations scolaires, transport opaque désactivé, limites/idempotence, faux adaptateurs synthétiques explicitement non cryptographiques, interfaces de confiance des appareils et écrans d'indisponibilité. Ni chaîne Base64 ni champ nommé `ciphertext` ne prouvent un chiffrement. Aucun adaptateur de production ne doit accepter le clair ou tomber silencieusement sur un chiffrement serveur.

## 2. Références locales et constat existant

Lectures : AGENTS.md, COMMENCER_ICI.md, `03-fonctionnel/extensions.md` U03, `04-technique/securite-vie-privee.md`, copies locales complètes des issues #67/#68/#77. U03 ne fournit pas de contrat de messagerie livré : il exige précisément de décider accès, archivage, modération et notifications. Les issues récentes cadrent ce nouveau chantier, elles ne valent pas validation des options.

Inventaire ciblé, par inspection uniquement :

| Protection déjà visible | Preuve locale | Limite pour #65 |
|---|---|---|
| OIDC et droits scolaires courants, RLS et rôle DB contraint documentés | `apps/api/README.md`, `docs/implementation/deploiement-refonte.md` | Identité applicative et autorisation ne constituent pas une authentification cryptographique d'appareil. |
| Idempotence, versions et résultat après commit documentés | `apps/api/README.md` | À préserver pour messages et opérations de membres. |
| Keychain `AfterFirstUnlockThisDeviceOnly` | `apps/ios/Drivy/Identity/IdentityVault.swift` | Ne prouve pas la gestion des clés de conversation. |
| AES.GCM sur outbox et brouillons locaux | `SchoolConfigurationAPI/SchoolCommandOutbox.swift`, `SchoolLessonReportUI/SchoolReportLocalDraft.swift` | Chiffrement local, pas E2EE de messagerie. Pas de réutilisation des mêmes clés. |
| TLS public et PostgreSQL vérifié, lien proxy/API privé HTTP documenté | `docs/implementation/deploiement-refonte.md` | Pas d'attestation live, ni de résidence suisse complète, ni de chiffrement applicatif des métadonnées. |

Aucun test de ces protections n'a été réexécuté dans cette étude. Aucun accès au worktree original, à une infrastructure réelle, à des secrets ou à des conversations.

## 3. Comparaison actuelle : protocole, bibliothèque et exploitation

Sources officielles consultées le 23 octobre 2026. « Maintenu » signifie ici dépôt actif et maintenance/usage amont documentés, pas SLA. Le prototype fixe matrix-sdk-crypto 0.19.1 et son Cargo.lock (vodozemac 0.11.1), avec provenance déclarée des crates et revue des avis dans `../../prototypes/messaging-crypto/SECURITY-REVIEW.md`. Les bindings Swift, le SDK complet et le homeserver restent à geler et qualifier séparément.

| Candidat | Licence vérifiée | Atouts et preuve amont | Réserves Drivy et conclusion |
|---|---|---|---|
| Matrix, Olm/Megolm via `matrix-rust-sdk` et vodozemac | Apache-2.0 pour SDK, binding Swift et vodozemac | SDK maintenu par Element, utilisé par Element X, support Swift, gestion réseau/sync/crypto intégrée. vodozemac annonce un audit tiers antérieur. [S1, S2, S7] | Candidat principal de prototype. L'audit d'une crate ne couvre pas Drivy ni tous les changements récents. Métadonnées serveur et rotation Megolm restent des risques. |
| Signal Protocol via `signalapp/libsignal` | AGPLv3 | Implémentation Rust utilisée par Signal, interfaces Swift/Java/TypeScript. [S3] | Usage externe non supporté, API changeante. Licence et distribution du binaire Drivy à examiner, ne pas déduire une compatibilité de distribution du seul dépôt public. Pas retenu initialement. |
| MLS RFC 9420 via OpenMLS | MIT | Maintenu par Phoenix R&D et CE Labs. iOS et WASM compilés en CI mais explicitement dans la liste non testée/non supportée. [S4, S5] | Alternative standard pour groupes, pas SDK de messagerie complet. Bindings Swift, stockage, orchestration et parcours à qualifier. Interdire features `content-debug` et `crypto-debug`. |
| MLS RFC 9420 via `awslabs/mls-rs` | Apache-2.0 OU MIT | Bibliothèque MLS avec WASM, stockage configurable et fournisseur CryptoKit. README annonce conformité RFC mais absence d'audit de sécurité tiers complet. [S6] | Comparateur secondaire, pas service AWS ni engagement fournisseur. Ne pas assimiler fournisseur CryptoKit à une app Swift prête ou auditée. |

**Coût d'exploitation séparé :** le homeserver candidat Synapse est sous AGPLv3, contrairement au SDK Apache-2.0. Son adoption, les modifications éventuelles et les obligations de distribution/service doivent être revues séparément. Aucune licence commerciale ni offre payante n'est sélectionnée. [S8]

**Limite décisive de Megolm :** la spécification décrit une confidentialité passée partielle et l'absence de récupération automatique de confidentialité future après compromission d'une session. Posséder un état de session permet de suivre sa progression. Changer les membres doit provoquer de nouvelles sessions sortantes et arrêter les envois à l'ancienne audience, pas seulement changer une ACL SQL. Ne pas annoncer les propriétés MLS/Double Ratchet pour tous les messages de groupe Matrix. [S9]

## 4. Arbitrage de confidentialité qui reste au porteur

| Modèle possible | Qui déchiffre | Conséquence |
|---|---|---|
| E2EE privé ET général | Appareils explicitement autorisés des participants de chaque conversation | Proposition recommandée, à approuver. Ni exploitant, API, OIDC, sauvegarde serveur, ni ADMIN non participant n'ont les clés du contenu. |
| E2EE privé, général lisible par un service désigné | Participants privés pour le privé, service et destinataires déclarés pour le général | Option distincte, non retenue silencieusement. Le général ne doit pas être présenté comme illisible par l'opérateur. |
| Chiffrement transport/stockage seulement | Service pouvant récupérer les clés et destinataires autorisés | Ce n'est pas E2EE. Pas de fallback acceptable à l'exigence sans nouvel arbitrage explicite. |

Un robot modérateur qui reçoit toutes les clés est un destinataire permanent, pas une exception technique invisible. Un ADMIN peut être participant du général sans acquérir l'accès aux privés. Mineurs, représentants et remplacement de moniteur nécessitent des règles explicites, aucun accès parental ou accès de toute l'équipe déduit automatiquement.

Décisions bloquantes : modèle par type de conversation, membres autorisés du général, modérateurs, historique des nouveaux membres, appareil supplémentaire, clés de secours et responsabilité de leur perte, conservation, éventuel web, APNs et copies hors Suisse. Enregistrer décideur/date/version/portée avant activation. Une préférence d'agent ne remplit pas ces champs.

## 5. Architecture proposée sans enfermer le produit

Les noms suivants sont des ports applicatifs proposés, **pas un nouveau format cryptographique**.

- `MessagingAuthorization` : relit école active, appartenance, relation autorisée, restriction chat, état du membre et version courante. Aucun rôle fourni seulement par le client.
- `MessagingTransport` : transporte les événements opaques du protocole choisi, curseurs et accusés durables. Limites de taille, anti-rejeu applicatif et idempotence, sans interpréter le contenu pour rechercher/modérer.
- `ConversationMembership` : source métier des participants et version de droits, mappée au groupe du protocole. Une école et une conversation ne sont jamais déduites d'une valeur cliente non vérifiée.
- `DeviceTrust` : appareil actif/révoqué/non vérifié, empreinte publique, liaison à l'identité. OIDC ne suffit pas à rendre une nouvelle clé fiable.
- `MessagingCrypto` côté client seulement : adaptateur SDK, opérations de confiance et événements typés. Aucun `decrypt` côté API, aucun secret privé de session dans un DTO serveur.
- `EncryptedMediaStore`, `NotificationDispatch`, `AbuseReportTransport` : interfaces distinctes, droits et rétention séparés, pas de connexion automatique à un prestataire.

La réalisation Matrix doit conserver les enveloppes et validations standards. Un token Matrix direct ne doit pas permettre de contourner les refus scolaires Fastify. Proposer un accès client via passerelle contrôlée et/ou un module d'autorisation homeserver, avec endpoint natif non exposé par un autre chemin. Vérifier aussi clés, sync, médias, créations/invitations et opérations de membres. **Ce raccordement est un jalon de faisabilité bloquant**, pas une capacité déjà démontrée. Ne pas réimplémenter la cryptographie pour adapter les routes.

Chaque changement de membres ferme l'ancienne version d'envoi, modifie l'audience du protocole, renouvelle les sessions appropriées et n'ouvre la nouvelle version qu'après confirmation. En cas de désaccord ou de client hors ligne : suspendre l'envoi, resynchroniser et rechiffrer via SDK, jamais accepter une ancienne session après révocation. Définir l'ordre de commit et reprise sans double succès. Les messages déjà remis restent hors de portée d'un effacement garanti.

Les schémas métier peuvent être développés avec `privacyDecisionId` absent et capacité indisponible. Les règles d'activation doivent dépendre d'une décision approuvée et des qualifications, pas d'un simple booléen d'environnement. Les faux adaptateurs restent en tests, jamais en configuration de production.

## 6. Modèle de menace et exigences proposées

| Adversaire/incident | Contrôle à construire et vérifier | Limite résiduelle à annoncer |
|---|---|---|
| Opérateur ou DB compromis | Clés privées aux appareils, contenu/médias chiffrés avant émission, sauvegardes de clés opaques | Métadonnées, disponibilité et injection de clés/appareils restent des menaces. |
| Serveur malveillant substituant un appareil | Vérification SDK entre appareils, changement d'identité visible, blocage des destinataires non fiables | Premier contact sans vérification indépendante ne fournit pas une identité forte. |
| Utilisateur d'une autre école | Autorisation chaque lecture/écriture/media/key request, contexte lié à l'école, refus des relations étrangères | E2EE ne corrige pas une invitation métier abusive. |
| Appareil perdu ou compromis | Coffre et cache chiffrés, verrouillage local, révocation des sessions et appareil, rotation future | Un appareil déverrouillé peut copier du clair. Pas d'effacement distant absolu. |
| Ancien participant | Refus service immédiat, rotation protocolaire avant nouveaux envois, arrêt des partages de clés | Garde ce qu'il a reçu. Un membre restant malveillant peut lui retransmettre du contenu. |
| Sauvegarde compromise/restauration ancienne | Clés de récupération non détenues par service, inventaire des copies, journal des révocations hors rollback | Restaurer les clés historiques rétablit l'accès aux données qu'elles protègent. |
| Web compromis | Pas de client web chat avant décision, CSP et origine stricte si retenu, pas de scripts tiers | Un serveur distribuant du JavaScript malveillant peut compromettre ce terminal de déchiffrement. |
| Diagnostics/exfiltration indirecte | Aucun corps, clé, token, texte de sondage ou preuve d'abus dans logs/crash/IA | Les horaires, volumes et identifiants indirects restent sensibles. |

## 7. Cycle de vie recommandé à faire approuver

Ces règles sont des exigences proposées pour le prototype, pas une affirmation de comportement déjà livré.

1. **Premier appareil :** générer les secrets dans le SDK sur l'appareil. Protéger l'état avec coffre local dédié, pas clé OIDC/serveur. Publier seulement les matériaux publics prévus. Un utilisateur doit voir un appareil inconnu ou une identité remplacée avant de lui partager des secrets.
2. **Second appareil du même compte :** liaison par un appareil vérifié ou secret de récupération utilisateur via mécanismes SDK. Tant que non vérifié, ne pas partager automatiquement l'historique. Une reconnexion OIDC seule ne restaure pas les clés.
3. **Nouveau membre de groupe :** recommandation initiale sans historique antérieur. Si le produit exige l'historique, validation distincte et mécanisme standard de partage depuis un participant autorisé, avec audit minimal. Ne pas confondre `history_visibility` et possession effective de clés. [S10]
4. **Retrait de membre/appareil :** invalider accès service et push, fermer les anciens envois, forcer nouvelles sessions des expéditeurs restants avant nouveaux messages. Tester appareil hors ligne puis reconnecté et fichier déposé avant retrait. Révoquer tous les appareils du membre concerné, sans retirer les cours ou le dossier.
5. **Perte de tous les appareils :** avec secret utilisateur et sauvegarde chiffrée approuvée, récupération via SDK. Sans secret ni appareil fiable, contenu perdu, réinitialisation d'identité visible et nouveaux échanges seulement. Le support ne possède aucune clé maîtresse. #50 restaure l'accès au compte, pas implicitement son historique.
6. **Sauvegarde :** proposition de coffre chiffré côté client conservé en Suisse, récupération détenue par l'utilisateur. Faire choisir activation/UX et conservation. Toute récupération par l'école modifierait la promesse et doit être explicitement décidée. La spécification Matrix définit sauvegarde de clés et secret storage, pas la politique Drivy. **Blocage technique identifié :** vodozemac 0.11.1 avertit que l'ancien `m.megolm_backup.v1.curve25519-aes-sha2` n'authentifie pas le ciphertext, et le SDK active transitivement `insecure-pk-encryption`. Ne pas adopter cette sauvegarde par défaut. Le prototype utilise seulement l'export fichier chiffré officiel distinct, sans appeler les APIs de sauvegarde serveur. Voir sa revue de sécurité. [S10]
7. **Destruction :** retirer les secrets locaux lors de la clôture selon politique, purger les copies serveur et backups selon délais approuvés. Ne pas promettre l'effacement des exports, captures ou anciennes sauvegardes détenues par un participant.

## 8. Contenu, fonctions et modération

Propositions à conserver cohérentes avec le modèle retenu :

- Messages, réactions, texte de mentions et sondages sont chiffrés côté client. Définir la confidentialité des votes et la preuve d'éligibilité, sans promettre simultanément anonymat fort et contrôle nominatif serveur. Pas d'agrégation serveur nécessitant le clair sous E2EE stricte.
- Recherche locale dans un index chiffré, jamais Elasticsearch/SQL plein texte serveur alimenté avec le clair. Export en clair produit par un appareil autorisé, pas par une API qui ne possède pas les clés.
- Médias et miniatures chiffrés avant dépôt avec primitives/formats du SDK. Clés de médias seulement dans l'événement chiffré, noms et légendes également. Matrix définit les pièces jointes chiffrées, pas leur politique métier. [S10]
- Le scan antivirus serveur de contenu chiffré n'est pas possible sans lecteur supplémentaire. Prévoir restrictions de types/tailles, rendu sûr côté client et choix produit explicite. Ne pas envoyer de fichier déchiffré à un scanner externe par défaut.
- Signalement #77 : l'auteur choisit précisément messages/contexte/pièces joints et voit les destinataires. Proposition de nouveau canal E2EE réservé aux appareils des modérateurs habilités. Le serveur conserve dossier et actions minimales, pas une porte dérobée sur les conversations sources. Si une file serveur en clair est souhaitée, la décider et la décrire séparément.
- Révocation d'un modérateur : retrait de ses accès et clés futures de signalement, aucune promesse de retrait de ses copies antérieures. Recours, conservation des preuves et doublons à décider.
- Une preuve volontaire est une déclaration contextualisée, pas une garantie automatique de non-répudiation. Aucun accès universel ADMIN, aucun contenu transmis à l'IA premium #63, y compris à un fournisseur OpenAI.

## 9. Prototype autorisé et compilé, scénarios non exécutés

Autorisation confirmée par le coordinateur le 23 octobre 2026 à 01:26 UTC. Livré dans `../../prototypes/messaging-crypto/` : machine officielle OlmMachine 0.19.1, quatre appareils synthétiques (deux d'un même compte), transport standard Matrix simulé en mémoire, groupe, rotation, retrait de membre/appareil, perte et récupération via export chiffré SDK. **Aucun homeserver nécessaire pour ce prototype de primitive**, aucun réseau production, OIDC réel ou APNs. `Cargo.lock` livré. `cargo check --locked --offline --all-targets` et `cargo build --locked --offline --tests` réussis. Aucun scénario exécuté conformément à #84, donc aucune assertion ci-dessous acquise.

Hypothèses de laboratoire non transférables en production : confiance locale attribuée explicitement par fixture, `OnlyTrustedDevices` pour partager, déchiffrement `TrustRequirement::Untrusted` faute de cross-signing/SAS. La liste des membres vient du harness, pas d'une autorité scolaire. Un seul expéditeur est couvert par les sources de scénarios. Ni coffre iOS, ni durabilité, ni serveur malveillant, ni résidence ne sont qualifiés. Voir le README et SECURITY-REVIEW du prototype pour les avis corrigés, les limites et le risque backup PK.

La recette complète suivante reste à exécuter ultérieurement sur autorisation :

| ID | Recette à exécuter | Résultat exigé |
|---|---|---|
| SEC01 | Deux appareils vérifiés et un inconnu | Clair uniquement sur appareils approuvés, aucun partage silencieux à l'inconnu. |
| SEC02 | Groupe, arrivée et retrait, message ancien et futur | Historique conforme à la décision, aucun nouveau message lisible après retrait/rotation. |
| SEC03 | Retrait concurrent à envoi et reconnexion hors ligne | Ancienne audience refusée, reprise idempotente sans perte annoncée comme succès. |
| SEC04 | Perte d'appareil puis récupération OIDC seule | Aucun accès automatique aux clés/historique. |
| SEC05 | Récupération avec secret puis sans secret | Restauration autorisée dans le premier cas, perte expliquée sans fallback dans le second. |
| SEC06 | DB, média, cache, dump réseau et logs sentinelles | Aucun clair/clé privée/token, métadonnées inventoriées. |
| SEC07 | ADMIN non participant et autre école | Refus privé, médias, clés et signalements non autorisés, y compris API Matrix directe. |
| SEC08 | Signalement explicite et retrait du modérateur | Seulement les pièces sélectionnées, restrictions futures effectives. |
| SEC09 | Rejeu/corruption/changement de contexte | Rejet SDK et aucun faux succès durable. |
| SEC10 | Rollback/restauration backup | Droits retirés et suppressions non réactivés, clés anciennes non remises à un exclu. |
| SEC11 | App verrouillée, restauration téléphone, Keychain absent | Aucune clé de secours en clair, erreur bloquante. |
| SEC12 | Panne chat | Leçons et capture GPS indépendantes, aucune fausse confirmation de message. |

Avant utilisateurs : revue indépendante de l'intégration et de la chaîne de dépendances, examen des avis de sécurité amont au SHA retenu, tests PostgreSQL réels et tests Swift sur runner Apple, essais physiques de coffre/verrouillage. Un audit ancien de vodozemac ne suffit pas. Aucune mesure GPS/batterie/VoiceOver revendiquée ici.

## 10. Sources officielles consultées

Les identifiants servent de références aux constats amont, pas de validation des propositions Drivy. URLs en code pour copie et vérification. Pages mouvantes consultées le 23 octobre 2026.

- S1 : Matrix Rust SDK, maintenance, usage, périmètre et licence. `https://github.com/matrix-org/matrix-rust-sdk` et `https://raw.githubusercontent.com/matrix-org/matrix-rust-sdk/main/LICENSE`.
- S2 : binding Swift officiel et licence Apache-2.0. `https://github.com/matrix-org/matrix-rust-components-swift`.
- S3 : libsignal README et licence AGPLv3. `https://github.com/signalapp/libsignal` et `https://raw.githubusercontent.com/signalapp/libsignal/main/README.md`.
- S4 : IETF RFC 9420, protocole MLS et modèle de sécurité. `https://www.rfc-editor.org/rfc/rfc9420.html`.
- S5 : OpenMLS README, cibles et maintenance, licence MIT. `https://raw.githubusercontent.com/openmls/openmls/main/README.md` et `https://raw.githubusercontent.com/openmls/openmls/main/LICENSE`.
- S6 : mls-rs fonctionnalités, fournisseurs crypto, avertissement audit et licences. `https://raw.githubusercontent.com/awslabs/mls-rs/main/mls-rs/README.md`.
- S7 : vodozemac README, indication d'audit et licence Apache-2.0. `https://raw.githubusercontent.com/matrix-org/vodozemac/main/README.md` et `https://raw.githubusercontent.com/matrix-org/vodozemac/main/LICENSE`. Rapport lié non réaudité ici.
- S8 : Synapse, dépôt officiel et licence serveur. `https://github.com/element-hq/synapse` et `https://raw.githubusercontent.com/element-hq/synapse/develop/LICENSE-AGPL-3.0`.
- S9 : limitations officielles Megolm. `https://spec.matrix.org/latest/olm-megolm/megolm/`.
- S10 : Matrix Client-Server, sections E2EE, pièces jointes, vérification, secret storage et sauvegarde. `https://spec.matrix.org/latest/client-server-api/`.

## 11. État de livraison

Effectué : lectures locales, comparaison de quatre bibliothèques/protocoles, consultation des sources officielles/licences/avis, modèle de menace, retour rapide, prototype officiel synthétique écrit et compilé avec lockfile (quatre scénarios). Non effectué : choix produit approuvé, exécution des scénarios cryptographiques, compilation Swift, déploiement, audit live ou preuve de résidence. #67 reste ouvert, #68 non qualifié, minimum #77 non livré. Voir `messaging-residency-20261023.md` pour les flux et barrières d'activation.
