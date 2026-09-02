import OndUI
import SwiftUI
import WidgetKit

/// The one complication: the app's mark on a watch face, and a tap that opens
/// önd. It states nothing, for the reason `OndActivityBundle` records about the
/// phone's home screen — a tile counting what you have not done is nagging.
struct LauncherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: LauncherProvider()) { _ in
            OpenRingMark()
                .fill(Theme.Accent.brand)
                // The system's own accessory ground, which is what makes the
                // slot read as filled on every face.
                .containerBackground(for: .widget) {
                    AccessoryWidgetBackground()
                }
                // A shape carries no label of its own, so without these the
                // complication announces nothing at all.
                .accessibilityElement()
                .accessibilityLabel("önd")
        }
        .configurationDisplayName("önd")
        .description("Opens önd.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
        // The system's content inset is there to hold text off a curved
        // bezel. This slot holds a drawing, and the mark already keeps the
        // icon's own margin — 85 percent of the square — so it draws to the
        // same edge its ground does.
        .contentMarginsDisabled()
    }

    /// WidgetKit writes this id into the face's own configuration, so changing
    /// it drops every complication already placed.
    private static let kind = "OndLauncher"
}

/// One entry, and no reason for a second: the mark reads the same at every
/// moment, so the timeline never asks to be rebuilt.
struct LauncherProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date = Date.now
    }

    func placeholder(in _: Context) -> Entry {
        Entry()
    }

    func getSnapshot(in _: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry()], policy: .never))
    }
}
