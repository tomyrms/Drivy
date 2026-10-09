# Aujourd’hui allégé et logo de protection — 9 octobre 2026

Le porteur trouve la carte principale d’Aujourd’hui trop chargée. Il confirme cette surface, puis demande le logo Drivy à la place du symbole de carte lorsque l’app se protège en arrière-plan ou demande Face ID.

## Changements

- Le résumé principal reprend `DrivyLessonRow` : horaire, élève, lieu et éventuel état À terminer. La date complète, le délai relatif et l’avatar disparaissent de ce résumé. Le lieu garde deux lignes en texte standard, toute sa longueur en grand texte et dans la fiche ouverte. Les tailles typographiques du composant partagé restent identiques.
- La disponibilité « Démarrer dès… » reste une métadonnée, sans hauteur minimale de bouton. La prochaine leçon reste visible sous une leçon À terminer ; son contexte temporel est conservé.
- Le reste de la journée commence replié sur iPhone et iPad. Le nombre de prochaines leçons et le contrôle d’ouverture restent visibles ; la vue ne réinitialise pas un choix d’ouverture volontaire lors d’un changement de largeur.
- Le masque opaque d’arrière-plan et l’écran verrouillé emploient l’asset `DrivyBrand`, clair/sombre. Le masque affiche le logo immédiatement, sans animation. Face ID, le recours au code, les délais et le déclenchement du verrouillage ne changent pas.

La sélection de la leçon, les droits, les conditions de démarrage, les actions métier, la carte et les transports restent identiques. Les skills `better-layout` et `better-writing` guident la correction ; un audit indépendant avec `improve-ui` a établi le [plan de composition](../../design-plans/today-card-density-20261009.md).

## Vérification

Relecture indépendante des branches Aujourd’hui et du masque ; aucun changement de garde d’authentification ou de droits. `git diff --check` et deux contrôles du harnais de captures réussis sur Windows. Les variantes de démonstration `home-to-finish` et `app-privacy` sont isolées aux builds DEBUG de simulateur ; elles utilisent les vues réelles, sans compte ni données de production.

Sur le code `86ef790`, les [vérifications générales](https://github.com/tomyrms/Drivy/actions/runs/37863223588) réussissent : 238 tests API/PostgreSQL, 104 tests web, types, builds et intégrité documentaire. La [compilation Release](https://github.com/tomyrms/Drivy/actions/runs/37863223579) produit l’IPA 0.7.0 build 121, non signée pour iLoader. Le paquet a été téléchargé ; son exécutable est présent et son SHA-256 correspond à `245b0a4529bf7c86f0f281efe34720bfaac2cdce5a0506ec96070cfe2e7d08f2`.

La compilation simulateur de l’app et des cibles de tests a réussi. Les campagnes [portrait iPhone/iPad](https://github.com/tomyrms/Drivy/actions/runs/37863242193) et [paysage iPad](https://github.com/tomyrms/Drivy/actions/runs/37863347673) réussissent et produisent 20 captures en clair/sombre, en taille usuelle. La variante `home-to-finish` vérifie avant la capture la présence du bouton de fin de leçon et du résumé de la suivante. La suite native métier complète n’est pas répétée pour cette passe de présentation ; les captures utilisent les tests d’interface ciblés.

Les 20 PNG ont été ouverts et inspectés : aucun texte coupé ni chevauchement constaté dans les zones visibles. Sur iPhone, le panneau tient au-dessus des onglets ; sur iPad paysage, il reste dans la colonne latérale. À terminer et la prochaine leçon sont lisibles, les autres leçons commencent repliées. Le logo est net et centré, avec un masque opaque sans contenu scolaire. Six tests de capture réussissent au total. [Manifestes et empreintes](proofs/today-privacy-20261009.json), [cinq originaux retenus](assets/today-privacy-20261009).

Ces rendus emploient des données fictives ; la localisation est indisponible. Ils ne montrent ni lieu très long, ni état « Démarrer dès… », ni trajet démarrable. La réduction de hauteur par rapport à l’ancienne version n’a pas été mesurée. Les transitions Face ID/app switcher sur appareil physique ne sont pas qualifiées par ces captures.
