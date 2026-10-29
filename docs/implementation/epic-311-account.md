# #311 — Compte, préférences, notifications et aide (#333, R22)

Reconstruit par le coordinateur le 29 octobre 2026, dans `portal/account/`.

- `PortalPreferencesPage` remplace la page `/app/preferences` quand la nouvelle présentation est choisie (`?presentation=nouvelle`) ; la page historique reste le défaut. Retour vers la page de console d’où l’on vient (`returnTo` limité aux adresses internes de console), sinon vers le compte.
- Apparence : Système / Clair / Sombre (contrôleur de thème existant, échec de stockage annoncé). Notifications : même `NotificationPreferenceStore` qu’avant (intentions par champ, vérification ou renvoi des mêmes choix après un résultat incertain, conflit de version avec choix explicite) ; seule la présentation change (interrupteurs). Compte et aide : mes écoles, récupération d’accès, contact de l’école.
- Le menu du compte de la nouvelle console ouvre les préférences avec le retour ; l’aperçu les ouvre en page autonome (`?page=preferences`), avec des routes personnelles fictives (`session`, `me`, préférences de notification) dans le transport d’aperçu.
- Texte explicatif « Où sont reçues ces notifications ? » retiré, conformément à la règle du peu de texte.

Exécuté : typage, 472 tests web (dont la frontière du portail), build de production, build d’aperçu, captures 1440/390 clair et sombre, changement d’un choix enregistré. Non exécuté : scénarios refus, conflit et réponse perdue en navigateur (le sélecteur de scénario n’est pas monté sur cette page autonome), vraie BFF.
