import OndKit
import SwiftUI

/// A profile answer that supplies the label for its optional picker row.
protocol OptionalPickerOption: CaseIterable, Hashable {
    var title: String { get }
}

extension ExperienceLevel: OptionalPickerOption {}
extension BirthYearBand: OptionalPickerOption {}
extension Gender: OptionalPickerOption {}

/// The shared unanswered choice followed by every typed answer.
///
/// This is picker content rather than a picker so Settings' standard rows and
/// onboarding's glass row retain their own presentation.
struct OptionalPickerOptions<Option: OptionalPickerOption>: View {
    var body: some View {
        Text("Rather not say").tag(Option?.none)
        ForEach(Array(Option.allCases), id: \.self) { option in
            Text(option.title).tag(Option?.some(option))
        }
    }
}
