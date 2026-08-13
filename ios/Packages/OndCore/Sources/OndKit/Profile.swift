import Foundation

/// How much breathwork someone has done before.
///
/// Chooses what the app explains, never what it offers — every technique is
/// available at every level. It lands on the coach, which is the only thing that
/// reads it (`experience_phrase`), and is why Settings words it as what the
/// coach assumes rather than as what a session shows: that second thing is
/// `SessionGuidance`, and a person who cannot tell them apart will turn one
/// down and wonder why the other kept talking.
///
/// Absent rather than "unspecified": a profile exists
/// before anyone has been asked, and `ExperienceLevel?` says so without adding a
/// case every `switch` would have to carry.
public enum ExperienceLevel: String, Sendable, CaseIterable, Codable, Identifiable {
    case new
    case occasional
    case regular

    public var id: Self {
        self
    }

    /// First person, and phrased as something a person would say rather than as
    /// a tier they are being sorted into.
    public var title: String {
        switch self {
        case .new: "I'm new to this"
        case .occasional: "I've tried it a few times"
        case .regular: "I practise already"
        }
    }

    public var detail: String {
        switch self {
        case .new: "We'll explain what's happening as you go."
        case .occasional: "We'll keep the guidance light."
        case .regular: "Straight to the breathing."
        }
    }
}

/// How much the app is invited to ask for someone's attention.
///
/// `never` is the default in every direction — the stored default, the proto
/// zero value, and what an unreadable preference falls back to — so nothing
/// that goes wrong can turn silence into a notification. Notification
/// permission is asked for only when this moves off it.
///
/// A live control, decided deliberately (TIM-75, 2026-08-09): the dial owns
/// exactly one schedule — marked `Schedule.fromDial` — seeding it at
/// onboarding and reshaping its frequency whenever `ReminderDial` moves
/// (`ScheduleStore.applyDial`). It was briefly an onboarding-only seed
/// that sat in Settings editable and inert; a control carrying the app's
/// "no pressure" promise either works or does not exist, and wiring it up was
/// the option chosen.
public enum ReminderIntensity: String, Sendable, CaseIterable, Codable, Identifiable {
    case never
    case gentle
    case daily

    public var id: Self {
        self
    }

    /// The whole of what a dial position says on screen. It had a second line
    /// each — "an occasional nudge, nothing counts a missed day against you" —
    /// which went with the screen that had room for it: the dial is one row
    /// among the opt-ins now, and three words that read as a choice rather than
    /// as opting out of the app is the job.
    public var title: String {
        switch self {
        case .never: "Never"
        case .gentle: "Now and then"
        case .daily: "Once a day"
        }
    }
}

/// The decade somebody was born in.
///
/// Bands by birth decade rather than by age, so a person's band never changes
/// under them. Optional everywhere: it exists so the age-band leaderboard can
/// compare like with like, and nobody has to answer it to use the app.
///
/// Both pickers render `allCases`, so the youngest case here is the youngest
/// band önd offers — which has to agree with the children's paragraph in the
/// privacy policy and with the age answers on the App Store Connect
/// questionnaire. `noughties` is that case, and somebody born later leaves the
/// band unanswered; the reasoning, and when a younger one may be added, is on
/// `BirthYearBand` in `proto/ond/v1/profile_service.proto`.
public enum BirthYearBand: String, Sendable, CaseIterable, Codable, Identifiable {
    case before1960
    case sixties
    case seventies
    case eighties
    case nineties
    case noughties

    public var id: Self {
        self
    }

    /// Phrased as a decade rather than as an age bracket — "born in the 1980s"
    /// is a fact about someone, where "aged 36–45" is a label being applied to
    /// them.
    public var title: String {
        switch self {
        case .before1960: "Before 1960"
        case .sixties: "The 1960s"
        case .seventies: "The 1970s"
        case .eighties: "The 1980s"
        case .nineties: "The 1990s"
        case .noughties: "The 2000s"
        }
    }
}

