# Messages : entrée administrateur, suppressions et noms locaux (#200, #238, #246)

29 octobre 2026. Base `2d9a5f64`, branche `codex/ios-messages-200-238-246`. Les trois issues ont été relues sur
GitHub : ouvertes, sans commentaire, sans PR dédiée retrouvée. Les manques étaient encore présents dans l’IPA 446.
Les anciens tickets #69–#77 ne sont pas recomptés comme nouvelles réalisations. La relecture confirme notamment que
le signalement #77 n’a pas encore son chiffrement de preuves produit : ce lot ne prétend pas le livrer.

## Changements

**#200.** Le choix de navigation a été annoncé au porteur avant réalisation : dans l’accueil de gestion de l’ADMIN
seul, Messages devient une action nommée dans le contenu, près du portail et d’Actualiser. L’ancien raccourci de barre
disparaît. `SchoolMessagingEntryButton` conserve la présentation existante, l’identité de portée et la fermeture au
changement d’école/compte. Aucun nouvel onglet, aucune autre messagerie. Une composition absente est expliquée sans
fabriquer d’accès. ADMIN+INSTRUCTOR, élève, compte, changement d’école et garde de conduite conservent leurs parcours.

**#238.** Le tag officiel Exyte `3.3.0` (`259188eff6064605899044440e44e4e22f023d8c`, identique au verrou) a été inspecté
avant décision. `MessageMenuAction.isDestructive()` couple le rouge et l’alerte interne contenant « Cancel ». Les
points publics title/icon/menuItems, localisation et deleteMenuActionClosure ne séparent pas ce comportement.
Sources : [protocole](https://github.com/exyte/Chat/blob/3.3.0/Sources/ExyteChat/Views/MessageView/MessageMenu/MessageMenu%2BAction.swift),
[menu](https://github.com/exyte/Chat/blob/3.3.0/Sources/ExyteChat/Views/MessageView/MessageMenu/MessageMenu.swift).

Les deux ouvertures (appui long et choix ambigu dans les réactions) utilisent désormais une feuille native Drivy.
Elle présente la même palette de six réactions, les actions actuellement autorisées et une section Suppression avec
boutons à rôle destructif, libellés, icônes et indications accessibles. La suppression ne dépend donc pas seulement
du rouge. Exyte continue de porter les bulles, la liste et les réactions rendues ; son menu n’est pas ouvert. Aucun
fork, patch, version, verrou ou fonction Edit/Forward supplémentaire.

Le choix est exécuté après fermeture de la feuille, en relisant la cible et les droits. « Pour moi » et « pour tout
le monde » ont chacun une seule confirmation Drivy en français et leur conséquence propre. Annuler ne crée aucune
mutation. Les droits sont encore relus au bouton final ; les intentions et états non confirmés utilisent toujours
le moteur existant. Une seule présentation de confirmation gère aussi la clôture du sondage, afin de ne pas empiler
des modificateurs concurrents. Fermer la conversation ou perdre le contexte annule le menu et son choix différé.

**#246.** Un nom local choisi par l’utilisateur identifie l’appareil ; en son absence, « Appareil » et une référence
non secrète sont affichés. Les références abrégées sont allongées en cas de collision dans les appareils relus.
Les doublons de noms restent autorisés et distingués par la référence. « Cet appareil » garde sa section propre ;
l’identifiant canonique et l’empreinte complète restent consultables et sélectionnables. Aucun modèle matériel,
horaire de connexion ou niveau de confiance supplémentaire n’est inféré.

Les alias occupent un item Trousseau dédié, avec `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` et synchronisation
désactivée. Le Trousseau chiffre ces valeurs au repos ; aucun fichier clair, UserDefaults ou protocole cryptographique
maison n’est introduit. Voir [Apple, protection des données du Trousseau](https://support.apple.com/en-nz/guide/security/secb0694df1a/web).
La clé de portée est un condensat compte + école + époque d’accès + API ; celle d’un appareil lie ID et empreinte.
Une clé remplacée ne récupère donc pas le nom de l’ancienne identité. Une autre portée ne lit pas ces alias, et une
réponse tardive n’est pas affichée dans le nouveau contexte. Les noms sont locaux à cet appareil/portée et
ne sont ni publiés ni synchronisés entre appareils. La classe ThisDeviceOnly ne permet pas leur migration vers un
autre appareil ; aucune promesse d’effacement physique absolu ou de restauration n’est ajoutée.

La mise à jour du Trousseau est relue avant d’adopter le nom. En cas d’échec, la saisie reste ouverte, l’ancien nom
reste affiché et l’erreur est expliquée ; aucune persistance claire de repli. Une lecture de noms indisponible laisse
les ID/empreintes et la vérification utilisables. Les alias n’entrent jamais dans les décisions de confiance, la
signature ou le protocole Matrix. Limites d’interface/stockage : 64 caractères par nom, une ligne, 128 noms et 64 Kio
maximum par portée. Effacer le champ retire l’alias.

## Recette à réaliser sur l’IPA

1. #200 : ouvrir une école active en ADMIN seul, repérer Messages sans utiliser la barre, ouvrir puis fermer et
   retrouver portail/compte. Refaire sans composition Messages, en multi-écoles, ADMIN+INSTRUCTOR et élève. Vérifier
   iPhone/iPad, grand texte et annonce VoiceOver du bouton nommé ; vérifier la garde existante pendant un trajet.
2. #238 : appui long clavier ouvert/fermé sur son message, celui d’un autre et un message en lecture seule ; retrouver
   les six réactions, Répondre/Copier/épinglage autorisés. Vérifier les deux suppressions, leur confirmation française
   unique, Annuler, puis retrait des droits pendant le menu et pendant la confirmation. Vérifier réseau perdu après
   validation : aucun faux succès, moteur de reprise existant. Tester aussi la clôture d’un sondage. Clair/sombre,
   Dynamic Type et VoiceOver : actions accessibles et conséquences distinctes, aucun « Cancel » anglais.
3. #246 : nommer cet appareil et un autre, fermer/réouvrir et actualiser. Tester noms identiques, nom long, emoji,
   suppression du nom, échec Trousseau et changement de compte/école pendant une sauvegarde. Vérifier qu’un remplacement
   d’empreinte ne réutilise pas l’alias. Comparer les empreintes puis vérifier : renommer seul ne signe rien et ne
   coche jamais « Vérifié ». Contrôler physiquement le comportement du Trousseau après verrouillage et re-signature.

## Contrôles et limites

Exécuté : audit code/contrats/PR, revue statique du diff, contrôle des appels restants au menu interne,
`git diff --check`. Onze scénarios unitaires ciblés préparés : fermeture avant confirmation, annulation de conversation,
droits relus, identité du menu, suppression personnelle en lecture seule, épinglage réservé aux admins du général ; alias durable sans confiance implicite,
échec de stockage, doublons/empreinte remplacée, portée complète/longueur Unicode, réponse tardive après changement
de contexte. Aucun de ces tests n’a été exécuté dans ce lot.

**NOT_EXECUTED :** compilation Apple, tests Swift/UI, rendu de la feuille sur iPhone/iPad, essais physiques Trousseau,
VoiceOver et confirmation du porteur. Compilation de l’IPA et vérifications indispensables consolidées par le root,
campagnes après essai conformément à la demande. Les interactions natives réelles restent à vérifier : le contrôle
statique et les doubles synthétiques ne prouvent ni l’accessibilité physique ni la persistance Trousseau réelle.

Références : `COMMENCER_ICI.md`, U03/extensions, décisions du 23 octobre, contrat messagerie v2, scénarios de droits,
vérification d’appareils et interfaces/tests existants. Skills `ui-skills-root`, `swiftui-ui-patterns` et
`swift-native-components` ; composants, palette, tailles tactiles et typographie Drivy réutilisés.

Aucun changement API, web, EPIC #311, CI, dépendance ou déploiement. Aucun push, merge, commentaire ou clôture d’issue
par ce lot. `STATUS.md` reste à la consolidation du coordinateur.
