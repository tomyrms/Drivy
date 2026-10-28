# Lot 4 de l'audit UX : Mon profil (#155 à #158)

27 octobre 2026, branche `claude/audit-ux-lots-2-4`, après le lot 3. Code iOS seulement, contrats existants (`PUT /v1/me/profile/photo`, `PATCH /v1/me/profile`) : rien à déployer.

## Ce qui change

| Ticket | Avant | Après |
|---|---|---|
| #155 A26 | Photo envoyée à part, mais son échec s'affichait en tête avec ceux des textes ; « Quitter sans enregistrer » laissait croire qu'une photo envoyée serait annulée. | Le résultat de la photo (« Photo enregistrée. », « Photo retirée. » ou l'erreur) s'affiche sous la photo. Si une photo a été enregistrée pendant l'ouverture, l'alerte de sortie dit : « Ta photo est déjà enregistrée. Seuls les autres changements seront perdus. » Aucune transaction commune n'est prétendue. |
| #156 A27 | Recadrage carré centré automatique, envoi dès le choix. | Feuille « Cadrer la photo » : pincer ou curseur de zoom (1 à 4), glisser, cercle de l'avatar sur un voile. Rien n'est envoyé avant « Utiliser » ; « Annuler » garde la photo actuelle. L'original est redressé et réduit par ImageIO (2048 px au plus, orientation EXIF appliquée) au lieu d'être décodé en entier ; seul le carré choisi est réencodé en JPEG de 512 px et 250 ko au plus, sans métadonnées, en mémoire seulement. |
| #157 A28 | Trois champs prénom, nom, nom affiché sans explication. | Aperçu à côté de la photo : le nom affiché saisi, tel que les membres le voient. Bouton d'information sur « Nom affiché » (pas de note permanente, conformément à la règle « peu de texte ») : « Le nom que voient les membres de ton école, dans les listes et Messages. Ton prénom et ton nom ne changent pas. » |
| #158 A29 | Champ « E-mail » qui écrit `contactEmail`. | « E-mail de contact », aussi dans le formulaire du dossier ; bouton d'information « L'adresse où ton école peut t'écrire. L'adresse de connexion ne change pas. » ; message de format aligné. Aucun accès à la gestion de l'identité ajouté. |

`DrivyFormField` accepte désormais `info:` : un bouton d'information de 44 pt qui ouvre un popover, sans agrandir la ligne du libellé.

## Vérification

- Compilation par l'IPA d'essai ; aucun test lancé avant l'essai du porteur.
- Nouveau test métier `SchoolProfilePhotoCropTests` (calcul du carré, bornes du déplacement et du zoom, aperçu réduit, JPEG final) : à exécuter avec les tests ciblés.
- À vérifier à l'œil sur appareil : photo portrait, paysage et prise de côté (orientation), grande photo, pincement et curseur, annuler, échec réseau de l'envoi ; popovers d'information sur iPhone et iPad ; VoiceOver sur le curseur de zoom.
