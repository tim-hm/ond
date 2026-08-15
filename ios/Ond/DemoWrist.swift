import OndKit
import SwiftUI

extension View {
    /// Answers this launch's pulse orders from a stand-in wrist when the
    /// screenshot fixture is installed, and does nothing otherwise.
    ///
    /// Its own task rather than folded into the launch one, for the reason
    /// `plus.watch()` has its own: it never returns, and it has to outlive each
    /// session so every order placed this launch is answered rather than only
    /// the first.
    func demoWrist(_ pulse: PulseMonitor) -> some View {
        #if DEBUG
            task {
                guard OndApp.wantsDemoPractice else { return }
                await DemoWrist.follow(pulse)
            }
        #else
            self
        #endif
    }
}

#if DEBUG

    /// Reports that the watch app launched, because on a simulator nothing can.
    ///
    /// Needed as well as [`DemoWrist`], and this is the part that is easy to
    /// miss: `PulseMonitor.begin` retracts its order the moment a launch is
    /// refused — deliberately, so a phone with no wrist is not left holding an
    /// arrangement nothing will answer. A simulator refuses every launch, so the
    /// order it places lives for milliseconds and there is nothing for a
    /// stand-in wrist to answer. Saying yes here is what lets the order stand
    /// long enough to be photographed.
    struct DemoWristLauncher: WristLaunching {
        func prepare() async {}

        func launchWatchApp() async -> Bool {
            true
        }
    }

    /// Answers a session's sharing order the way a paired watch would, so the
    /// screenshot set can show the live heart rate.
    ///
    /// Live heart rate is one of the four things önd+ sells, which makes it worth
    /// a screenshot, and it is the one feature no simulator can produce: a watch
    /// simulator runs `HKWorkoutSession` with no sensor behind it, so the badge
    /// and the curve stay empty however the session is started.
    ///
    /// What this does *not* do is as deliberate as what it does. It places no
    /// order, starts no session, and invents no arrangement — it waits until a
    /// real session has placed a real order and then answers it through
    /// `PulseMonitor.receive`, which runs every check it runs for the radio. A
    /// session where the person never asked for a heart rate places no order and
    /// so gets no readings, exactly as on a phone with no watch.
    ///
    /// Debug-only, and started only under `--ui-testing-demo`, on the same terms
    /// as [`DemoPractice`].
    @MainActor
    enum DemoWrist {
        /// How often a reading arrives.
        ///
        /// Faster than `PulseRelay.spacing`, which is what a real wrist sends
        /// at, and deliberately: the curve behind the badge needs several points
        /// before it is worth photographing, and at the real cadence the capture
        /// would wait minutes for them. Well inside `PulseMonitor.staleness`
        /// either way — a stand-in that let the badge expire mid-capture would
        /// photograph the empty state it exists to avoid.
        private static let spacing: Duration = .milliseconds(200)

        /// A rate settling as the breathing does.
        ///
        /// Falling, because that is what the feature is for — the point of
        /// showing a heart rate beside a slow exhale is that one follows the
        /// other. It holds at the end rather than falling forever, so a long
        /// session does not photograph a resting rate no adult has.
        private static let rates = [
            78, 77, 76, 74, 73, 71, 70, 68, 67, 66, 65, 64, 63, 63, 62, 62,
        ]

        /// Answers every order this launch places, until the app goes away.
        static func follow(_ pulse: PulseMonitor) async {
            var next = 0

            while !Task.isCancelled {
                if let orderId = pulse.placedOrderId {
                    _ = pulse.receive(
                        WatchPulse(
                            orderId: orderId,
                            beatsPerMinute: rates[min(next, rates.count - 1)]
                        )
                    )
                    next += 1
                } else {
                    // Between sessions. Reset so the next one starts high and
                    // settles again rather than resuming a stranger's pulse.
                    next = 0
                }

                try? await Task.sleep(for: spacing)
            }
        }
    }
#endif
