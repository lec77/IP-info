import Foundation
import ExitIPCore

/// The single owner of the few things that must survive a relaunch. Values are
/// held in memory and written through to UserDefaults when they change.
@MainActor
final class SettingsStore {
    private enum Key {
        static let notificationsEnabled = "notificationsEnabled"
        static let expectedCountryCode = "expectedCountryCode"
        static let homeExit = "homeExit"
        static let history = "history"
        static let pollInterval = "pollInterval"
    }

    private let defaults: UserDefaults

    var notificationsEnabled: Bool {
        didSet { if notificationsEnabled != oldValue { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    }
    var expectedCountryCode: String? {
        didSet { if expectedCountryCode != oldValue { defaults.set(expectedCountryCode, forKey: Key.expectedCountryCode) } }
    }
    var homeExit: IPInfo? {
        didSet { if homeExit != oldValue { defaults.set(Self.encode(homeExit), forKey: Key.homeExit) } }
    }
    var history: [IPChangeEvent] {
        didSet { if history != oldValue { defaults.set(Self.encode(history), forKey: Key.history) } }
    }
    var pollInterval: TimeInterval {
        didSet { if pollInterval != oldValue { defaults.set(pollInterval, forKey: Key.pollInterval) } }
    }

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [Key.notificationsEnabled: Config.notificationsEnabledByDefault])
        self.defaults = defaults
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        expectedCountryCode = defaults.string(forKey: Key.expectedCountryCode)
        homeExit = Self.decode(defaults.data(forKey: Key.homeExit))
        history = Self.decode(defaults.data(forKey: Key.history)) ?? []
        pollInterval = validPollInterval(defaults.object(forKey: Key.pollInterval) as? TimeInterval)
    }

    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T?) -> Data? {
        value.flatMap { try? JSONEncoder().encode($0) }
    }
}
