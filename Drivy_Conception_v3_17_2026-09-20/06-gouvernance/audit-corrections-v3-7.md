# Recherches et corrections : Drivy V3.6 vers V3.7

> **19 septembre 2026 · Référence 3.7** · [Index](../README.md) · [Fonctions](../01-fonctionnalites-prevues.md)
> Documentation et contrats uniquement. Aucun code applicatif modifié, aucun build natif ou service réel exécuté.

<a id="apports"></a>
## Résultat et méthode

Cette version poursuit la revue en profondeur sur quatre jonctions risquées : présence/droit, accomplissement/preuve, mesure GPS/séance et notification/compte. Elle corrige aussi les compteurs et instructions de contrôle périmés de la référence active. Les modifications sont dans les références actives et leurs dépendances, pas uniquement dans ce rapport. **V3.7 remplace V3.6** comme référence ; les 23 fonctions de haut niveau restent les mêmes.

Le ZIP V3.6 complet fourni est la base, copié sans modifier l’original. Ses cinq vérificateurs ont été relancés avant correction et ont tous réussi : [contrôles initiaux](../annexes/controle-v3-6-avant-correction.json). Ces succès ne détectaient donc pas les manques ci-dessous. Les liens, références, schémas, cas existants et registres sont recontrôlés transversalement ; l’approfondissement sémantique et la recherche externe sont ciblés, pas une nouvelle validation de toutes les affirmations historiques sur les écoles ou la réglementation.

Les [preuves](../annexes/preuves-audit-v3-7.json) conservent les extraits, lignes et SHA-256 de V3.6. Les lignes désignent l’original, pas le fichier corrigé. Le [diff](../annexes/corrections-v3-6-vers-v3-7.patch) expose les modifications textuelles hors dérivés. Les historiques, jeux originaux et captures antérieures restent datés, sans devenir les instructions courantes.

## V37-01 · Présence réelle et régularisation du droit

**Nature :** fonctionnalité laissée incomplète, avec choix de résolution explicite. **Importance : élevée.**

La V3.6 refusait la correction ABSENT→PRESENT après libération du droit, en attendant un parcours de compensation encore non défini (R63 et son test T323). Cela risquait de conserver une information pédagogique fausse uniquement parce qu’un crédit était épuisé. La lacune était déjà déclarée : ce n’est pas une découverte artificiellement nouvelle.

**Correction :** AP146 enregistre le fait autorisé et ouvre un `rightSettlement` séparé, sans débit. AP201 permet à ADMIN de régulariser depuis le lot d’origine ou de renoncer explicitement à consommer ce droit. Le serveur déduit la quantité et vérifie versions/source/disponibilité ; pas de lot choisi librement par le client. Une insuffisance de crédit bloque la régularisation, pas la présence déjà corrigée. Le suivi commercial ne doit pas bloquer une validation pédagogique étayée.

L’absence rétablie avant résolution classe le suivi NOT_REQUIRED ; une ancienne commande n’agit plus. Les restitutions après consommation restent motivées sous les règles existantes. Régularisation, dette et remboursement peuvent coexister et sont vérifiés avant archive. Une clôture de suivi ne génère ni argent, ni cours accompli, ni nouvelle place.

**Arbitrage :** R109 est une politique proposée, à approuver avec l’école ; notamment le droit ADMIN de renoncer au décompte. La correction des anciens cycles d’inscription n’est pas rendue possible par une substitution silencieuse de cycle. Le refus des commandes périmées reste conservé.

