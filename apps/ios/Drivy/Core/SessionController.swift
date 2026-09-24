import Foundation
import Observation

@MainActor
@Observable
final class SessionController {
    private(set) var sessions: [DrivingSession] = []
    private(set) var activeSession: DrivingSession?
    private(set) var selectedSession: DrivingSession?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var isCapturing = false
    private(set) var errorMessage: String?
    private(set) var gpsStatus: GPSStatus = .inactive
    private(set) var storageStatus = "Vérification du stockage chiffré…"

    @ObservationIgnored private var store: (any SessionStore)?
    @ObservationIgnored private let location: any LocationSource
    @ObservationIgnored private var writeTail: Task<Void, Never>?
    @ObservationIgnored private var observationTasks: [UUID: Task<Bool, Never>] = [:]
    @ObservationIgnored private var admission: LocationAdmission?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var nativeSourceRunning = false
    @ObservationIgnored private var persistenceFailed = false
    @ObservationIgnored private var captureStart: ContinuousClock.Instant?
    @ObservationIgnored private var captureDate: Date?
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPoints = 0

    init(store: (any SessionStore)? = nil, location: (any LocationSource)? = nil) {
        self.store = store
        self.location = location ?? NativeLocationSource()
        self.location.onEvent = { [weak self] event in self?.receive(event) }
    }

    func load() async {
        guard !isBusy, !isCapturing else { return }
        isBusy = true
        isLoading = true
        defer { isBusy = false; isLoading = false }
        await writeTail?.value
        do {
            if store == nil {
                store = try await Task.detached(priority: .userInitiated) {
                    try SQLCipherSessionStore.openDefault()
                }.value
            }
            guard let store else { throw SessionError.storageUnavailable }
            try await store.recoverInterruptedSessions()
            sessions = try await store.sessions()
            activeSession = nil
            persistenceFailed = false
            storageStatus = "Enregistré sur cet appareil · stockage chiffré"
            errorMessage = nil
            if let id = selectedSession?.id { selectedSession = sessions.first { $0.id == id } }
        } catch { report(error) }
    }

    func startSession(useGPS: Bool) async {
        guard !isBusy, activeSession == nil, let store, !persistenceFailed else { return }
        isBusy = true
        defer { isBusy = false }
        let session = DrivingSession(usesGPS: useGPS)
        do {
            try await store.create(session)
            activeSession = session
            selectedSession = nil
            sessions.insert(session, at: 0)
            generation = UUID()
            isCapturing = true
            errorMessage = nil
            admission = LocationAdmission(startedAt: session.startedAt)
            captureStart = .now
            captureDate = Date()
            gpsStatus = useGPS ? .waitingForPosition : .inactive
            if useGPS {
                switch location.permission {
                case .allowed: beginNativeSource()
                case .notDetermined:
                    gpsStatus = .requestingPermission
                    location.requestPermission()
                case .denied: gpsStatus = .denied
                }
            }
            startDurationLimit()
        } catch { report(error) }
    }

    // Barrière synchrone : aucune nouvelle mesure ou observation après cet appel.
    // Les écritures déjà admises terminent dans la file sérialisée avant le scellement.
    func stopSession() { finishSession(state: .completed) }

    func beginObservation() -> ObservationContext? {
        guard isCapturing, !persistenceFailed, let session = activeSession else { return nil }
        let now = Date()
        let anchor = session.points.last.flatMap { point -> UUID? in
            let age = now.timeIntervalSince(point.timestamp)
            return (0...15).contains(age) ? point.id : nil
        }
        return ObservationContext(id: UUID(), sessionID: session.id, observedAt: now, anchorPointID: anchor)
    }

    @discardableResult
    func addObservation(theme: ObservationTheme, status: ObservationStatus, note: String,
                        context: ObservationContext) async -> Bool {
        if let task = observationTasks[context.id] { return await task.value }
        guard isCapturing, !persistenceFailed, let store, activeSession?.id == context.sessionID else {
            errorMessage = SessionError.sessionClosed.localizedDescription
            return false
        }
        guard note.count <= 1_000 else { errorMessage = SessionError.invalidObservation.localizedDescription; return false }
        let observation = LessonObservation(id: context.id, observedAt: context.observedAt,
            theme: theme, status: status, note: note, anchorPointID: context.anchorPointID)
        let previous = writeTail
        let task = Task { @MainActor [weak self] () -> Bool in
            await previous?.value
            guard let self, !self.persistenceFailed else { return false }
            do {
                try await store.append(observation, to: context.sessionID)
                self.updateSession(context.sessionID) { session in
                    if !session.observations.contains(where: { $0.id == observation.id }) {
                        session.observations.append(observation)
                    }
                }
                return true
            } catch { self.storageFailed(error); return false }
        }
        observationTasks[context.id] = task
        writeTail = Task { _ = await task.value }
        return await task.value
    }

    @discardableResult
    func updateSummary(_ text: String, for sessionID: UUID) async -> Bool {
        guard let store, !persistenceFailed else { return false }
        guard text.count <= 10_000 else { errorMessage = "Le bilan est limité à 10 000 caractères."; return false }
        let previous = writeTail
        let task = Task { @MainActor [weak self] () -> Bool in
            await previous?.value
            guard let self, !self.persistenceFailed else { return false }
            do {
                try await store.updateSummary(text, for: sessionID)
                self.updateSession(sessionID) { $0.summary = text }
                return true
            } catch { self.storageFailed(error); return false }
        }
        writeTail = Task { _ = await task.value }
        return await task.value
    }

