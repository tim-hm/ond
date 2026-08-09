import OndKit
import SwiftUI

extension Appearance {
    /// What `preferredColorScheme` takes: an override, or nil to follow the
    /// system. Mapped here rather than in OndKit so the domain package
    /// stays free of SwiftUI, and here rather than in `OndStyle` because
    /// this scene is the only reader and the mapping touches no palette.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
