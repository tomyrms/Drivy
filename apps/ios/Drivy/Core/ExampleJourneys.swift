import Foundation

/// Exemples locaux demandés pour découvrir le replay. Aucun appel réseau, capteur ou service scolaire.
/// Géométries routées le 24.09.2026 avec OSRM sur OpenStreetMap, simplifiées à 6 m, puis échantillonnées ici.
/// © contributeurs OpenStreetMap, ODbL : https://www.openstreetmap.org/copyright
/// API de routage : https://project-osrm.org/docs/v5.24.0/api/#route-service
/// Repères de localités : https://api3.geo.admin.ch/rest/services/api/SearchServer (swisstopo).
/// Les horaires, vitesses implicites, observations et bilans sont entièrement fictifs.
enum ExampleJourneys {
    static let version = 1
    static let attributionURL = URL(string: "https://www.openstreetmap.org/copyright")
    private static let provenance = """
        Parcours fictif préparé pour découvrir le replay. Aucun trajet n’a été enregistré par le GPS d’un téléphone.

        Le tracé cartographique simplifié suit un itinéraire calculé sur la cartographie OpenStreetMap via OSRM le 24 septembre 2026. Les repères de localités proviennent de swisstopo. Les horaires, observations et bilans sont inventés ; ils ne décrivent ni une personne ni une leçon réellement réalisée. Ce tracé n’est pas un guide de navigation.

        © contributeurs OpenStreetMap — ODbL
        https://www.openstreetmap.org/copyright
        """

    static func make(now: Date = Date()) throws -> [DrivingSession] {
        [
            try journey(number: 1, title: "Cernier → Neuchâtel", encoded: outward,
                start: now.addingTimeInterval(-172_800), duration: 35 * 60,
                notes: [
                    Note(fraction: 0.06, theme: .observation, status: .positive,
                        text: "regard mobile au départ de Cernier, rétroviseurs relus avant de s’insérer."),
                    Note(fraction: 0.25, theme: .priority, status: .attention,
                        text: "ralentir à l’approche d’un carrefour et identifier la règle de priorité avant de s’engager."),
                    Note(fraction: 0.48, theme: .anticipation, status: .positive,
                        text: "adapter progressivement l’allure dans la descente vers Valangin, en gardant une marge confortable."),
                    Note(fraction: 0.76, theme: .signs, status: .toWorkOn,
                        text: "annoncer plus tôt la direction recherchée et relire la signalisation en arrivant en ville."),
                    Note(fraction: 0.97, theme: .parking, status: .toWorkOn,
                        text: "préparer une manœuvre de stationnement à faible allure, avec contrôles tout autour du véhicule.")
                ], summary: """
                    EXEMPLE FICTIF — Cernier → Neuchâtel, par Fontaines et Valangin.

                    Travail proposé : observation, anticipation dans la descente et arrivée en environnement urbain.
                    Constat inventé : les contrôles visuels sont réguliers ; la lecture de la signalisation et la préparation d’une manœuvre restent à travailler.
                    Prochaine étape fictive : reprendre calmement les choix de direction et les contrôles avant un stationnement.

                    Ce bilan local n’évalue personne. Il n’a pas été publié à un élève et n’entraîne aucune facturation.
                    """),
            try journey(number: 2, title: "Neuchâtel → Cernier · via Peseux", encoded: homeward,
                start: now.addingTimeInterval(-86_400), duration: 44 * 60,
                notes: [
                    Note(fraction: 0.08, theme: .signs, status: .positive,
                        text: "choisir sa direction assez tôt en quittant Neuchâtel, sans changer de voie au dernier instant."),
                    Note(fraction: 0.29, theme: .roundabout, status: .toWorkOn,
                        text: "préparer l’approche d’un giratoire, observer les véhicules engagés et signaler clairement sa sortie."),
                    Note(fraction: 0.51, theme: .observation, status: .attention,
                        text: "élargir le regard dans les virages et garder une marge face à une visibilité réduite."),
                    Note(fraction: 0.73, theme: .anticipation, status: .positive,
                        text: "anticiper les changements d’allure en remontant vers le Val-de-Ruz, sans freinage tardif."),
                    Note(fraction: 0.96, theme: .priority, status: .toWorkOn,
                        text: "à l’arrivée à Cernier, vérifier chaque intersection sans supposer que les règles du carrefour précédent se répètent.")
                ], summary: """
                    EXEMPLE FICTIF — Neuchâtel → Cernier, variante par Peseux, Valangin et Fontaines.

                    Travail proposé : choix de direction en ville, approche des giratoires et anticipation sur un itinéraire varié.
                    Constat inventé : l’allure est préparée suffisamment tôt ; l’observation dans les virages et l’identification des priorités demandent une nouvelle séance.
                    Prochaine étape fictive : verbaliser les indices utiles avant chaque intersection et préparer la sortie d’un giratoire.

                    Ce parcours est distinct du premier. Les annotations décrivent un scénario d’entraînement inventé, pas les règles d’un carrefour réel. Aucun élève ni moniteur n’est associé à ces données.
                    """)
        ]
    }

