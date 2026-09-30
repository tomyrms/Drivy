# Docker Desktop — reprise du 30 septembre 2026

Docker Desktop 4.91.0 ne démarrait plus sur le PC : le backend échouait en renommant `sailor-ingest.sock`, puis `docker-secrets-engine/engine.sock`, avec l'erreur Windows 1920 (« Le système ne peut pas accéder au fichier »). Le moteur Linux n'était pas accessible. Les objets concernés étaient des fichiers de zéro octet avec l'attribut `ReparsePoint` ; leur type de reparse exact n'a pas pu être lu.

Après vérification de l'absence d'un backend actif, les répertoires contenant uniquement ces sockets ont été renommés sur place, sans suppression. Le premier essai avait recréé des sockets avant d'échouer sur le second répertoire ; ce répertoire transitoire a aussi été conservé. Les sauvegardes locales sont :

- `%LOCALAPPDATA%/Docker/run.before-drivy-20260930`
- `%LOCALAPPDATA%/Docker/run.retry-drivy-20260930`
- `%LOCALAPPDATA%/docker-secrets-engine.before-drivy-20260930`

L'arrêt normal de Desktop en état d'erreur échouait. Seuls les processus Desktop/backend lancés pendant cette intervention, identifiés par leur heure de création, ont été arrêtés avant le renommage. Aucun arrêt global de WSL, reset, réinstallation, changement de paramètres, modification de droits, suppression d'image ou de volume n'a été effectué.

Le redémarrage avec les deux répertoires de sockets neufs a réussi : le moteur répond en version **29.8.0**. Les conteneurs antérieurs étaient toujours présents et arrêtés ; les volumes existants restaient listés. Cela vérifie leur présence, pas une restauration ni le contenu métier de leurs bases. La recette backend qui suit utilise deux nouveaux conteneurs identifiés pour cette intervention, avec PostgreSQL en `tmpfs`, des ports limités à la boucle locale et aucune liaison avec les volumes antérieurs. Les résultats sont dans [la preuve backend](proofs/backend-resume-20260930.json).

La même classe d'erreur est décrite dans les signalements [Docker desktop-feedback #676](https://github.com/docker/desktop-feedback/issues/676) et [#531](https://github.com/docker/desktop-feedback/issues/531). Il s'agit d'un rétablissement constaté sur cette machine, pas d'une correction du logiciel Docker ni d'une garantie contre une récidive après un autre arrêt anormal. Les anciens sockets restent isolés ; ils ne doivent pas être remis à la place des sockets actifs.
