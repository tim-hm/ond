import Foundation
import Observation

/// The session preferences that survive a launch.
///
/// `UserDefaults` rather than the session store: these are preferences, not
/// history, and they are the kind of value that will move onto the profile once
/// there is an identity to hang them on.
///
/// A `PersonalStore` because of what is in here rather than because a
/// preference is private: the dialled techniques are somebody's practice, the
/// mood check is a question they answered about whether to be asked, and a
/// deletion that left either behind would be a fresh install that knew things.
@MainActor
@Observable
public final class SessionSettings: PersonalStore {
    /// Every key a preference is stored under.
    ///
    /// An enum rather than eight constants and a list beside them, because the
    /// list is what a deletion walks and a key missing from it is a preference
    /// that quietly survives being erased — the failure `PersonalStore` exists
    /// against. `CaseIterable` derives the walk, and since there is no other
    /// way to name a key, a preference cannot be added to this class without
    /// joining it.
    ///
    /// The raw values are stored keys: renaming one silently discards whatever
    /// people had chosen, which is the rule `Passage` states at length.
    ///
    /// Internal rather than private so the deletion test can walk the same
    /// list the deletion does — a test with its own copy of the list would be
    /// asserting against the mistake it exists to catch.
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

    /// What each preference is before anybody has an opinion, named once so
    /// that the launch reading them and the deletion restoring them cannot
    /// disagree about what a fresh install looks like.
    ///
    /// `sound` is computed rather than stored: which voice is preferred is
    /// decided beside the voice roster, and a `static let` would fix it at
    /// first use.
    private static let defaultAppearance = Appearance.system
    private static let defaultBreathVisual = BreathVisualStyle.sphere
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
        didSet { defaults.set(sound.rawValue, forKey: Key.sound.rawValue) }
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
        didSet { defaults.set(showsWristPulse, forKey: Key.wristPulse.rawValue) }
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
    /// It governs the invitation: nothing is written to Health that was not
    /// tapped, so switching this off ends the writes as well — see
    /// `MoodRecorder`, which has no preference of its own.
    public var asksHowYouFeel: Bool {
        didSet { defaults.set(asksHowYouFeel, forKey: Key.moodCheck.rawValue) }
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
    ///
    /// Readable as a whole, which is what a screen printing a length has to
    /// watch: Home states "5 min" beside a row and the tap owes that number, so
    /// re-dialling the same exercise on another tab has to reach it. Watching
    /// the set rather than asking per technique is what makes that one
    /// comparison instead of one per row.
    public private(set) var overridesBySlug: [String: TechniqueOverrides] {
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
    /// and on disk both.
    ///
    /// The dialled techniques are the part that matters: they are a record of
    /// how somebody practised, keyed by slug, and an erased account that kept
    /// them would hand the next person the last one's session. The rest goes
    /// with them because `PersonalStore` asks for a fresh install rather than a
    /// selective one — and because a switch left where somebody put it, after
    /// they asked for everything to be deleted, is a preference this app has no
    /// standing to keep.
    ///
    /// Removed after the assignments rather than before: each one writes its
    /// new value back through `didSet`, so clearing first would leave the
    /// defaults written out as though they had been chosen.
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
    ///
    /// Here rather than at the two call sites that wrote the reduce by hand:
    /// what a stop states as its length comes out of this, and two copies of the
    /// join are two chances for one screen to print a curated length while the
    /// other prints a dialled one.
    ///
    /// A slug this person has not dialled is absent rather than nil-valued —
    /// assigning an `Optional` into a dictionary removes the key — which is what
    /// `DialStop`'s `saved:` parameter means by nil.
    public func overrides(forSlugsOf techniques: [Technique]) -> [String: TechniqueOverrides] {
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