/// Gender, as someone chose to share it.
///
/// It exists so the coach can read a breath-test score against the right
/// baseline, and for nothing else. A closed list without a self-describe
/// field, on purpose: the one consumer is a prompt, and free text here would
/// be a second injection surface bought for a single prose reader. Optional
/// everywhere — nobody has to answer, and "rather not say" is absence rather
/// than a fourth case every `switch` would have to carry.
public enum Gender: String, Sendable, CaseIterable, Codable, Identifiable {
    case female
    case male
    case nonBinary

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        case .nonBinary: "Non-binary"
        }
    }
}

/// What someone told the app about themselves.
///
/// Answers, not derived state: streaks and totals are computed from the sessions
/// on this device (see `JourneyStats`), so this stays something a person would
/// recognise as the things they typed. `Codable` because it is kept locally as
/// well as on the server — onboarding has to finish with no network.
public struct Profile: Sendable, Equatable, Codable {
    /// What they are here for, in the order they picked. Empty is a real
    /// answer: someone can skip the question, and it does not mean "all of
    /// them".
    public var goals: [TechniqueGoal]
    /// `nil` until they answer.
    public var experienceLevel: ExperienceLevel?
    public var reminderIntensity: ReminderIntensity
    /// Why they are here, in their own words. Empty is the normal state.
    public var intentNote: String
    /// What the leaderboards call this person, and the whole of the opt-in to
    /// them. Empty means invisible to everyone else, which is where every
    /// profile starts.
    ///
    /// The server owns the final value — it trims, screens, and suffixes a name
    /// somebody already holds — so what comes back from a sync is what other
    /// people will see and may not be what was typed.
    public var displayName: String
    /// `nil` until they say, which most people never will.
    public var birthYearBand: BirthYearBand?
    /// `nil` until they say, and staying `nil` is a full answer.
    public var gender: Gender?
    /// What to call this person. Empty is the normal state — the question is
    /// optional and one tap from being skipped — and every greeting has to read
    /// as well without it.
    ///
    /// Empty rather than `nil`, following `displayName` two fields up: both are
    /// names, both are nullable columns the server stores absence for, and one
    /// of the pair modelled the other way round would be a difference readers
    /// look for a reason behind. The reason they are *not* one field is that
    /// this one is nobody else's business — the boards never print it, so the
    /// server neither screens it nor suffixes it, and what comes back is what
    /// was sent.
    public var givenName: String

    /// How long a note may be, in Unicode scalars — the unit the server's
    /// validation and the database `CHECK` both count. Held here so the field
    /// can stop accepting input rather than letting someone write past the
    /// point where saving would fail.
    public static let maxIntentNoteLength = 500

    /// The same rule for a display name, in the same unit. The server also
    /// insists on a minimum of two.
    public static let maxDisplayNameLength = 24
    public static let minDisplayNameLength = 2

    /// And for the given name, which has no minimum: one letter is a name
    /// somebody goes by, and the only floor is that a greeting has something to
    /// print.
    public static let maxGivenNameLength = 24

    /// A profile of unanswered questions — what a person has before onboarding,
    /// and what the server returns for an identity that has never written one.
    public static let unanswered = Self(
        goals: [],
        experienceLevel: nil,
        reminderIntensity: .never,
        intentNote: ""
    )

    /// Whether anybody has told this profile anything.
    ///
    /// The question a restore turns on: the server answers `GetProfile` for an
    /// identity it has never been written to, so "there is a profile" is not the
    /// same claim as "there are answers worth adopting". Compared against the
    /// default wholesale rather than field by field, so a field added later is
    /// covered without anybody remembering to extend a list.
    public var hasAnswers: Bool {
        self != .unanswered
    }

    public init(
        goals: [TechniqueGoal],
        experienceLevel: ExperienceLevel?,
        reminderIntensity: ReminderIntensity,
        intentNote: String,
        displayName: String = "",
        birthYearBand: BirthYearBand? = nil,
        gender: Gender? = nil,
        givenName: String = ""
    ) {
        self.goals = goals
        self.experienceLevel = experienceLevel
        self.reminderIntensity = reminderIntensity
        self.intentNote = intentNote
        self.displayName = displayName
        self.birthYearBand = birthYearBand
        self.gender = gender
        self.givenName = givenName
    }

