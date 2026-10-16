import Foundation
import IlluminateCore
import os

/// Persists `Preferences` as one JSON blob, so a write is atomic.
struct PreferencesStore {
    private let defaults: UserDefaults
    private let key = "preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Preferences {
        guard let data = defaults.data(forKey: key) else { return Preferences() }
        do {
            return try JSONDecoder().decode(Preferences.self, from: data)
        } catch {
            Log.app.error("Discarding unreadable preferences: \(error.localizedDescription, privacy: .public)")
            return Preferences()
        }
    }

    func save(_ preferences: Preferences) {
        do {
            defaults.set(try JSONEncoder().encode(preferences), forKey: key)
        } catch {
            Log.app.error("Could not save preferences: \(error.localizedDescription, privacy: .public)")
        }
    }
}
