// The small vocabularies a technique is described in, apart from the type they
// describe: three enums whose docs are longer than their cases, in front of a
// `Technique` that is already at the file-length cap without them.

/// The outcome a technique is chosen for. Distinct from the generated
/// `Ond_V1_TechniqueGoal`: that carries a wire-producible `UNSPECIFIED`, and
/// decoding resolves it once rather than every view branching on it. The raw
/// value is the JSON storage key for onboarding answers.
public enum TechniqueGoal: String, Sendable, CaseIterable, Codable {
    case calm
    case sleep
    case energy
    case reset
    case focus
}

/// The evidence verdict as one word a row can carry. Distinct from the
/// generated `Ond_V1_EvidenceGrade`: the wire's `UNSPECIFIED` becomes nil at
/// decoding, because "nobody has graded this" is an absence rather than a
/// third grade every view would branch on. The rubric, and why there is no
/// `strong`, are in `docs/product/breathing-science.md` §2.1.
public enum EvidenceGrade: String, Sendable, CaseIterable, Codable {
    /// Randomised trials exist and point one way, but they are unblinded,
    /// small, single-lab, or read across from another population or outcome.
    case moderate

    /// No trials of this pattern, pilot-sized work only, or the best-controlled
    /// trial of it is a null.
    case limited
}

/// Who wrote a technique, and therefore who may change it. Not carried on
/// the wire: origin is which service answered, and `UserTechniqueRepository`
/// is the only thing that stamps `.personal`. On the domain type so screens
/// ask one question instead of tracking which array a value came from.
public enum TechniqueOrigin: String, Sendable, Hashable, Codable {
    /// Curated, seeded, and the same for everybody.
    case catalogue

    /// Composed by the person holding the phone, and stored server-side against
    /// their identity so it is the same exercise on every device they use.
    case personal
}
