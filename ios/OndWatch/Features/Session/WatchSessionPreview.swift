#if DEBUG
    import OndKit
    import SwiftUI

    enum WatchSessionPreview {
        static var slug: String? {
            argument(after: "--preview-session")
        }

        static var textSize: DynamicTypeSize? {
            switch argument(after: "--preview-text") {
            case "large": .xxxLarge
            case "accessibility": .accessibility2
            default: nil
            }
        }

        private static func argument(after flag: String) -> String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            return arguments.dropFirst(index + 1).first
        }

        struct Recorder: SessionRecording {
            func record(_: SessionRecord) async {}
            func recordedSessions() async -> [SessionRecord] {
                []
            }

            func remove(_: SessionRecord.ID) async {}
            func merge(_: [SessionRecord]) async -> Bool {
                false
            }
        }
    }
#endif
