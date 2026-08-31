import Foundation
import Observation

/// The session preferences that survive a launch. `UserDefaults` rather than
/// the session store: preferences, not history. A `PersonalStore` because the
/// dialled techniques and the mood-check answer are personal — a deletion that
/// left either behind would be a fresh install that knew things.
@MainActor
@Observable
public final class SessionSettings: PersonalStore {
    /// Every key a preference is stored under. `CaseIterable` because the
    /// deletion walks `allCases`, and there is no other way to name a key, so
    /// a preference cannot be added without joining the walk. The raw values
    /// are stored keys: renaming one discards what people had chosen. Internal
    /// so the deletion test walks this list rather than its own copy.
    enum Key: String, CaseIterable {
        case appearance = "app.appearance"
        case breathVisual = "session.breathVisual"
        case cueMode = "session.cueMode"
        case guidance = "session.guidance"
        case hapticStrength = "session.hapticStrength"
        case moodCheck = "session.moodCheck"
        case sound = "session.sound"
        case wristPulse = "session.wristPulse"
    }

    /// Named once so the launch reading them and the deletion restoring them
    /// cannot disagree about a fresh install. `sound` is computed: the
    /// preferred voice is decided beside the voice roster, and a `static let`
    /// would fix it at first use.
    private static let defaultAppearance = Appearance.system
    private static let defaultBreathVisual = BreathVisualStyle.scaling
    private static let defaultCueMode = SessionCueMode.hapticsAndAudio
    private static let defaultGuidance = SessionGuidance.full
    private static let defaultHapticStrength = HapticStrength.standard
    private static let defaultAsksHowYouFeel = true
    private static let defaultShowsWristPulse = false
    private static var defaultSound: SessionSound {
        SessionVoice.preferred.map(SessionSound.voice) ?? .tones
    }

    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance.rawValue) }
    }

    public var cueMode: SessionCueMode {
        didSet { defaults.set(cueMode.rawValue, forKey: Key.cueMode.rawValue) }
    }

    public var guidance: SessionGuidance {
        didSet { defaults.set(guidance.rawValue, forKey: Key.guidance.rawValue) }
    }

    public var breathVisual: BreathVisualStyle {
        didSet { defaults.set(breathVisual.rawValue, forKey: Key.breathVisual.rawValue) }
    }

    /// How hard the taps land. Separate from `cueMode`, which decides *whether*
    /// there are taps: wanting haptics and wanting them stronger are different
    /// questions, and folding them into one control would mean a person who
    /// turns the strength down loses the channel.
    public var hapticStrength: HapticStrength {
        didSet { defaults.set(hapticStrength.rawValue, forKey: Key.hapticStrength.rawValue) }
    }

    /// What the sound *is*; `cueMode` decides whether there is any. A voice by
    /// default — the one the manifest marks, so the choice lives beside the
    /// roster. A stored choice is read before this default; it falls back to
    /// tones only where a build shipped no clips at all.
    public var sound: SessionSound {
        didSet { defaults.set(sound.rawValue, forKey: Key.sound.rawValue) }
    }

    /// Whether a session asks the paired watch for a live heart rate. Off by
    /// default: honouring it wakes the watch app and holds a workout session
    /// open for the whole practice, a cost nobody agreed to by tapping Begin.
    /// On with no watch paired is not an error — see `PulseMonitor`.
    public var showsWristPulse: Bool {
        didSet { defaults.set(showsWristPulse, forKey: Key.wristPulse.rawValue) }
    }

    /// Whether a session asks how you feel, before and after, and records the
    /// answers to Health. On by default: it costs one tap and is the only way
    /// to tell whether the practice works from the person's own data. It
    /// governs the invitation — nothing untapped is written, so off ends the
    /// Health writes too; `MoodRecorder` has no preference of its own.
    public var asksHowYouFeel: Bool {
        didSet { defaults.set(asksHowYouFeel, forKey: Key.moodCheck.rawValue) }
    }

    /// Whether a session will say its phases out loud. Both halves, because
    /// either one silences the voice: a mode with no sound plays no clips, and
    /// tones are not speech. `SessionView` asks so its VoiceOver announcement
    /// does not repeat a sentence a clip is already speaking.
    public var speaksPhases: Bool {
        cueMode.playsAudio && sound.voice != nil
    }

    /// Every dialled technique, keyed by slug — the key the catalogue keeps
    /// stable across reseeds. One blob rather than a default per technique:
    /// the set is read on launch and written on change. Device-only — see
    /// `TechniqueOverrides` for why the profile is not where this belongs.
    /// Watched as a whole so a length on one tab tracks a dial on another.
    public private(set) var overridesBySlug: [TechniqueSlug: TechniqueOverrides] {
        didSet { persistOverrides() }
    }

    private let defaults: UserDefaults
    private let overridesStore: DefaultsJSONStore<[TechniqueSlug: TechniqueOverrides]>

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
        appearance = defaults.string(forKey: Key.appearance.rawValue)
            .flatMap(Appearance.init(rawValue:)) ?? Self.defaultAppearance
        cueMode = defaults.string(forKey: Key.cueMode.rawValue)
            .flatMap(SessionCueMode.init(rawValue:)) ?? Self.defaultCueMode
        hapticStrength = defaults.string(forKey: Key.hapticStrength.rawValue)
            .flatMap(HapticStrength.init(rawValue:)) ?? Self.defaultHapticStrength
        sound = defaults.string(forKey: Key.sound.rawValue)
            .flatMap(SessionSound.init(rawValue:)) ?? Self.defaultSound
        guidance = defaults.string(forKey: Key.guidance.rawValue)
            .flatMap(SessionGuidance.init(rawValue:)) ?? Self.defaultGuidance
        breathVisual = defaults.string(forKey: Key.breathVisual.rawValue)
            .flatMap(BreathVisualStyle.init(rawValue:)) ?? Self.defaultBreathVisual
        showsWristPulse = defaults.flag(
            forKey: Key.wristPulse.rawValue,
            default: Self.defaultShowsWristPulse
        )
        asksHowYouFeel = defaults.flag(
            forKey: Key.moodCheck.rawValue,
            default: Self.defaultAsksHowYouFeel
        )
        // Unreadable stored preferences read as none: the curated defaults are
        // always a correct session, and the person is one visit to Advanced
        // away from their own again.
        overridesBySlug = overridesStore.load() ?? [:]
    }

    /// Returns every preference to what a fresh install would find, in memory
    /// and on disk both. The dialled techniques matter most: an erased account
    /// that kept them would hand the next person the last one's practice. Keys
    /// are removed after the assignments: each writes back through `didSet`,
    /// so clearing first would leave defaults written as though chosen.
    public func erase() async {
        appearance = Self.defaultAppearance
        breathVisual = Self.defaultBreathVisual
        cueMode = Self.defaultCueMode
        guidance = Self.defaultGuidance
        hapticStrength = Self.defaultHapticStrength
        sound = Self.defaultSound
        showsWristPulse = Self.defaultShowsWristPulse
        asksHowYouFeel = Self.defaultAsksHowYouFeel
        overridesBySlug = [:]

        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
        overridesStore.erase()
    }

    /// What this person dialled for `technique`, or nil where they took it as
    /// the catalogue curated it.
    public func overrides(for technique: Technique) -> TechniqueOverrides? {
        overridesBySlug[technique.slug]
    }

    /// The same, for a whole list, in the shape every fold over stops takes.
    /// One join rather than one per call site: two copies are two chances for
    /// one screen to print a curated length while the other prints a dialled
    /// one. An undialled slug is absent, not nil-valued — assigning an
    /// `Optional` removes the key — which is `DialStop`'s meaning of nil.
    public func overrides(
        forSlugsOf techniques: [Technique]
    ) -> [TechniqueSlug: TechniqueOverrides] {
        techniques.reduce(into: [:]) { dialled, technique in
            dialled[technique.slug] = overrides(for: technique)
        }
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
