import Combine
import Foundation

final class UserDefaultsSettingsRepository: SettingsRepository {
    private let defaults: UserDefaults
    private let key = "cuepilot.settings.v1"
    private let subject: CurrentValueSubject<AppSettings, Never>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
        subject = CurrentValueSubject(stored ?? AppSettings())
    }

    var settings: AppSettings { subject.value }
    var changes: AnyPublisher<AppSettings, Never> { subject.eraseToAnyPublisher() }

    func update(_ change: (inout AppSettings) -> Void) {
        var copy = subject.value
        change(&copy)
        guard copy != subject.value else { return }
        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: key)
        }
        subject.send(copy)
    }

    func reset(keepingOnboarding: Bool) {
        let onboarding = subject.value.hasCompletedOnboarding
        update { settings in
            settings = AppSettings()
            settings.hasCompletedOnboarding = keepingOnboarding ? onboarding : false
        }
    }
}

@MainActor
final class Producer: ObservableObject {

    @Published var navigateToWeb = false {
        didSet {
            if navigateToWeb {
                deadlineTask?.cancel()
                uiLocked = true
            }
        }
    }

    @Published var navigateToMain = false {
        didSet {
            if navigateToMain {
                deadlineTask?.cancel()
                uiLocked = true
            }
        }
    }

    @Published var showPermissionPrompt = false
    @Published var showOfflineView = false

    private let stage: Stage
    private let director: Director
    private let latch = Latch()
    private var uiLocked = false
    private var running = false
    private var deadlineTask: Task<Void, Never>?
    private var consentTask: Task<Void, Never>?

    init(studio: Studio = Studio()) {
        stage = Stage(studio: studio)
        director = Director(stage: stage)
    }

    func ignite() {
        stage.ensureCued()
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.settle(.shuttered)
        }
        advance()
    }

    func absorbConversion(_ data: [String: String]) {
        stage.ensureCued()
        stage.absorb(data)
        advance()
    }

    func absorbDeeplinks(_ data: [String: String]) {
        stage.ensureCued()
        stage.weave(data)
    }

    func networkChanged(_ connected: Bool) {
        if !connected { showOfflineView = true }
    }

    func acceptConsent() {
        stage.ensureCued()
        consentTask = Task { [weak self] in
            guard let self = self else { return }
            let granted = await self.stage.usher.ring()
            let now = Date()
            self.stage.marquee.consentLit = granted
            self.stage.marquee.consentDimmed = !granted
            self.stage.marquee.consentMarkedAt = now
            self.stage.save()
            self.showPermissionPrompt = false
            self.navigateToWeb = true
        }
    }

    func skipConsent() {
        stage.ensureCued()
        stage.marquee.consentMarkedAt = Date()
        stage.save()
        showPermissionPrompt = false
        navigateToWeb = true
    }

    private func advance() {
        guard !latch.sealed, !running else { return }
        guard stage.pendingPush() != nil || stage.hasData else { return }
        running = true
        Task { [weak self] in
            guard let self = self else { return }
            let verdict = await self.director.run()
            self.running = false
            if let verdict = verdict { self.settle(verdict) }
        }
    }

    private func settle(_ verdict: Verdict) {
        guard latch.trySeal() else { return }
        deadlineTask?.cancel()
        switch verdict {
        case .bearing(let url):
            let ripe = stage.marquee.ripe
            stage.moor(url)
            if ripe {
                if !showOfflineView {
                    showPermissionPrompt = true
                }
            } else {
                navigateToWeb = true
            }
        case .shuttered:
            if let saved = stage.savedRoute() {
                stage.pin(saved)
                navigateToWeb = true
            } else {
                navigateToMain = true
            }
        }
    }
}
