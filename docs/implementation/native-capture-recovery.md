# Retrouver une capture et relire son trajet

L’école propose une liste des trajets scolaires arrêtés ou interrompus présents dans le journal de cet appareil. Avant de présenter une ligne, AP155 vérifie l’accès à cette capture ; un ancien lien de formation ne suffit pas. Une capture devenue introuvable est retirée de la liste sans révoquer une autre leçon. Fermer la liste ne ferme pas la séance GPS courante.

Les commandes d’envoi reprennent les octets déjà conservés. Une finalisation incertaine conserve son UUID, son manifeste et son choix de clôture partielle ; l’écran indique le choix qui sera repris. Les refus explicites `VERSION_CONFLICT` et `CAPTURE_INCOMPLETE` d’AP158 sont archivés comme refus, sans modifier leur corps et sans annoncer un accusé. Un nouveau clic peut alors créer une nouvelle intention après relecture ; aucune erreur réseau ou réponse inconnue ne permet cette correction automatique.

La confirmation d’AP158, conservée dans le coffre, prouve la finalisation. `PARTIAL` ne suffit pas : une coupure serveur peut déjà produire cet état avant AP158. Le parcours garde donc les actions nécessaires dans ce cas et n’annonce pas une clôture fictive.

`SchoolCaptureReplayWorkspace` lit AP155 puis AP160 sous la même portée. Les pages sont assemblées progressivement ; une erreur réseau laisse clairement le chargement incomplet. Une révocation, une reconstruction modifiée ou un contenu invalide retire les données affichées. Seuls deux fragments contigus, explicitement signalés comme continuation et vérifiés par leurs séquences, sont joints. Plusieurs fragments d’un même segment après un lot manquant restent séparés. Aucun point personnel ou exemple n’est converti en point scolaire.

Relecture indépendante ciblée : trois défauts de reprise corrigés (PARTIAL confondu avec finalisation, accès local insuffisant après changement d’affectation, refus AP158 bloquant une correction). Compilation Apple groupée à effectuer ; récupération après fermeture forcée, réseau interrompu et usage physique restent à qualifier.
