# Drivy V3.16 : affiner sans changer la direction

> 20 septembre 2026 · Source V3.15 intacte · Prototype HTML et documentation, pas application native.

## Mandat et limites de preuve

Le porteur apprécie la V3.15 et demande l’application du [plan d’affinage visuel](../01-recherche/affinage-visuel.md). La carte, le bleu, les surfaces et le déclencheur Signaler restent inchangés dans leur rôle. Les recherches externes viennent de la note fournie ; aucune nouvelle consultation ni test d’application concurrente n’est revendiqué. Cette passe couvre les quatre vues E23/E24, pas l’agenda, les fiches élèves ou les 49 écrans.

## Changements appliqués

| Proposition | Application | Limite conservée |
|---|---|---|
| VIS-01 · Statuts | Retrait des chevrons, état pressé, instruction commune et nom accessible explicite | Compréhension à vérifier avec utilisateurs ; choix explicite et publication séparée |
| VIS-02 · Repère | Seul point sélectionné : pictogramme du thème et symbole de statut ; thème repris au panneau | Pas d’étiquette sur chaque point ; les marqueurs proches peuvent se superposer |
| VIS-03 · Panneau | Même nœud de dialogue et même carte de catégories à statut ; contenu/hauteur animés, retour focalisé | 200 ms est une proposition de prototype, pas une qualification native ; mouvements réduits respectés |
| VIS-04 · Iconographie | Pictogramme de giratoire revu, famille SVG et textes courts conservés | « Observation » reste inchangé : renommer en « Contrôles visuels » requiert confirmation métier |
| VIS-05 · Densité | Fond urbain fictif et quatre observations optionnelles, dont deux au même instant | Carte MapKit réelle, collisions natives, lisibilité extérieure et performances non testées |

L’en-tête n’est pas déplacé lors de la transition de panneau. Le moment et l’ancre restent figés à l’ouverture ; annuler n’ajoute rien. Aucune animation de succès n’est déclenchée par une écriture simulée en échec. Les contrôles restent immédiatement actionnables, sans attendre la fin de la transition.

## Corrections découvertes pendant l’intégration

Le parcours précédent/suivant parcourt maintenant les identifiants distincts au même horodatage au lieu de sauter directement au temps suivant. Une correction de qualification peut être annulée en restaurant l’événement antérieur, sans le supprimer. Un échec de repère simple est affiché explicitement. Une sélection cartographique en replay ne remet plus le cadrage libre à zéro ; la sélection temporelle ne continue pas d’afficher une observation éloignée pendant la lecture. Ces comportements sont vérifiés en HTML, pas côté serveur.

## Documentation consolidée

Les fiches E23/E24, les composants, la cartographie et les microtextes décrivent la même interaction. Les descriptions de pastilles numérotées sont réservées à la galerie historique au lieu de contredire la référence privée courante. La capture est distinguée du temps de leçon, la fin de leçon de l’arrêt GPS, le commit local de la publication.

Les sources de l’atelier et leur HTML sont régénérés ensemble ; les huit SVG sont des exports statiques. Ni fichier .fig, ni composant Figma, ni API ou table nouvelle. Le contrat OpenAPI 3.11.0, les tokens 3.8 et le registre de traçabilité sont conservés par empreinte.

## Contrôles de la passe

[Livraison](../annexes/verification-livraison-v3-16.json), [atelier](../annexes/verification-atelier-v3-16.json), [invariants](../annexes/verification-visuel-v3-16.json), [lecteur](../annexes/verification-lecteur-v3-16.json), [provenance](../annexes/provenance-v3-16.json). Le rapport de l’atelier précise les assertions réellement exécutées et les 128 combinaisons de disposition. La matrice combine quatre formats, deux thèmes, deux tailles de texte, quatre vues et deux fonds fictifs. Les événements denses ont leurs parcours vérifiés séparément.

**Ouverture directe locale :** l’essai `file://` a été refusé par la politique du navigateur de cet environnement (`ERR_BLOCKED_BY_ADMINISTRATOR`). Le [rapport séparé](../annexes/verification-ouverture-locale-v3-16.json) reste bloqué, pas réussi. Les 65 assertions d’interaction et les 128 dispositions chargent les mêmes octets HTML avec `page.set_content` ; elles ne qualifient pas l’ouverture sous chaque navigateur utilisateur.

Les contrôles spécialisés historiques de l’API applicative, des fichiers et du mobile ne sont pas tous rejoués. Aucun rapport historique n’est annoncé comme résultat courant. **434 scénarios métier et 68 scénarios mobiles restent NOT_EXECUTED sur l’application.**

## À vérifier avant implémentation définitive

Compréhension des statuts, pertinence des pictogrammes, taxonomie, accès aux commandes GPS depuis une feuille, disposition sur fond MapKit réel, gestion native des collisions, grands textes, VoiceOver et réduction des mouvements réels. Aucun entretien, trajet routier, contrôle Windows/Safari, build Swift, synchronisation serveur, base locale durable ou mesure batterie effectué. L’atelier utilise des données en mémoire qui disparaissent au rechargement.
