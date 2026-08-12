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

    /// What this mode costs once the screen goes off, said where the mode is
    /// chosen rather than discovered three phases into a practice.
    ///
    /// Observed platform behaviour, not a preference: iOS withholds haptics from
    /// a locked device however much background runtime the app holds, so sound is
    /// the only channel that follows somebody out — `SessionCues.playsInBackground`
    /// carries the device finding this rests on. Exhaustive so a fourth mode
    /// cannot be added without answering the question.
    public var screenOffNote: String {
        switch self {
        case .hapticsAndAudio:
            "iPhone haptics aren't supported when the screen is off — you'll hear the session but not feel it."
        case .haptics:
            "iPhone haptics aren't supported when the screen is off, so the session pauses and says so."
        case .visualOnly:
            "The session pauses when you leave the app, and says so."
        }
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
/// `sphere` is the default and the one the app was built around: a soft disc
/// swelling and shrinking with the breath, which is the whole instruction.
/// `ring` fills its arc over the phase instead of scaling — the rendering
/// Reduce Motion forces, offered to anyone who reads a filling gauge faster
/// than a growing body.
///
/// An enum rather than a toggle because the guide is the app's one screen
/// worth iterating on: a third rendering should be a case and a `switch` arm,
/// not a redesign of the setting. A tumbling cage of rings lived here for a
/// while and did not survive contact with a real breath; git holds it.
///
/// The raw value is a stored key — see `Passage` for the rule.
public enum BreathVisualStyle: String, Sendable, CaseIterable, Identifiable {
    case sphere
    case ring

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .sphere: "Sphere"
        case .ring: "Ring"
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
    private static let moodCheckKey = "session.moodCheck"
    private static let soundKey = "session.sound"
    private static let wristPulseKey = "session.wristPulse"

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

    /// What the sound *is*, where `cueMode` decides whether there is any — the
    /// same split this makes with `hapticStrength` against the taps.
    ///
    /// A voice by default — the one the manifest marks, so which voice that is
    /// is decided beside the roster rather than named here. A guided practice
    /// is what most people are reaching for, and a beep is a poor first
    /// impression of one.
    ///
    /// Anybody already breathing to tones has chosen them, and a stored choice
    /// is read before this default is reached. It falls back to the tones only
    /// where a build shipped no clips at all.
    public var sound: SessionSound {
        didSet { defaults.set(sound.rawValue, forKey: Self.soundKey) }
    }

    /// Whether a session asks the paired watch for a live heart rate.
    ///
    /// Off by default, and asked for rather than assumed: honouring it wakes the
    /// watch app and holds a workout session open on somebody's wrist for the
    /// length of the practice, which is a cost nobody agreed to by tapping Begin.
    /// A person who wants the number will find this; a person who does not is
    /// never charged for it.
    ///
    /// On with no watch paired is not an error and not a lie — see
    /// `PulseMonitor`, where every way this can come to nothing arrives as the
    /// same silence.
    public var showsWristPulse: Bool {
        didSet { defaults.set(showsWristPulse, forKey: Self.wristPulseKey) }
    }

    /// Whether a session asks how you feel, once before the breathing and once
    /// after, and records the answers to Health.
    ///
    /// On by default, which is the opposite of the wrist pulse above and for the
    /// opposite reason: this costs a tap and nothing else — no sensor, no other
    /// device, no battery — and it is the only way the app can answer whether
    /// any of this is working from the person's own data rather than from a
    /// number önd made up. A prompt that ships off is a loop that never closes.
    ///
    /// It governs the asking, and the asking is the whole gate: nothing is
    /// written to Health that was not tapped, so switching this off ends the
    /// writes as well — see `MoodRecorder`, which has no preference of its own.
    public var asksHowYouFeel: Bool {
        didSet { defaults.set(asksHowYouFeel, forKey: Self.moodCheckKey) }
    }

    /// Whether a session will say its phases out loud.
    ///
    /// Both halves, because either one silences the voice: a mode with no sound
    /// plays no clips, and tones are not speech. `SessionView` asks so that its
    /// VoiceOver announcement does not post the same sentence a clip is already
    /// speaking, a beat apart and in a different voice.
    public var speaksPhases: Bool {
        cueMode.playsAudio && sound.voice != nil
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
        sound = defaults.string(forKey: Self.soundKey)
            .flatMap(SessionSound.init(rawValue:))
            ?? SessionVoice.preferred.map(SessionSound.voice) ?? .tones
        guidance = defaults.string(forKey: Self.guidanceKey)
            .flatMap(SessionGuidance.init(rawValue:)) ?? .full
        breathVisual = defaults.string(forKey: Self.breathVisualKey)
            .flatMap(BreathVisualStyle.init(rawValue:)) ?? .sphere
        // Absent reads as false, which is this one's default anyway.
        showsWristPulse = defaults.bool(forKey: Self.wristPulseKey)
        // This one defaults on, so an absent key cannot be read with
        // `bool(forKey:)` — its default is false, which is the wrong answer for
        // every install before the switch is ever touched.
        asksHowYouFeel = defaults.object(forKey: Self.moodCheckKey) == nil
            || defaults.bool(forKey: Self.moodCheckKey)
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
