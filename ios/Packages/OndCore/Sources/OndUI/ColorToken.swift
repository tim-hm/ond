import SwiftUI

/// Every colour the design system ships, under the name it is filed as in
/// `Colors.xcassets`. One list because `Color(_:bundle:)` has no failing form:
/// a name that no longer matches an asset paints black at runtime and says
/// nothing. `ThemeColorTests` walks these cases against the catalogue on disk.
enum ColorToken: String, CaseIterable {
    case surfaceGround = "Surface/Ground"
    case surfaceRaised = "Surface/Raised"
    case surfaceRaisedAlt = "Surface/RaisedAlt"
    case surfaceLit = "Surface/Lit"
    case surfaceLine = "Surface/Line"

    case inkPrimary = "Ink/Primary"
    case inkSecondary = "Ink/Secondary"
    case inkTertiary = "Ink/Tertiary"

    case actionBrandLabel = "Action/BrandLabel"

    case accentBrand = "Accent/Brand"
    case accentBrandText = "Accent/BrandText"
    case accentSettle = "Accent/Settle"
    case accentNight = "Accent/Night"
    case accentNightText = "Accent/NightText"
    case accentSpark = "Accent/Spark"
    case accentRestore = "Accent/Restore"
    case accentAttend = "Accent/Attend"
    case accentCaution = "Accent/Caution"
    case accentPlay = "Accent/Play"

    case breathInhale = "Breath/Inhale"
    case breathHold = "Breath/Hold"
    case breathExhale = "Breath/Exhale"

    var color: Color {
        Color(rawValue, bundle: .module)
    }
}