    func selectSession(_ id: UUID) async {
        guard let store else { return }
        do { selectedSession = try await store.session(id: id) }
        catch { report(error) }
    }

    @discardableResult
    func deleteSession(_ sessionID: UUID) async -> Bool {
        guard let store, !isBusy, activeSession?.id != sessionID else {
            errorMessage = SessionError.sessionStillActive.localizedDescription
            return false
        }
        isBusy = true
        defer { isBusy = false }
        await writeTail?.value
        do {
            try await store.deleteSession(sessionID)
            sessions.removeAll { $0.id == sessionID }
            if selectedSession?.id == sessionID { selectedSession = nil }
            return true
        } catch { report(error); return false }
    }

    func dismissError() { errorMessage = nil }

    // Les tests de concurrence attendent ainsi toutes les écritures admises.
    func awaitPendingWrites() async { await writeTail?.value }

    private func beginNativeSource() {
        guard isCapturing, activeSession?.usesGPS == true, !nativeSourceRunning else { return }
        nativeSourceRunning = true
        gpsStatus = .waitingForPosition
        location.start()
    }

    private func receive(_ event: LocationEvent) {
        guard isCapturing, !persistenceFailed, let session = activeSession, session.usesGPS else { return }
        switch event {
        case .permission(let permission):
            switch permission {
            case .allowed:
                // Seule la demande initiale attend cette autorisation. Une permission
                // rétablie après refus ne relance jamais silencieusement la capture.
                if gpsStatus == .requestingPermission { beginNativeSource() }
            case .notDetermined: gpsStatus = .requestingPermission
            case .denied:
                nativeSourceRunning = false
                location.stop()
                admission?.interrupt()
                gpsStatus = .denied
            }
        case .unavailable:
            admission?.interrupt()
            gpsStatus = .interrupted
        case .samples(let samples):
            guard nativeSourceRunning, clockIsValid() else { return }
            let receivedAt = Date()
            for sample in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
                guard isCapturing else { break }
                guard let point = admission?.admit(sample, receivedAt: receivedAt) else { continue }
                enqueue(point, sessionID: session.id)
            }
        }
    }

    private func enqueue(_ point: RecordedPoint, sessionID: UUID) {
        guard isCapturing, let store else { return }
        guard pendingPoints < 256 else {
            finishSession(state: .interrupted)
            errorMessage = "La sauvegarde ne suit plus le GPS. La capture est arrêtée ; les points déjà admis sont conservés."
            return
        }
        pendingPoints += 1
        let previous = writeTail
        let admittedGeneration = generation
        writeTail = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            defer { self.pendingPoints -= 1 }
            guard !self.persistenceFailed else { return }
            do {
                try await store.append(point, to: sessionID)
                self.updateSession(sessionID) { $0.points.append(point) }
                if self.generation == admittedGeneration, self.isCapturing { self.gpsStatus = .recording }
            } catch { self.storageFailed(error) }
        }
    }

    private func finishSession(state: SessionState) {
        guard isCapturing, let session = activeSession, let store else { return }
        isCapturing = false
        nativeSourceRunning = false
        generation = UUID()
        location.stop()
        limitTask?.cancel()
        limitTask = nil
        gpsStatus = state == .interrupted && session.usesGPS ? .interrupted : .inactive
        let stoppedAt = Date()
        isBusy = true
        let previous = writeTail
        writeTail = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            defer { self.isBusy = false }
            guard !self.persistenceFailed else { return }
            do {
                try await store.finish(session.id, at: stoppedAt, state: state)
                let saved = try await store.session(id: session.id)
                self.updateSession(session.id) { $0 = saved }
                self.selectedSession = saved
                self.activeSession = nil
                self.observationTasks.removeAll()
            } catch { self.storageFailed(error) }
        }
    }

    private func updateSession(_ id: UUID, change: (inout DrivingSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        change(&session)
        sessions[index] = session
        if activeSession?.id == id { activeSession = session }
        if selectedSession?.id == id { selectedSession = session }
    }

    private func storageFailed(_ error: Error) {
        isCapturing = false
        nativeSourceRunning = false
        generation = UUID()
        location.stop()
        limitTask?.cancel()
        limitTask = nil
        persistenceFailed = true
        gpsStatus = .interrupted
        storageStatus = "Sauvegarde interrompue · données déjà écrites conservées"
        report(error)
    }

    private func report(_ error: Error) {
        errorMessage = (error as? SessionError ?? .storageUnavailable).localizedDescription
    }

    private func clockIsValid() -> Bool {
        guard let captureStart, let captureDate else { return false }
        let elapsed = captureStart.duration(to: .now)
        let components = elapsed.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        guard seconds < 7_200, abs(Date().timeIntervalSince(captureDate) - seconds) < 5 else {
            finishSession(state: .interrupted)
            errorMessage = seconds >= 7_200
                ? "La séance d’essai a atteint sa limite de deux heures. Les données sont conservées."
                : "L’horloge a changé. La capture est arrêtée pour conserver des repères temporels fiables."
            return false
        }
        return true
    }

    private func startDurationLimit() {
        let currentGeneration = generation
        limitTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.generation == currentGeneration, self.isCapturing else { return }
                guard self.clockIsValid() else { return }
            }
        }
    }
}
