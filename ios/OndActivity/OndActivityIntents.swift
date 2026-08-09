import AppIntents
import OndKit

/// The extension's half of the same declaration the app carries.
///
/// Per target rather than once, because App Intents metadata is extracted per
/// target: this is what puts `OndKit`'s intents in the index the buttons in this
/// extension are encoded against. `Ond/OndAppIntents.swift` has the whole of the
/// reasoning.
struct OndActivityIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [OndKitIntents.self]
    }
}
