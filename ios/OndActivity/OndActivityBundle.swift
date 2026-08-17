import OndUI
import SwiftUI
import WidgetKit

/// The widget extension's entry point.
///
/// One widget in it, and no home-screen widget: what this extension exists for
/// is a session that is already running, and a tile that said "you have not
/// breathed today" would be the app nagging from the home screen — which is a
/// product decision nobody has made.
@main
struct OndActivityBundle: WidgetBundle {
    init() {
        // The extension is its own process, so the app's registration does
        // nothing for it — and it draws the phase word too.
        Theme.Typeface.register()
    }

    var body: some Widget {
        SessionActivityWidget()
    }
}
