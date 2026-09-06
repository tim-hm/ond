import Foundation
@testable import OndKit
import Testing

@MainActor
struct LegacyAssistantDataTests {
    @Test("Account erasure removes preview chats and consent while preserving other files")
    func erasesPreviewData() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "assistant.consent")
        defaults.set(Data("preview".utf8), forKey: "assistant.consent.unreadable")
        for name in ["conversations.json", "conversations.json.unreadable", "sessions.json"] {
            try Data("preview".utf8).write(to: directory.appending(path: name))
        }

        await LegacyAssistantData(directory: directory, defaults: defaults).erase()

        #expect(defaults.object(forKey: "assistant.consent") == nil)
        #expect(defaults.object(forKey: "assistant.consent.unreadable") == nil)
        #expect(!FileManager.default
            .fileExists(atPath: directory.appending(path: "conversations.json").path()))
        #expect(!FileManager.default
            .fileExists(atPath: directory.appending(path: "conversations.json.unreadable").path()))
        #expect(FileManager.default
            .fileExists(atPath: directory.appending(path: "sessions.json").path()))
    }
}
