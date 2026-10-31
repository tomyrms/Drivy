/// La confirmation décrit l’intention, jamais un constat déjà accepté par l’école.
enum SchoolLessonCompletionMessage {
    static let withTrip = "Le trajet s’arrêtera. Son envoi pourra continuer pendant la préparation du bilan, après confirmation de la fin de leçon par l’école."
    static let withoutTrip = "La fin de leçon sera envoyée à l’école. Après sa confirmation, tu pourras préparer le bilan."
    static let stopOnly = "Le trajet s’arrêtera. Son envoi pourra continuer en arrière-plan ; tu pourras terminer la leçon depuis sa fiche."
}
