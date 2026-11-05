import Foundation

extension SchoolCommandKind {
    /// Ce que la demande faisait, nommé comme l’action d’où elle est partie.
    var requestTitle: String {
        switch self {
        case .updateSchool: "Modification de l’école"
        case .saveSetup: "Configuration de l’école"
        case .activate: "Activation de l’école"
        case .saveDataPolicy: "Politique de données"
        case .createInvitation: "Invitation"
        case .resendInvitation: "Renvoi d’une invitation"
        case .revokeInvitation: "Retrait d’une invitation"
        case .createProfilePolicy, .publishProfilePolicy: "Champs du profil"
        case .updateProfile: "Modification d’un profil"
        case .saveOnboarding, .completeOnboarding: "Accueil dans l’école"
        case .createOffering: "Offre de formation"
        case .createCurriculum: "Référentiel"
        case .createCatalogPolicy: "Procédure de l’école"
        case .createTraining: "Nouvelle formation"
        case .createAssignment: "Affectation d’un moniteur"
        case .updateMember: "Modification d’un membre"
        case .createLesson: "Nouvelle leçon"
        case .moveLesson: "Déplacement d’une leçon"
        case .cancelLesson: "Annulation d’une leçon"
        case .createCommercialTerms: "Conditions commerciales"
        case .createServiceProduct: "Tarif"
        case .createAvailabilityRule, .updateAvailabilityRule, .removeAvailabilityRule: "Horaires d’ouverture"
        case .createClosure, .removeClosure: "Fermeture"
        case .savePreparation: "Objectifs de la leçon"
        case .saveWish: "Souhait de l’élève"
        case .completeLesson: "Fin de la leçon"
        case .saveReportDraft: "Bilan de la leçon"
        case .publishReportDraft: "Publication du bilan"
        case .updateLessonSharing: "Partage avec l’élève"
        case .createObservation, .updateObservation, .removeObservation: "Observation"
        case .recordPermitCheck: "Permis d’élève vu"
        case .markNoShow: "Élève absent"
        case .startLessonNow: "Leçon sans rendez-vous"
        case .startLesson: "Début de la leçon"
        case .savePlanningDefaults: "Préférences de planification"
        case .createExam: "Nouvel examen"
        case .updateExam: "Date d’un examen"
        case .postponeExam: "Report d’un examen"
        case .setExamResult: "Résultat d’un examen"
        case .courseSheetIntent: "Appel, règlement ou validation d’un cours"
        case .courseLearnerIntent: "Inscription à un cours"
        case .courseEditorIntent: "Cours collectif en préparation"
        }
    }
}

extension SchoolCommandKind {
    /// Ce que la demande conservée est en train de faire, avant toute preuve de l’école.
    /// Jamais « Réservé », « Annulé » ni « Envoyé » : ces mots attendent la confirmation.
    var inProgressTitle: String? {
        switch self {
        case .createLesson: "Planification en cours"
        case .moveLesson: "Déplacement en cours"
        case .cancelLesson: "Annulation en cours"
        case .createInvitation: "Création en cours"
        case .resendInvitation: "Renvoi en cours"
        case .revokeInvitation: "Révocation en cours"
        default: nil
        }
    }
}

extension PendingSchoolCommand {
    /// Début demandé par une création ou un déplacement de leçon ; nil pour toute autre demande.
    var requestedLessonStart: Date? {
        guard kind == .createLesson || kind == .moveLesson,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let value = object["plannedStart"] as? String else { return nil }
        return SchoolLesson.date(value)
    }

    /// Une réservation dont l’horaire est passé — ou dont le début n’est plus lisible — ne se renvoie plus : l’école
    /// la refuserait, et rien ne doit la rejouer à l’insu de la personne. Elle reste à vérifier, puis à abandonner si
    /// l’école ne la connaît pas. Les autres commandes gardent leur propre contrat.
    func isStaleLessonRequest(at now: Date = Date()) -> Bool {
        !SchoolPlanningRecoveryPolicy.permitsWrite(self, at: now)
    }

    /// Dit quelle demande attend, depuis quand, et ce que l’école en sait après une vérification.
    /// `absent` : l’école a répondu qu’elle n’a aucune trace de cette opération.
    func waitingMessage(absent: Bool) -> String {
        let moment = createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "fr_CH")))
        return absent
            ? "L’école n’a pas enregistré « \(kind.requestTitle) » (\(moment))."
            : "« \(kind.requestTitle) » (\(moment)) : la réponse de l’école n’est pas arrivée. Vérifie si elle a été enregistrée."
    }
}
