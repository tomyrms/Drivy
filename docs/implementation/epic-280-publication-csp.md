# EPIC #280 — contrôle ciblé du build sous CSP BFF

28 octobre 2026, immédiatement avant publication du candidat `be8a02457ef2c8877117e9a13557b288738fc4bf`. Complément à `epic-280-foundation.md` ; aucun changement produit ni assouplissement de sécurité à l’issue de ce contrôle.

Le vrai serveur compilé `buildWebApp` sert `apps/web/dist/client` sur un port loopback temporaire, avec `development: false`. Edge Chromium charge les fichiers de production, sans Vite ni injection de composants. Seules les réponses GET BFF sont remplacées dans le navigateur par les données synthétiques de la fixture locale. Les passerelles et l’identité synthétiques refusent tout accès réel ; aucune mutation n’est autorisée. Le serveur et le navigateur sont fermés à la fin.

L’en-tête du document a été comparé à la politique exacte du BFF, sans ajout d’`unsafe-inline` ni d’`unsafe-eval` :

```text
default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; manifest-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'
```

Quatre vérifications fonctionnelles réussies :

1. Chargement de la route de gestion compilée avec l’en-tête CSP exact.
2. SettingsSearch : ouverture du dialogue, saisie, résultats et fermeture par Échap.
3. Sélecteur d’école Combobox : ouverture du popup, options et fermeture par Échap.
4. Confirmation de départ avec brouillon : ouverture, Retour et conservation exacte de la saisie.

Aucune exception JavaScript de page, aucune erreur console et aucune violation CSP de style, fonte ou ressource de popup observées sur ces gestes. Les contrôles fonctionnent avec les styles de production et la politique appliquée par le navigateur.

L’assertion de diagnostic « zéro événement CSP » a néanmoins détecté **un événement `script-src`, `blockedURI: eval`, disposition `enforce`**. Sa provenance a été localisée dans `index-eK8kWx7N.js`, ligne 10, colonne 53070 : le probe `allowsEval` de Zod 4.6.6, qui essaie `Function('')`, attrape le refus et utilise son interpréteur sans génération de code. La source `node_modules/zod/v4/core/util.js` documente explicitement ce comportement sous CSP stricte. Le même probe est présent dans le build de référence e5166404 ; il ne provient pas des dialogues shadcn et n’a pas empêché les validations ou les quatre gestes contrôlés.

La politique reste inchangée et continue de bloquer cette tentative. Le réglage Zod `jitless: true` pourrait supprimer le probe dans une évolution séparée ; aucune modification de candidat pendant la publication n’a été faite pour ce signal préexistant et intercepté. Ce résultat ne doit pas être résumé comme « aucun événement CSP ».

Limites : navigateur Chromium desktop local, réponses et identité synthétiques, aucune authentification OIDC ni base PostgreSQL réellement exercées, aucun TLS/proxy du homelab ni Safari/Android physique qualifié par ce contrôle. Il s’agit d’un smoke de déploiement sur les popups demandés, pas de la campagne complète #309/#84 qui reste conditionnée à l’essai utilisateur.
