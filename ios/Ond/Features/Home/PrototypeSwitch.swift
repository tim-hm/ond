import OndUI
import SwiftUI

/// Something the prototype offers a choice between, named in one word.
///
/// Two of these exist — which home, and which take on the dial — and they are
/// switched the same way because they are the same kind of scaffolding: a row of
/// quiet words that costs nothing to read past and goes when the question it
/// asks is answered.
protocol PrototypeChoice: CaseIterable, Equatable, Identifiable {
    /// What the switch calls it, in the app's lowercase.
    var title: String { get }
}

extension PrototypeChoice where Self: RawRepresentable, RawValue == String {
    var id: Self {
        self
    }

    var title: String {
        rawValue
    }
}

/// The row of words a prototype question is switched with.
///
/// Deliberately the smallest thing that works: a control worth designing is a
/// control somebody might keep.
struct PrototypeSwitch<Choice: PrototypeChoice>: View {
    @Binding var chosen: Choice

    var body: some View {
        HStack(spacing: Theme.Spacing.standard) {
            ForEach(Array(Choice.allCases)) { candidate in
                Button(candidate.title) {
                    chosen = candidate
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    candidate == chosen ? Theme.Accent.brand : Theme.Ink.tertiary
                )
                .accessibilityAddTraits(candidate == chosen ? [.isSelected] : [])
            }
        }
        .font(.caption)
    }
}
