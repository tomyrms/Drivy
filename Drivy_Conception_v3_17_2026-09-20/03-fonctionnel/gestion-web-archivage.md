# Espace web de gestion et cycle de vie des élèves

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; choix détaillés proposés, à valider. [Index](../README.md).

<a id="f22"></a>
## F22 · Gérer les dossiers en détail sans changer de produit

**Besoins :** B05 B12. **Parcours :** J24, J25. **Écrans :** E33–E37, E46, E48 ; E06/E13/E29 restent disponibles dans l’app. **Dépendances :** F01/F02/F03/F10/F13/F14/F17/F18 et F20/F21. **Règles :** R86–R91, R95–R97. **Tests :** T200–T214, T229–T232.

Le web est un poste de travail connecté : listes, filtres, dossiers, paramètres, cours, règlements et statistiques. Il exploite la même API et les mêmes entités que l’app. Ce n’est ni le site vitrine public, ni une console technique permettant de modifier la base, ni une carte live des moniteurs.

## Navigation proposée du personnel

**Vue d’ensemble**, **Agenda**, **Élèves**, **Cours**, **Offres et packs**, **Activité**, **Paramètres**. Compte et choix d’école restent dans l’en-tête. Cours/packs sont masqués si inutilisés, mais un lien vers les engagements existants reste accessible. Une destination sans permission n’est pas affichée ; la route reste également protégée au serveur.

Un moniteur sans privilèges administratifs peut préparer ses journées, consulter ses élèves affectés et compléter ses bilans au clavier. Il ne découvre pas les revenus de l’école en passant de l’app au navigateur. ADMIN seul ne gagne pas accès aux notes privées ou traces pédagogiques.

## Vue d’ensemble utile, sans faux tableau de bord

Présenter les prochaines actions selon le rôle : leçons à compléter, pièces en attente de vérification pour les personnes habilitées, nouvelles demandes de formation, cours à préparer et dossiers à compléter. Les compteurs renvoient vers les listes correspondantes avec filtres.

Les indicateurs de F23 occupent un espace secondaire et renvoient à leur définition. Une école neuve voit une checklist d’installation et les actions « Inviter un élève » ou « Configurer une prestation », pas des courbes de démonstration présentées comme réelles.

## Liste détaillée des élèves

Recherche par nom, filtres état ACTIF/ARCHIVÉ/TOUS, catégorie, moniteur affecté et complétude pour une action. Le statut de paiement n’est visible qu’avec accès financier. Colonnes proposées : nom, catégories en cours, référent, prochaine leçon, état du dossier. Email/téléphone sont des colonnes facultatives ; date de naissance complète et adresse ne sont pas dans la liste par défaut.

Tri déterministe avec identifiant comme second critère, pagination serveur et compteur de résultats. L’archivage n’apparaît jamais comme une corbeille de suppression. Les sélections sont explicites et bornées : « 8 élèves sélectionnés », pas « tout ce qui correspondra à ce filtre demain ». Les noms recherchés restent dans la requête autorisée ; les URLs partageables ne portent pas de renseignements personnels.

Les préférences de colonnes mémorisables ne contiennent que des noms de colonnes non sensibles. Les résultats et filtres personnels restent en mémoire de session, pas dans un cache navigateur persistant.

## Fiche détaillée

| Zone | Contenu et précaution |
|---|---|
| Aperçu | Identité, formations, état d’accueil, prochaines actions, contacts utiles. |
| Informations | Profil administratif, finalité des champs, corrections et provenance ; changement d’email de connexion séparé. |
| Formations | Permis distincts, référents, contrôles, progression et décisions. |
| Leçons | Planning et bilans ; contenu pédagogique seulement aux personnes habilitées. |
| Cours | Offres/inscriptions, dates, reconfirmations, présence et exigences séparées. |
| Documents | Statut de contrôle, type, audience et finalité ; pas de galerie ouverte à tous les administrateurs. |
| Packs et règlements | Droits, réservations/consommations et journal de compte, selon permission. |
| Historique administratif | Changements utiles et événements, sans dump technique ni données privées d’autres personnes. |

La lecture simultanée de plusieurs panneaux ne change pas les droits. Le passage au dossier d’un autre élève annule la sélection du précédent et ne réutilise jamais son formulaire non soumis.

## Quatre actions qui ne sont pas synonymes

**Terminer une formation** concerne un permis. **Archiver le dossier** retire la relation scolaire de l’usage courant, sans effacer son historique. **Révoquer l’accès** retire une appartenance ou un rôle. **Demander l’effacement** déclenche la procédure F14 et sa décision de conservation. Ces opérations ont des boutons, explications et journaux distincts.

Un élève peut avoir terminé B et poursuivre A : il faut terminer B, pas archiver toute la personne. Une personne peut appartenir à deux écoles : aucune action de l’école A ne modifie son dossier dans B.

## Archivage unitaire : prévisualiser, traiter, confirmer

