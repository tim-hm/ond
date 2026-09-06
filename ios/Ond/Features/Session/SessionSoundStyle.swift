enum SessionSoundStyle: String, CaseIterable, Identifiable, Sendable {
    case current, rounded

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .current: "Current"
        case .rounded: "Rounded preview"
        }
    }
}
