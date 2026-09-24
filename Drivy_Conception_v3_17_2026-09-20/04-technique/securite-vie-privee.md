# Sécurité, données personnelles et cadre suisse à valider

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Qualification du cas mineur : trois questions indépendantes

Avant données réelles, distinguer : qui peut accepter les conditions contractuelles ; quelles données justificatives sont nécessaires et proportionnées ; un représentant dispose-t-il d’un accès, à quoi et sous quel fondement. Ne déduire ni accès parental aux trajets ni consentement universel d’un âge. Les affirmations juridiques du rapport externe ne sont pas transformées ici en règles validées ; Q06 et DM06 exigent une qualification compétente. Le suivi des échéances de permis/cours reste un besoin à vérifier auprès des écoles avant modélisation.

## Portée et statut juridique

Cette analyse identifie les points à instruire ; **elle ne certifie pas une conformité juridique**. Elle s’appuie sur les pages officielles du PFPDT accessibles lors de la recherche, pas sur une lecture complète des textes consolidés Fedlex. Les obligations précises de l’école, du prestataire, de conservation comptable et les conditions applicables aux mineurs doivent être validées avant traitement réel. Les durées proposées ci-dessous sont des décisions de conception à approuver, non des délais imposés par la loi.

Les principes de protection dès la conception et par défaut justifient ici minimisation, accès par formation et séparation des finalités. La synthèse officielle traite notamment information, risques et obligations d’annonce ; elle ne justifie pas d’appliquer automatiquement une règle européenne de 72 heures à chaque incident suisse [S15](../06-gouvernance/sources.md#s15). Le déclenchement d’une analyse d’impact dépend du risque du traitement, à évaluer pour le montage réel, particulièrement avant le pilote GPS désormais central [S19](../06-gouvernance/sources.md#s19).

## Responsabilités et prérequis de lancement

**Hypothèse de travail :** chaque école détermine ses finalités de gestion pédagogique, et l’exploitant de Drivy traite ces données pour son compte. Cela ne règle pas automatiquement les traitements propres de Drivy tels que gestion des comptes, sécurité ou facturation du service. Formaliser un tableau finalité → responsable → sous-traitant → destinataires, puis faire approuver contrats et notices. Le PFPDT décrit les responsabilités en sous-traitance et le contrôle des sous-traitants ultérieurs [S20](../06-gouvernance/sources.md#s20).

Aucun fournisseur n’est déclaré « suisse donc conforme ». Documenter pays de stockage, accès de support, sauvegardes, emails, identité, logs et sous-traitants ; analyser les communications à l’étranger et les garanties pertinentes avec les sources officielles [S17](../06-gouvernance/sources.md#s17). Un datacenter en Suisse ne prouve pas à lui seul que tout accès est limité à la Suisse.

Avant le premier pilote réel : responsable identifié ; registre de traitements ; notice de collecte ; procédure de droits ; politique de rétention signée ; accord de sous-traitance ; qualification des fournisseurs ; contact d’incident ; approbation du traitement des élèves mineurs selon situations réelles. Ne pas inventer un consentement parental universel fondé sur un âge arbitraire. Le service peut accueillir des élèves mineurs selon catégories : la procédure doit être instruite, pas contournée en cochant une case généralisée.

## Classification et minimisation

| Catégorie | Finalité proposée | Lecture normale | Interdictions de conception |
|---|---|---|---|
| Identité et appartenance | Connexion, bon établissement et rôle | Personne, gestion scolaire limitée | Recherche publique par email, fusion inter-écoles automatique. |
| Planning et lieu | Organiser la leçon | Élève concerné, son moniteur, administration | Exposer noms/lieux d’un autre élève dans les conflits ou emails collectifs. |
| Bilans et observations | Préparer la prochaine étape pédagogique | Élève et moniteurs affectés, brouillon privé | Notes de santé ou jugements personnels sans nécessité ; score global d’aptitude. |
| Justificatif de permis | Contrôle humain d’une pièce nécessaire | Contrôleurs autorisés et personne selon audience | OCR général ou collecte systématique de verso non nécessaire ; pièce en notification. |
| Règlements internes | Vérifier charge et encaissements déclarés | Personne, moniteur selon périmètre, ADMIN | Numéros de carte, identifiants bancaires non utiles ou promesse de comptabilité fiscale. |
| Logs et audit | Diagnostic, responsabilité des actions | Exploitant habilité, école selon finalité | Corps de bilan, token, URL signée complète, coordonnées GPS détaillées. |
| GPS du cœur | Relecture pédagogique explicitement choisie | Participants et affectations autorisées | Suivi permanent, géolocalisation des élèves hors leçon, partage public par défaut. |

Les observations de conduite et les trajets sont des données personnelles nécessitant protection ; leur qualification juridique exacte et les risques contextuels restent à analyser. Ne pas présenter chaque coordonnée comme une catégorie juridique automatiquement identique à une donnée de santé. Interdire les champs libres invitant à recueillir un diagnostic médical au pilote.

## Information au bon moment

À l’invitation : expliquer école, finalités, destinataires et contact. Au dépôt : finalité et audience de la pièce avant envoi. Avant chaque première procédure GPS puis selon version/choix applicable : démarrage/arrêt, visibilité, conservation et alternative sans suivi, distincts de la permission technique du système. Dans Compte : notice stable, accès aux demandes et état d’instruction. Le contenu exact doit refléter le montage réel, conformément au devoir d’informer décrit par le PFPDT [S18](../06-gouvernance/sources.md#s18).

Une autorisation caméra ou localisation délivrée par iOS/Android n’est ni un accord contractuel général, ni la preuve que toute utilisation ultérieure des données est licite. Refuser une permission facultative ne doit pas empêcher la réservation, la leçon ou le bilan textuel.

## Menaces et contrôles prioritaires

| Menace | Prévention | Détection et test requis |
|---|---|---|
| Identifiant d’une autre école dans une URL | Autorisation courante, clés étrangères composites, RLS avec rôle contraint | Tests croisés A/B sur liste, détail, sync, export et téléchargement. |
| Token encore valable après révocation | Appartenance et epoch contrôlées au serveur pour chaque commande | Rejouer un ancien token après retrait ; aucun effet métier. |
| Appareil perdu | Base native chiffrée, clé protégée, durée d’accès bornée, verrouillage d’app | Essai sur build réel, backup/restore du téléphone, logs locaux inspectés. |
| Injection ou XSS dans notes/nom de fichier | Texte rendu sans HTML arbitraire, paramètres SQL, CSP web, encodage des sorties | Corpus de caractères, liens, noms pathologiques ; aucun script exécuté. |
| Fichier malveillant ou accès direct bucket | Pipeline fermé, scan, limites, clé aléatoire, passerelle de lecture | Tests MIME falsifié, PDF actif, fichier surdimensionné et ticket volé. |
| Compte d’administration détourné | MFA pour personnel privilégié, réauthentification actions sensibles, accès support temporaire | Récupération de compte, retrait dernier ADMIN, double contrôle de purge. |
| Double commande ou concurrente | Idempotence, versions, verrous, contraintes SQL | Réponse perdue puis réessai ; deux transactions réellement concurrentes. |
| Fuite par télémétrie | Journal minimal, filtrage avant émission, environnement séparé | Scanner logs et captures d’erreur avec données fictives sentinelles. |
| Fournisseur ou sauvegarde indisponible | Contrats, export, sauvegarde indépendante, restauration éprouvée | Exercice de perte primaire, vérification d’objets et de clés. |

Le chiffrement ne remplace ni permissions ni minimisation. Un SQLCipher configuré dans un fichier n’est pas une preuve de chiffrement d’un build installé ; la capacité doit être vérifiée sur chaque plateforme [S23](../06-gouvernance/sources.md#s23). RLS exige un rôle correct et n’élimine pas toutes les menaces de l’application [S26](../06-gouvernance/sources.md#s26).

## Authentification et secrets

OIDC Authorization Code + PKCE avec navigateur système natif ; validation issuer, audience, state/nonce et redirections exactes. Côté web, BFF et cookies `Secure`, `HttpOnly`, portée `__Host-` ; contrôle Origin et CSRF pour mutations. Aucun refresh token dans localStorage. Le fournisseur candidat documente le flux OIDC, pas la configuration effective de Drivy [S31](../06-gouvernance/sources.md#s31).

Les clés API email, stockage, OIDC et chiffrement ne sont ni dans l’app distribuée, ni dans le dépôt documentaire. Stockage dans un gestionnaire de secrets qualifié, comptes distincts par environnement et privilèges minimaux. Clés de migrations distinctes de l’API. Rotation préparée avec période de recouvrement pour clés de signature lorsque nécessaire ; révocation immédiate d’un secret compromis. Les sauvegardes de clés nécessaires à la restauration sont chiffrées et contrôlées séparément des sauvegardes de données.

## Téléchargement et révocation

Les tickets de téléchargement renvoient vers **une passerelle Drivy authentifiée**, pas vers une URL S3 publique ou un lien pré-signé autonome exposé au client. À chaque lecture, la passerelle vérifie session, école, droits actuels, état READY, audience, portée du ticket et expiration. La révocation bloque les nouveaux téléchargements même si le ticket a été émis auparavant. Un flux déjà reçu ne peut pas être récupéré à distance. Une interruption de session coupe au mieux les flux encore actifs, sans prétendre effacer les octets déjà copiés.

Les tickets de dépôt peuvent autoriser une écriture limitée vers le stockage objet ; la finalisation et la publication requièrent encore les droits courants. Un envoi qui termine après révocation reste en quarantaine et est éliminé selon politique, jamais rendu lisible automatiquement. Les logs de passerelle retirent tokens et paramètres de ticket.

## Politique de conservation proposée, non juridique

| Données | Paramètre de produit proposé | Point de départ / mécanisme | Validation requise |
|---|---|---|---|
| Invitation | 7 jours de validité | Émission ; renvoi révoque l’ancienne | Besoin de l’école et notice. |
| Accès hors ligne | 24 h au maximum | Dernière validation de droits, sans prolongation par l’horloge locale | Risque appareil et usage terrain. |
| Snapshot temporaire | 10 minutes | Création, purge même si non téléchargé | Volumes et lenteur réseau. |
| Ticket dépôt / lecture | 10 minutes / 60 secondes | Émission ; contrôle de droits lors de lecture | Qualification stockage et passerelle. |
| Dépôt incomplet / fichier rejeté | Purge après 24 h / 7 jours | Dernier essai / décision de rejet ; métadonnées minimales de cause | Support nécessaire sans garder un malware indéfiniment. |
| Export prêt | 24 h | Mise à disposition, suppression automatique de l’archive | Délai d’accès convenu, nouvelle génération possible. |
| Journal de changements sync | 30 jours | Commit ; au-delà nouveau snapshot | Volume et besoin hors ligne. |
| Logs techniques expurgés | 30 jours | Émission | Finalité et budget, pas d’archive générale permanente. |
| Audit d’accès et d’actions | 12 mois proposés | Action ; gels instruits séparément | Justification et besoin de preuve à approuver. |
| Sauvegardes tournantes | 30 jours proposés | Création ; expiration effective vérifiée | RPO/RTO, contrats et obligations applicables. |
| Bilans, dossiers et pièces de permis | **Pas de durée arbitraire retenue** | Calendrier par catégorie à approuver avant pilote ; pièce invalidée non utilisée comme contrôle courant | École, finalité, obligations, contestations, minimisation. |
| Règlements et preuves d’opérations | **Durée métier/légale à déterminer** | Catégorie financière et besoin de preuve | Ne pas reprendre automatiquement le paramètre des logs. |
| GPS du cœur | 30 jours proposés pour trace brute | Fin de leçon ; conservation pédagogique distincte à justifier | Analyse de risques et décision avant toute collecte réelle du pilote F15. |

Les paramètres techniques sont centralisés dans une configuration versionnée, avec propriétaire et alerte de purge échouée. « Durée non encore approuvée » bloque l’entrée de données réelles de cette catégorie ; ce n’est pas une autorisation de conserver indéfiniment. Un éventuel gel de conservation est motivé, limité à une portée et réévalué.

## Droits, export, rectification et effacement

Le PFPDT décrit les possibilités de connaître et faire valoir ses droits [S16](../06-gouvernance/sources.md#s16). Drivy propose : dépôt d’une demande, accusé sans promesse de délai légal non vérifié, vérification proportionnée de l’identité, recherche dans les écoles concernées, examen des restrictions et réponses séparées lorsque nécessaire. Un ADMIN ne reçoit pas automatiquement les bilans confidentiels de tous les élèves par le biais d’un export global.

L’export d’une personne contient un manifeste, un JSON structuré, une lecture Markdown ou HTML simple et les pièces partageables autorisées. Il indique portée, date et exclusions motivées. Il exclut secrets, pièces d’autres personnes et logs internes non pertinents. L’identité OIDC globale et chaque dossier scolaire sont instruits sans supprimer les autres appartenances. Un lien d’export n’est délivré qu’à l’intéressé vérifié ou à un mandataire explicitement habilité.

Rectifier une adresse met à jour la donnée courante avec audit minimal. Rectifier un bilan publié produit une nouvelle révision ou un retrait motivé ; il ne réécrit pas invisiblement la parole passée. Un mouvement financier réel n’est pas détruit par une demande générique : analyser ce qui doit être conservé et informer de la décision.

Une purge approuvée produit un plan des objets, références et sauvegardes, requiert un second contrôle, masque les données courantes, détruit les objets autorisés et enregistre des tombstones sans contenu personnel superflu. Toute restauration réapplique ces décisions avant ouverture aux utilisateurs. Le résultat d’une purge comprend éléments supprimés, éléments retenus et motif, échecs résiduels et nouvelle tentative. Voir [runbooks](../05-realisation/deploiement-exploitation.md).

## Gestion d’incident

Détecter, contenir, préserver une trace minimale, qualifier les données et personnes exposées, identifier le responsable de traitement et apprécier les obligations d’information ou d’annonce. Les décisions et leur chronologie sont consignées. La marche à suivre et le contact PFPDT applicables doivent être re-vérifiés au moment de l’incident ; ne pas attendre un délai arbitraire ni promettre qu’un incident bénin ou grave a déjà été juridiquement qualifié.

Le pilote ne démarre pas sans exercice sur un scénario de compte révoqué, fuite de ticket, perte de stockage et restauration après effacement. Les failles bloquantes sont corrigées avant réouverture, même si cela retarde la disponibilité d’une fonctionnalité.

## Menaces introduites par le cœur V2

| Risque | Prévention et détection | Limite explicite |
|---|---|---|
| Tracking après la leçon | Arrêt local obligatoire, autorisation bornée, cutoff serveur et indicateur de collecte | Appareil compromis : pas de garantie physique absolue. |
| Refus GPS contourné | Choix métier distinct des permissions OS, contrôle avant capture | Un refus verbal doit être enregistré immédiatement par l’opérateur. |
| Géolocalisation dans logs/push | Schémas de logs en liste blanche et payloads minimaux | Un fond de carte peut impliquer un fournisseur, à qualifier. |
| Dernière place ou dernier droit vendu deux fois | Transaction commune, verrou école/planning puis ressources et droits | Mécanisme à tester réellement, pas preuve par diagramme. |
| Fuite d’identité dans cours | Pas de liste participants pour élèves ; compteurs agrégés | Le formateur a besoin d’une liste nominative sous finalité de présence. |
| Campagne envoyée après sortie/validation | Relecture des droits/statut à envoi et deep link authentifié | Un push déjà accepté peut encore parvenir au terminal. |
| Preuve d’accomplissement fabriquée | Présences et validation séparées, preuve et auteur audités | L’outil ne certifie pas indépendamment la vérité de l’attestation fournie. |
| Pack modifié rétroactivement | Snapshots et ledger immuable | Les conditions commerciales doivent être obtenues, non devinées. |

La classification légale de chaque traitement se qualifie avec le montage réel. Une trace est traitée comme hautement confidentielle par décision produit, sans affirmer que toute coordonnée relève automatiquement d’une catégorie légale particulière. Le devoir d’information est vérifié auprès du PFPDT [S47](../06-gouvernance/sources.md#s47).

La proposition de 30 jours pour les traces brutes reste à valider. Les dérivés, publications, sauvegardes et preuves de présence n’héritent pas automatiquement de cette durée. Aucun paramètre ne peut être laissé à « infini » sans finalité justifiée. L’approbation du profil de conservation et la procédure pour mineurs/salariés restent un gate avant données personnelles réelles.

## Revue de menace V3

| Menace | Contrôle proposé | Recette |
|---|---|---|
| Web traité comme compte superadministrateur | Même autorisation par école/affectation ; grants et listes/agrégats filtrés | T200,T227 |
| Collecte initiale excessive | Catalogue de finalités/stades borné ; photo facultative ; GPS/push distincts | T170,T177–T178 |
| Fuite de naissance/adresse dans tableaux, URLs ou logs | API profil séparée ; redaction logs ; no-store ; aucune PII dans URL de filtre/analytics | T201,T232 |
| Copie de profil d’une école à l’autre | Reprise personnelle explicite limitée ; aucune pièce ni permission transférée | T180 |
| Faux choix GPS signé par personnel | Source/acteur, choix par séance et procédures séparées | T185 |
| Tablette partagée révélant un autre dossier | Compte propre, verrou, purge et présentation publiée seule | T197,T198 |
| Lot d’archivage forcé ou accès retiré | Preview non autorisante, recontrôle par ligne, journal et résultats explicites | T207–T213 |
| Export utilisé comme extraction massive | Grant dédié, scope, plafond, expiration, accès courant à la génération et au téléchargement | T229,T231 |
| Formule dans CSV | Neutralisation des cellules, test tableurs cibles | T230 |

Les principes d’autorisation/session sont documentés par OWASP [S55](../06-gouvernance/sources.md#s55), [S56](../06-gouvernance/sources.md#s56). L’export CSV requiert un traitement spécifique [S57](../06-gouvernance/sources.md#s57). Il s’agit d’une conception à tester, pas d’un audit de sécurité exécuté.

Le devoir d’informer documenté par le PFPDT [S47](../06-gouvernance/sources.md#s47) motive une information claire sur finalités/destinataires. La photo et l’âge ne justifient pas de collecter par défaut documents d’identité complets, santé ou numéro AVS. Aucune règle parentale ou obligation de naissance/adresse uniforme n’est déduite sans qualification par prestation. Les responsabilités école/éditeur, mineurs, salariés, hébergement et conservation doivent être approuvées avant pilote.

Les notifications de cours et GPS ne sont pas des consentements généraux. Une information lue, une acceptation contractuelle et une autorisation de localisation du système sont des objets distincts. Les graphiques de refus GPS et classements d’instructeurs ne font pas partie des métriques. Un téléchargement volontaire peut rester sur le poste client après révocation : cette limite doit être annoncée et encadrée par organisation/formation, pas dissimulée par une promesse d’effacement distant.

## Lecture de snapshots après retrait et droits concurrents

L’accès au bilan ne rend pas irrévocable celui à sa géométrie. Les projections de [R48](../03-fonctionnel/regles-etats.md#r48) interdisent de renvoyer des coordonnées avec une simple étiquette DELETED. Les exports, URLs temporaires, miniatures et données enrichies sont invalidés avec la capture. L’immutabilité de preuve n’autorise pas à conserver des positions dont l’effacement est dû.

La relecture des droits au début d’un handler ne garantit pas seule l’ordre avec une révocation concurrente. [R02](../03-fonctionnel/regles-etats.md#r02) et l’ordre de verrouillage fixent cette frontière ; une révocation peut attendre une transaction déjà autorisée, mais son effet commité interdit une nouvelle écriture sous cette ancienne autorisation. Les tests d’accès réels et de restauration de sauvegarde restent requis.

## Intégration stores et binaire mobile

Les [guides iOS](integration-ios-ipados.md) et [Android](preparation-android.md) ajoutent l’examen du binaire réel : permissions générées, SDK, manifeste de confidentialité, déclarations de données et flux de tiers. La collecte GPS pédagogique n’est pas assimilée automatiquement à du tracking publicitaire, mais les fournisseurs restent à analyser.

Le parcours global de suppression de compte est distinct des demandes scolaires ; [DM06](integration-mobile-transverse.md#cloture-compte) bloque la publication publique tant que son contrat et son traitement ne sont pas définis et testés. Les [cas MOB035/MOB036](../05-realisation/qualification-mobile-ui-ux.md#mob035) vérifient ces éléments sur la future implémentation, pas dans cette passe documentaire.


<a id="suppression-globale-et-secrets-de-suivi-v35"></a>
## Suppression globale et secrets de suivi
Le [contrat global](../03-fonctionnel/compte-suppression-globale.md) est indépendant d’un tenant actif. Contrôler l’auteur depuis la session serveur ; aucun ADMIN ne désigne une personne tierce à supprimer. Le reçu de suivi est opaque, limité et vérifié dans un domaine distinct des tokens OIDC. Aucune réutilisation sur /me ou une route d’école ; no-store et minimisation des réponses. Auditer l’orchestration sans lire toutes les traces inter-écoles. Le contrat est spécifié, mais DM06 conserve la validation des délais, des rétentions, des responsabilités et des procédures avant diffusion.

<a id="frontières-précisées-v36"></a>
## Frontières d’accès et responsabilité des données
Le protocole d’accès global protège le commit contre un compte passé CLOSING selon [l’ordre unique](transactions-v2.md#autorisation-et-commit). Les notes de remise ne contiennent ni clé de licence ni mot de passe ; une preuve de remise n’exige pas de photographier un document personnel. La pagination de suppression est privée et liée au propriétaire, au manifeste et à son expiration ; la limite de page ne devient pas une obligation de joindre le support. Les annotations textuelles sans coordonnées restent des données personnelles quand leur contenu le permet, soumises aux demandes et rétentions applicables.

<a id="menaces-croisées-ajoutées-v37"></a>
## Menaces croisées sur preuves et notifications
Rejouer une décision de formation avec le cycle d’inscription précédent, présenter une preuve invalidée ou réutiliser un callback de position d’une autre leçon ne doit pas fournir un droit courant. Les contrôles R110/R111 limitent ces incohérences, sans certifier l’authenticité d’une attestation externe ni d’un capteur.

Le routage R112 réduit les erreurs de compte sur appareil partagé, mais un token n’est pas une preuve cryptographique d’installation possédée. Minimiser les messages externes, valider la session et traiter toute compromission de tokens. Une notification déjà remise au fournisseur n’est pas effaçable à distance par la simple révocation du compte ; la minimisation doit précéder l’envoi. Les rétentions continuent de couvrir décisions de preuve et suivis commerciaux sans journaliser les documents complets.

## Scellement, transport et résurrection de fichiers

Une analyse antivirus ne suffit pas si ses octets peuvent être remplacés après analyse. Le [pipeline canonique](fichiers-temps-communications.md#scellement-fichiers) impose staging conditionnel, génération scellée, scan de cette génération et promotion par version. Prévoir une épreuve avec remplacement concurrent, suppression en cours de scan, résultat retardé, métadonnées PDF/image hostiles et ressources de décodage saturées. Ces scénarios sont des modèles de menace, pas des vulnérabilités reproduites de Drivy.

Une URL présignée est une autorisation technique temporaire et non un droit métier pérenne. Aucun bearer Drivy n’est envoyé à son origine. Refuser redirections et origines non qualifiées ; le même impératif couvre fichiers, logos et exports. Ne pas journaliser les URLs signées ou leurs paramètres. L’effacement crée les informations minimales nécessaires pour empêcher un worker retardé de republier du contenu supprimé, y compris dérivés.

Les caches HTTP et snapshots du sélecteur d’applications doivent être traités en plus de SQLCipher/Keychain. [Responsabilités natives](architecture-client-swift.md#confidentialite-transports). Les copies volontairement exportées sortent du périmètre de révocation ; la notice et l’UI le disent sans annoncer une protection absolue.
