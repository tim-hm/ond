import Foundation

/// How hard the phone taps.
///
/// Three steps rather than a slider: the useful range is narrow, the difference
/// between neighbouring percentages is not perceptible, and a person adjusting
/// this is answering "I can barely feel it" rather than dialling a number.
///
/// The scale and the boost are applied to values *authored* in
/// `HapticController`'s patterns, which is why `standard` is exactly identity —
/// today's feel is the reference the other two are named against, and a default
/// that quietly re-tuned every pattern would be a change nobody asked for.
///
public enum HapticStrength: String, Sendable, CaseIterable, Identifiable, Codable {
    case gentle
    case standard
    case strong

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .gentle: "Gentle"
        case .standard: "Standard"
        case .strong: "Strong"
        }
    }

    /// What an authored intensity is multiplied by.
    private var scale: Float {
        switch self {
        case .gentle: 0.6
        case .standard: 1
        case .strong: 1.4
        }
    }

    /// What is added to an authored sharpness.
    ///
    /// Carried alongside the scale because intensity alone cannot deliver
    /// "stronger": the patterns are authored up to 0.9, so scaling has barely a
    /// tenth of headroom before it clips. Sharpness is the other axis — it is
    /// what makes a tap read as a crisp knock rather than a soft push — and it
    /// is where most of `strong`'s extra actually comes from.
    private var edge: Float {
        switch self {
        case .gentle: -0.15
        case .standard: 0
        case .strong: 0.25
        }
    }

    /// `authored` at this strength, kept inside the 0...1 the engine accepts.
    ///
    /// Floored just above zero rather than at it: a scaled-down inhale that
    /// reached exactly zero would be a phase with no cue at all, which is not
    /// what "gentle" was asked for.
    public func intensity(_ authored: Float) -> Float {
        clamped(authored * scale, floor: 0.05)
    }

    /// `authored` at this strength, kept inside the 0...1 the engine accepts.
    public func sharpness(_ authored: Float) -> Float {
        clamped(authored + edge, floor: 0)
    }

    private func clamped(_ value: Float, floor: Float) -> Float {
        min(max(value, floor), 1)
    }
}
