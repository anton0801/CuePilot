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