    /// Written by hand for one reason: the synthesised decoder throws on a
    /// missing key even where the property has a default, so a profile stored
    /// before `displayName` existed would fail to decode and be discarded —
    /// silently asking somebody their onboarding questions again after an
    /// update. Every field is therefore optional on the way in.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        goals = try container.decodeIfPresent([TechniqueGoal].self, forKey: .goals) ?? []
        experienceLevel = try container.decodeIfPresent(
            ExperienceLevel.self,
            forKey: .experienceLevel
        )
        reminderIntensity = try container.decodeIfPresent(
            ReminderIntensity.self,
            forKey: .reminderIntensity
        ) ?? .never
        intentNote = try container.decodeIfPresent(String.self, forKey: .intentNote) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        birthYearBand = try container.decodeIfPresent(BirthYearBand.self, forKey: .birthYearBand)
        gender = try container.decodeIfPresent(Gender.self, forKey: .gender)
        givenName = try container.decodeIfPresent(String.self, forKey: .givenName) ?? ""
    }

    /// This profile narrowed to what the server will accept.
    ///
    /// The one statement of the client's half of the validation rules, because
    /// the cost of two is specific and silent: a field the client lets through
    /// and the server refuses leaves `UpdateProfile` returning
    /// `INVALID_ARGUMENT` on every launch for the life of the install, taking
    /// the *whole* profile with it — goals, experience and reminders never
    /// reach the server because of a tab somebody pasted into their name.
    ///
    /// Both models that edit a profile call this, so a field added to one of
    /// their screens is narrowed by the same rule without either remembering.
    ///
    /// The note is bounded but not stripped: it is a multi-line field the
    /// server only measures, so a newline in it is somebody's paragraph rather
    /// than a character that would break a line it is drawn on.
    func clampedToServerLimits() -> Self {
        var clamped = self
        clamped.displayName = displayName.clampedName(toScalars: Self.maxDisplayNameLength)
        clamped.givenName = givenName.clampedName(toScalars: Self.maxGivenNameLength)
        clamped.intentNote = intentNote.clamped(toScalars: Self.maxIntentNoteLength)
        return clamped
    }
}

extension String {
    /// This string cut to `limit` Unicode scalars — the unit the server's
    /// validation and the database `CHECK` both count, and the one rule behind
    /// every bounded field above: a grapheme-cluster count would let through
    /// multi-scalar emoji the server then rejects. The UTF-8 length is checked
    /// first because it is O(1) and never smaller than the scalar count, so
    /// the common under-limit case walks nothing and returns `self` untouched.
    func clamped(toScalars limit: Int) -> String {
        guard utf8.count > limit, unicodeScalars.count > limit else { return self }
        let end = unicodeScalars.index(unicodeScalars.startIndex, offsetBy: limit)
        return String(unicodeScalars[..<end])
    }

    /// This string as a name the server will take: control characters gone,
    /// then cut to `limit` Unicode scalars.
    ///
    /// The server refuses a name carrying one outright — a name is drawn on one
    /// line, and a tab or a newline either breaks that line or renders as
    /// nothing. Stripped here rather than refused because this runs as somebody
    /// types: the field simply will not accept the character, which is the same
    /// thing the length limit does and needs no error to explain it. A pasted
    /// name arrives cleaned rather than blocked.
    ///
    /// Category Cc exactly, matching Rust's `char::is_control` on the other
    /// side. `CharacterSet.controlCharacters` is wider — it takes the format
    /// characters too, and a zero-width joiner is load-bearing inside an emoji
    /// the server would have stored intact.
    func clampedName(toScalars limit: Int) -> String {
        let stripped = unicodeScalars.contains { $0.properties.generalCategory == .control }
            ? String(String.UnicodeScalarView(
                unicodeScalars.filter { $0.properties.generalCategory != .control }
            ))
            : self

        return stripped.clamped(toScalars: limit)
    }
}