1. Ouvrir « Archiver le dossier » depuis la fiche autorisée. Le serveur crée un ArchivePreview lié à l’acteur, à l’école, à l’élève et à sa version ; validité proposée de 15 minutes.
2. Afficher les blocages et avertissements avec liens d’action : formation encore active/en pause, leçon future/en cours, inscription future ou À reconfirmer, présence/bilan obligatoire restant à clôturer, droit réservé, capture connue non terminale, solde débiteur ou suivi financier non soldé même à solde nul. Un transfert incomplet après arrêt apparaît séparément comme avertissement.
3. Résoudre explicitement les blocages dans leurs fonctions respectives. L’archivage ne déclenche ni remboursement, ni annulation groupée, ni clôture de formation à la place du responsable.
4. Les droits non consommés et non réservés sont conservés avec avertissement et confirmation de compréhension. Les éventuelles dates contractuelles continuent de s’appliquer ; aucun crédit n’est perdu ni prolongé par l’archivage.
5. Refaire la prévisualisation après une résolution ou un changement ; confirmer une raison administrative courte et la version courante. Le serveur recontrôle les règles sous verrou avant commit.

Une demande de données en cours n’est pas annulée par l’archive. Les échéances de conservation continuent de courir ; une conservation justifiée est portée par un retentionHold, pas par une archive illimitée.

Le serveur peut connaître des captures autorisées non réconciliées et des opérations déjà reçues. Il **ne sait pas certifier l’absence de toutes les frappes ou notes présentes sur un appareil déconnecté**. L’écran demande de synchroniser les appareils concernés ; après archive, une commande locale arrive en conflit de dossier, sans réactivation silencieuse ni disparition de son message d’erreur.

## Conséquences d’un dossier archivé

Le dossier quitte les listes actives et devient non éligible aux nouvelles réservations, achats et annonces de cours. Il reste retrouvé via le filtre Archives. Les écritures financières de correction, décisions de données et opérations de conservation autorisées restent possibles et auditées.

L’archivage **ne révoque pas à lui seul le compte**. Si l’appartenance LEARNER est encore valide, l’élève garde la consultation de ses documents/bilans déjà partagés et ses demandes de données selon leur durée de conservation. Il voit « Votre dossier est archivé dans cette école », sans nouveaux boutons d’inscription. Pour retirer aussi l’accès, l’école effectue une révocation distincte et explicite.

Un moniteur conserve seulement les lectures historiques encore permises par son affectation et les règles de conservation. L’archivage ne crée aucun grant. Un export global du dossier nécessite la procédure d’accès appropriée, pas le bouton d’export de liste.

## Archivage par sélection sur le web

Limite proposée : **50 dossiers par opération**. L’utilisateur sélectionne des identifiants concrets. Le serveur produit une prévisualisation listant chaque dossier, version, blocages et avertissements. Les dossiers bloqués ne sont pas retirés silencieusement : le responsable choisit explicitement le sous-ensemble éligible à confirmer.

Le job enregistre cette sélection figée. Chaque dossier est retraité sous sa propre transaction avec droits courants, contrôles et version ; une erreur n’archive pas un autre dossier par compensation. Résultats possibles par ligne : ARCHIVED, ALREADY_ARCHIVED, BLOCKED, VERSION_CONFLICT, ACCESS_REVOKED, FAILED. L’état global peut être COMPLETED, PARTIAL ou FAILED.

Un résultat partiel dit exactement combien ont changé et pourquoi les autres restent actifs. Rejouer la même opération ne crée pas un second audit par élève déjà traité. Réessayer les lignes refusées nécessite une nouvelle prévisualisation, pas un « forcer tout ».

Pas de suppression de personnes en lot, de fusion automatique de doublons, d’export massif de permis ni de modification collective des prix passés dans ce périmètre.

## Restauration

Depuis Archives, présenter l’école, la raison d’archive, les contraintes actuelles et l’effet de restauration. ADMIN ou gestionnaire explicitement habilité confirme avec If-Match. Le dossier revient actif ; **aucune formation terminée, affectation retirée, réservation annulée, appartenance révoquée ni choix GPS ancien ne redevient actif automatiquement**.

Le personnel ouvre une nouvelle formation ou confirme la suite selon F03 ; les droits encore valides restent visibles. Restaurer le dossier ne réinvite pas automatiquement quelqu’un. La restauration est auditée sans effacer l’événement d’archive.

## Exports de gestion

Exports inclus : liste minimale des élèves correspondant à une sélection/filtre autorisé, et métriques F23. Ils ne remplacent pas l’export complet F14. Aucune pièce, naissance, adresse ou trace GPS dans le format de liste standard. Les colonnes sont une allowlist ; pas de requête SQL personnalisable.

