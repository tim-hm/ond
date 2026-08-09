import AppIntents
import OndKit

/// Names `OndKit`'s intents as this app's own.
///
/// App Intents metadata is extracted per target at build time, so the intents
/// compiled into the package are not in this app's own index — and the lock
/// screen's buttons are resolved against *this* index, because a
/// `LiveActivityIntent` runs in the app's process rather than in the extension
/// that drew the button. This declaration is Apple's mechanism for closing that
/// gap. Without it the controls draw correctly and do nothing when pressed,
/// which is the kind of failure that only shows up on a device.
///
/// The extension carries its own for the same reason — see
/// `OndActivity/OndActivityIntents.swift`.
struct OndAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [OndKitIntents.self]
    }
}
