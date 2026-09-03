import SwiftUI
import WidgetKit

/// The watch extension's entry point. No `Theme.Typeface.register()`, unlike
/// the phone's `OndActivityBundle`: this extension draws a shape and no text,
/// so it needs no font.
@main
struct OndWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        LauncherComplication()
    }
}
