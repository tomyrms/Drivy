# Revue et corrections de conception V3.14

**20 septembre 2026 · Source V3.13 fournie par le porteur · Drivy**

## Mandat et limite

Le porteur confirme une expérience centrée sur l’enregistrement des trajets et une bulle de signalement pédagogique inspirée du principe Waze. Cette passe modifie la documentation et la démonstration HTML, pas l’application Swift ni le backend. Les trois rapports de Claude fournis dans la conversation éclairent la revue ; leurs recommandations ne sont pas des validations produit. Les sources externes utilisées dans cette passe sont consignées en S135–S139.

## Évolution réellement livrée

La carte occupe l’espace principal de E23. « Signaler » reste hors défilement, avec Pause/Arrêter accessibles. L’ouverture fixe l’heure et l’ancre candidate sans création ; la sélection explicite thème/statut crée une observation privée. Annuler ne crée rien. Un repère non qualifié et le complément détaillé restent disponibles. Le replay privé et le replay publié sont distincts. Les observations sans GPS utilisent la même qualification sans fabriquer de point.

Les catégories et durées d’animation sont des propositions. Les six catégories de la fixture ne constituent pas un référentiel métier approuvé. Le prototype n’émet aucune coordonnée géographique : il illustre des références à des points de canvas fictifs. Une mémoire JavaScript n’est ni une outbox durable ni une preuve d’idempotence serveur. Recharger efface les observations de cette visite.

## Traitement des constats de Claude

| Constat | Traitement dans cette livraison | Preuve ou limite |
|---|---|---|
| RCH-001 | E23 recomposé ; déclencheur hors défilement et informations secondaires compressibles. | Mesures navigateur de la nouvelle géométrie ; cible 60 unités proposée, pas sûreté prouvée. |
| RCH-002 | Libellés alignés sur « Signaler », « Marquer un moment » et « Compléter l’observation ». | Le remplacement global par « Observer à l’arrêt » n’est pas retenu : il ne traduit pas le besoin précisé par le porteur. L’usage en mouvement reste non qualifié. |
| RCH-003 | Protocole hors circulation décrit dans le plan mobile. | Pas de seuil NHTSA transposé en preuve de sécurité du moniteur, pas d’entretien exécuté. |
| RCH-004 | Règle fondée sur classes de taille/espace utile, Split View et fenêtre redimensionnable. | T428 reste NOT_EXECUTED sur appareil ; le resize HTML ne teste pas le collecteur Swift. |
| RCH-005 | Clause générale d’accessibilité applicable à tous les écrans ; contraste renforcé et réduction des mouvements explicites. | VoiceOver, clavier natif et Dynamic Type restent à qualifier. |
| RCH-006 | Six états canoniques sur les 49 fiches ; anciennes explications conservées. | Contrôle de structure, pas couverture comportementale nouvellement prouvée. |
| RCH-007 | DM01 reste une décision de compatibilité avant G2B. | Aucun plancher commercial ni parc pilote inventé. |
| RCH-008 | Effet système de bord de défilement contextualisé à la frontière d’un contenu défilant. | Ne pas imposer cet effet sur toute surface superposée à une carte. |
| RCH-009 | Benchmark complémentaire non exécuté dans cette passe centrée sur le parcours GPS. | QualiDrive/OrphyDrive ne sont pas déclarés étudiés ici ni « majeurs » sans mesure. |
| RCH-010 | Questions contractuelles, données nécessaires et droits éventuels d’un représentant séparés. | Aucun accès parental ni régime juridique automatique ajouté ; avis externe toujours requis. |
| RCH-011 | Pastilles et en-tête web adaptés au texte agrandi. | Mesures DOM dans les rapports courants ; aucune certification globale d’accessibilité. |
| RCH-012 | Quotas MapKit JS renseignés et sourcés. | DM05 n’est pas fermé : volumes, allocation partagée, cache et conditions restent à instruire. |
| RCH-013 | Versions indépendantes expliquées ; galerie/scènes/interactions changées en 3.14. | API 3.11.0, tokens 3.8 et ancien replay 3.9 demeurent inchangés. |
| RCH-014 | Arrière-plan distingué de terminaison/fermeture forcée. | Aucune promesse « GPS permanent application fermée ». Indicateur système à constater sur appareil. |
| RCH-015 | Formatage des nombres et montants par les API de locale, pas concaténation. | Textes DE/IT et tests des formats non réalisés sur application. |

## Traçabilité et simplicité

R46, E04/E08/E23/E24, D33, parcours, synchronisation, modèle logique et API documentaire sont alignés. Les douze scénarios T423–T434 spécifient les transitions supplémentaires ; les 434 scénarios métier et 68 mobiles restent NOT_EXECUTED sur le produit. Aucune entité, route ni schéma OpenAPI n’est ajouté. La création de l’observation réutilise la forme GeoObservationCommand et ses références d’ancre existantes.

## Vérification et interprétation

Exécuter `python annexes/verifier-livraison.py --browser --chromium /chemin/vers/chromium --write-report` après installation des dépendances. Les rapports V3.14 portent sur le contenu documentaire, les schémas et le navigateur. Les rapports antérieurs sont conservés comme historique, pas présentés comme tests de la V3.14.

Le vérificateur de signalement inclut des contrôles négatifs : un événement sur ouverture, une ancre déplacée à la validation et un statut omis doivent être rejetés par les assertions correspondantes. L’indisponibilité du navigateur ou d’une dépendance échoue explicitement. Les dates et résultats d’exécution sont ceux du rapport, jamais des résultats terrain.

Aucun build Swift, test GPS réel, transaction PostgreSQL, test routier, entretien utilisateur, estimation commerciale validée ou validation juridique n’est effectué. La source V3.13 reste intacte. Les caches Python ne sont pas livrés.
