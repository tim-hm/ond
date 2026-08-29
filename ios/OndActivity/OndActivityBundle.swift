import OndUI
import SwiftUI
import WidgetKit

/// The widget extension's entry point. One widget and deliberately no
/// home-screen widget: a tile that said "you have not breathed today" would
/// be the app nagging, a product decision nobody has made.
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
