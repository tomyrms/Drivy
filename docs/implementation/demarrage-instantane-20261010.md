# Démarrage instantané d’une leçon — un seul parcours orchestré (10 octobre 2026)

Demande du porteur : rendre continu le geste « Démarrer une leçon » sans rendez-vous (choix de l’élève, accord GPS, rideau de marque, carte du trajet). Trois audits en lecture seule (UI/UX, Core Location, architecture) ont précédé l’implémentation.

## Causes constatées

- **Sélecteur d’élève** : la ligne « Élève » poussait une `List` + `.searchable` dans une feuille en détente moyenne, en forçant la détente `.large` au même moment. Push, agrandissement de la feuille et apparition de la barre de recherche se superposaient ; la liste gardait les fonds système (flash en thème sombre) ; au retour, la feuille restait haute et la formation se chargeait avec un squelette qui poussait la mise en page.
- **Accord GPS pendant le rideau** : le rideau se montrait au geste, la préparation découvrait ensuite un accord absent, effaçait le rideau et ouvrait une seconde feuille ; une fois l’accord donné, le rideau revenait (double chargement). Même enchaînement depuis « Démarrer le trajet » d’une leçon planifiée.
- **Position tardive** : le réveil du récepteur n’arrivait qu’après la création de la leçon et la lecture complète de la préparation, et chaque relecture (`load()`) l’arrêtait. La mesure de diagnostic repassait par `requestLocation()` (plusieurs secondes en précision maximale). Le départ enchaînait environ 49 requêtes en série, dont 20 `/me`, avec deux relectures complètes du départ (`reviewStart` puis `confirmStart`) sans personne entre les deux.
- **Rideau levé trop tôt** : quand le départ est confirmé, « Aujourd’hui » laisse place à la carte ; la feuille de préparation disparaissait alors avec lui et son `onDisappear` effaçait le rideau avant la première position. La carte affichait ensuite un écran d’attente vide.
- **Autorisation perdue** : une autorisation de capture reçue après la disparition de l’écran n’était pas enregistrée, donc jamais scellée ; l’école la gardait active jusqu’à trois heures.
- **Double appui** : un second appui lancé avant le rendu suivant effaçait le rideau pendant que la première création était en vol.

## Parcours retenu

1. **Démarrer une leçon** ouvre une feuille unique, toujours en `.large` (aucun changement de hauteur en cours de route), fond `canvas`.
2. **Élève** : champ de recherche Drivy fixe en tête, liste à hauteur stable (même règle de recherche, noms repliés une fois). Un toucher choisit ; le récapitulatif remplace la liste sur place (ressort court, fondu seul sous Réduire les animations). Élève imposé par sa fiche ou élève unique : le récapitulatif d’emblée.
3. **Récapitulatif** : élève (« Changer »), formation, lieu, puis **l’accord GPS de l’élève**, au niveau de l’élève (le choix général vaut pour une leçon neuve). Deux réponses de même poids tant que rien ne vaut pour l’information actuelle de l’école ; sinon la réponse et « Modifier ». La réponse reste locale jusqu’au départ : un oui effleuré n’est jamais enregistré. Sans réponse, la leçon démarre sans GPS et rien n’est enregistré. L’état de l’appareil (localisation refusée, position exacte désactivée) n’apparaît que s’il empêchera le trajet.
4. **Démarrer maintenant** : la question d’iOS (autorisation de localisation) passe avant le rideau, sur la feuille. Puis, avec GPS, le rideau couvre l’enregistrement de l’accord et la création de la leçon (en parallèle), le départ du trajet et sa première position. Sans GPS, pas de rideau : la leçon s’ouvre à la place du récapitulatif, dans la même feuille.
5. **Carte prête** : le rideau se lève à la première position enregistrée, sept secondes au plus après la confirmation du départ. Tant qu’aucune position n’est enregistrée, la carte montre déjà la position de l’appareil (point Plans, jamais enregistré, comme « Aujourd’hui ») avec l’état « En attente de position ».

Un départ du trajet qui échoue n’est jamais un échec de la leçon : elle s’ouvre dans la feuille avec la raison en tête (masquable) ; son bouton « Démarrer le trajet » reste le chemin de reprise. Un conflit de planning garde le récapitulatif et propose de planifier autrement.

Depuis une leçon planifiée, « Démarrer le trajet » lit d’abord leçon et accord (attente dans le bouton) : le rideau ne se montre que si le départ peut partir sans question ; sinon la feuille de préparation s’ouvre sur la question d’accord, posée en ligne (plus de feuille supplémentaire).

## Implémentation

