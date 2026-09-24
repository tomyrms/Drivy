# F17 : prestations, packs composites et droits de consommation

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

<a id="f17"></a>

## Objectif

Adapter Drivy à une école qui vend à la leçon comme à une école qui propose une formule comprenant conduite, sensibilisation, examen et service externe. La recherche [dix écoles](../01-recherche/auto-ecoles-suisses.md) documente cette variété, mais ne remplace pas les contrats à obtenir lors du paramétrage.

**Source normative :** [R23–R25](regles-etats.md#r23), [R35](regles-etats.md#r35), [R49](regles-etats.md#r49), [R51–R54](regles-etats.md#r51), [R72](regles-etats.md#r72). F10 conserve le journal de règlement ; F17 gère la vente et les droits. Ni moteur fiscal ni prestataire de paiement intégré au pilote.

## Configuration minimale et configuration avancée

L’école choisit ses catégories, les prestations qu’elle réalise, leur unité et leur durée, les lieux/sites et la devise du pilote. Une petite école sans packs n’a qu’un tarif par prestation et les conditions de réservation. L’activation des packs révèle les composants ; l’activation de cours révèle les règles de place. Les garanties de sécurité et les profils réglementaires ne sont pas des options commerciales.

Le premier produit prend en charge un prix fixe unitaire, des packs à prix fixe, des options sélectionnées à l’achat, les dates d’effet, la déclinaison par site et les frais ponctuels définis. Des règles complexes arbitraires, coupons combinables, prorata automatique et échéanciers programmatiques restent différés. Un prix convenu exceptionnel peut être saisi par personnel autorisé avec motif et snapshot, sans inventer un moteur de promotions.

## Modèle et responsabilités

ServiceProductVersion représente une prestation : type, catégorie, durée contractuelle, unité, prix, site, période et conditions. PackOfferVersion contient la liste versionnée des composants et un total convenu. Purchase fige les composants réellement choisis, le prix final et les conditions. EntitlementLot contient les droits du bénéficiaire ; EntitlementMovement conserve chaque accord, immobilisation, utilisation, libération ou restauration.

L’adhésion à l’école, une formation pour un permis et un achat sont distincts. Une prestation externe donne un droit ou un accès à remettre, pas une présence de cours. Un composant « inscription offerte » est un élément de prix/frais, pas une leçon.

## Parcours nominal

Le personnel habilité CONFIGURE_CATALOG crée une nouvelle version de produit/pack. Avant activation il vérifie le libellé, la durée, la quantité, les sites et les conditions ; une modification de tarif ne réécrit pas les ventes existantes.

Pour vendre, le personnel sélectionne l’élève et l’offre versionnée, fait confirmer les conditions puis crée l’achat. Les droits sont accordés selon la politique : soit après paiement intégral pour un pack prépayé strict, soit utilisables immédiatement si l’école autorise la facturation ultérieure. Cette dernière possibilité doit être explicite dans l’achat et ne peut être changée silencieusement après utilisation.

À la réservation d’une leçon ou d’un cours compatible, le système montre les droits utilisables et le solde après réservation. Un HOLD diminue le disponible. À réalisation d’une leçon, il devient CONSUME. Un cours collectif utilise la politique R54. Le paiement est enregistré sur le compte de l’achat ou de la prestation unitaire, pas sur chaque utilisation couverte par pack.

## Exemple inspiré de Luc’s

Le site de Luc’s publie un pack Start comprenant 10 leçons de 45 minutes, sensibilisation et accompagnement à l’examen, avec inscription offerte [S33](../06-gouvernance/sources.md#s33). Le modèle suivant est une **traduction proposée**, pas le catalogue importé d’un logiciel interne :

| Composant | Droit créé | Quand il est utilisé |
|---|---|---|
| 10 × conduite 45 minutes | Dix unités du service versionné | Une leçon réalisée ; double séance selon quantité réservée. |
| Sensibilisation | Un droit de série compatible | Réservé à inscription, consommé selon R54. |
| Accompagnement examen | Un droit de service examen | Au constat de prestation effectivement réalisée. |
| Inscription offerte | Frais à zéro dans le snapshot | Pas de décompte pédagogique. |

L’élève pourrait voir « Conduite : 7 disponibles, 1 réservée, 2 utilisées ; sensibilisation : à réserver ; paiement du pack : réglé ». Cette projection illustre le modèle, elle ne décrit pas un utilisateur réel. Acheter ce pack ne l’inscrit pas automatiquement à la prochaine sensibilisation.

## Quantités et compatibilité

Une unité de 45 minutes ne devient pas une unité de 60 minutes au changement de grille. Une double leçon utilise deux unités seulement si le service acheté le prévoit. Aucun arrondi de durée GPS ne calcule le nombre de droits à consommer. Le prix d’un pack composite n’est pas divisé arbitrairement par ses composants pour inventer leurs valeurs de remboursement.

La correspondance entre ancien produit et nouveau produit se fait par décision administrative validée et auditée, pas par égalité de nom. Un droit voiture B ne finance pas automatiquement un cours moto. Un cours déjà accompli ailleurs peut satisfaire l’exigence sans consommer un droit acheté ; un éventuel remboursement/remplacement du composant dépend des conditions acceptées.

## Annulations, remboursement et corrections

Annuler avant utilisation libère une réservation de droit selon les conditions. Une pénalité éventuelle est un mouvement distinct, motivé et contractuellement justifié. Une annulation scolaire après début de cours requiert arbitrage sur les droits déjà consommés et les prestations restantes. Rien n’est assimilé automatiquement à un remboursement en espèces.

Le registre F10 distingue mouvement réel de paiement, remboursement réel et contre-écriture d’erreur. Une correction d’une consommation erronée utilise RESTORE relié au mouvement, au plus une fois ; ne pas supprimer l’ancienne consommation. Le remboursement d’un achat tient compte des droits déjà réservés/utilisés et ne transforme pas un droit monétaire nul en avoir fictif.

## Concurrence et erreurs

Deux réservations tentant d’utiliser le dernier droit sont sérialisées avec le compte de droits du même élève. Le serveur valide le produit, la quantité, les occupations et le solde dans la même transaction. Échec de capacité de cours : rollback du HOLD. Rejeu d’une réponse perdue : même achat ou réservation, pas un second GRANT.

Erreurs : PRODUCT_INACTIVE, OFFER_CHANGED, ENTITLEMENT_INCOMPATIBLE, INSUFFICIENT_ENTITLEMENT, PREPAYMENT_REQUIRED, ACCOUNT_BALANCE_CONFLICT, PURCHASE_HAS_COMMITMENTS. Elles donnent une action compréhensible sans révéler les comptes d’autres élèves. Les commandes financières ne sont pas placées dans une file d’attente hors ligne.

## Données et validations

Montants entiers en centimes CHF ; quantités entières positives au pilote ; durée d’unité explicitée. Un pack ne contient pas de pack récursif. Composants maximum proposé : 32, options maximum 16 ; la somme des lignes affichées et ajustements doit correspondre au total accepté. Un rabais informatif déjà inclus n’est pas appliqué une seconde fois. La référence externe de paiement est facultative ; ne jamais enregistrer de carte bancaire.

Les écritures sont append-only, sous version et idempotence. L’audit conserve auteur, cause et relations ; les exports comptables ne sont pas appelés factures homologuées. Les conditions de validité, reliquats, transfert d’école et responsabilité fiscale restent des champs et questions explicites, pas des règles inventées.

## Recette et décision de pilote

Les scénarios couvrent l’école sans packs, pack composite, nouvelle grille, double leçon, première présence collective, annulation, transfert de formation, dernier droit concurrent, double facturation interdite et preuve externe. Les jeux de données sont fictifs. Avant pilote réel, chaque école valide ses propres conditions et un exemple de remboursement partiel ; aucune règle commerciale litigieuse ne doit être improvisée par le développeur.


## Configuration guidée et lecture de gestion

L’onboarding école F20 prépare catégories, unités, prix, conditions et composants par le même catalogue versionné ; aucune formule scolaire n’est créée à partir d’un montant vide interprété comme zéro. Une offre reste brouillon jusqu’à validation. Un établissement sans packs n’a pas à compléter ce module.

F22 expose sur le dossier bureau les droits disponibles/réservés/consommés, leurs achats et leurs conditions. Un dossier archivé peut conserver des droits disponibles avec avertissement explicite ; l’archivage n’est ni remboursement ni expiration forcée. F23 calcule l’argent depuis le journal de paiements unique, jamais depuis les consommations de droits. Les services et tarifs historiques des packs restent inchangés après une reconfiguration de l’école.

<a id="prepaiement-recontrole"></a>
## Prépaiement corrigé après activation

La projection sépare « droits restant au registre » de « droits utilisables maintenant », selon [R53](regles-etats.md#r53). Une contre-écriture de reçu ou un remboursement peut rendre le prépaiement insuffisant ; le logiciel ne doit pas laisser l’ancien état ACTIVE autoriser indéfiniment de nouvelles réservations.

La suspension proposée ne supprime ni les leçons confirmées ni les consommations. La gestion de ces engagements suit [R54](regles-etats.md#r54) et est signalée dans le dossier. Un achat annulé devient inutilisable même si son reliquat est encore visible pour justification ; le statut CLOSED suppose ses engagements et obligations résolus, il ne signifie pas simplement « payé ». Aucune clôture automatique n’est déclenchée par un paiement.

La finance et les droits sont recontrôlés sous le même ordre de verrous pour un compte d’achat. Une commande purement comptable sans effet sur droits peut utiliser le chemin court défini techniquement ; un remboursement/reversal d’achat ne le peut pas. La règle s’applique à l’API, pas seulement au bouton « Réserver ».

Les options choisies à l’achat constituent un ensemble : doublon refusé avant attribution. Le service contrôle également l’existence, la compatibilité et le calcul du prix de chaque option ; une liste sans doublon n’est pas à elle seule un achat valide.

## Prix, frais inclus et options : source de vérité

[R108](regles-etats.md#r108) rend concrets les frais ponctuels inclus et les options du modèle annoncé. Une formule peut afficher une base de 146 000 centimes, une ligne informative « Inscription offerte : 0 » et un supplément optionnel de 12 000 centimes. C’est un exemple fictif de calcul, pas un nouveau prix de Luc’s. Le montant final est calculé au serveur et relu avant confirmation. Les frais inclus ne sont pas vendus comme une leçon ; aucune prestation sans durée n’est transformée artificiellement en unité de conduite.

Le paramétrage exige la décomposition de base et la table de prix d’options. Un même groupe optionnel peut contenir plusieurs composants, avec un seul supplément. Sans options, optionPrices=[] ; sans remise détaillée, une ligne « Forfait » égale au prix de base suffit. Un total exceptionnel à l’achat est réservé à ADMIN avec motif et acceptation du prix ; la délégation SELL_SERVICES seule ne l’autorise pas. Les frais automatiques conditionnels tels que « dès la deuxième leçon » ne sont pas couverts par cette décomposition : ils restent à paramétrer ou à consigner explicitement selon F10, sans moteur de déclenchement implicite.

## Remise des accès externes et accompagnement examen

Depuis un lot du dossier ou de Mes achats, le personnel habilité peut « Consigner une prestation remise » après sa réalisation. Saisir quantité, date civile et confirmation sans secret ; prévisualiser droits restants puis confirmer en ligne. [R107](regles-etats.md#r107) régit AP199 et le journal AP113. L’élève voit « Remise consignée par l’école », pas une activation du fournisseur ou une réussite d’examen. Aucune position GPS n’est collectée pour cette action.

Cette voie complète les services d’examen et externes déjà prévus ; elle ne prétend pas planifier l’examen officiel, réserver un créneau auprès d’une autorité ou gérer un planning de ressources supplémentaire. Une remise d’examen est distincte d’une leçon pédagogique. Une restauration motivée AP114 garde le mouvement d’origine et n’envoie pas automatiquement une demande de remboursement au prestataire.

Pour le collectif, le reliquat immobilisé d’une personne jamais présente est libéré explicitement à la clôture selon [R106](regles-etats.md#r106), sans effacer les absences ou fabriquer une consommation.

## Régularisation d’un droit après correction de présence

La référence unique est [R109](regles-etats.md#r109). F17 expose le lot d’origine, le mouvement RELEASE/RESTORE source, le dossier de régularisation courant et la décision ADMIN. AP201 ne reçoit ni prix, ni quantité, ni lot arbitraire : ces données sont dérivées et contrôlées au serveur. Renoncer à une consommation n’ajoute pas d’unité et ne diminue pas le compte financier. Le reçu du règlement reste un événement de droit, pas un justificatif de paiement ou un diplôme.

Après une consommation réellement régularisée, une nouvelle correction ne réécrit pas l’historique : toute restitution suit AP114, ses plafonds et son motif. Si une nouvelle présence rend nécessaire un droit déjà restitué, une nouvelle revue remplace le dossier courant et conserve les anciens. Le serveur refuse les doubles consommations, même avec de nouvelles clés d’opération. Les politiques générales d’expiration, de suspension et de prépaiement restent applicables.
