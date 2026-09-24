# Intégration mobile transverse : frontières, cycle de vie et distribution

> Référence 3.10 · [Index](../README.md). Propositions d’implémentation pour le client natif. Les [contrats API](api.md) et [règles métier](../03-fonctionnel/regles-etats.md) restent les autorités correspondantes.

## 1. Une architecture mobile limitée au nécessaire

Le domaine reste serveur : affectation, place, droit de pack, résultat de leçon et publication ne sont pas décidés par un écran. Le client connaît ses brouillons et la capture locale autorisée. Le web n’acquiert pas les capacités d’une app installée parce que ses composants sont en TypeScript.

```text
App téléphone / tablette
  Navigation + UI adaptées à la plateforme
            ↓ commandes / projections
  Application locale : session, brouillons, file de synchronisation
       ↓                     ↓                    ↓
  CapturePort           MapPresentationPort   Intégration système
  (source native)       (dessiner / caméra)   (auth, liens, push, fichiers)
       ↓
  Stockage chiffré : segments, manifeste, états durables
            ↓ transferts bornés et opérations identifiées
       API Drivy commune → services métier → PostgreSQL / stockage privé
```

**Contrats internes proposés**, pas nouveaux DTO HTTP :

| Frontière | Responsabilité | Ce qu’elle n’a pas le droit de faire |
|---|---|---|
| `CapturePort` | Démarrer après autorisation, recevoir/persister des mesures, pauser/arrêter, décrire erreurs natives | Choisir un élève, débiter un pack, publier, prolonger une autorisation |
| `MapPresentationPort` | Présenter segments/observations autorisés, cadrer et gérer suivi caméra | Démarrer un GPS parce qu’une carte est visible ; reconstituer un segment absent |
| `SecureLocalStore` | Transaction locale et clé protégée, migrations, purge des caches | Considérer un tombstone distant comme une simple couleur de ligne |
| `AuthSessionPort` | Session système, tokens, revalidation, logout | Stocker un secret de client public ou autoriser un rôle depuis un claim ancien seul |
| `LinkRouter` | Valider domaine/path, conserver destination et relire après connexion | Confirmer une inscription à partir d’un paramètre de lien |
| `NotificationPort` | Enregistrer installation/jeton, demander le droit utile, afficher contenu minimal | Garantir livraison ou transformer un push en commande de collecte |

Ces frontières peuvent être de simples modules dans le dépôt, pas six bibliothèques publiées, microservices ou mécanismes d’injection complexes. Isoler uniquement ce qui varie ou a une responsabilité de sécurité/lifecycle.

## 2. Autorités et états visibles

La [spécification GPS](../03-fonctionnel/gps-replay.md) sépare autorisation serveur, collecteur local, transport et publication. Ces états ne sont pas aplatis en une booléenne `isRecording`. La leçon peut être terminée alors que des points sont encore à envoyer ; l’upload peut être terminé sans publication. L’app d’un second appareil n’affirme pas un état live qu’elle ne connaît pas.

La source de mesure écrit sur un chemin durable indépendant du montage d’écran. Les remontées UI sont regroupées pour ne pas réafficher toute la liste d’élèves à chaque position. Une erreur de carte ou une animation lente ne doit pas annuler le stockage. En revanche, une impossibilité durable de conserver les points doit être signalée et traitée, pas cachée derrière un indicateur vert.

L’acquittement local signifie persistance réussie, non réception par serveur. L’acquittement distant signifie résultat de la commande vérifié, non simple succès de transport. Les mutations sensibles gardent l’identité d’opération à travers timeout, changement d’écran et relance ; respecter 202/PENDING et la reprise définie en V3.2.

## 3. Cycle de vie et interruptions

| Événement | Réponse attendue du client | Pas de promesse implicite |
|---|---|---|
| Rotation / redimensionnement | Recomposer, garder identité et source de capture | Pas de double collecteur ni perte de brouillon |
| Passage au fond / verrouillage | Poursuivre seulement par le profil natif autorisé ; file durable | Pas de tâche Swift présumée toujours exécutable après suspension |
| Réseau absent après départ autorisé | Conserver dans les limites existantes, indiquer transfert différé | Ni nouvelle réservation confirmée ni nouvelle autorisation hors ligne |
| Processus arrêté | Réconcilier au prochain accès ce qui est effectivement écrit | Pas de reconstruction de points manquants |
| Utilisateur force l’arrêt | Ne pas contourner le choix ; capture partielle explicitée au retour | Pas d’auto-relance cachée pour surveiller |
| Arrêt demandé | Couper la source locale, borner callbacks tardifs, sceller et envoyer plus tard | L’absence de réseau ne bloque pas l’arrêt |
| Jeton expiré | Protéger les données locales, reprendre auth/envoi selon droits et preuves actuels | Pas d’allongement de droit de collecte |
| Déconnexion / changement de compte | Arrêter la collecte, résoudre données locales dans le périmètre et purger ce qui doit l’être | Ne jamais envoyer les points du compte A sous le compte B |
| Révocation apprise du serveur | Stopper accès/collecte et appliquer purge selon règle | Pas d’effacement instantané garanti sur appareil déconnecté |

