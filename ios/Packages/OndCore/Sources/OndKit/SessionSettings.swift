import Foundation
import Observation

/// Which cues accompany the animation.
///
/// Haptics and audio are separable because the situations differ: a phone face
/// down in a pocket needs the taps and nothing else, a quiet office needs
/// neither, and both need the same session underneath.
public enum SessionCueMode: String, Sendable, CaseIterable, Identifiable {
    case hapticsAndAudio
    case haptics
    case visualOnly

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .hapticsAndAudio: "Haptics & sound"
        case .haptics: "Haptics only"
        case .visualOnly: "Visual only"
        }
    }

    public var playsHaptics: Bool {
        self != .visualOnly
    }

    public var playsAudio: Bool {
        self == .hapticsAndAudio
    }
}

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
/// The wrist shares the selector but none of the arithmetic: `WKHapticType` has
/// no intensity at all, so `WatchHapticStyle` renders each strength as tick
/// density and tap choice instead of scaling anything.
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

/// What the session's breath guide draws.
///
/// `rings` is the bloom — a dot that opens into a cage of turning rings and
/// settles onto one circle at full lungs (`BreathOrb`). `sphere` is the guide
/// that shipped first: one soft disc scaling with the breath, kept for anybody
/// who finds the rings busier than a breath should be. An enum rather than a
/// toggle so a third rendering is a case away, not a redesign of the setting.
///
/// The raw value is a stored key — see `Passage` for the rule.
public enum BreathVisualStyle: String, Sendable, CaseIterable, Identifiable {
    case rings
    case sphere

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .rings: "Rings"
        case .sphere: "Sphere"
        }
    }
}

/// Which colour scheme the app draws in.
///
/// `system` is the default and the absence of an opinion. Every token in the
/// palette carries a light and a dark value (M3), so this is one override at
/// the root of the view tree — never a per-view branch, which is exactly the
/// thing the token system exists to prevent.
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

/// The session preferences that survive a launch.
///
/// `UserDefaults` rather than the session store: these are preferences, not
/// history, and they are the kind of value that will move onto the profile once
/// there is an identity to hang them on.
@MainActor
@Observable
public final class SessionSettings {
    private static let appearanceKey = "app.appearance"
    private static let breathVisualKey = "session.breathVisual"
    private static let cueModeKey = "session.cueMode"
    private static let guidanceKey = "session.guidance"
    private static let hapticStrengthKey = "session.hapticStrength"

    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    public var cueMode: SessionCueMode {
        didSet { defaults.set(cueMode.rawValue, forKey: Self.cueModeKey) }
    }

    public var guidance: SessionGuidance {
        didSet { defaults.set(guidance.rawValue, forKey: Self.guidanceKey) }
    }

    public var breathVisual: BreathVisualStyle {
        didSet { defaults.set(breathVisual.rawValue, forKey: Self.breathVisualKey) }
    }

    /// How hard the taps land. Separate from `cueMode`, which decides *whether*
    /// there are taps: wanting haptics and wanting them stronger are different
    /// questions, and folding them into one control would mean a person who
    /// turns the strength down loses the channel.
    public var hapticStrength: HapticStrength {
        didSet { defaults.set(hapticStrength.rawValue, forKey: Self.hapticStrengthKey) }
    }

    /// Every technique the person has dialled, keyed by slug — the key the
    /// catalogue promises to keep stable across reseeds.
    ///
    /// One blob rather than a default per technique: the whole set is read on
    /// launch and written on any change, so a key each would buy nothing but
    /// more keys. It stays on the device — see `TechniqueOverrides` for why the
    /// profile is not where this belongs.
    private var overridesBySlug: [String: TechniqueOverrides] {
        didSet { persistOverrides() }
    }

    private let defaults: UserDefaults
    private let overridesStore: DefaultsJSONStore<[String: TechniqueOverrides]>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overridesStore = DefaultsJSONStore(
            key: "session.techniqueOverrides",
            what: "the technique overrides",
            category: "settings",
            defaults: defaults
        )
        // Assigning in an initialiser does not run `didSet`, which is what keeps
        // this from writing back the value it just read.
        appearance = defaults.string(forKey: Self.appearanceKey)
            .flatMap(Appearance.init(rawValue:)) ?? .system
        cueMode = defaults.string(forKey: Self.cueModeKey)
            .flatMap(SessionCueMode.init(rawValue:)) ?? .hapticsAndAudio
        hapticStrength = defaults.string(forKey: Self.hapticStrengthKey)
            .flatMap(HapticStrength.init(rawValue:)) ?? .standard
        guidance = defaults.string(forKey: Self.guidanceKey)
            .flatMap(SessionGuidance.init(rawValue:)) ?? .full
        breathVisual = defaults.string(forKey: Self.breathVisualKey)
            .flatMap(BreathVisualStyle.init(rawValue:)) ?? .rings
        // Unreadable stored preferences read as none: the curated defaults are
        // always a correct session, and the person is one visit to Advanced
        // away from their own again.
        overridesBySlug = overridesStore.load() ?? [:]
    }

    /// What this person dialled for `technique`, or nil where they took it as
    /// the catalogue curated it.
    public func overrides(for technique: Technique) -> TechniqueOverrides? {
        overridesBySlug[technique.slug]
    }

    /// Stores a dialled technique, or clears it back to the curated defaults
    /// when `overrides` is nil or matches them exactly — so "reset" leaves
    /// nothing behind to outlive a change to the catalogue.
    public func setOverrides(_ overrides: TechniqueOverrides?, for technique: Technique) {
        if let overrides, overrides != technique.curatedOverrides {
            overridesBySlug[technique.slug] = overrides
        } else {
            overridesBySlug.removeValue(forKey: technique.slug)
        }
    }

    private func persistOverrides() {
        overridesStore.save(overridesBySlug)
    }
}