Un export est un job privé, avec identité du demandeur, école, paramètres figés, version des métriques et date. Recontrôle des droits à génération et téléchargement ; durée proposée de disponibilité 24 heures. Réutiliser le pipeline Export/F14 avec type STUDENT_LIST ou METRICS, sans élargir les exports de données personnelles existants.

Plafond proposé de 10 000 lignes ; au-delà, demander un filtre plus précis, jamais livrer un fichier tronqué sans avertissement. Les cellules textuelles CSV sont neutralisées contre l’interprétation comme formule, y compris après séparateur/retour ligne [S57](../06-gouvernance/sources.md#s57). Une copie déjà téléchargée ne peut pas être rappelée ; l’interface le signale.

## Paramètres avancés utiles

Catégories et référentiels, prestations et packs, sites/salles, horaires, équipe et délégations, politiques de données et notifications, identité graphique bornée. Le web propose des formulaires plus détaillés et un résumé de l’impact ; il ne révèle aucun secret fournisseur et ne permet pas de désactiver la protection des données.

La configuration initiale est F20 ; les changements ultérieurs sont F13/F17. La même modification effectuée sur tablette ou web doit produire la même version et les mêmes événements. Les permissions sont décrites dans [la matrice](roles-permissions.md).

<a id="précisions-de-cohérence-v31"></a>
## Prévisualisation, grants et opérations de gestion
Le contrôle normatif [R88](regles-etats.md#r88) inclut les remboursements et compensations encore à traiter, même à solde nul. Le code `ARCHIVE_FINANCIAL_FOLLOW_UP_REQUIRED` désigne ce blocage. Une capture arrêtée mais partielle relève d’un avertissement de transfert ; une capture non terminale bloque. Les obligations connues sont relues au commit, pas seulement à la prévisualisation.

## Vérifications additionnelles sur le dossier

Avant archivage, afficher séparément droits restant au registre et droits utilisables ; une suspension de prépaiement ne solde pas la dette. Le journal de cours conserve les cycles annulés et leurs présences, sans les fusionner à une nouvelle inscription. Les mêmes contrôles R53/R59/R63 s’appliquent aux actions de lot et aux pages individuelles. Une réponse PENDING ne devient pas un succès de lot ; chaque résultat demeure à suivre avec son opération.

## Droits et clôtures à résoudre

Le dossier expose le journal de remise des services externes/examen et les reliquats résultants. Un HOLD collectif sans présence n’est pas résolu en marquant PRESENT : ouvrir la revue de clôture F18/R106. Après libération, les droits disponibles continuent d’être signalés avant archive ; la dette ou le remboursement restant suit toujours R88. La preuve de remise n’est pas une preuve de paiement, d’accès effectif chez un tiers ni de réussite d’examen.

## Suivis nouveaux à exposer avant archive

La fiche et l’aperçu d’archive comprennent les régularisations `rightSettlement.status=REVIEW_REQUIRED`. Elles bloquent avec `ARCHIVE_RIGHT_SETTLEMENT_REQUIRED`, même si le compte est à zéro et qu’aucun HOLD ne reste. Le responsable peut ouvrir AP201 depuis le suivi autorisé, puis refaire l’aperçu. Une décision de renonciation à consommer un droit n’efface pas une dette ni un remboursement séparé. Un suivi clos NOT_REQUIRED/SETTLED n’est pas un nouveau blocage.

Une exigence repassée EVIDENCE_PENDING expose le motif de réexamen sans confondre cet état avec une dette. Les conditions de cycle de vie existantes restent celles de R88 ; cette passe n’ajoute pas un blocage universel d’archive pour toute preuve manquante.

## Continuité visuelle après une action

La vue conserve recherche, filtres, tri et portée lors d’une réponse d’archivage. Si l’archive retire l’élève du résultat courant, supprimer sa sélection et les actions de son détail, annoncer le résultat et replacer le focus sur un contrôle utile. Une sélection explicitement retrouvée dans le filtre « Tous » ou « Archivés » permet de consulter l’état archivé dans les droits déjà définis. Un échec ne doit pas vider les autres résultats ni être affiché comme une absence de dossiers.

Dans les actions par lot, appliquer le même principe sur les résultats individuels : les lignes échouées restent identifiables. La galerie n’exécute qu’un cas individuel fictif ; elle ne constitue pas un test de ce lot serveur. [DS22 et tables](../DESIGN/02-composants.md).

## Format réel et droits au téléchargement

Les exports de gestion sont des CSV UTF-8, contrairement au ZIP de la demande de données personnelles. AP91 décrit maintenant les deux résultats ; `Export` READY fournit nom sûr, type, taille et checksum des octets finalisés. [Spécification unique](../04-technique/fichiers-temps-communications.md#export-binaire). Un export généré avant retrait d’une affectation n’est pas téléchargeable au seul motif qu’EXPORT_MANAGEMENT reste attribué : les droits de son manifeste sont encore nécessaires. Proposer une nouvelle génération, sans modifier silencieusement l’ancien fichier.
