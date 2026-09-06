import Foundation
import os

/// Keeps account deletion effective for conversations saved by preview builds.
@MainActor
public final class LegacyAssistantData: PersonalStore {
    private let directory: URL
    private let defaults: UserDefaults
    private let logger = Logger(category: "chat-store")

    public init(directory: URL = .applicationSupportDirectory, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
    }

    public func erase() async {
        defaults.removeObject(forKey: "assistant.consent")
        defaults.removeObject(forKey: "assistant.consent.unreadable")
        for name in ["conversations.json", "conversations.json.unreadable"] {
            let url = directory.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger
                    .error(
                        "Failed to erase legacy conversations: \(error.localizedDescription, privacy: .public)"
                    )
            }
        }
    }
}
