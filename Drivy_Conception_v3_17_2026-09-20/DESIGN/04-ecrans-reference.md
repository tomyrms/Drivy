# Écrans de référence et couverture

> Référence 3.17 · [Accueil design](README.md) · [Application unifiée](APPLICATION.html).

## Lire la couverture correctement

L’atelier courant comporte **20 compositions** : 16 hors carte et les quatre vues de capture/replay. Elles représentent au moins une variante de **17 écrans E sur 49**. La planche « Composants » est un outil de revue supplémentaire, pas un écran métier. Les six autres fiches uniquement illustrées dans la galerie antérieure portent le total à **23 écrans avec au moins une illustration** ; **26 restent non dessinés**. Aucune de ces valeurs ne signifie couverture exhaustive des rôles ou états.

`APPLICATION.html` et `LECON.html` sont générés depuis les mêmes sources. Les maquettes utilisent les mêmes composants pour les mêmes fonctions. Les prix, personnes, leçons et documents sont des fixtures. Réservation, publication, analyse, autorisation et persistance réelles ne sont pas exécutées. Les réglages de revue entourent l’appareil ; ils ne sont pas des fonctions destinées aux élèves.

Les cadres sont des unités de prototype, pas des appareils qualifiés. Les fenêtres larges réutilisent les lignes dans une composition liste/détail ; le grand texte peut remettre cette composition en une colonne. Le contenu pédagogique du bilan reste lisible, même lorsqu’il est plus long que celui d’un signalement.

## Atelier courant : compositions et limites

