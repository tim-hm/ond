/// Which colour scheme the app draws in. `system` is the absence of an
/// opinion. Every palette token carries a light and a dark value (M3), so
/// this is one override at the root of the view tree — never a per-view
/// branch.
public enum Appearance: String, Sendable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .system: "Match the system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
