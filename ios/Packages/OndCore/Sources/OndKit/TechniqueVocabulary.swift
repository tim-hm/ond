// The small vocabularies a technique is described in, apart from the type they
// describe: three enums whose docs are longer than their cases, in front of a
// `Technique` that is already at the file-length cap without them.

/// The outcome a technique is chosen for.
///
/// Distinct from the generated `Ond_V1_TechniqueGoal` on purpose: that type
/// carries an `UNSPECIFIED` case the wire format can always produce, and every
/// view that switched over it would need a branch for a value that means
/// "the server and this app disagree". Decoding resolves that once, here.
///
/// The raw value exists so a goal can be written down: the answers someone gives
/// at onboarding are stored locally as JSON, and a synthesised case name is not
/// a key that should survive a refactor.
public enum TechniqueGoal: String, Sendable, CaseIterable, Codable {
    case calm
    case sleep
    case energy
    case reset
    case focus
}

/// How much the research supports what an exercise is offered for — the
/// evidence verdict as one word a row can carry.
///
/// Distinct from the generated `Ond_V1_EvidenceGrade` on `TechniqueGoal`'s
/// reasoning, and with the same resolution made once at decoding: the wire's
/// `UNSPECIFIED` becomes nil here, because "nobody has graded this" is an
/// absence rather than a third grade every view would need a branch for.
///
/// The rubric each exercise was graded against, and why there are two grades
/// and no `strong`, are in `docs/product/breathing-science.md` §2.1. The grades
/// themselves are seeded beside the verdicts they summarise.
public enum EvidenceGrade: String, Sendable, CaseIterable, Codable {
    /// Randomised trials exist and point one way, but they are unblinded,
    /// small, single-lab, or read across from another population or outcome.
    case moderate

    /// No trials of this pattern, pilot-sized work only, or the best-controlled
    /// trial of it is a null.
    case limited
}

/// Who wrote a technique, and therefore who may change it.
///
/// Not carried on the wire: a technique's origin is which service answered for
/// it, and `UserTechniqueRepository` is the only thing that ever stamps
/// `.personal`. It lives on the domain type so that everything above the
/// repositories — a list section, a detail screen deciding between Customise and
/// Edit — asks one question instead of tracking which array a value came out of.
public enum TechniqueOrigin: String, Sendable, Hashable, Codable {
    /// Curated, seeded, and the same for everybody.
    case catalogue

    /// Composed by the person holding the phone, and stored server-side against
    /// their identity so it is the same exercise on every device they use.
    case personal
}