Un timestamp modifiable ne suffit pas à prolonger le budget de collecte. Conserver les références temporelles nécessaires dans le profil d’implémentation, tester changement d’heure et redémarrage, et rejeter les points hors bornes au serveur. Ne pas inventer une nouvelle durée maximale en contradiction avec l’autorisation existante. La référence Apple est le collecteur Swift ; le futur collecteur Android devra satisfaire les mêmes invariants métier avec ses propres mécanismes OS.

## 4. Authentification et ouverture de liens

Pour le client natif public, utiliser le parcours OIDC Authorization Code avec PKCE dans le navigateur/session d’authentification système, plutôt que lire des mots de passe dans une WebView intégrée. [S77](../06-gouvernance/sources.md#s77). Vérifier state, nonce, issuer, redirect URI et association de session. Le BFF web conserve son propre mécanisme de cookie sécurisé ; ne pas copier le refresh token mobile dans le stockage web.

Proposition de routage : accepter uniquement les domaines possédés et chemins enregistrés pour invitation, leçon, cours ou bilan ; transmettre un identifiant opaque, pas une date de naissance, un email ou une position dans l’URL. Ouvrir à froid/chaud produit le même résultat. La destination peut survivre à la connexion, mais elle est revalidée dans l’école choisie. Un redirect arbitraire n’est pas suivi. Un lien partagé donne au mieux l’accès déjà autorisé, pas les droits de son émetteur.

Universal Links et Android App Links reposent sur l’association vérifiée entre app et site. [S78](../06-gouvernance/sources.md#s78), [S79](../06-gouvernance/sources.md#s79). Conserver une page web utilisable si l’app manque ou ne traite pas le lien. Une installation ne réserve jamais un cours. Les liens de réinitialisation/invitation et leurs tokens ne sont ni journalisés ni conservés dans l’historique analytique.

## 5. Données locales, secrets et sauvegardes

**Apple : Security/Keychain natif**, avec accessibilité explicitement choisie pour le stockage requis sous verrouillage [S100](../06-gouvernance/sources.md#s100). Aucun token/secret dans `UserDefaults`, une constante ou un log. Une réinstallation ou une restauration ne suffit pas à établir une session métier : revalider l’identité et l’installation. Android aura son coffre/Keystore qualifié séparément.

Le dossier retient une base locale chiffrée. SQLCipher natif est le candidat Apple ; son chiffrement doit être activé et démontré sur le binaire construit [S104](../06-gouvernance/sources.md#s104). Vérifier base, WAL, journaux, fichiers temporaires, pièces et exports locaux. L’aperçu du sélecteur d’app protège les écrans personnels sans arrêter artificiellement le collecteur. [Conception de persistance](architecture-client-swift.md#persistance).

Politique proposée : exclure secrets, traces et brouillons sensibles des sauvegardes grand public et transferts automatiques tant que la restauration chiffrée et les responsabilités ne sont pas explicitement conçues. La politique Keychain ne protège pas, à elle seule, toute la base Drivy. Ne pas promettre de récupérer un brouillon non envoyé après désinstallation. Annoncer cette limite avant une action qui l’efface.

Tester clé inaccessible après changement biométrique, réinstallation avec credentials résiduels, restauration sans clé et changement de compte. Une nouvelle installation ne reçoit pas automatiquement une identité active en se fiant à un ancien secret ; revalidation serveur et politique locale explicites. Une erreur cryptographique ne conduit jamais à créer une copie non chiffrée « pour continuer ».

## 6. Notifications, fichiers et services externes

L’outbox backend décrit l’intention ; le client Apple utilise l’inscription APNs native et UserNotifications, avec adaptation serveur explicitement qualifiée [S105](../06-gouvernance/sources.md#s105). Distinguer tokens/environnements de distribution, renouvellement et révocation. Un seul transport de push est retenu par installation ; le centre in-app garde ses identifiants de déduplication. Android futur pourra employer FCM ou un transport approuvé sans ajouter une seconde base métier Firebase. Aucun relais de framework mobile n’est requis pour Apple.

Le contenu externe est minimal et le contenu complet se relit sous droits. Une annonce de cours n’inscrit pas ; une notification de modification n’est pas une reconfirmation. Le calendrier interne Drivy n’exige pas l’accès aux calendriers OS. Une exportation personnelle ultérieure nécessitera une décision sur consentement, doublons et mise à jour, pas une permission anticipée.

Les sélecteurs système de fichiers/photos sont préférés à une lecture large de la médiathèque. Conserver l’extension et le nom d’origine comme métadonnées non fiables ; vérifier contenu/taille côté pipeline existant. Un fichier encore en quarantaine ne s’affiche pas comme prêt. L’export dans une autre app est volontaire et sa copie externe ne peut pas être révoquée à distance par Drivy.

Les fournisseurs de cartes, auth, crash et push figurent dans l’inventaire de traitement. Leur présence peut transmettre des métadonnées même sans achat de publicité ; inspecter le comportement réel. Pas de capture d’écran automatique des bilans dans la télémétrie, pas de coordonnées ni textes pédagogiques dans breadcrumbs/logs. Le monitoring reste technique : code d’erreur, version, durée agrégée et corrélation opaque minimale.

## 7. Transferts et distribution native

**Référence Apple : URLSession pour les commandes et chunks JSON existants.** Les files durables chiffrées sont reprises lorsque l’app peut s’exécuter, notamment à son retour au premier plan. Un envoi GPS ne constitue ni une publication ni une nouvelle autorisation de collecte. L’acquittement est celui du contrat ; un timeout garde la même clé de commande. [Client HTTP Swift](architecture-client-swift.md#api-swift).

Un transfert système de fichier en arrière-plan n’est pas promis par défaut. Avant de l’ajouter, spécifier fichiers temporaires/protection, droits courants, expiration de session, redirections, annulation et réponse serveur. Ne pas contourner le chiffrement au repos avec une copie en clair pour faciliter ce transfert. Le calendrier de tâches de fond n’est pas une garantie de délai.

**Distribution Apple : binaire signé, TestFlight puis canal public retenu.** Le projet Xcode et les dépendances SwiftPM produisent un artefact identifié. Les environnements, entitlements, domaines et identifiants d’app ne sont pas mélangés. Distinguer version marketing, numéro de build, schéma local et version API. Pas de mise à jour de code par bundle JavaScript distant ; les configurations distantes ne contiennent que les paramètres autorisés de fonctions déjà livrées.

Ne pas imposer un redémarrage applicatif ou une migration initiée par Drivy pendant une capture. L’app ne peut pas garantir d’empêcher une terminaison ou un remplacement par l’OS : le journal doit permettre de retrouver une capture partielle et ses données déjà persistées au prochain lancement. Les migrations sont atomiques, interrompables de façon contrôlée et n’ouvrent pas une base plus récente avec un ancien schéma en silence. Un retour de binaire n’est ni toujours distribuable ni une inversion automatique des données.

Maintenir une compatibilité API définie pour les versions supportées. Un client trop ancien reçoit un parcours de mise à jour expliqué ; la collecte en cours peut toujours être arrêtée localement. Élargir le déploiement après preuve sur la cohorte de test. La reprise des données et les scénarios MOB033–MOB034 sont distincts d’une promesse de mise à jour sans aucune interruption.

<a id="cloture-compte"></a>
## 8. Suppression globale : contrat courant, validation avant publication

La [spécification F01/F14](../03-fonctionnel/compte-suppression-globale.md) définit AP193–AP198 et AP200, J29/E49, états et suivi après révocation. AP76–AP80 restent scolaires et ne suffisent pas à clôturer une identité multi-écoles. Distinguer SUBMITTED et COMPLETED, et ne jamais remplacer suppression par désactivation.

Depuis Compte, « Supprimer mon compte Drivy » reste distinct de quitter l’école ou demander l’effacement d’un trajet. Présenter le périmètre complet, les traitements concernés, les rétentions justifiées, le délai annoncé et le suivi. Réauthentifier de façon proportionnée et confirmer une demande durable dédupliquée. L’aperçu est paginé au-delà de cent appartenances, sans assistance obligatoire et sans limiter la confirmation à la page visible.

L’orchestrateur coordonne identités, appartenances, données et fournisseurs. Le dernier ADMIN est traité avant PROCESSING dans un processus motivé et suivi, sans suppression de toute l’école ni promotion automatique du support. La porte d’accès globale et les commandes ordinaires respectent le même [ordre de commit](transactions-v2.md#autorisation-et-commit). Les jobs internes ne rétablissent aucune session normale du compte CLOSING.

**DM06 reste un blocage de publication :** le contrat existe, mais fournisseur d’identité, procédure du dernier administrateur, pouvoirs, rétentions, délais, orchestration et essais réels sont à valider. Le reçu limité ne donne aucun accès aux leçons, écoles, trajets ou anciennes sessions. Les sauvegardes et dérivés suivent les procédures d’effacement documentées.

Les exigences externes sont distinguées des choix de Drivy : [S91/S92](../06-gouvernance/sources.md#s91), avec reconsultation Apple [S110](../06-gouvernance/sources.md#s110). Un traitement manuel interne peut être nécessaire ; il n’impose pas un appel ou un email de l’utilisateur pour déposer sa demande. Le [registre courant](../06-gouvernance/audit-corrections-v3-10.md#decisions) suit ce qui manque réellement, et non une absence de routes déjà ajoutées.

## 9. Sécurité et observabilité vérifiables

Utiliser OWASP MASVS pour structurer les essais stockage, authentification, réseau, plateforme, code et confidentialité. [S90](../06-gouvernance/sources.md#s90). TLS avec validation standard, absence de clés serveur dans l’app et droits courants restent nécessaires. Le certificate pinning n’est pas ajouté comme formule magique : une éventuelle adoption exige modèle de menace, rotation et récupération, sans casser l’accès légitime lors d’un renouvellement.

Mesures proposées : temps jusqu’à un état UI reconnu, latence d’écriture locale, taille des files, taux de reprise d’envoi, incidents de capture et interruptions expliquées. Aucune télémétrie de production ne doit exiger la trace complète pour comprendre un crash. Les budgets chiffrés et consentements sont fixés avant collecte, avec jeux fictifs et essais contrôlés.

## 10. Livrables d’intégration

La [matrice de build](../annexes/matrice-build-mobile-v3-4.json) est un gabarit non qualifié. La [recette mobile](../05-realisation/qualification-mobile-ui-ux.md) complète les tests métier existants sans les déclarer exécutés. Chaque release documente capacité, preuve, limite et version ; l’étiquette « iOS/Android » n’est pas une preuve suffisante.

<a id="v37-appartenance-preuve-et-notifications-en-transit"></a>
## Appartenance, preuve et notifications en transit
L’intégration respecte [R112](../03-fonctionnel/regles-etats.md#r112) : une liaison technique native peut avoir plusieurs routes scolaires du même compte, mais ne continue pas à viser l’ancien propriétaire après réaffectation connue du serveur. Un refus de push garde le calendrier et le centre interne. En déconnexion hors ligne, aucune garantie de rappel fournisseur n’est possible : payload générique, nettoyage local quand exécutable, relecture autorisée à l’ouverture.

La correction de présence et la résolution de droit sont deux opérations UX distinctes. Le récapitulatif de décompte/renonciation est confirmé par le responsable avant effet ; on ne rajoute pas un dialogue à chaque frappe du relevé. L’orientation correspond à la prévention des erreurs significatives documentée par W3C pour le web [S114](../06-gouvernance/sources.md#s114) ; son adaptation au natif est une recommandation Drivy, pas une certification WCAG de l’app.

## Fichiers, caches et passage en arrière-plan

Le [profil natif de transport/confidentialité](architecture-client-swift.md#confidentialite-transports) complète la persistance : sessions API et staging séparées, absence de cache HTTP disque sensible, validation d’origine et couverture des scènes avant snapshot. Le GPS autorisé demeure un service indépendant de cette couverture ; aucun enregistrement n’est créé ni arrêté par sa seule présentation. Le web n’utilise pas Service Worker/Cache API pour garder implicitement les dossiers ou exports ; tout mode hors ligne supplémentaire demande un périmètre défini et une purge vérifiable.

La [reprise des pièces](fichiers-temps-communications.md#reprise-depot) est un workflow complet contrôlé, pas une promesse d’upload par fragments. Une réponse de transport ambiguë se réconcilie avant nouvelle intention. La consultation d’un export ne confirme ni encaissement ni suppression du compte.
