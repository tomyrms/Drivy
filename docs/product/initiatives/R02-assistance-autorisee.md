# R02 — Accès d'assistance autorisé

[← Roadmap produit](../ROADMAP.md)

| Maturité | Horizon | Décision de développement |
| --- | --- | --- |
| À étudier | À définir | Non prise |

## L'idée

Permettre à une auto-école de demander de l'aide à l'équipe Drivy dans son propre contexte, sans donner à l'exploitant un accès permanent à ses informations.

L'école pourrait autoriser une intervention limitée afin de résoudre un problème. Cette idée nécessite un cadrage produit, juridique et de sécurité avant tout développement ou essai sur des données réelles.

## Parcours à explorer

Une demande explicite, une personne habilitée à l'approuver, un périmètre précis et une durée limitée. L'école doit pouvoir identifier l'intervention et révoquer son autorisation. Les actions de l'assistance doivent rester distinguables de celles de l'élève ou du personnel scolaire.

Un accès en lecture seule, avec certaines données masquées, constitue un point de départ à évaluer ; il n'est pas encore décidé.

## Questions à trancher

| Sujet | Question ouverte |
| --- | --- |
| Finalité | Quel problème justifie l'accès et quelles informations sont réellement nécessaires ? |
| Autorisation | Qui peut l'accorder pour l'école, pour quelle durée et avec quelle preuve ? |
| Données | Quelles catégories restent interdites, masquées ou accessibles seulement après accord complémentaire ? |
| Actions | Consultation uniquement, diagnostic, correction ou accompagnement de l'utilisateur ? |
| Traçabilité | Que voit l'école, qui consulte le journal et combien de temps est-il conservé ? |
| Révocation | Que se passe-t-il pour les sessions, les requêtes en cours et une connexion interrompue ? |
| Cadre applicable | Quelles responsabilités, informations aux personnes et dispositions contractuelles faut-il définir ? |

## Limites non négociables du cadrage

L'accord d'un administrateur scolaire ne constitue pas, à lui seul, une garantie juridique suffisante. Les obligations applicables devront être examinées sur le fonctionnement réellement retenu ; cette fiche ne vaut pas avis juridique ni preuve de conformité.

Pas de porte dérobée, d'usurpation invisible de session ou de contournement du chiffrement de bout en bout. Une opération de support ne doit pas être attribuée fictivement à un élève ou à un moniteur.

L'administration commerciale [R01](R01-administration-plateforme.md) doit pouvoir fonctionner sans cet accès aux données pédagogiques.

## Avant de créer une epic

Faire valider le besoin, la matrice d'accès, le parcours d'autorisation et de révocation, les responsabilités et les garanties de sécurité. Étudier la faisabilité avec des données synthétiques avant de définir les tickets techniques.

**Aucun mécanisme juridique, durée de conservation ou accès réel n'est décidé par cette fiche.**
