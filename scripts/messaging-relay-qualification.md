# Qualification intégrée Matrix / relais Drivy

Ces fichiers sont un harnais synthétique, jamais un serveur à déployer. Le bootstrap emploie les vraies routes `registerMessaging`/`registerMessagingKeys`, la vraie PostgreSQL avec RLS et les migrations/fixtures canoniques. Le vérificateur d'identité est synthétique, donc **aucune qualification OIDC** n'en découle.

## Préparer le runner Apple (responsabilité CI)

1. Node 24 et `npm ci` depuis la racine (workspace API). PostgreSQL natif local, cluster jetable distinct créé pour ce job, base **drivy_test**. Ne pas mettre `services: postgres` sur un runner macOS et ne pas contacter un service distant.
2. Certificat HTTPS éphémère avec SAN `localhost` et `127.0.0.1`, signé par une racine temporaire approuvée dans le simulateur. Utiliser la validation TLS normale. Ne pas modifier les protections réseau de l'app distribuée ni désactiver la validation de certificat dans le transport Swift.
3. Le certificat doit autoriser l'usage serveur TLS. Tester la connectivité du simulateur, pas seulement `curl` sur le Mac. Le serveur écoute exclusivement `127.0.0.1`.
4. Limiter les logs PostgreSQL : pas de log de requêtes/paramètres ou données en erreur. Les erreurs Fastify ne contiennent ni corps, ni en-tête, ni stack. Ne pas uploader cluster, stores simulateur, certificats privés, variables d'environnement ou réponses crypto.

Variables de bootstrap (valeurs synthétiques uniquement) :

```text
NODE_ENV=test
DRIVY_RELAY_ALLOW_RESET=1
TEST_DATABASE_URL=postgresql://fixture:fixture@127.0.0.1:15432/drivy_test
DRIVY_RELAY_TLS_CERT=/temporary/localhost.crt
DRIVY_RELAY_TLS_KEY=/temporary/localhost.key
DRIVY_RELAY_PORT=18443
```

Le bootstrap **recrée le schéma de la base isolée**, avec migrations sous propriétaire non privilégié comme les tests API. Cette opération exige l'opt-in ci-dessus et refuse toute base autre que drivy_test, tout hôte hors loopback et tout paramètre d'URL susceptible de changer la destination.

Depuis la racine :

```text
node --import tsx scripts/messaging-relay-qualification.mts
```

Attendre `GET https://localhost:18443/qualification/ready` avec un délai borné. Réponse attendue : `ready: true`, `fixture: drivy-messaging-relay-v1` et IDs canoniques synthétiques. Le seul log de démarrage est `RELAY_QUALIFICATION_READY` ou `RELAY_QUALIFICATION_START_FAILED`. Pas de route distante de reset.

Le script possède un arrêt SIGINT/SIGTERM et une durée maximale de 120 minutes, supérieure au budget de 90 minutes du job Apple. CI doit néanmoins arrêter son processus et son cluster dans une étape always/trap, sans tuer des services étrangers. Démarrer le serveur après la longue compilation si nécessaire pour ne pas consommer sa durée de vie avant XCTest.

## Exécuter le XCTest intégré

Classe incluse par `apps/ios/project.yml` dans DrivyTests via le dossier de sources :

```text
DrivyTests/MatrixMessagingRelayIntegrationTests/testRealRelayExchangeIdempotenceRecoveryAndContextRefusal
```

Transmettre **dans le processus XCTest** :

```text
DRIVY_RELAY_QUALIFICATION_URL=https://localhost:18443
```

Pas de slash final. Une variable shell du Mac n'est pas une preuve de transmission au simulateur : configurer l'environnement du test runner (xctestrun ou mécanisme de lancement validé par CI) et contrôler effectivement la découverte/exécution. La classe refuse une URL non HTTPS, non loopback, contenant utilisateur/mot de passe/query/fragment, sans port dédié. Absence de variable = XCTFail, jamais XCTSkip.

**Garde de résultat : exactement un scénario intégré attendu, aucun ignoré, compteur exécuté positif et conclusion réussie.** Les suites qui découvrent cette classe doivent fournir l'environnement. Ne pas faire passer une campagne complète en la sautant silencieusement. Les jobs ciblés qui ne la découvrent pas ne constituent pas sa qualification.

Scénario : vraie création conversation, publication clés B, chiffrement A, POST durable, répétition idempotente, GET B puis déchiffrement. Backup B après réception, nouvel appareil C avec magasin et Keychain distincts, refus sans clé, refus d'une mauvaise clé valide, restauration effective avec la bonne clé et lecture du même message. Rejet serveur attendu pour acteur incorrect et école étrangère.

Trois namespaces du **vrai Keychain** sont utilisés : un chemin de vault différent seul ne crée pas un appareil distinct. Les namespaces de qualification sont retirés à la fin. Stores chiffrés dans le temporaire du simulateur jetable, jamais joints aux artefacts. Les assertions de contenu sont booléennes pour ne pas afficher valeur attendue/réelle.

## Contrôles locaux exécutables sans base

```text
node --import tsx --test scripts/messaging-relay-qualification.test.mjs
node node_modules/typescript/bin/tsc --noEmit --strict --module NodeNext --moduleResolution NodeNext --target ES2022 --esModuleInterop --skipLibCheck scripts/messaging-relay-qualification.mts
```

Observation du 23 octobre 2026 : **9 gardes passées**, 0 échec/ignoré, 1692,2318 ms de suite sous Node **26.8.1** Windows (hors cible Node24). Typage strict réussi. Premier essai de test avant création du module : erreur module absent, pas un rouge métier. Premier typage sans `--strict` : erreurs de modèles API dépendant de strictNullChecks, corrigé en utilisant le mode strict canonique, sans modifier ces sources.

**Non exécuté localement :** bootstrap PostgreSQL réel, HTTPS simulateur, compilation Swift, XCTest intégré. Aucun binaire psql/initdb/pg_ctl trouvé dans PATH Windows et pas de Xcode. Le passage des neuf gardes ne prouve pas l'intégration ni les quatre scénarios du prototype Rust.

## Limites et suites

Ce minimum ne qualifie pas encore perte réelle d'acquittement réseau, retrait/réintégration, sauvegarde automatique des clés reçues après activation préalable, attaques d'altération, relance de processus, panne disque/Keychain ou absence de contenu dans tous les logs 400/403/409/500. Il ne valide ni résidence ni appareil physique. Les évolutions du contrat par les autres agents doivent être requalifiées sur le SHA final.
