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

Compilation Apple et captures ciblées iPhone/iPad en cours. Les résultats seront ajoutés ici et dans `STATUS.md`. Les essais de transitions Face ID/app switcher, VoiceOver, clavier et GPS sur appareil physique ne sont pas exécutés par cette passe.
