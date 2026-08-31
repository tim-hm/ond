/// How much the session says while it guides: full keeps the instruction, the
/// countdown, and the phase hints on screen; essentials leaves the orb to
/// carry the session. VoiceOver announcements do not obey it — wanting less
/// on screen is not the same as hearing nothing.
public enum SessionGuidance: String, Sendable, CaseIterable, Identifiable {
    case full
    case essentials

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .full: "Full guidance"
        case .essentials: "Just the visuals"
        }
    }
}