    private struct Coordinate { let latitude: Double; let longitude: Double }
    private struct Note {
        let fraction: Double
        let theme: ObservationTheme
        let status: ObservationStatus
        let text: String
    }
    private static func journey(number: Int, title: String, encoded: String, start: Date, duration: TimeInterval,
                                notes: [Note], summary: String) throws -> DrivingSession {
        let coordinates = try decode(encoded)
        let lengths = zip(coordinates, coordinates.dropFirst()).map { distance($0.0, $0.1) }
        let total = lengths.reduce(0, +)
        guard total > 0, total < 100_000, duration > 0 else { throw SessionError.invalidPoint }
        let segmentID = try identifier(journey: number, kind: 1)
        var points: [RecordedPoint] = []
        func append(_ coordinate: Coordinate, at offset: TimeInterval) throws {
            let date = start.addingTimeInterval(offset)
            points.append(RecordedPoint(id: try identifier(journey: number, kind: 2, index: points.count),
                timestamp: date, receivedAt: date, latitude: coordinate.latitude, longitude: coordinate.longitude,
                accuracy: -1, segmentID: segmentID))
        }
        try append(coordinates[0], at: 0)
        var travelled = 0.0
        for index in lengths.indices {
            let first = coordinates[index], last = coordinates[index + 1], length = lengths[index]
            // Interpolation réservée à EXAMPLE : préserver les sommets cartographiques et proposer
            // un curseur continu. Elle n'est jamais appliquée à des positions enregistrées.
            let count = max(1, Int(ceil(length / total * duration / 8)))
            for step in 1...count {
                let fraction = Double(step) / Double(count)
                let point = Coordinate(latitude: first.latitude + (last.latitude - first.latitude) * fraction,
                    longitude: first.longitude + (last.longitude - first.longitude) * fraction)
                try append(point, at: min(duration, (travelled + length * fraction) / total * duration))
            }
            travelled += length
        }
        var session = DrivingSession(id: try identifier(journey: number, kind: 0), startedAt: start,
            usesGPS: false, origin: .example, title: title, provenance: provenance)
        session.state = .completed; session.endedAt = start.addingTimeInterval(duration)
        session.points = points; session.summary = summary
        session.observations = try notes.enumerated().map { index, note in
            let point = points[min(points.count - 1, max(0, Int(Double(points.count - 1) * note.fraction)))]
            return LessonObservation(id: try identifier(journey: number, kind: 3, index: index), observedAt: point.timestamp,
                theme: note.theme, status: note.status, note: note.text, anchorPointID: point.id)
        }
        return session
    }
    private static func identifier(journey: Int, kind: Int, index: Int = 0) throws -> UUID {
        let value = String(format: "D71A%04X-%04X-4000-8000-%012llX", journey, kind, Int64(index))
        guard let id = UUID(uuidString: value) else { throw SessionError.invalidPoint }
        return id
    }
    private static func distance(_ first: Coordinate, _ second: Coordinate) -> Double {
        let factor = Double.pi / 180
        let latitude = (second.latitude - first.latitude) * factor
        let longitude = (second.longitude - first.longitude) * factor
        let a = pow(sin(latitude / 2), 2) + cos(first.latitude * factor) * cos(second.latitude * factor) * pow(sin(longitude / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
    private static func decode(_ polyline: String) throws -> [Coordinate] {
        let bytes = Array(polyline.utf8)
        var offset = 0, latitude = 0, longitude = 0
        var result: [Coordinate] = []
        func delta() throws -> Int {
            var value = 0, shift = 0
            while true {
                guard offset < bytes.count, (63...126).contains(bytes[offset]), shift < 55 else { throw SessionError.invalidPoint }
                let byte = Int(bytes[offset]) - 63; offset += 1
                value |= (byte & 0x1f) << shift; shift += 5
                if byte < 0x20 { return (value & 1) == 1 ? ~(value >> 1) : value >> 1 }
            }
        }
        while offset < bytes.count {
            latitude += try delta(); longitude += try delta()
            let coordinate = Coordinate(latitude: Double(latitude) / 1_000_000, longitude: Double(longitude) / 1_000_000)
            guard (46.8...47.2).contains(coordinate.latitude), (6.7...7.1).contains(coordinate.longitude), result.count < 5_000 else { throw SessionError.invalidPoint }
            if let last = result.last, distance(last, coordinate) < 0.01 { continue }
            result.append(coordinate)
        }
        guard result.count > 1 else { throw SessionError.invalidPoint }
        return result
    }

    // Cernier → Fontaines → Valangin → Neuchâtel. Géométrie OSRM polyline6, 11,75 km routés.
    private static let outward = #"kcjwxAyxgdLj~@kbAl\`sB~B|k@lFyDr|@zYvbHldAz~DAnEjHpEkHtoBuBjpAsZ`i@oAdRkLpY_a@n}@bXvz@xv@bb@viAj_@ko@w]yj@v]xj@k_@jo@g[k|@|n@snBd_@r\|VVdbAmfBl_@}^n\}NbxAmQjd@g[joAyrApiEk}Brc@ei@j{@{|Bt^_m@~|@g~@b`B}dAvJz@|hClaBfpAlpAhp@d[riBtPjmDuNzm@jJbgBll@lPpMfUlk@|XbZy@pLib@b|@{Fvh@jKvCkKwCxCs`@ta@cbAzf@rEt_@sHlp@`w@`\tPjZbx@~LzN`NdBh~@mOfu@sB`e@rJhYp[th@tqA~QtXvbBjfAxl@dRpw@hIbaBwMjaJ_kEdaFi|@zx@ac@biCeuBnnAya@lqAHbT}RdKoZhEscAsNagBuYykB{^_jAq\y}BcvBctGaaAmtBoYk|@weB_hJ"#
    // Retour par le nord de Peseux : itinéraire routé distinct, 19,85 km ; pas l'aller inversé.
    private static let homeward = #"uljsxA}e}eLwxEmpSsZwtBqF_eBjF{fBvOuoArrAceGrLa{An@a{@mT_iB}Zi_As[m\go@eLqL|KZ`Jdi@dJ`Xl\nG`[jEjwA`v@biA|Ize@R~p@tE~DvEoH}M}lAod@itAoL_Nw_@kP_BmPfFcT`YaAtT`^~Kts@~@dy@aLtkAyyArxFgUbtA_Jr_C|AheAvJljAt^pmBh{EjwSbvAv`Ifb@nuAnrA|mCpp@zpCbbAxxBvXzlBpi@lkBrY|aCu@z~AiLj_@aRhYyQlJ|Avq@qHxc@hLnwD~i@f|IlJ|bCqbAfQzEdn@gFt`@m@zq@gGp_@hAfwAiAgwAfGq_@l@{q@fFu`@{Een@pbAgQc{@i}O}C{sAbDkf@kZsO{Jch@Oaa@gN}Oys@pRge@cHeZfAe{@hi@mt@nAmaAp]snB~~Ai_BlUau@he@yu@|z@wd@vTq]xCcw@eE}s@vH{}Alm@aw@]inBt_@wl@Dg_@sM}SqVm`AeiBs[y[u[eIcpB`Fu_@aEcIkImKcc@kl@gTij@at@_L_ByXrHke@uFc`@`{@wI`t@}kB`cBigAdmCmJfd@wEzu@zKrpDiAfz@uMddAcZn}@qZjf@wd@dc@}xFb_E}jBrDif@u`@cdAcKw}Amw@kQcOgcA{|AocBowAs`AskAegB_kAsb@ei@kZmMkx@_De`Asn@ajAuZw\uSu`BplBc]kz@j_@ko@w]yj@v]xj@k_@jo@cb@wiAwz@yv@o}@cXqY~`@eRjLai@nAkpArZuoBtBuFsHkDrH{~D@aqHmiAo{@u_@w|@enBi\da@"#
}