**Références corrigées :** [cours](../03-fonctionnel/cours-collectifs.md#correction-presence-tardive), [R109](../03-fonctionnel/regles-etats.md#r109), packs, droits, archive, données, API, transactions, E28/E30, catalogue et roadmap. **Recettes :** [T351–T360](../05-realisation/tests-recette.md#t351). T323 garde son identifiant mais son résultat attendu est révisé et expliqué ; l’ancien résultat reste dans V3.6.

## V37-02 · Preuve de formation identifiable et réexaminable

**Nature :** lacune de contrat et de transition. **Importance : élevée.**

`ReviewRequirementCommand` désignait une inscription sans son cycle ; `RequirementRecord` pouvait porter COMPLETED avec auteur/date nuls et sans snapshot structuré des sources. La prose disait qu’une preuve devait être tracée, mais ne suffisait pas à empêcher une interprétation différente par chaque client.

**Correction :** le cycle source et les versions des éléments vus pendant la revue sont explicites. Une source modifiée depuis cet aperçu doit faire confirmer une nouvelle revue, pas être substituée silencieusement. Le serveur vérifie les présences et documents sous le profil approuvé et fige leurs versions dans `RequirementDecisionBasis`. COMPLETED exige source interne vérifiée ou preuve externe ; EXEMPT exige une règle applicable du profil, pas une validation inventée par un clic. Les schémas imposent la forme ; existence, propriété, unicité par id et qualité des preuves restent des vérifications du service.

Une correction d’une preuve utilisée fait repasser la décision courante à EVIDENCE_PENDING, sans effacer l’historique du contrôle. La présence et l’exigence changent de façon cohérente avant qu’un nouvel acte utilise ce préalable. Une validation et une correction simultanées doivent être testées dans les deux ordres. Les rendez-vous déjà acquis ne sont pas annulés automatiquement et les campagnes n’assimilent pas « à revoir » à « cours jamais suivi ».

**Limite importante :** invalidation métier, remplacement de pièce et purge légitime selon politique de conservation sont distincts. La purge ne crée pas une accusation de fraude. Une nouvelle version de profil ne révoque pas rétroactivement toutes les formations ; les règles de transition et les rétentions restent à approuver. Il n’y a pas d’automatisation réglementaire nouvelle ni d’envoi à une autorité.

**Références corrigées :** [R110](../03-fonctionnel/regles-etats.md#r110), identités/formations, documents, cours, notifications, modèles, API, transactions, E07 et client Swift. **Recettes :** [T361–T370](../05-realisation/tests-recette.md#t361).

## V37-03 · Ne pas commencer un trajet avec une ancienne position

**Nature :** précision d’intégration et de qualification. **Importance : élevée pour le GPS central.**

Les points avaient des dates, séquences et précisions, mais l’admission du premier callback, la provenance temporelle et la distinction de l’heure de transfert n’étaient pas assez concrètes. Apple documente la possibilité de positions en cache dans son guide archivé [S113](sources.md#s113). Ce constat ne prouve pas qu’une mauvaise attribution s’était produite dans l’ancienne app.

**Correction :** distinguer mesure, réception, écriture et transfert. Une ancienne position ne devient pas le départ du nouvel élève. Le collecteur affiche l’attente d’un point admissible sauvegardé. Les batches réellement mesurés dans la période restent compatibles avec un transfert tardif ; aucun seuil arbitraire de quinze secondes copié d’un exemple. Un saut d’horloge non réconciliable interrompt clairement le segment, sans rallonger le bail monotone. Une précision invalide ne devient pas zéro ; `(0,0)` n’est pas une preuve universelle de valeur invalide.

Le guide Apple précise aussi le filtrage d’installation par `UIRequiredDeviceCapabilities`. Drivy ayant des usages sans capture, le dossier n’exige pas `gps` globalement : diagnostic local avant capture, accès aux autres fonctions selon les droits. Cela ne promet pas un capteur précis sur tout iPad.

**Niveau de preuve :** la référence est archivée et n’est pas utilisée pour prescrire les sessions de fond iOS 26/27. Les API exactes, tolérances d’horloge et qualités de signal doivent être qualifiées sur appareils. Les filtres ne prouvent pas l’authenticité d’un capteur. **Références :** [R111](../03-fonctionnel/regles-etats.md#r111), GPS, synchronisation, architecture Swift, guide iOS, E23. **Recettes :** [T371–T376](../05-realisation/tests-recette.md#t371), [MOB053–MOB056](../05-realisation/qualification-mobile-ui-ux.md#mob053).

## V37-04 · Environnement push et propriétaire de l’installation

**Nature :** intégration promise mais contrat insuffisant. **Importance : élevée pour la confidentialité.**

AP148 acceptait IOS/ANDROID/WEB avec un simple token, sans environnement fournisseur. La projection ne matérialisait pas la révision du propriétaire technique. Apple explique qu’un token identifie appareil/application ; l’association avec un compte est une responsabilité du service [S111](sources.md#s111). L’environnement vient de la signature et de sa configuration APNs [S112](sources.md#s112).

**Correction :** environnement explicite, validation contre la configuration du serveur, liaison technique globale versionnée et routes scolaires autorisées. Une réaffectation connue du serveur invalide les routes d’un ancien compte pour ce token ; une vieille révocation ne supprime pas celles du nouveau. Le worker recontrôle juste avant envoi. Le token et deviceId ne sont pas une authentification ni une preuve cryptographique de possession de matériel.

**Frontière rendue visible :** le contrat ne prétend plus que WEB+token implémente Web Push. Le centre interne du portail et les emails prévus sont conservés ; le push natif reste facultatif. Android garde son adaptateur futur, non déclaré disponible. Le choix ne supprime pas une exigence de notifications navigateur formulée par le porteur : aucune telle exigence n’a été identifiée dans le brief.

Un push déjà accepté chez le fournisseur ne peut pas être déclaré rappelé par la déconnexion. Le contenu externe est donc générique ; à ouverture, relecture sous compte/école/droits courants. La réinscription demande le token au système plutôt qu’une copie persistée supposée permanente.

**Références :** [R112](../03-fonctionnel/regles-etats.md#r112), notifications, API, données, identité mobile, sécurité, exploitation et calendrier. **Recettes :** [T377–T382](../05-realisation/tests-recette.md#t377), [MOB057–MOB060](../05-realisation/qualification-mobile-ui-ux.md#mob057).

## V37-05 · Compteurs et instructions de contrôle périmés

**Nature :** défaut de rapport, pas de fonction de l’app. **Importance : moyenne.**

Le vérificateur mobile V3.6 contrôlait correctement 350 scénarios métier, mais émettait encore `businessScenariosCurrent:310` dans son rapport. Il est remplacé par un calcul depuis le registre courant. Les anciens rapports restent des preuves datées ; le nouveau dossier ne présente pas ces chiffres historiques comme ses résultats.

Les deux fixtures CourseEnrollment SC076/SC077 sont adaptées dans un fichier distinct pour ajouter `rightSettlement=null`, exigé par le nouveau contrat. Leurs intentions et résultats attendus restent inchangés. Aucun test n’est assoupli pour autoriser une incohérence. [Adaptation explicitée](../annexes/adaptation-cas-v3-7.json).

L’index V3.6 présentait aussi comme courants certains rapports, scripts et diffs V3.4/V3.5, et un contrat 3.5. Les commandes, annexes et libellés de README et de la revue sont maintenant alignés sur V3.7 ; les anciens résultats restent historiques. Les compteurs actifs de la synthèse, du guide mobile et de l’architecture sont réconciliés avec les registres, sans réécrire les volumes des journaux passés.

Le contrôle visuel final a aussi révélé un titre du lecteur masqué partiellement par la barre fixe après navigation/redimensionnement. Le défilement vers les documents et les marges des ancres sont corrigés ; une assertion de visibilité du titre complète les essais du lecteur. Il s’agit du lecteur documentaire, pas de l’interface native.

## Recherche externe et limites

Sept références nouvelles ou reconsultées figurent dans [le relevé daté](../annexes/recherche-v3-7.json) : APNs et entitlement, guide de localisation archivé, prévention des erreurs W3C, verrous PostgreSQL et état des versions/outils Apple. Les textes W3C et PostgreSQL étayent respectivement une recommandation UX et une stratégie de concurrence, pas une certification de Drivy.

Les sources Apple consultées distinguent les publications 27.0 du 14 septembre 2026 des bêtas et les exigences Xcode [S116](sources.md#s116), [S117](sources.md#s117). Aucun OS minimum utilisateur ni binaire qualifié n’est déduit de ces listes. Les tarifs des dix écoles et le détail du droit suisse n’ont pas été reconfirmés dans cette passe. La politique R109 n’est pas attribuée à une école ou à Apple.

<a id="decisions"></a>
## Fidélité au produit et arbitrages conservés

Swift natif Apple, GPS/replay central mais facultatif, cours publiés sans inscription automatique, tablette, web, onboarding et packs sont conservés. Aucun chatbot, notation automatique ou moteur de frais conditionnels n’est ajouté. La correction pédagogique indépendante d’un paiement renforce la séparation déjà voulue entre apprentissage et commerce.

Restent à approuver : la politique de régularisation/renonciation R109, la preuve et les rétentions acceptables, les versions/appareils et fournisseurs, l’exploitation de suppression du compte et le calendrier Android. Démarrage GPS en ligne, une capture publiée par bilan et palette commune restent des propositions explicites, pas des contraintes techniques universelles. Le traitement des corrections d’anciens cycles reste limité, sans perte ou changement silencieux des anciens faits.

## Contrat et migration

Le contrat passe à **3.7.0**, avant implémentation. Une opération AP201 complète les 200 existantes ; quatre schémas de domaine sont ajoutés et des champs/conditions sont renforcés. Les clients doivent prendre le fichier complet. Les vues d’inscription, d’exigence et de registration changent : ce n’est pas une simple mise à jour de libellé. Les instructions de migration interdisent d’inventer une preuve historique ou un environnement de token absent.

## Vérifications et portée

La [revue de cohérence](revue-coherence.md) donne les commandes et rapports courants. Les 182 cas de forme antérieurs, dont deux adaptés explicitement, sont rejoués avec 47 cas nouveaux. Les comparaisons avant/après distinguent un schéma nouveau, une forme devenue obligatoire et une contrainte métier de forme renforcée. Un ancien payload rejeté faute d’un nouveau champ n’est pas présenté comme une vulnérabilité exploitée.

Les 14 calculs tarifaires antérieurs et 22 cas de modèles isolés R109/R111 sont exécutables dans le dossier. Ces derniers manipulent des états et temps synthétiques : ils ne valident ni transaction réelle, ni horloge Core Location, ni token, ni autorisation appliquée. Les **382 scénarios métier et 60 scénarios mobiles restent NOT_EXECUTED** ; les six lignes appareil/build restent NOT_QUALIFIED.

Le lecteur documentaire est régénéré et contrôlé séparément. Les fichiers d’origine, le ZIP et les empreintes sont vérifiés. La tentative d’installation d’un validateur intégral OpenAPI reste impossible dans ce runtime ; les contrôles disponibles de références, paramètres, schémas et exemples ne sont pas une validation intégrale du méta-schéma ni une preuve de génération Swift.

**Bilan :** quatre domaines ont été précisés et corrigés, avec un parcours précédemment incomplet désormais contractualisé. Aucun test documentaire ne démontre que le produit est parfait ou prêt à publier ; les preuves suivantes restent l’implémentation et les essais réels.