- `SchoolStartNowLaunch` (nouveau, `SchoolAgendaUI/SchoolStartNowLaunch.swift`) : machine à états explicite (`editing`, `requestingPermission`, `creating`, `startingTrip`, `waitingForPosition`, `done`) et étapes de la feuille (`learner`, `summary`, `lesson`). Garde synchrone contre le double appui. La chaîne survit à l’écran d’origine (la carte remplace « Aujourd’hui ») et termine le geste elle-même. Attend le premier plan avant d’ouvrir le trajet.
- `SchoolStartNowGPS` : accord de l’élève (`SchoolRecordingChoiceWorkspace` lié à l’élève, sans leçon) et état de l’appareil, deux questions distinctes ; réveil du récepteur dès que le trajet est voulu et permis ; le récepteur réveillé passe tel quel à la préparation (`capturePreparation(…, source:)`).
- `SchoolLearnerPicker`, `DrivySearchField`, `SchoolLearnerIndex` (`UI/SchoolLearnerPicker.swift`) ; `SchoolRecordingChoiceInline` (`SchoolCaptureUI/`), aussi utilisé par la préparation.
- `SchoolCaptureLocationSource` : chaque `warmUp()` repousse l’arrêt automatique ; le réveil se suspend en arrière-plan et reprend au retour ; ses mesures récentes (≤ 5 s, ≤ 35 m, prises après le réveil, ni simulées ni d’accessoire) servent de mesure de diagnostic (âge et précision seulement) ; réponse toujours asynchrone ; `preciseLocation` exposée.
- `SchoolCapturePreparationWorkspace` : `load()` ne coupe plus un réveil en cours ; réveil après l’accord confirmé ; position exacte et absence de mesure détectées sans requête ; une seule relecture du départ (`confirmStart(…, revalidate: false)`, l’école revérifiant tout au POST) ; droits relus une fois par contexte ; lectures indépendantes en parallèle ; `readyForOneStepStart`, `isStarting`, `onQuickStep` (étapes annoncées au rideau sans vue).
- `DrivyLaunchCurtain` : levée dès que le symbole est assemblé (`minimumShown`, 1,1 s) et que le départ est prêt, au lieu de la séquence entière de 2 s ; garde-fou réarmé à chaque étape.
- `SchoolCaptureTransferCoordinator` : une autorisation reçue est enregistrée avant tout contrôle d’annulation, puis scellée par l’appelant si le départ n’a plus lieu.
- `SchoolStartNowWorkspace.send` : plus de second enregistrement chiffré d’une demande neuve.
- Jetons `DrivyMotion.step` et `DrivyMotion.reveal`.

## Vérification

- IPA Release compilée par le workflow « IPA d’essai · iLoader » (voir STATUS).
- Tests ajoutés (`SchoolStartNowLaunchTests`, deux tests dans `SchoolCaptureLifecycleTests`) : double appui → une seule création et leçon ouverte sur place ; conflit → récapitulatif conservé ; élève unique → récapitulatif puis retour à la liste ; seuils de réutilisation d’une mesure ; index de recherche identique à la règle ; relecture unique au départ (une seule lecture de l’école, un seul POST) et réveil après l’accord ; état prêt avant tout rideau. **Non exécutés** à la demande du porteur (compilation de l’IPA seulement) : la cible de tests n’est pas compilée par ce workflow.

## Limites

- Rien de ce parcours n’a été vu tourner ni mesuré : fluidité, délai réel de première position, comportement du point Plans et de la question d’iOS restent à observer sur iPhone.
- La création de la leçon et le diagnostic de l’appareil restent séquentiels : le diagnostic dépend encore de la leçon dans la préparation. Le faire en parallèle demanderait un diagnostic indépendant de la leçon (même journal, mêmes garde-fous).
- Réseau très lent : le rideau reste jusqu’au garde-fou (40 s sans étape), sans issue intermédiaire.
- Un trajet démarré depuis la fiche d’un élève fait passer l’app sur « Aujourd’hui » ; la feuille est fermée explicitement sous le rideau.
- Échec du départ dans la toute dernière vérification des droits (après l’autorisation de l’école) : la carte a déjà remplacé « Aujourd’hui », la feuille a disparu avec lui ; le rideau se lève sur « Aujourd’hui » et la leçon créée, sans la raison de l’échec. Cas rare (coupure réseau à cet instant précis).
- Depuis une leçon planifiée, au tout premier usage de l’app, l’alerte d’autorisation d’iOS peut encore apparaître au-dessus du rideau (le démarrage immédiat, lui, la pose avant).
- L’accord donné dans le récapitulatif est enregistré au départ, en même temps que la leçon : il reste enregistré si l’école refuse ensuite la leçon (conflit), puisqu’il exprime le choix de l’élève et non la leçon.

## Relecture QA (agent dédié, même jour)

Aucune régression bloquante. Corrigés : départ possible pendant la lecture de l’accord (bouton désormais inactif tant que l’accord se lit ; accord de l’élève imposé lu en même temps que la feuille), récapitulatif bloqué après l’abandon d’une demande sans élève choisi (retour à la liste), échec d’enregistrement de l’accord muet dans la question (message affiché), récepteur laissé réveillé après un départ refusé (préparation invalidée), refus de localisation à l’alerte d’iOS sans explication (message au-dessus de la leçon), garde-fou du rideau non réarmé quand sa barre plafonne, mesure de diagnostic précise remplacée par une moins précise du réveil, protection du bilan modifié concurrencée par celle de la feuille.
