# Déploiement de l’agenda web — 26 octobre 2026

Le portail et son BFF ont été activés à **13:25:08 UTC, soit 14:25:08 Europe/Zurich**, version `71390e97d3c3ac313673635fe06c40c2f8e98c46`, sur [Drivy](https://drivy.shulker.ch/app/). La [PR #178](https://github.com/tomyrms/Drivy/pull/178) est fusionnée ; les issues #144, #145, #146, #147, #172, #173 et #175 sont fermées.

Leçons et séances collectives partagent la chronologie, les repères et les compteurs de l’agenda. Les lectures incomplètes ou interrompues restent explicites et peuvent être reprises ; l’ouverture conserve le rendez-vous choisi. La [qualification du lot](agenda-fiable-20261026.md) distingue les résultats web, métier Apple, UI et visuels, avec leur commit d’exécution.

## Sauvegarde et activation

La sauvegarde préalable de `drivy_refonte` sur CT113 mesure **2 276 844 octets**. Son catalogue et ses blocs ont été vérifiés. Elle est conservée sur le serveur à `/root/drivy_refonte-before-web-71390e97d3c3ac313673635fe06c40c2f8e98c46-20261026T132502Z-7fe84f58ebaa.dump`. Aucune restauration d’essai n’est revendiquée et aucune donnée ni empreinte de sauvegarde n’est publiée ici.

Le registre compte **53 migrations** ; aucune migration n’a été exécutée pendant cette bascule. La version précédente du web était `5888f03718045e13dc3c304040ead26991ffe719`, également base applicative déjà en service. Le runtime du déploiement est **Node v24.21.0**.

Dans CT114, le web utilise `/opt/drivy-refonte/web-releases/71390e97d3c3ac313673635fe06c40c2f8e98c46/apps/web`. L’override actif est `/etc/systemd/system/drivy-refonte-web.service.d/90-qa84-web-anchor.conf`.

Seul le processus web a été remplacé. Son état actif et son répertoire de travail réel ont été vérifiés. **API, identité, ingress et worker de cours restent actifs avec les mêmes PID et répertoires de travail avant et après la bascule.** Les environnements privés sont inchangés ; leur contenu et leurs empreintes ne sont pas recopiés dans ce rapport.

## Vérification publiée

**35 contrôles HTTPS réussis** : les 20 fichiers publics correspondent au build par SHA-256 ; neuf routes SPA répondent HTTP 200 avec le HTML attendu et `no-store` ; la session anonyme répond HTTP 200 avec `no-store` ; l’API et la nouvelle route BFF de leçon refusent l’accès sans jeton avec HTTP 401. Une requête avec paramètre inconnu et la readiness interne appelée publiquement répondent HTTP 404, comme attendu.

La page anonyme a été chargée dans Chromium après publication : l’écran « Se connecter à Drivy » et sa capture ont été inspectés. Aucun avertissement ou erreur console, aucune erreur de page ni requête échouée n’ont été relevés. Aucune commande métier sur les données de production n’est revendiquée par ces contrôles.

À **13:28:07 UTC**, le contrôle final confirme les cinq services actifs, aucun redémarrage automatique et les PID/répertoires conformes au reçu d’activation. Le web utilise `71390e97` ; l’API, le worker et le lien global `current` restent sur `5888f03`. La readiness interne de l’API répond HTTP 200 avec l’état prêt. Une relecture en lecture seule confirme les 53 migrations et leurs empreintes attendues. Le journal web ne contient aucune entrée depuis la bascule à 13:25:08 UTC, donc aucune erreur ni aucun avertissement sur cette fenêtre. Les preuves publiées sont limitées aux résultats nécessaires, sans données ni empreintes privées.

[Reçu de déploiement](proofs/web-agenda-20261026/deployment.json) · [32 contrôles HTTPS](proofs/web-agenda-20261026/deployment-https.json) · [Navigateur et trois contrôles complémentaires](proofs/web-agenda-20261026/deployment-browser.json) · [Contrôle du runtime](proofs/web-agenda-20261026/deployment-runtime.json) · [Capture publique](proofs/web-agenda-20261026/production-anonymous.png).

## Retour arrière web

L’override précédent a été sauvegardé dans `/root/drivy-web-rollback-71390e97d3c3ac313673635fe06c40c2f8e98c46.conf`. Il désigne `/opt/drivy-refonte/releases/5888f03718045e13dc3c304040ead26991ffe719/apps/web`.

Pour revenir à cette version, restaurer ce fichier dans `/etc/systemd/system/drivy-refonte-web.service.d/90-qa84-web-anchor.conf`, puis exécuter `systemctl daemon-reload` et `systemctl restart drivy-refonte-web`. Vérifier l’état actif, le répertoire réel du processus et les routes HTTPS. Cette opération porte seulement sur le web et ne demande pas de restauration de base.

Lors d’un prochain déploiement global, cet override devra être actualisé ou retiré explicitement : modifier le lien global `current` seul ne change pas la version du web.

## Installation native distincte

L’**IPA 381**, issue de `23b19f3`, reste non signée pour iLoader. Sa compilation et son contrôle d’empreinte sont documentés dans la qualification ; le déploiement web ne signe ni n’installe l’application sur l’iPhone. La signature et l’installation restent une étape distincte effectuée par le porteur. Aucune qualification physique VoiceOver, GPS, batterie ou réception push n’est déduite de cette bascule.
