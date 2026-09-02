import Foundation

/// User-adjustable widget settings, persisted to ~/.zcode/widget-settings.json.
final class WidgetSettingsStore: ObservableObject {
    @Published var dailyBudget: Int = 0  // 0 = disabled
    @Published var pinnedProjectDirs: [String] = []

    /// Default: user-visible file next to prompts.json. Overridable for tests.
    static var settingsPath = NSHomeDirectory() + "/.zcode/widget-settings.json"

    private var fileURL: URL { URL(fileURLWithPath: Self.settingsPath) }

    func load() {
        guard FileManager.default.fileExists(atPath: Self.settingsPath) else { return }
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        dailyBudget = obj["dailyBudget"] as? Int ?? 0
        pinnedProjectDirs = obj["pinnedProjectDirs"] as? [String] ?? []
    }

    func save() {
        // Merge with whatever is on disk so independent store instances (the
        // settings sheet vs the Database tab) don't clobber each other's keys.
        var obj: [String: Any] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = existing
        }
        obj["dailyBudget"] = dailyBudget
        obj["pinnedProjectDirs"] = pinnedProjectDirs
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
