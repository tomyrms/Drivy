# Décisions du porteur du 12 novembre 2026

| Sujet | Décision | Précise |
|---|---|---|
| Demandes en file et brouillons abandonnés (#106, L1) | **Garder et demander.** Une commande restée en file ou un brouillon abandonné n'est jamais supprimé ni renvoyé en silence. À la reprise, l'app la montre à la personne, qui choisit de l'envoyer ou de l'abandonner. Aucune durée d'expiration. | Contrat R2 (`reactivite-restes-contrat-20261104.md`, L1) : « ne pas inventer un TTL universel ». Remplace l'attente d'une décision de durée. |

Règles qui en découlent, vérifiées dans le code le 12 novembre 2026 (détail et écarts : `reactivite-restes-20261111.md` §3.2) :

- aucune suppression déclenchée par un délai ;
- aucun renvoi automatique d'une entrée reprise ou orpheline ;
- un écran montre l'entrée et propose deux gestes : l'envoyer (même clé, même corps) ou arrêter son suivi ;
- libellés français courts, sans sous-titre explicatif (AGENTS.md).

Un renvoi qui ne peut plus avoir de sens métier (créneau de leçon passé) reste retiré de l'écran : la personne vérifie le résultat ou arrête le suivi. C'est la seule restriction, elle ne dépend pas d'une durée de conservation.