| Vue | Composition | Fiche | Limite propre |
|---|---|---|---|
| APP01 | [Séance](APPLICATION.html?screen=home) | [E22](../02-experience/ecrans.md#e22) | Données de démonstration, mémoire volatile. |
| APP02 | [Agenda du moniteur](APPLICATION.html?screen=agenda) | [E03](../02-experience/ecrans.md#e03) | Données de démonstration, mémoire volatile. |
| APP03 | [Recherche d’élèves](APPLICATION.html?screen=students) | [E06](../02-experience/ecrans.md#e06) | Données de démonstration, mémoire volatile. |
| APP04 | [Dossier et formation](APPLICATION.html?screen=student) | [E07](../02-experience/ecrans.md#e07) | Données de démonstration, mémoire volatile. |
| APP05 | [Détail de leçon](APPLICATION.html?screen=lesson) | [E04](../02-experience/ecrans.md#e04) | Données de démonstration, mémoire volatile. |
| APP06 | [Planifier ou déplacer](APPLICATION.html?screen=planning) | [E05](../02-experience/ecrans.md#e05) | Disponibilités/prix fictifs ; réservation simulée. |
| APP07 | [Bilan privé](APPLICATION.html?screen=report) | [E08](../02-experience/ecrans.md#e08) | Bilan terminé du 18 septembre ; observations distinctes de la capture du 21. |
| APP08 | [Aperçu élève](APPLICATION.html?screen=preview) | [E08](../02-experience/ecrans.md#e08) | Lecture du seul sous-ensemble publiable ; aucun envoi. |
| APP09 | [Bilan partagé](APPLICATION.html?screen=shared) | [E09](../02-experience/ecrans.md#e09) | Copie publiée simulée, pas un serveur ni une notification réelle. |
| APP10 | [Documents](APPLICATION.html?screen=documents) | [E10](../02-experience/ecrans.md#e10) | Aperçu de supports fictifs ; aucun contenu ajouté n’est analysé. |
| APP11 | [Compte et préférences](APPLICATION.html?screen=account) | [E19](../02-experience/ecrans.md#e19) | Préférences et accès aux demandes ; pas de réauthentification ni exécution E49. |
| APP12 | [Notifications](APPLICATION.html?screen=notifications) | [E32](../02-experience/ecrans.md#e32) | Données de démonstration, mémoire volatile. |
| APP13 | [École, accès moniteur](APPLICATION.html?screen=school) | [E13](../02-experience/ecrans.md#e13) | Vue moniteur en lecture, pas la configuration administrateur. |
| APP14 | [Mes leçons, élève](APPLICATION.html?screen=learner) | [E14](../02-experience/ecrans.md#e14) | Données de démonstration, mémoire volatile. |
| APP15 | [Engagements élève](APPLICATION.html?screen=learner-agenda) | [E25](../02-experience/ecrans.md#e25) | Engagements seulement ; offres et cours restent dans la galerie antérieure. |
| APP16 | [Parcours pédagogique](APPLICATION.html?screen=progress) | [E15](../02-experience/ecrans.md#e15) | Source publiée du 11 septembre, échelle proposée, pas de note globale. |
| APP17 | [Carte en cours](LECON.html?view=capture) | [E23](../02-experience/ecrans.md#e23) | Données de démonstration, mémoire volatile. |
| APP18 | [Catégories](LECON.html?view=categories) | [E23](../02-experience/ecrans.md#e23) | Données de démonstration, mémoire volatile. |
| APP19 | [Statut](LECON.html?view=status) | [E23](../02-experience/ecrans.md#e23) | Données de démonstration, mémoire volatile. |
| APP20 | [Replay privé](LECON.html?view=replay) | [E24](../02-experience/ecrans.md#e24) | Privé uniquement ; traces fictives, pas MapKit. |

Le rôle se choisit dans l’outil de revue, hors appareil. Pour examiner les vues élève, choisir « Élève » : Mes leçons, Agenda et Mon parcours. Cet outil ne représente pas une permission de changer de rôle dans l’app réelle. La lecture de bilan ne charge pas les observations privées ou commandes de capture.

La [matrice JSON](couverture-ecrans.json) est la source des comptages ; le [registre de composants](composants-usage.json) couvre les 49 fiches. Les 434 scénarios métier et 68 scénarios mobiles restent NOT_EXECUTED sur le produit.

## Priorité des références

Pour les variantes APP ci-dessus, cet atelier prévaut visuellement sur la galerie 3.14. Les vues restantes de la galerie restent complémentaires et doivent être adaptées au même répertoire DS avant réalisation. Il n’existe pas deux composants candidats équivalents à laisser au choix du développeur. Les vecteurs et la vidéo V3.16 restent ceux de la leçon ; ils ne représentent pas les nouvelles vues.

## Galerie complémentaire conservée

| Vue | Parcours illustré | Écrans de référence | Support | Intention |
|---|---|---|---|---|
| VIS01 | [Préparer une leçon](MAQUETTES.html#seance) | [E22](../02-experience/ecrans.md#e22), [E04](../02-experience/ecrans.md#e04) | iPhone | Élève, objectifs et choix GPS avant le départ. |
| VIS02 | [Enregistrer une leçon](MAQUETTES.html#capture) | [E23](../02-experience/ecrans.md#e23) | iPhone | Carte dominante, état local, pause et arrêt. Transfert distinct. |
| VIS03 | [Réaliser sans GPS](MAQUETTES.html#sans-gps) | [E04](../02-experience/ecrans.md#e04) | iPhone | Une séance normale avec objectifs et bilan, sans carte désactivée. |
| VIS04 | [Revoir un trajet](MAQUETTES.html#replay) | [E24](../02-experience/ecrans.md#e24), [E09](../02-experience/ecrans.md#e09) | iPhone | Observation numérotée, lecture et caméra indépendantes, état partagé. |
| VIS05 | [Agenda de l’élève](MAQUETTES.html#agenda) | [E25](../02-experience/ecrans.md#e25) | iPhone | Engagements distincts des offres sans inscription. |
| VIS06 | [S’inscrire à une série](MAQUETTES.html#cours) | [E26](../02-experience/ecrans.md#e26) | iPhone | Toutes les dates ; états disponible/en cours/inscrit/complet/à reconfirmer. |
| VIS07 | [Préparer le bilan](MAQUETTES.html#bilan) | [E08](../02-experience/ecrans.md#e08) | iPhone | Travail, constat, prochaine étape et contexte de compétence ; prévisualisation fidèle, aucun envoi. |
| VIS08 | [Accueillir un élève](MAQUETTES.html#profil) | [E40](../02-experience/ecrans.md#e40) | iPhone | Identité utile et photo facultative ; aucun GPS demandé au profil. |
| VIS09 | [Lire un pack](MAQUETTES.html#pack) | [E30](../02-experience/ecrans.md#e30) | iPhone | Droits de types différents et paiement dans deux groupes. |
| VIS10 | [La leçon sur iPad](MAQUETTES.html#ipad-capture) | [E23](../02-experience/ecrans.md#e23) | iPad | Carte large et panneau latéral, repli selon fenêtre. |
| VIS11 | [Agenda du moniteur sur iPad](MAQUETTES.html#ipad-agenda) | [E03](../02-experience/ecrans.md#e03) | iPad | Semaine et détail ; vue liste sur fenêtre trop étroite. |
| VIS12 | [Gérer les dossiers](MAQUETTES.html#web-eleves) | [E34](../02-experience/ecrans.md#e34), [E07](../02-experience/ecrans.md#e07) | Web | Recherche, tableau/détail, archivage via aperçu. |
| VIS13 | [Consulter l’activité](MAQUETTES.html#web-activite) | [E45](../02-experience/ecrans.md#e45) | Web | Mesures, période, définition et limites, pas de données de trace privées. |
| VIS14 | [Configurer une école](MAQUETTES.html#web-ecole) | [E38](../02-experience/ecrans.md#e38) | Web | Catégories, prestations et modules ; aucune configuration GPS imposée. |

| VIS15 | [Mes leçons, côté élève](MAQUETTES.html#mes-lecons) | [E14](../02-experience/ecrans.md#e14), [E04](../02-experience/ecrans.md#e04) | iPhone élève | Engagement confirmé et dernier bilan publié ; aucune commande de capture ou note privée. |

## Hiérarchie spécifique des vues

**Séance / capture / sans GPS.** Trois compositions distinctes pour ne pas mélanger la préparation, la collecte et l’alternative sans trace. Le choix d’enregistrer n’est pas un consentement implicite ; la maquette suppose un scénario autorisé. L’état local, le transfert et le partage occupent trois libellés séparés.

**Replay / bilan.** Le replay élève montre une publication déjà autorisée. Le bilan moniteur reste un brouillon avant l’action explicite. Les numéros de repères reprennent ceux de la chronologie. La capture est unique dans la publication illustrée ; aucun parcours réutilisable n’est créé par cette démonstration.

**Agenda / cours.** Deux groupes « Mes engagements » et « Cours disponibles ». Les quatre dates fictives d’une série se relisent au détail. Le scénario PENDING conserve une demande en cours ; le scénario Complet ne propose pas une liste d’attente absente du périmètre. Pas de minuteur promotionnel.

**Profil / pack.** Le profil ne montre ni photo obligatoire ni note de complétude. Le pack distingue leçons, sensibilisation et accompagnement examen. Le règlement est séparé de ces droits. Les boutons de paiement intégré ne sont pas ajoutés au pilote.

**iPad.** Capture : carte + panneau. Agenda : liste/détail et grille quand la fenêtre le permet. À fenêtre étroite, passer en composition verticale ; ne pas compresser trois colonnes jusqu’à rendre l’arrêt ou les heures illisibles.

**Web.** Le personnel voit recherche, lignes et détail. Le menu scolaire est soumis aux permissions. L’aperçu d’archive expose les bloqueurs avant une mutation ; la démo ne réalise aucune suppression. L’activité ne contient pas de carte de surveillance. L’onboarding école explique la raison des catégories et n’impose pas de configurer tous les modules.

## Couverture de l’ensemble des 49 écrans

« Illustré » signifie au moins une composition, pas tous les états, tailles ou rôles. « Spécifié par pattern » signifie une règle de composition associée à l’écran fonctionnel existant, **pas une maquette haute fidélité livrée pour cet écran**. Le JSON permet de vérifier cette distinction automatiquement.

| Écran | Famille de composition | Illustration | Référence |
|---|---|---|---|
| E01 · Connexion | Formulaire / accueil | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e01) |
| E02 · Choix d’école et acceptation | Formulaire / accueil | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e02) |
| E03 · Agenda du personnel | Agenda / engagement / séance | APP02 · courant | [Spécification](../02-experience/ecrans.md#e03) |
| E04 · Leçon de référence | Agenda / engagement / séance | APP05 · courant | [Spécification](../02-experience/ecrans.md#e04) |
| E05 · Planifier ou déplacer | Agenda / engagement / séance | APP06 · courant | [Spécification](../02-experience/ecrans.md#e05) |
| E06 · Rechercher une personne à accompagner | Agenda / engagement / séance | APP03 · courant | [Spécification](../02-experience/ecrans.md#e06) |
| E07 · Dossier et formation | Dossier / liste / détail | APP04 · courant | [Spécification](../02-experience/ecrans.md#e07) |
| E08 · Rédiger et prévisualiser un bilan | Dossier / liste / détail | APP07, APP08 · courant | [Spécification](../02-experience/ecrans.md#e08) |
| E09 · Lire un bilan partagé | Dossier / liste / détail | APP09 · courant | [Spécification](../02-experience/ecrans.md#e09) |
| E10 · Documents utiles | Dossier / liste / détail | APP10 · courant | [Spécification](../02-experience/ecrans.md#e10) |
| E11 · Journal d’un compte de prestation | État / journal / opération sensible | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e11) |
| E12 · Disponibilités | Agenda / engagement / séance | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e12) |
| E13 · École et responsabilités | État / journal / opération sensible | APP13 · courant | [Spécification](../02-experience/ecrans.md#e13) |
| E14 · Mes leçons, élève | Dossier / liste / détail | APP14 · courant | [Spécification](../02-experience/ecrans.md#e14) |
| E15 · Mon parcours | Dossier / liste / détail | APP16 · courant | [Spécification](../02-experience/ecrans.md#e15) |
| E16 · Invitations et équipe | Dossier / liste / détail | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e16) |
| E17 · Brouillons et opérations en attente | État / journal / opération sensible | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e17) |
| E18 · Demandes concernant mes données | État / journal / opération sensible | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e18) |
| E19 · Compte et préférences | État / journal / opération sensible | APP11 · courant | [Spécification](../02-experience/ecrans.md#e19) |
| E20 · Contrôle d’une pièce de permis | État / journal / opération sensible | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e20) |
| E21 · Conflit à résoudre | État / journal / opération sensible | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e21) |
| E22 · Séance, accueil du personnel | Agenda / engagement / séance | APP01 · courant | [Spécification](../02-experience/ecrans.md#e22) |
| E23 · Carte de séance et capture | Carte / collecte / replay | APP17, APP18, APP19 · courant | [Spécification](../02-experience/ecrans.md#e23) |
| E24 · Replay et observations | Carte / collecte / replay | APP20 · courant | [Spécification](../02-experience/ecrans.md#e24) |
| E25 · Agenda élève, engagements et offres | Agenda / engagement / séance | APP15 · courant | [Spécification](../02-experience/ecrans.md#e25) |
| E26 · Fiche d’une série et inscription | Agenda / engagement / séance | VIS06 · antérieur | [Spécification](../02-experience/ecrans.md#e26) |
| E27 · Composer et publier un cours | Agenda / engagement / séance | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e27) |
| E28 · Inscrits et présences | Agenda / engagement / séance | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e28) |
| E29 · Catalogue et formules d’école | Dossier / liste / détail | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e29) |
| E30 · Mes achats et droits | Dossier / liste / détail | VIS09 · antérieur | [Spécification](../02-experience/ecrans.md#e30) |
| E31 · Reconfirmer une série modifiée | Agenda / engagement / séance | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e31) |
| E32 · Centre de notifications | État / journal / opération sensible | APP12 · courant | [Spécification](../02-experience/ecrans.md#e32) |
| E33 · Vue d’ensemble web | Dossier / liste / détail | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e33) |
| E34 · Liste détaillée des élèves | Dossier / liste / détail | VIS12 · antérieur | [Spécification](../02-experience/ecrans.md#e34) |
| E35 · Dossier élève sur bureau | Dossier / liste / détail | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e35) |
| E36 · Prévisualisation et résultat d’archivage | État / journal / opération sensible | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e36) |
| E37 · Restauration du dossier | État / journal / opération sensible | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e37) |
| E38 · Configuration guidée de l’école | Formulaire / accueil | VIS14 · antérieur | [Spécification](../02-experience/ecrans.md#e38) |
| E39 · Préparation et activation de l’école | Formulaire / accueil | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e39) |
| E40 · Identité et coordonnées élève | Formulaire / accueil | VIS08 · antérieur | [Spécification](../02-experience/ecrans.md#e40) |
| E41 · Formations souhaitées et acquis déclarés | Formulaire / accueil | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e41) |
| E42 · Comprendre le GPS et les notifications | Formulaire / accueil | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e42) |
| E43 · Prochaines étapes personnelles | Formulaire / accueil | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e43) |
| E44 · Préparation de l’appareil GPS | Carte / collecte / replay | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e44) |
| E45 · Activité et indicateurs détaillés | Dossier / liste / détail | VIS13 · antérieur | [Spécification](../02-experience/ecrans.md#e45) |
| E46 · Export de gestion | État / journal / opération sensible | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e46) |
| E47 · Accueil personnel du moniteur | Formulaire / accueil | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e47) |
| E48 · Politique de profil et paramètres détaillés | Formulaire / accueil | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e48) |
| E49 · Supprimer mon compte Drivy et suivre la demande | État / journal / opération sensible | Spécifié par pattern, non dessiné | [Spécification](../02-experience/ecrans.md#e49) |

## Priorité de couverture avant implémentation

Les 26 écrans non dessinés n’ont pas tous la même urgence. Avant de figer G1/G2, produire et revoir au minimum les écrans qui introduisent une interaction irréversible, une erreur difficile à comprendre ou une décision de sécurité : **E05 planification/déplacement, E17 opérations en attente, E19 compte/préférences, E21 conflit, E42 explication GPS/notifications, E44 préparation appareil GPS et E49 suppression de compte**. Pour G3/G4, prioriser E27/E28/E31 puis E36/E37/E46.

Cette liste n’ajoute aucune fonction. Elle évite de découvrir trop tard la forme d’un conflit, d’une reprise ou d’une suppression sensible alors que le backend est déjà figé. Un écran peut être développé à partir d’un pattern seulement si ses états sensibles ont été revus explicitement ; « même famille visuelle » n’est pas une validation de parcours.

## Compléter les vues restantes

Décliner les familles DS dans l’ordre des tranches du produit, puis examiner les états exceptionnels avant de déclarer un écran prêt. La suppression de compte, le détail d’une régularisation de droits et les changements de preuve nécessitent leurs propres validations de parcours même si leur style de formulaire est déjà défini.

La maquette ne décide ni des durées légales, ni de l’autorisation d’archivage, ni d’un prix automatiquement calculé. La source fonctionnelle reste prioritaire pour ces règles. [Composants](02-composants.md), [microtextes](05-contenu-etats.md), [recette](06-livraison-validation.md).

## Navigation de revue et navigation du produit

**À l’intérieur d’une composition**, un lien conserve l’utilisateur, l’école et le support représentés. L’agenda élève ouvre VIS15 puis le bilan publié ; il ne passe pas par VIS01/VIS02 du personnel. Les liens Cours/Offres du workspace désignent E27/E29, pas une inscription élève ou « Mes achats ».

**Le sélecteur extérieur** permet volontairement au lecteur de comparer les rôles et les appareils. Ce contrôle de galerie et les sélecteurs de scénarios ne seront pas intégrés à l’application. Les changements de scénario explicites peuvent réinitialiser la fiction ; un retour normal dans une leçon conserve en revanche la capture en cours et le brouillon.

**Prévisualisation du bilan VIS07 :** afficher les valeurs actuellement saisies, y compris le constat et le contexte d’une compétence observée. Cette variante ne sélectionne ni capture ni annotation autonome supplémentaire ; la prévisualisation le dit explicitement. Une future vue native devra aussi présenter toutes les sélections effectivement transmises par PublishCommand, pas seulement ces champs textuels.
