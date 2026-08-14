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

    func preparationInstruction(for breath: Breath, in register: CopyRegister) -> String {
        connectedInstruction ?? breath.instruction(in: register)
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
