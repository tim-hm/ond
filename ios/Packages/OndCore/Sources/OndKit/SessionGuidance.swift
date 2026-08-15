/// How much the session says while it guides.
///
/// The dial a person turns down as a technique stops needing narration: full
/// keeps the instruction, the countdown, and the phase hints on screen;
/// essentials leaves the orb to carry the session. VoiceOver announcements do
/// not obey it — wanting less on screen is not the same as hearing nothing.
///
/// It used to carry a second exemption, for the caution under the breath
/// guide. There is no longer a caution there: every per-technique notice came
/// out at once, ahead of a different approach to them, so this dial now governs
/// the whole of what a session says.
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
