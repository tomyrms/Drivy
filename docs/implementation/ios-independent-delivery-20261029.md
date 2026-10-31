# IPA d’essai — lot iOS indépendant, 29 octobre 2026

[PR brouillon #337](https://github.com/tomyrms/Drivy/pull/337), six issues : #195, #197, #198, #199, #237, #241.
Base `master c94ec2bb`, branches séparées puis intégration `codex/ios-independent-20261029`.
Le [triage des 155 issues ouvertes](ios-independent-triage-20261029.md) distingue le périmètre exclu #311 et les lots suivants.

## Produit réellement compilé

- [Run 40941417787](https://github.com/tomyrms/Drivy/actions/runs/40941417787) : **SUCCESS**, workflow IPA seul, lancé explicitement avec `messaging_qualification=true`.
- SHA du produit : `eb4a5aaec9934b7054b624206539893ad4a2c450`.
- [Télécharger l’artefact IPA](https://github.com/tomyrms/Drivy/actions/runs/40941417787/artifacts/12928142080) : version **0.7.0**, build **445**, Release, iPhone/iPad **iOS 26 minimum**, non signé pour iLoader. L’archive contient `ios/Drivy.ipa`. Rétention GitHub annoncée jusqu’au 12 novembre 2026.
- Archive Xcode créée, architectures appareil/signatures vérifiées par le workflow ; accès scolaire configuré et accès Messages de qualification inclus. Aucune fixture dans l’IPA Release.
- Téléchargement local et vérification effectués : les trois empreintes de `SHA256SUMS.txt` concordent (`Drivy.ipa`, `build-info.json`, `Package.resolved`), CRC ZIP valide, version/build du plist identiques au reçu, aucun profil ou répertoire de signature présent.
- Taille de l’IPA : **17 941 786 octets** ; SHA-256 : `3bf049ccc5b1318fce16d8e058c325e1e010a09df122b64bce783e2d0ce6696c`.

Les commits postérieurs à ce SHA complètent uniquement la documentation de livraison. L’identité du produit ne se déduit jamais de la tête courante de la PR.

## Vérifications et limites

Exécuté : revues de source et revues croisées auth/Messages, contrôle du périmètre, `git diff --check`, compilation et contrôles du paquet ci-dessus. Aucun fichier web/API/contrat/migration/dépendance/workflow changé. Worktrees de Claude et fichier local préexistant conservés.

**NOT_EXECUTED** : tests Swift/UI préparés, compilation des cibles de tests, campagnes complètes, essai physique, VoiceOver physique et réseau dégradé réel. La compilation réussie ne qualifie pas le rendu Exyte ni les scénarios de reprise. Aucun déploiement, fusion ou clôture ; #50 reste désactivée selon sa configuration existante.

Le retour du porteur sur cette IPA précède les tests pertinents, corrections éventuelles, fusion dans `master` et clôture des issues effectivement terminées. Références des suites préparées dans [auth](ios-auth-195-199.md) et [Messages](ios-messages-237-241.md).

## Essai proposé

1. Connexion : adresse incomplète et mot de passe vide, passage au champ suivant et validation clavier ; puis panne réseau et édition de l’adresse. Une panne reste un retour du formulaire, sans accusation du mot de passe.
2. Code d’invitation : après saisie d’un code, coller du contenu trop long ou non reconnu ; refus visible, saisie précédente intacte. Dans « Mot de passe oublié », si le service n’est pas configuré, revenir directement à la connexion sans faux envoi de courrier.
3. Messages : ouvrir plusieurs fois une épingle, puis utiliser l’action suivante ; la cible affichée doit correspondre à celle ouverte. Sous réseau lent/interrompu, distinguer confirmation attendue, résultat inconnu et refus ; aucun second envoi pendant la requête en vol, aucune seconde bulle après reprise.

Suite prioritaire proposée après retour : #207 (cours dans Aujourd’hui), puis #211–#213 (préférences de planification) et #202–#204 (notifications). Ces lots ne sont pas revendiqués réalisés par la présente IPA.
