/// How one phase contributes to a connected instruction.
///
/// Most phases stand alone. The exact inhale-inhale-exhale shape of a sigh is
/// one sentence spread across three boundaries, and only the stage can identify
/// those roles without coupling the copy to a seeded exercise slug.
enum BreathCueRole: String, Sendable, Hashable, Codable {
    case plain
    case sighOpening
    case sighTopUp
    case sighRelease

    /// The how-to line for a phase, read before anything starts.
    ///
    /// A connected sigh outranks a manner, which is a decision rather than an
    /// observation: a sigh's three rows are one sentence, and a manner cannot be
    /// inserted into the middle of it. No seeded sigh has a manner today, so
    /// nothing exercises the order — it is written down here so that a future
    /// one does not resolve it by accident.
    func preparationInstruction(
        for breath: Breath,
        doneWith manner: Manner?,
        in register: CopyRegister
    ) -> String {
        connectedInstruction
            ?? manner?.instruction(for: breath.kind)
            ?? breath.instruction(in: register)
    }

    func writtenInstruction(for breath: Breath, in register: CopyRegister) -> String {
        connectedInstruction ?? breath.writtenInstruction(in: register)
    }

    func spokenInstruction(for breath: Breath, in register: CopyRegister) -> String {
        connectedInstruction ?? breath.spoken(in: register)
    }

    private var connectedInstruction: String? {
        switch self {
        case .plain: nil
        case .sighOpening: "Breathe in"
        case .sighTopUp: "And in"
        case .sighRelease: "And breathe out"
        }
    }
}

extension Stage {
    /// One role per phase, connected only for the complete shape that makes a sigh.
    var cueRoles: [BreathCueRole] {
        guard phases.map(\.kind) == [.inhale, .inhale, .exhale] else {
            return Array(repeating: .plain, count: phases.count)
        }
        return [.sighOpening, .sighTopUp, .sighRelease]
    }
}
